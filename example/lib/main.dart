import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/core/utils/logger_utils.dart';
import 'package:mfa_demo/core/utils/macos_init.dart';
import 'package:mfa_demo/di/dependency_scope.dart';
import 'package:mfa_demo/di/factories/bloc_factory.dart';
import 'package:mfa_demo/di/factories/repository_factory.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/views/root_screen.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final logger = Logger();
  LoggerUtils.initializeConsoleLogAppender(logger);

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize macOS window delegate support for full-screen detection
      await initMacOS();

      // Get storage file path
      final appDir = await getApplicationDocumentsDirectory();
      final storageFilePath = '${appDir.path}/${AppConstants.storageFileName}';

      // Create factories
      final repositoryFactory = RepositoryFactoryImpl(
        storageFilePath: storageFilePath,
      );

      await repositoryFactory.init();

      final blocFactory = BlocFactoryImpl(
        lockerRepository: repositoryFactory.lockerRepository,
        timerService: repositoryFactory.timerService,
      );

      runApp(
        DependencyScope(
          repositoryFactory: repositoryFactory,
          blocFactory: blocFactory,
          child: const MainApp(),
        ),
      );
    },
    zoneValues: {
      Logger.loggerKey: logger,
    },
    (error, stackTrace) => logger.logError(
      'Error captured in main zone',
      error: error,
      stackTrace: stackTrace,
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => context.blocFactory.lockerBloc..add(const LockerEvent.checkInitializationStatus()),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MFA Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    ),
  );
}
