import 'dart:async';

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
/// 1. **Instant user feedback** — a user-tap end fires the terminate in the
///    background and transitions to SummaryScreen in the same frame. The
///    terminate used to be BLOCKING (commit eeff36e) to protect against the
///    Summary→Idle→Summary loop, but that loop is now independently prevented
///    by the `recentlyCompletedSessionIds` cooldown.
/// 2. **Deduplication** — same session won't be terminated twice simultaneously.
/// 3. **Retry** — failed terminates are always enqueued to the heartbeat retry queue
///    (max 10 retries, then give up).
/// 4. **Deferral** — if the user is on an active screen (BoardState.active),
///    the board transition AND the server terminate are deferred together:
///    killing the server session would invalidate attendance submissions the
///    teacher is still marking. The WS `session_ended` event or the user's
///    own end action handles it.
/// 5. **Logging** — every termination is logged with a reason for debugging.
/// 6. **Count sync** — final present/absent counts are synced to SessionStateService
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
    bool forceTransition = false,
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
    // or the user's own end action will handle the actual transition —
    // UNLESS the caller asked to force the transition (e.g. the slot-end
    // timer fired while the app is minimized; there is nobody to disturb
    // and the session must be eliminated locally without depending on WS).
    final machine = BoardStateMachine();
    final boardState = machine.currentState;

    final bool deferTransition = boardState == BoardState.active &&
        reason != EndReason.userTap &&
        !forceTransition;

    if (deferTransition) {
      // Defer: user is on an active screen and this is NOT their own action.
      // Do NOT rip them away AND do NOT kill the server session — killing it
      // would invalidate any attendance submissions the teacher is still
      // marking. The teacher's own End Session action, the WS session_ended
      // event, or server-side reconciliation ends the session at the right
      // time. No dedup lease is held here so the teacher's subsequent End
      // Session (userTap) is never blocked.
      Log.i('[Lifecycle] Deferring end — user on active screen; server session kept alive');
      _endingSessions.remove(sessionId);
    } else {
      if (reason == EndReason.userTap || forceTransition) {
        // IMMEDIATE: fire the terminate in the background and transition in
        // the same frame so the user lands on SummaryScreen instantly (user
        // tap) or the session is eliminated locally even while minimized
        // (forced timer termination). These paths used to wait on the server
        // (commit eeff36e) to prevent the Summary->Idle->Summary loop, but
        // that loop is now independently prevented by markRecentlyCompleted()
        // above (60s re-discovery cooldown), so the wait is redundant.
        // Failures fall through to the heartbeat retry queue and the
        // server-side idempotent terminate.
        unawaited(_fireTerminate(sessionId, reason));
      } else {
        // Server-first for non-user terminations (slot timers, safety net —
        // background). There is no UX to block here, so prefer waiting for
        // server confirmation before transitioning.
        var enqueued = false;
        try {
          await ApiService.terminateSession(sessionId);
          Log.i('[Lifecycle] Server confirmed session $sessionId ended');
        } catch (e) {
          Log.e('[Lifecycle] Terminate API failed for $sessionId (${reason.label}): $e');
          // Enqueue for retry but still transition — don't block forever.
          // The heartbeat service will retry in the background.
          HeartbeatService.enqueuePendingTermination(sessionId);
          enqueued = true;
        }

        // NOW transition to closed — server has been notified (or will retry).
        if (setFullscreen) {
          await KioskService.setMode(KioskMode.fullscreen);
        }
        machine.transitionTo(BoardState.closed);

        // Hold the dedup lease while the heartbeat retry queue owns the
        // session (10 × 15s retries), so lifecycle + heartbeat can never
        // stack duplicate terminate calls on the same session.
        _releaseDedupLease(
          sessionId,
          enqueued
              ? const Duration(minutes: 6)
              : const Duration(seconds: 5),
        );
      }
    }
  }

  /// Release the dedup lease for [sessionId] after [window]. While held,
  /// duplicate [end] calls for the same session are silently skipped.
  static void _releaseDedupLease(String sessionId, Duration window) {
    Future.delayed(window, () {
      _endingSessions.remove(sessionId);
    });
  }

  /// Fire the terminate API call. On failure, enqueue to heartbeat retry queue.
  static Future<void> _fireTerminate(String sessionId, EndReason reason) async {
    try {
      await ApiService.terminateSession(sessionId);
      _releaseDedupLease(sessionId, const Duration(seconds: 3));
    } catch (e) {
      Log.e('[Lifecycle] Terminate API failed for $sessionId (${reason.label}): $e');
      HeartbeatService.enqueuePendingTermination(sessionId);
      // Keep the dedup lease held for the duration of the heartbeat retry
      // window so lifecycle + heartbeat never stack duplicate terminates.
      _releaseDedupLease(sessionId, const Duration(minutes: 6));
    }
  }

  /// Whether a session is currently being terminated.
  static bool isEnding(String sessionId) => _endingSessions.contains(sessionId);
}
