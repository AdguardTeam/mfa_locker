import 'package:flutter/material.dart';
import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/di/dependency_scope.dart';
import 'package:mfa_demo/di/factories/bloc_factory.dart';
import 'package:mfa_demo/di/factories/repository_factory.dart';

extension DependencyContextExtension on BuildContext {
  RepositoryFactory get repositoryFactory => DependencyScope.getRepositoryFactory(this);

  BlocFactory get blocFactory => DependencyScope.getBlocFactory(this);

  TimerService get timerService => repositoryFactory.timerService;
}

extension NavigatorExtension on BuildContext {
  void pop<T extends Object?>({
    T? result,
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(this);
    if (scaffoldMessenger.mounted) {
      scaffoldMessenger.removeCurrentSnackBar();
    }

    Navigator.of(this).pop(result);
  }

  Future<T?> push<T extends Object?>(
    Widget widget, {
    RouteSettings? settings,
    bool rootNavigator = false,
    Widget Function(BuildContext context, Widget child)? builder,
  }) =>
      Navigator.of(
        this,
        rootNavigator: rootNavigator,
      ).push(
        MaterialPageRoute(
          settings: settings,
          builder: (context) {
            if (builder != null) {
              return builder(context, widget);
            }

            return widget;
          },
        ),
      );
}

extension SnackBarExtension on BuildContext {
  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(_shortenErrorMessage(message)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

String _shortenErrorMessage(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return 'Unexpected error';
  }

  final colonIndex = trimmed.indexOf(':');
  if (colonIndex != -1) {
    final beforeColon = trimmed.substring(0, colonIndex).trim();
    if (beforeColon.isNotEmpty) {
      return beforeColon;
    }
  }

  final sentenceEndIndex = trimmed.indexOf('.');
  if (sentenceEndIndex != -1) {
    final sentence = trimmed.substring(0, sentenceEndIndex).trim();
    if (sentence.isNotEmpty) {
      return sentence;
    }
  }

  return trimmed;
}
