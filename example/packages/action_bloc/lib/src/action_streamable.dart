part of 'action_bloc.dart';

abstract class ActionStreamable<T> {
  Stream<T> get actions;
}

abstract class StateActionStreamable<S, A> implements StateStreamable<S>, ActionStreamable<A> {}
