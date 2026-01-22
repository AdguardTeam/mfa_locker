part of 'action_bloc.dart';

typedef BlocActionWidgetListenerWithState<S, A> = void Function(BuildContext context, S state, A action);
typedef BlocActionWidgetListener<A> = void Function(BuildContext context, A action);
typedef BlocActionListenerCondition<A> = bool Function(A? previous, A current);

class BlocActionListener<B extends StateActionStreamable<S, A>, S, A> extends BlocActionListenerBase<B, S, A> {
  const BlocActionListener({
    super.key,
    required BlocActionWidgetListener<A> listener,
    super.bloc,
    super.listenWhen,
    super.child,
  }) : super(listener: listener);

  const BlocActionListener.withState({
    super.key,
    required BlocActionWidgetListenerWithState<S, A> listener,
    super.bloc,
    super.listenWhen,
    super.child,
  }) : super(listenerWithState: listener);
}

abstract class BlocActionListenerBase<B extends StateActionStreamable<S, A>, S, A> extends StatefulWidget {
  const BlocActionListenerBase({
    this.listener,
    this.listenerWithState,
    super.key,
    this.bloc,
    this.child,
    this.listenWhen,
  });

  final Widget? child;
  final B? bloc;
  final BlocActionWidgetListener<A>? listener;
  final BlocActionWidgetListenerWithState<S, A>? listenerWithState;
  final BlocActionListenerCondition<A>? listenWhen;

  @override
  State<BlocActionListenerBase<B, S, A>> createState() => _BlocActionListenerBaseState<B, S, A>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<B?>('bloc', bloc))
      ..add(ObjectFlagProperty<BlocActionWidgetListener<A>>.has('listener', listener))
      ..add(ObjectFlagProperty<BlocActionWidgetListenerWithState<S, A>>.has('listenerWithState', listenerWithState))
      ..add(
        ObjectFlagProperty<BlocListenerCondition<A>?>.has(
          'listenWhen',
          listenWhen,
        ),
      );
  }
}

class _BlocActionListenerBaseState<B extends StateActionStreamable<S, A>, S, A>
    extends State<BlocActionListenerBase<B, S, A>> {
  StreamSubscription<A>? _subscription;
  late B _bloc;
  A? _previousAction;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.read<B>();
    _subscribe();
  }

  @override
  void didUpdateWidget(BlocActionListenerBase<B, S, A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBloc = oldWidget.bloc ?? context.read<B>();
    final newBloc = widget.bloc ?? context.read<B>();
    if (oldBloc != newBloc) {
      _subscription?.cancel();
      _bloc = newBloc;
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bloc == null) {
      context.select<B, bool>((bloc) => identical(_bloc, bloc));
    }

    return widget.child ?? const SizedBox.shrink();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription = _bloc.actions.listen((action) {
      if (widget.listenWhen?.call(_previousAction, action) ?? true) {
        if (mounted) {
          widget.listener?.call(context, action);
          widget.listenerWithState?.call(context, _bloc.state, action);
        }
      }
      _previousAction = action;
    });
  }
}
