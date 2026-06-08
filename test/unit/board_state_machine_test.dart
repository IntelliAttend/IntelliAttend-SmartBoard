import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/state/board_state_machine.dart';

void main() {
  group('BoardStateMachine - State Transitions', () {
    late BoardStateMachine machine;

    setUp(() {
      machine = BoardStateMachine();
      machine.reset();
    });

    test('initial state is IDLE', () {
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('IDLE → PRE-FLIGHT is valid', () {
      machine.transitionTo(BoardState.preFlight);
      expect(machine.currentState, equals(BoardState.preFlight));
    });

    test('IDLE → ATTENDANCE is invalid (must go through PRE-FLIGHT)', () {
      machine.transitionTo(BoardState.attendance);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('IDLE → SUMMARY is invalid', () {
      machine.transitionTo(BoardState.summary);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('PRE-FLIGHT → ATTENDANCE is valid', () {
      machine.transitionTo(BoardState.preFlight);
      machine.transitionTo(BoardState.attendance);
      expect(machine.currentState, equals(BoardState.attendance));
    });

    test('PRE-FLIGHT → IDLE is valid (abort)', () {
      machine.transitionTo(BoardState.preFlight);
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('ATTENDANCE → SUMMARY is valid', () {
      machine.transitionTo(BoardState.preFlight);
      machine.transitionTo(BoardState.attendance);
      machine.transitionTo(BoardState.summary);
      expect(machine.currentState, equals(BoardState.summary));
    });

    test('SUMMARY → IDLE is valid', () {
      machine.transitionTo(BoardState.preFlight);
      machine.transitionTo(BoardState.attendance);
      machine.transitionTo(BoardState.summary);
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('full lifecycle: IDLE → PRE-FLIGHT → ATTENDANCE → SUMMARY → IDLE', () {
      machine.transitionTo(BoardState.preFlight);
      machine.transitionTo(BoardState.attendance);
      machine.transitionTo(BoardState.summary);
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('fire-and-forget path: IF session null go IDLE', () {
      machine.transitionTo(BoardState.preFlight);
      machine.transitionTo(BoardState.attendance);
      machine.forceTransitionTo(BoardState.summary);
      expect(machine.currentState, equals(BoardState.summary));
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('transition to same state is a no-op', () {
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('stateStream emits on valid transition', () async {
      final states = <BoardState>[];
      machine.stateStream.listen((s) => states.add(s));
      machine.transitionTo(BoardState.preFlight);
      await Future(() {});
      expect(states, equals([BoardState.preFlight]));
    });

    test('stateStream does NOT emit on invalid transition', () async {
      final states = <BoardState>[];
      machine.stateStream.listen((s) => states.add(s));
      machine.transitionTo(BoardState.attendance);
      await Future(() {});
      expect(states, isEmpty);
    });

    test('forceTransitionTo bypasses validation', () {
      machine.forceTransitionTo(BoardState.summary);
      expect(machine.currentState, equals(BoardState.summary));
    });
  });
}
