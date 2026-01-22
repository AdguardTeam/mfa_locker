import 'package:flutter/material.dart';
import 'package:mfa_demo/di/factories/bloc_factory.dart';
import 'package:mfa_demo/di/factories/repository_factory.dart';

class DependencyScope extends StatefulWidget {
  final RepositoryFactory repositoryFactory;
  final BlocFactory blocFactory;
  final Widget child;

  const DependencyScope({
    super.key,
    required this.repositoryFactory,
    required this.blocFactory,
    required this.child,
  });

  @override
  State<DependencyScope> createState() => _DependencyScopeState();

  static BlocFactory getBlocFactory(BuildContext context) => _scopeOf(context).blocFactory;

  static RepositoryFactory getRepositoryFactory(BuildContext context) => _scopeOf(context).repositoryFactory;

  static DependencyScope _scopeOf(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<_InheritedDependencyScope>()!.widget
              as _InheritedDependencyScope)
          .state
          .widget;
}

class _DependencyScopeState extends State<DependencyScope> {
  @override
  Widget build(BuildContext context) => _InheritedDependencyScope(
    state: this,
    child: widget.child,
  );

  @override
  void dispose() {
    super.dispose();
  }
}

class _InheritedDependencyScope extends InheritedWidget {
  final _DependencyScopeState state;

  const _InheritedDependencyScope({
    required super.child,
    required this.state,
  });

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}
