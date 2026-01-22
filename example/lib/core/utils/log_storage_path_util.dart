import 'dart:io';

import 'package:mfa_demo/core/utils/app_version_utils.dart';
import 'package:path_provider/path_provider.dart';

class LogStoragePathUtil {
  static Future<String> getLogFileStoragePath() async {
    try {
      const fileName = 'mfa_locker.demo_app';

      late final Directory directory;

      if (Platform.isWindows) {
        const directoryName = 'Logs';
        final appName = await AppVersionUtils.getAppName();
        directory = await _getOrCreateWindowsDirectory(directoryName: directoryName, appName: appName);
      } else {
        directory = await getApplicationSupportDirectory();
      }

      return '${directory.path}${Platform.pathSeparator}$fileName';
    } catch (e) {
      throw Exception('Failed to get log file storage path: $e');
    }
  }

  static Future<Directory> _getOrCreateWindowsDirectory({
    required String directoryName,
    required String appName,
  }) async {
    try {
      final programDataPath = Platform.environment['AppData'];

      final path = [
        programDataPath,
        appName,
        directoryName,
      ].join(Platform.pathSeparator);

      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      return directory;
    } catch (e) {
      throw Exception('Failed to get windows log file storage path: $e');
    }
  }

  const LogStoragePathUtil._();
}
