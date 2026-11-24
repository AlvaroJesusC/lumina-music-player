import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_motion.dart';
import 'music_library_page.dart';

/// Pantalla de bienvenida animada que se muestra brevemente al iniciar la app.
///
/// Respeta movimiento reducido, cancela su temporizador limpiamente al salir y
/// permite saltar instantáneamente con un toque en la pantalla.
class SplashScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;
  const SplashScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _autoNavigateTimer;
  bool _navigated = false;

  final List<String> _chunks = const [
    'Lumina,',
    'ilumina tu vida',
    'con música',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoNavigateTimer == null && !_navigated) {
      final isReduced = LuminaMotion.isReduced(context);
      final wait = isReduced
          ? const Duration(milliseconds: 350)
          : const Duration(milliseconds: 1900);
      _autoNavigateTimer = Timer(wait, _goToLibrary);
    }
  }

  void _goToLibrary() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _autoNavigateTimer?.cancel();
    _autoNavigateTimer = null;

    final isReduced = LuminaMotion.isReduced(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: isReduced
            ? Duration.zero
            : const Duration(milliseconds: 420),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MusicLibraryPage(
              themeMode: widget.themeMode,
              onThemeChanged: widget.onThemeChanged,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (isReduced) return child;
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _autoNavigateTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goToLibrary,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/iconoApp.png',
                width: 150,
                height: 150,
                cacheWidth: 300,
                cacheHeight: 300,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6.0,
                runSpacing: 4.0,
                children: List.generate(_chunks.length, (index) {
                  final double start = index / _chunks.length;
                  final double end = (start + 0.35).clamp(0.0, 1.0);

                  final Animation<double> slideAnimation =
                      Tween<double>(begin: 16.0, end: 0.0).animate(
                        CurvedAnimation(
                          parent: _controller,
                          curve: Interval(
                            start,
                            end,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      );

                  final Animation<double> opacityAnimation =
                      Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _controller,
                          curve: Interval(start, end, curve: Curves.easeIn),
                        ),
                      );

                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, slideAnimation.value),
                        child: Opacity(
                          opacity: opacityAnimation.value,
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      _chunks[index],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
