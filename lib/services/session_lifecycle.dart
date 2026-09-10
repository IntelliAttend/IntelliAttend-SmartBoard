import '../core/state/board_state_machine.dart';
import '../core/utils/logger.dart';
import '../core/platform/kiosk_service.dart';
import 'api_service.dart';
import 'heartbeat_service.dart';
import 'session_state_service.dart';

/// Why the session is being ended. Used for logging and debugging.
enum EndReason {
  userTap,
  wsSessionEnded,
  heartbeatCompleted,
  heartbeatNull,
  slotExpiredT1,
  slotExpiredAutoClose,
  safetyNet,
}

extension _EndReasonLabel on EndReason {
  String get label => switch (this) {
        EndReason.userTap => 'user_tap',
        EndReason.wsSessionEnded => 'ws_session_ended',
        EndReason.heartbeatCompleted => 'heartbeat_completed',
        EndReason.heartbeatNull => 'heartbeat_null',
        EndReason.slotExpiredT1 => 'slot_expired_t1',
        EndReason.slotExpiredAutoClose => 'slot_expired_auto_close',
        EndReason.safetyNet => 'safety_net',
      };
}

/// Single entry point for ALL session termination.
///
/// Every code path that ends a session — user tap, timer, heartbeat, WS event —
/// calls [SessionLifecycle.end] instead of directly calling [ApiService.terminateSession]
/// + [BoardStateMachine.transitionTo]. This ensures:
///
/// 1. **Deduplication** — same session won't be terminated twice simultaneously.
/// 2. **Retry** — failed terminates are always enqueued to the heartbeat retry queue
///    (max 10 retries, then give up).
/// 3. **Deferral** — if the user is on an active screen (BoardState.active), the
///    board transition is deferred (the WS `session_ended` event or the user's
///    own end action handles it).
/// 4. **Logging** — every termination is logged with a reason for debugging.
/// 5. **Count sync** — final present/absent counts are synced to SessionStateService
///    so the orchestrator has accurate data when building SummaryScreen.
class SessionLifecycle {
  SessionLifecycle._();

  /// Sessions currently in the process of being terminated.
  /// Prevents duplicate API calls when multiple paths fire simultaneously.
  static final Set<String> _endingSessions = {};

  /// End a session. Safe to call from any context.
  ///
  /// - [sessionId] — the session to end.
  /// - [reason] — why it's ending (for logging).
  /// - [presentCount] — final present count (optional, synced to SessionStateService).
  /// - [absentCount] — final absent count (optional, synced to SessionStateService).
  /// - [setFullscreen] — if true, switch to fullscreen kiosk mode before
  ///   transitioning (default: true for user-initiated, false for server-initiated).
  static Future<void> end({
    required String sessionId,
    required EndReason reason,
    int? presentCount,
    int? absentCount,
    bool setFullscreen = true,
  }) async {
    if (sessionId.isEmpty) return;

    // Deduplicate — don't fire two terminate calls for the same session.
    if (_endingSessions.contains(sessionId)) {
      Log.d('[Lifecycle] Already ending $sessionId (${reason.label}) — skipping');
      return;
    }
    _endingSessions.add(sessionId);

    Log.i('[Lifecycle] Ending session $sessionId — reason: ${reason.label}');

    // Mark session as recently completed to prevent IdleScreen from
    // re-discovering it during the cooldown window.
    SessionStateService().markRecentlyCompleted(sessionId);

    // Sync final counts to SessionStateService before transitioning.
    // The orchestrator reads these when building SummaryScreen.
    if (presentCount != null && absentCount != null) {
      SessionStateService().updateCounts(presentCount, absentCount);
    }

    // Handle board state transition.
    // If user is on an active screen (BoardState.active) and this is NOT
    // their own tap, defer — let them finish. The WS session_ended event
    // or the user's own end action will handle the actual transition.
    final machine = BoardStateMachine();
    final boardState = machine.currentState;

    if (boardState == BoardState.active && reason != EndReason.userTap) {
      // Defer: user is on an active screen and this is NOT their own action.
      // Record the intent to close but don't rip them away.
      Log.i('[Lifecycle] Deferring board transition — user on active screen');
    } else {
      // Force transition: either user tapped End, or board is idle/closed.
      if (setFullscreen) {
        await KioskService.setMode(KioskMode.fullscreen);
      }
      machine.transitionTo(BoardState.closed);
    }

    // Fire terminate API as fire-and-forget — don't block the caller.
    _fireTerminate(sessionId, reason);

    // Clean up dedup tracking after a short delay.
    // This allows the same session to be re-terminated if needed (e.g., after
    // a crash recovery), while preventing rapid-fire duplicates.
    Future.delayed(const Duration(seconds: 5), () {
      _endingSessions.remove(sessionId);
    });
  }

  /// Fire the terminate API call. On failure, enqueue to heartbeat retry queue.
  static void _fireTerminate(String sessionId, EndReason reason) {
    ApiService.terminateSession(sessionId).catchError((e) {
      Log.e('[Lifecycle] Terminate API failed for $sessionId (${reason.label}): $e');
      HeartbeatService.enqueuePendingTermination(sessionId);
    });
  }

  /// Whether a session is currently being terminated.
  static bool isEnding(String sessionId) => _endingSessions.contains(sessionId);
}
