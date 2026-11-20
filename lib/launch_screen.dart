import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key, required this.child});

  final Widget child;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _markScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleOffset;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onIntroStatus);
    _markScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.07,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.07,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 58,
      ),
    ]).animate(_intro);
    final titleEntry = CurveTween(
      curve: const Interval(.1, .45, curve: Curves.easeOut),
    );
    _titleOpacity = titleEntry.animate(_intro);
    _titleOffset = Tween(
      begin: const Offset(0, .24),
      end: Offset.zero,
    ).chain(titleEntry).animate(_intro);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _intro.forward();
    });
  }

  void _onIntroStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) setState(() {});
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_intro.isCompleted) return widget.child;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final mark = Image.asset(
      'assets/brand/molecule.png',
      width: 114,
      height: 114,
      excludeFromSemantics: true,
    );
    const title = Text(
      'Swifty Protein',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: brandIvory,
        fontSize: 23,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: brandPine,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 48),
                  reduceMotion
                      ? mark
                      : ScaleTransition(scale: _markScale, child: mark),
                  const SizedBox(height: 20),
                  reduceMotion
                      ? title
                      : FadeTransition(
                          opacity: _titleOpacity,
                          child: SlideTransition(
                            position: _titleOffset,
                            child: title,
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
