import 'dart:async';
import '../utils/logger.dart';

enum BoardState { idle, preparing, igniting, active, closed }

class BoardStateMachine {
  BoardStateMachine._();

  static final BoardStateMachine _instance = BoardStateMachine._();
  factory BoardStateMachine() => _instance;

  BoardState _state = BoardState.idle;
  final StreamController<BoardState> _stateController =
      StreamController<BoardState>.broadcast();

  Stream<BoardState> get stateStream => _stateController.stream;
  BoardState get currentState => _state;

  bool _allowTransition(BoardState from, BoardState to) {
    switch (from) {
      case BoardState.idle:
        return to == BoardState.preparing;
      case BoardState.preparing:
        return to == BoardState.igniting || to == BoardState.idle;
      case BoardState.igniting:
        return to == BoardState.active || to == BoardState.idle;
      case BoardState.active:
        return to == BoardState.closed || to == BoardState.idle;
      case BoardState.closed:
        return to == BoardState.idle;
    }
  }

  void transitionTo(BoardState newState) {
    if (_state == newState) return;

    if (!_allowTransition(_state, newState)) {
      Log.w('[StateMachine] Illegal: ${_state.name} -> ${newState.name} rejected');
      return;
    }

    Log.i('[StateMachine] ${_state.name} -> ${newState.name}');
    _state = newState;
    _stateController.add(_state);
  }

  void forceTransitionTo(BoardState newState) {
    if (_state == newState) return;
    Log.i('[StateMachine] Forced: ${_state.name} -> ${newState.name}');
    _state = newState;
    _stateController.add(_state);
  }

  void reset() {
    _state = BoardState.idle;
    _stateController.add(_state);
  }

  void dispose() {
    _stateController.close();
  }
}
