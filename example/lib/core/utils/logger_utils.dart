import 'package:adguard_logger/adguard_logger.dart';
import 'package:mfa_demo/core/utils/log_storage_path_util.dart';

class LoggerUtils {
  static void initializeConsoleLogAppender(Logger logger) => ConsoleLogAppender().attachToLogger(logger);

  static Future<FileLogAppender> initializeFileLogAppender(Logger logger) async {
    try {
      final filePath = await LogStoragePathUtil.getLogFileStoragePath();

      logger.logInfo('File log path: $filePath');

      final fileAppender = FileLogAppender(
        filePath: filePath,
        logStorage: FileLogStorage(
          formatter: SpacedLoggerFormatter(),
        ),
        rotationFileController: RotationFileController(),
      );

      fileAppender.attachToLogger(logger);

      logger.logInfo(_logSessionHeader());

      return fileAppender;
    } catch (e, s) {
      logger.logError(
        'Failed to initialize FileLogAppender',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  static String _logSessionHeader() {
    final now = DateTime.now().toIso8601String();

    return '======= Log session started at $now =======';
  }

  const LoggerUtils._();
}

class SpacedLoggerFormatter extends DataLoggerFormatter {
  @override
  String format(LogRecord rec) => '\n${super.format(rec)}';
}
