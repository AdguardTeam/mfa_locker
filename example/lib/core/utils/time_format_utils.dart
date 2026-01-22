import 'package:mfa_demo/core/constants/app_constants.dart';

class TimeFormatUtils {
  static String formatLockTimeout(Duration duration) {
    if (duration == AppConstants.lockTimeoutDisabledDuration) {
      return 'Never';
    }

    final minutes = duration.inMinutes;

    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }
}
