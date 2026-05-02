import 'package:flutter/material.dart';
import '../providers/language_provider.dart';

/// Splash screen that shows logo while app is initializing
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.languageProvider,
    required this.onLoginSuccess,
    required this.isLoggedIn,
    required this.onSplashComplete,
  });

  final LanguageProvider languageProvider;
  final VoidCallback onLoginSuccess;
  final bool isLoggedIn;
  final VoidCallback onSplashComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    // Animasyon bitsin + en az kısa bir süre (önceki sabit 2 sn yerine max(animasyon, ~800ms))
    await Future.wait([
      _controller.forward(),
      Future<void>.delayed(const Duration(milliseconds: 800)),
    ]);

    if (!mounted) return;

    widget.onSplashComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF48631F), // Uygulama ana rengi
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Image.asset(
            'assets/images/logoCo2.png',
            width: 200,
            height: 200,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // Logo yüklenemezse alternatif göster
              return const Icon(
                Icons.eco,
                size: 200,
                color: Colors.white,
              );
            },
          ),
        ),
      ),
    );
  }
}
