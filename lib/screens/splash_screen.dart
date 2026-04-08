import 'package:flutter/material.dart';
import 'music_library_page.dart';

/// Pantalla de bienvenida animada que se muestra al iniciar la app.
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
  late AnimationController _controller;
  final List<String> _chunks = [
    "Lumina,",
    "ilumina tu vida",
    "con música",
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MusicLibraryPage(
              themeMode: widget.themeMode,
              onThemeChanged: widget.onThemeChanged,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black87;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/iconoApp.png', width: 150, height: 150),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6.0,
              runSpacing: 4.0,
              children: List.generate(_chunks.length, (index) {
                final double start = index / _chunks.length;
                final double end = (start + 0.2).clamp(0.0, 1.0);

                final Animation<double> slideAnimation =
                    Tween<double>(begin: 20.0, end: 0.0).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Interval(start, end, curve: Curves.easeOutCubic),
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
                      color: color.withValues(alpha: 0.8),
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
