import 'dart:async';

/// Marks a `withTransaction` body with its owner so reentrant calls fail instead
/// of deadlocking on the lane; the marker survives awaits inside the body.
abstract final class TransactionZone {
  static final Object _key = Object();

  static Future<R> run<R>(Object owner, Future<R> Function() body) =>
      runZoned<Future<R>>(body, zoneValues: {_key: owner});

  static Object? get current => Zone.current[_key];
}
