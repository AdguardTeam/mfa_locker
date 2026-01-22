import 'package:flutter/material.dart';

/// A wrapper that detects when modal bottom sheet animation completes.
///
/// Use to trigger actions (like biometric auth) only after the sheet is fully
/// visible, without relying on hardcoded delays.
class AnimationAwareBottomSheet extends StatefulWidget {
  /// The child widget to display inside the bottom sheet.
  final Widget child;

  /// Called when the bottom sheet entrance animation completes.
  /// This is guaranteed to be called only once per bottom sheet instance.
  final VoidCallback? onAnimationComplete;

  const AnimationAwareBottomSheet({
    super.key,
    required this.child,
    this.onAnimationComplete,
  });

  @override
  State<AnimationAwareBottomSheet> createState() => _AnimationAwareBottomSheetState();
}

class _AnimationAwareBottomSheetState extends State<AnimationAwareBottomSheet> {
  bool _hasNotifiedAnimationComplete = false;
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToAnimation();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _animation?.removeStatusListener(_onAnimationStatusChanged);
    super.dispose();
  }

  void _subscribeToAnimation() {
    // Avoid re-subscribing if already done
    if (_animation != null) {
      return;
    }

    final route = ModalRoute.of(context);
    if (route == null) {
      return;
    }

    _animation = route.animation;
    _animation?.addStatusListener(_onAnimationStatusChanged);

    // Check if animation is already complete (e.g., if widget rebuilds after animation finished)
    if (_animation?.status == AnimationStatus.completed) {
      _notifyAnimationComplete();
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _notifyAnimationComplete();
    }
  }

  void _notifyAnimationComplete() {
    if (_hasNotifiedAnimationComplete) {
      return;
    }

    _hasNotifiedAnimationComplete = true;

    // Use post-frame callback to ensure the widget tree is stable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onAnimationComplete?.call();
      }
    });
  }
}
