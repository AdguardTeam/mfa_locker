part of 'action_bloc.dart';

class BlocActionConsumer<B extends StateActionStreamable<S, A>, S, A> extends StatefulWidget {
  const BlocActionConsumer({
    super.key,
    required this.builder,
    required this.listener,
    this.bloc,
    this.buildWhen,
    this.listenWhen,
  });

  final B? bloc;
  final BlocWidgetBuilder<S> builder;
  final BlocActionWidgetListener<A> listener;
  final BlocBuilderCondition<S>? buildWhen;
  final BlocActionListenerCondition<A>? listenWhen;

  @override
  State<BlocActionConsumer<B, S, A>> createState() => _BlocActionConsumerState<B, S, A>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<B?>('bloc', bloc))
      ..add(ObjectFlagProperty<BlocWidgetBuilder<S>>.has('builder', builder))
      ..add(ObjectFlagProperty<BlocActionWidgetListener<A>>.has('listener', listener))
      ..add(
        ObjectFlagProperty<BlocBuilderCondition<S>?>.has(
          'buildWhen',
          buildWhen,
        ),
      )
      ..add(
        ObjectFlagProperty<BlocActionListenerCondition<A>?>.has(
          'listenWhen',
          listenWhen,
        ),
      );
  }
}

class _BlocActionConsumerState<B extends StateActionStreamable<S, A>, S, A> extends State<BlocActionConsumer<B, S, A>> {
  late B _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.read<B>();
  }

  @override
  void didUpdateWidget(BlocActionConsumer<B, S, A> oldWidget) {
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
      listenWhen: widget.listenWhen,
      listener: widget.listener,
      child: BlocBuilder<B, S>(
        bloc: _bloc,
        builder: widget.builder,
        buildWhen: (previous, current) => widget.buildWhen?.call(previous, current) ?? true,
      ),
    );
  }
}
