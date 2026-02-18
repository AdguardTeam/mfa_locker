import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EntryRevealScreen extends StatefulWidget {
  final String entryName;
  final String entryValue;

  const EntryRevealScreen({
    super.key,
    required this.entryName,
    required this.entryValue,
  });

  @override
  State<EntryRevealScreen> createState() => _EntryRevealScreenState();
}

class _EntryRevealScreenState extends State<EntryRevealScreen> with TickerProviderStateMixin {
  static const _revealDuration = Duration(milliseconds: 1500);
  static const _copyResetDelay = Duration(seconds: 2);
  static const _clipboardClearSeconds = 30;
  static const _clipboardClearedMessageSeconds = 3;
  static const _skipRevealThreshold = 0.08;
  static const _skipRevealActivationDelay = Duration(milliseconds: 220);
  static const _glyphChars = '░▒▓█▄▀╬◆●◈◉◊▪▫▸▹►▻';

  late final AnimationController _revealController;
  late final AnimationController _copyController;

  final Random _random = Random();
  Timer? _clipboardTimer;
  Timer? _skipActivationTimer;

  bool _copied = false;
  bool _clipboardActive = false;
  bool _clipboardCleared = false;
  int _clipboardSecondsLeft = _clipboardClearSeconds;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: _revealDuration,
      animationBehavior: AnimationBehavior.preserve,
    );
    _copyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRevealIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context)?.animation?.addStatusListener(_onRouteAnimationStatus);
    _startRevealIfNeeded();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0D0D),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0D0D0D),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              widget.entryName,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTapDown: (_) => _onRevealValueTapped(),
                  child: AnimatedBuilder(
                    animation: _revealController,
                    builder: (context, _) => Text(
                      _buildDisplayValue(_revealController.value),
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 17,
                        fontFamily: 'monospace',
                        letterSpacing: 1.5,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _CopyButton(
              controller: _copyController,
              copied: _copied,
              onPressed: _onCopyPressed,
            ),
            const SizedBox(height: 16),
            _ClipboardStatus(
              active: _clipboardActive,
              cleared: _clipboardCleared,
              secondsLeft: _clipboardSecondsLeft,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _revealController.dispose();
    _copyController.dispose();
    _clipboardTimer?.cancel();
    _skipActivationTimer?.cancel();
    super.dispose();
  }

  String _buildDisplayValue(double progress) {
    final value = widget.entryValue;
    if (value.isEmpty) {
      return '';
    }
    final revealedCount = (progress * value.length).floor();
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i < revealedCount) {
        buffer.write(value[i]);
      } else {
        buffer.write(_glyphChars[_random.nextInt(_glyphChars.length)]);
      }
    }

    return buffer.toString();
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startRevealIfNeeded();
    }
  }

  void _startRevealIfNeeded() {
    if (!mounted) {
      return;
    }
    final routeAnimation = ModalRoute.of(context)?.animation;
    final isRouteReady = routeAnimation == null || routeAnimation.status == AnimationStatus.completed;
    if (!isRouteReady || _revealController.isAnimating || _revealController.value > 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _revealController.forward(from: 0.0);
    });
  }

  void _onRevealValueTapped() {
    if (_revealController.value < _skipRevealThreshold) {
      _skipActivationTimer?.cancel();
      _skipActivationTimer = Timer(_skipRevealActivationDelay, () {
        if (!mounted) {
          return;
        }
        _revealController.value = 1.0;
        _revealController.stop();
      });

      return;
    }
    _revealController.value = 1.0;
    _revealController.stop();
  }

  void _onCopyPressed() {
    unawaited(_performCopy());
  }

  Future<void> _performCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.entryValue));
    if (!mounted) {
      return;
    }
    setState(() {
      _copied = true;
      _clipboardActive = true;
      _clipboardCleared = false;
      _clipboardSecondsLeft = _clipboardClearSeconds;
    });
    unawaited(_copyController.forward(from: 0.0));

    _clipboardTimer?.cancel();
    _clipboardTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();

        return;
      }
      setState(() {
        _clipboardSecondsLeft--;
      });
      if (_clipboardSecondsLeft <= 0) {
        timer.cancel();
        unawaited(_clearClipboard());
      }
    });

    await Future<void>.delayed(_copyResetDelay);
    if (!mounted) {
      return;
    }
    setState(() {
      _copied = false;
    });
    unawaited(_copyController.reverse());
  }

  Future<void> _clearClipboard() async {
    await Clipboard.setData(const ClipboardData(text: ''));
    if (!mounted) {
      return;
    }
    setState(() {
      _clipboardActive = false;
      _clipboardCleared = true;
    });
    await Future<void>.delayed(const Duration(seconds: _clipboardClearedMessageSeconds));
    if (!mounted) {
      return;
    }
    setState(() {
      _clipboardCleared = false;
    });
  }
}

class _CopyButton extends StatelessWidget {
  final AnimationController controller;
  final bool copied;
  final VoidCallback onPressed;

  const _CopyButton({
    required this.controller,
    required this.copied,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final color = Color.lerp(const Color(0xFF1E88E5), const Color(0xFF2E7D32), controller.value)!;

      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: onPressed,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: copied
                ? const Icon(Icons.check, key: ValueKey('check'), color: Colors.white)
                : const Icon(Icons.copy, key: ValueKey('copy'), color: Colors.white),
          ),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              copied ? 'Copied!' : 'Copy',
              key: ValueKey(copied),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      );
    },
  );
}

class _ClipboardStatus extends StatelessWidget {
  final bool active;
  final bool cleared;
  final int secondsLeft;

  const _ClipboardStatus({
    required this.active,
    required this.cleared,
    required this.secondsLeft,
  });

  @override
  Widget build(BuildContext context) {
    if (cleared) {
      return const Text(
        'Clipboard cleared',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
    }
    if (!active) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: secondsLeft / _ClipboardStatus._totalSeconds,
            strokeWidth: 2,
            color: Colors.white38,
            backgroundColor: Colors.white12,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Clipboard clears in ${secondsLeft}s',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  static const _totalSeconds = 30;
}
