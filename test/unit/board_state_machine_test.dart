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

    test('IDLE -> PREPARING is valid', () {
      machine.transitionTo(BoardState.preparing);
      expect(machine.currentState, equals(BoardState.preparing));
    });

    test('IDLE -> IGNITING is invalid (must go through PREPARING)', () {
      machine.transitionTo(BoardState.igniting);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('IDLE -> ACTIVE is invalid', () {
      machine.transitionTo(BoardState.active);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('IDLE -> CLOSED is invalid', () {
      machine.transitionTo(BoardState.closed);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('PREPARING -> IGNITING is valid', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.igniting);
      expect(machine.currentState, equals(BoardState.igniting));
    });

    test('PREPARING -> IDLE is valid (abort)', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('IGNITING -> ACTIVE is valid', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.igniting);
      machine.transitionTo(BoardState.active);
      expect(machine.currentState, equals(BoardState.active));
    });

    test('ACTIVE -> CLOSED is valid', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.igniting);
      machine.transitionTo(BoardState.active);
      machine.transitionTo(BoardState.closed);
      expect(machine.currentState, equals(BoardState.closed));
    });

    test('CLOSED -> IDLE is valid', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.igniting);
      machine.transitionTo(BoardState.active);
      machine.transitionTo(BoardState.closed);
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('full lifecycle: IDLE -> PREPARING -> IGNITING -> ACTIVE -> CLOSED -> IDLE', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.igniting);
      machine.transitionTo(BoardState.active);
      machine.transitionTo(BoardState.closed);
      machine.transitionTo(BoardState.idle);
      expect(machine.currentState, equals(BoardState.idle));
    });

    test('fire-and-forced: force to CLOSED from ACTIVE', () {
      machine.transitionTo(BoardState.preparing);
      machine.transitionTo(BoardState.igniting);
      machine.transitionTo(BoardState.active);
      machine.forceTransitionTo(BoardState.closed);
      expect(machine.currentState, equals(BoardState.closed));
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
      machine.transitionTo(BoardState.preparing);
      await Future(() {});
      expect(states, equals([BoardState.preparing]));
    });

    test('stateStream does NOT emit on invalid transition', () async {
      final states = <BoardState>[];
      machine.stateStream.listen((s) => states.add(s));
      machine.transitionTo(BoardState.active);
      await Future(() {});
      expect(states, isEmpty);
    });

    test('forceTransitionTo bypasses validation', () {
      machine.forceTransitionTo(BoardState.active);
      expect(machine.currentState, equals(BoardState.active));
    });
  });
}
