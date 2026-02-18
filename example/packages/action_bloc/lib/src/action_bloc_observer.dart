part of 'action_bloc.dart';

class ActionBlocObserver extends BlocObserver {
  @protected
  @mustCallSuper
  void onActionChange(BlocBase<dynamic> bloc, ActionChange<dynamic> change) {}
}

@immutable
class ActionChange<A> {
  const ActionChange({
    required this.currentAction,
    required this.nextAction,
  });

  final A? currentAction;
  final A nextAction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionChange<A> &&
          runtimeType == other.runtimeType &&
          currentAction == other.currentAction &&
          nextAction == other.nextAction;

  @override
  int get hashCode => currentAction.hashCode ^ nextAction.hashCode;

  @override
  String toString() => 'ActionChange { currentAction: $currentAction, nextAction: $nextAction }';
}
