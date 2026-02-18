import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'action_bloc_observer.dart';
part 'action_streamable.dart';
part 'bloc_action_consumer.dart';
part 'bloc_action_listener.dart';
part 'bloc_action_state_consumer.dart';

abstract class ActionBloc<E, S, A> extends Bloc<E, S> implements StateActionStreamable<S, A> {
  ActionBloc(super.initialState);

  final _blocObserver = Bloc.observer;
  final _actionStreamController = StreamController<A>.broadcast();
  A? _currentAction;

  @override
  Stream<A> get actions => _actionStreamController.stream;

  @mustCallSuper
  @override
  Future<void> close() async {
    await disposeActions();
    return super.close();
  }

  void action(A action) {
    if (_actionStreamController.isClosed) {
      throw StateError('Cannot emit new actions after calling close');
    }

    if (_blocObserver is ActionBlocObserver) {
      _blocObserver.onActionChange(this, ActionChange<A>(currentAction: _currentAction, nextAction: action));
    }

    _actionStreamController.add(action);
    _currentAction = action;
  }

  Future<void> disposeActions() => _actionStreamController.close();
}
