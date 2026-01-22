part of 'action_bloc.dart';

class BlocActionStateConsumer<B extends StateActionStreamable<S, A>, S, A> extends StatefulWidget {
  const BlocActionStateConsumer({
    super.key,
    required this.builder,
    required this.stateListener,
    required this.actionListener,
    this.bloc,
    this.buildWhen,
    this.listenStateWhen,
    this.listenActionWhen,
  });

  final B? bloc;
  final BlocWidgetBuilder<S> builder;
  final BlocWidgetListener<S> stateListener;
  final BlocActionWidgetListener<A> actionListener;
  final BlocBuilderCondition<S>? buildWhen;
  final BlocListenerCondition<S>? listenStateWhen;
  final BlocActionListenerCondition<A>? listenActionWhen;

  @override
  State<BlocActionStateConsumer<B, S, A>> createState() => _BlocActionStateConsumerState<B, S, A>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<B?>('bloc', bloc))
      ..add(ObjectFlagProperty<BlocWidgetBuilder<S>>.has('builder', builder))
      ..add(ObjectFlagProperty<BlocWidgetListener<S>>.has('stateListener', stateListener))
      ..add(ObjectFlagProperty<BlocActionWidgetListener<A>>.has('actionListener', actionListener))
      ..add(
        ObjectFlagProperty<BlocBuilderCondition<S>?>.has(
          'buildWhen',
          buildWhen,
        ),
      )
      ..add(
        ObjectFlagProperty<BlocListenerCondition<S>?>.has(
          'listenStateWhen',
          listenStateWhen,
        ),
      )
      ..add(
        ObjectFlagProperty<BlocActionListenerCondition<A>?>.has(
          'listenActionWhen',
          listenActionWhen,
        ),
      );
  }
}

class _BlocActionStateConsumerState<B extends StateActionStreamable<S, A>, S, A>
    extends State<BlocActionStateConsumer<B, S, A>> {
  late B _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.read<B>();
  }

  @override
  void didUpdateWidget(BlocActionStateConsumer<B, S, A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBloc = oldWidget.bloc ?? context.read<B>();
    final currentBloc = widget.bloc ?? oldBloc;
    if (oldBloc != currentBloc) _bloc = currentBloc;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bloc = widget.bloc ?? context.read<B>();
    if (_bloc != bloc) _bloc = bloc;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bloc == null) {
      context.select<B, bool>((bloc) => identical(_bloc, bloc));
    }
    return BlocActionListener<B, S, A>(
      listenWhen: widget.listenActionWhen,
      listener: widget.actionListener,
      child: BlocBuilder<B, S>(
        bloc: _bloc,
        builder: widget.builder,
        buildWhen: (previous, current) {
          if (widget.listenStateWhen?.call(previous, current) ?? true) {
            widget.stateListener(context, current);
          }
          return widget.buildWhen?.call(previous, current) ?? true;
        },
      ),
    );
  }
}
