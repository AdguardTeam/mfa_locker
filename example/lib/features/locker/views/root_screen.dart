import 'package:action_bloc/action_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/core/utils/fullscreen_listener.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/views/auth/biometric_setup_screen.dart';
import 'package:mfa_demo/features/locker/views/auth/init_password_screen.dart';
import 'package:mfa_demo/features/locker/views/auth/locked_screen.dart';
import 'package:mfa_demo/features/locker/views/auth/not_initialized_screen.dart';
import 'package:mfa_demo/features/locker/views/storage/init_entry_screen.dart';
import 'package:mfa_demo/features/locker/views/storage/unlocked_screen.dart';
import 'package:mfa_demo/features/locker/views/widgets/loading_screen.dart';

/// State machine for tracking macOS full-screen transitions.
enum _FullScreenState {
  /// Not in a full-screen transition.
  none,

  /// During full-screen transition (after willEnter/willExit, before didEnter/didExit).
  transitioning,

  /// After windowDidExitFullScreen, waiting for final `resumed` state.
  /// macOS triggers a second lifecycle sequence after this callback.
  awaitingFinalResumed,
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  bool _lockedPopupPushed = false;
  var _fullScreenState = _FullScreenState.none;
  late final FullscreenListener _fullscreenListener;

  bool get _isFullScreenTransitioning => _fullScreenState != _FullScreenState.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fullscreenListener = FullscreenListener(
      onTransitionStart: () => _fullScreenState = _FullScreenState.transitioning,
      onTransitionEnd: () => _fullScreenState = _FullScreenState.none,
      onExitComplete: () => _fullScreenState = _FullScreenState.awaitingFinalResumed,
    )..init();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _onActivity(),
    child: BlocListener<LockerBloc, LockerState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        if (state.status == LockerStatus.locked && !_lockedPopupPushed) {
          _lockedPopupPushed = true;
          showGeneralDialog(
            context: context,
            pageBuilder: (ctx, _, _) => const PopScope(
              canPop: false,
              child: LockedScreen(),
            ),
          );
        } else if (state.status == LockerStatus.unlocked && _lockedPopupPushed) {
          context.pop();
          _lockedPopupPushed = false;
        }
      },
      child: BlocActionConsumer<LockerBloc, LockerState, LockerAction>(
        listener: (context, action) {
          action.mapOrNull(
            showError: (value) => context.showErrorSnackBar(value.message),
            showSuccess: (value) => context.showSuccessSnackBar(value.message),
          );
        },
        buildWhen: (prev, curr) => prev.status != curr.status,
        builder: (context, state) => switch (state.status) {
          LockerStatus.initializing => const LoadingScreen(),
          LockerStatus.notInitialized => const NotInitializedScreen(),
          LockerStatus.settingPassword => const InitPasswordScreen(),
          LockerStatus.offeringBiometric => const BiometricSetupScreen(),
          LockerStatus.settingInitialEntry => const InitEntryScreen(),
          LockerStatus.locked => const LoadingScreen(),
          LockerStatus.unlocked => const UnlockedScreen(),
        },
      ),
    ),
  );

  @override
  void dispose() {
    _fullscreenListener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After windowDidExitFullScreen, wait for the final `resumed` state
    // to clear the transition flag. macOS triggers a second lifecycle
    // sequence after the callback.
    if (state == AppLifecycleState.resumed && _fullScreenState == _FullScreenState.awaitingFinalResumed) {
      _fullScreenState = _FullScreenState.none;

      return;
    }

    // Skip lock during macOS full-screen transitions.
    if (_isFullScreenTransitioning) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      context.read<LockerBloc>().add(const LockerEvent.appResumed());
    }
  }

  void _onActivity() {
    context.read<LockerBloc>().add(const LockerEvent.activityDetected());
  }
}
