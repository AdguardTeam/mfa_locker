// Re-export of the plugin's platform-support predicate: the plugin owns the
// fact, so consumers of `locker` can ask it without depending on
// `biometric_cipher` directly.
export 'package:biometric_cipher/data/platform_support.dart';
