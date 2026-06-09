import 'package:flutter/material.dart';
// Platform kontrolleri yerine ekran boyutu ile karar vereceğiz; ek ithalat yok
import 'dart:ui' show ImageFilter;

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'themes/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_nav.dart';
import 'providers/language_provider.dart';
import 'localization/translations.dart';
import 'services/postgres_service.dart';
import 'services/firebase_realtime_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_auth_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseRealtimeService.instance.initialize();
    debugPrint('Firebase başarıyla başlatıldı');
  } catch (e) {
    debugPrint('Firebase başlatma hatası: $e');
    if (Firebase.apps.isNotEmpty) {
      try {
        FirebaseRealtimeService.instance.initialize();
      } catch (initError) {
        debugPrint('Firebase Realtime init hatası: $initError');
      }
    }
  }

  runApp(const CarbonFootprintApp());

  // İlk frame çizildikten sonra: açılışı bloklamaz; bildirim + opsiyonel API health.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.instance.initialize().catchError((_) {});
    PostgresService.instance.connect().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint(
          'PostgreSQL bağlantısı zaman aşımına uğradı (devam ediliyor)',
        );
      },
    ).catchError((e) {
      debugPrint('PostgreSQL bağlantı hatası: $e');
    });
  });
}

/// Root widget configuring Material 3, theming, and bottom navigation.
class CarbonFootprintApp extends StatefulWidget {
  const CarbonFootprintApp({super.key});

  @override
  State<CarbonFootprintApp> createState() => _CarbonFootprintAppState();
}

class _CarbonFootprintAppState extends State<CarbonFootprintApp>
    with WidgetsBindingObserver {
  static const String _kThemePrefKey = 'app_theme_mode';

  // Dialog ve sayfa geçişleri için güvenli Navigator erişimi
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ThemeMode _themeMode = ThemeMode.system;
  int _selectedIndex = 0;
  final LanguageProvider _languageProvider = LanguageProvider();
  bool _isLoggedIn = false; // Login durumu
  bool _showSplash = true; // Splash screen gösterimi

  /// Ayarlardaki anahtar ile MaterialApp’ın gerçekten kullandığı tema uyumlu olsun.
  /// `ThemeMode.system` iken OS karanlıksa true döner (önceki `_themeMode == dark` hatayı giderir).
  bool get _effectiveIsDark {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _languageProvider.initialize();
    _loadThemePreference();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system) {
      setState(() {});
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kThemePrefKey);
      if (!mounted || saved == null) return;
      setState(() {
        switch (saved) {
          case 'dark':
            _themeMode = ThemeMode.dark;
            break;
          case 'light':
            _themeMode = ThemeMode.light;
            break;
          case 'system':
            _themeMode = ThemeMode.system;
            break;
        }
      });
    } catch (_) {}
  }

  void _toggleThemeMode(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_kThemePrefKey, isDark ? 'dark' : 'light');
    });
  }

  double _responsiveTextScaleForWidth(double width) {
    if (width < 360) return 0.90;
    if (width < 480) return 0.95;
    if (width < 768) return 1.00;
    if (width < 1100) return 1.04;
    return 1.08;
  }

  void _handleLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
    });
  }

  void _handleLogout() {
    final BuildContext? navContext = _navigatorKey.currentContext;
    if (navContext != null) {
      final navigator = Navigator.of(navContext);
      // Ayarlar paneli (showGeneralDialog) açıksa kapat
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
    FirebaseAuthService.instance.signOut().catchError((_) {});
    setState(() {
      _isLoggedIn = false;
      _selectedIndex = 0;
    });
  }

  void _handleSplashComplete() {
    setState(() {
      _showSplash = false;
    });
  }

  void _onItemTapped(int index) {
    // Ayarlar ikonu: küçük ekranlarda sağdan açılan panel olarak göster
    final double width = MediaQuery.of(context).size.width;
    final bool isCompactLayout = width < 1100;
    final bool isSettingsIndex = index == 3 && isCompactLayout;

    if (isSettingsIndex) {
      _openSettingsSheet();
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _openSettingsSheet() async {
    // MaterialApp altındaki Navigator'ın context'i ile aç
    final BuildContext? navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final theme = Theme.of(navContext);
    await showGeneralDialog(
      context: navContext,
      barrierDismissible: true,
      barrierLabel: 'Ayarlar',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      pageBuilder: (context, anim1, anim2) {
        final size = MediaQuery.of(context).size;
        // İçeriğe daha yakın panel genişliği: web'de kenar boşluğu azaltılır.
        final double panelWidth = size.width < 600
            ? size.width * 0.92
            : (size.width * 0.62).clamp(620.0, 860.0).toDouble();
        return Align(
          alignment: Alignment.centerRight,
          child: AnimatedBuilder(
            animation: anim1,
            builder: (context, child) {
              return FractionalTranslation(
                translation: Offset(1 - anim1.value, 0),
                child: child,
              );
            },
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    width: panelWidth,
                    height: size.height,
                    color: theme.colorScheme.primary.withValues(alpha: 0.18),
                    child: SettingsScreen(
                      isDarkMode: _effectiveIsDark,
                      onToggleTheme: _toggleThemeMode,
                      transparentBackground: true,
                      languageProvider: _languageProvider,
                      onLogout: _handleLogout,
                      onNavigationRequested: (index) {
                        // Dialog'u kapat
                        Navigator.of(navContext).pop();
                        // Seçili index'i güncelle
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secAnim, child) {
        return FadeTransition(opacity: anim, child: child);
      },
      transitionDuration: const Duration(milliseconds: 260),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.buildThemeData(ThemeMode.light);
    final darkTheme = AppTheme.buildThemeData(ThemeMode.dark);

    // Platform ve ekran tabanlı belirleme
    final double width = MediaQuery.of(context).size.width;
    // Genişlik < 1100: alt [NavigationBar] (telefon, çoğu tablet dikey/yatay, dar web).
    // Örn. iPad (768–1024) ve Surface tabletlerde alt çubuk görünür; ≥1100 geniş Masaüstü/Web’de üst menü.
    final bool isCompactLayout = width < 1100;

    final pages = <Widget>[
      HomeScreen(
        onToggleTheme: _toggleThemeMode,
        themeMode: _themeMode,
        languageProvider: _languageProvider,
      ),
      ReportsScreen(languageProvider: _languageProvider),
      GoalsScreen(languageProvider: _languageProvider),
      if (isCompactLayout)
        SettingsScreen(
          isDarkMode: _effectiveIsDark,
          onToggleTheme: _toggleThemeMode,
          languageProvider: _languageProvider,
          onLogout: _handleLogout,
          onNavigationRequested: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
    ];

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: translate('home', _languageProvider.currentLocale),
      ),
      NavigationDestination(
        icon: const Icon(Icons.insights_outlined),
        selectedIcon: const Icon(Icons.insights),
        label: translate('reports', _languageProvider.currentLocale),
      ),
      NavigationDestination(
        icon: const Icon(Icons.flag_outlined),
        selectedIcon: const Icon(Icons.flag),
        label: translate('goals', _languageProvider.currentLocale),
      ),
      if (isCompactLayout)
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: translate('settings', _languageProvider.currentLocale),
        ),
    ];

    // Clamp selected index if settings tab yok
    if ((!isCompactLayout) && _selectedIndex > 2) {
      _selectedIndex = 0;
    }

    return ChangeNotifierProvider<LanguageProvider>(
      create: (_) => _languageProvider,
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: translate('app_title', languageProvider.currentLocale),
            navigatorKey: _navigatorKey,
            theme: theme,
            darkTheme: darkTheme,
            themeMode: _themeMode,
            locale: languageProvider.currentLocale,
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(
                    _responsiveTextScaleForWidth(media.size.width),
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: _showSplash
                ? SplashScreen(
                    languageProvider: _languageProvider,
                    onLoginSuccess: _handleLoginSuccess,
                    isLoggedIn: _isLoggedIn,
                    onSplashComplete: _handleSplashComplete,
                  )
                : (_isLoggedIn
                    ? Scaffold(
                        extendBody: true,
                        extendBodyBehindAppBar: true,
                        appBar: AppBar(
                          titleSpacing: isCompactLayout ? 12 : 0,
                          leadingWidth: 0,
                          title: isCompactLayout
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Image.asset(
                                    'assets/images/navbarbaslik.png',
                                    height: 32,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      // Resim yüklenemezse text göster
                                      return Text(
                                        translate(
                                          'app_title',
                                          languageProvider.currentLocale,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Transform.rotate(
                                      angle: 1.5708, // 90 derece (pi/2)
                                      child: Image.asset(
                                        'assets/images/logoCo2.png',
                                        height: 110,
                                        width: 110,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          // Logo yüklenemezse boş widget göster
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Image.asset(
                                      'assets/images/navbarbaslik.png',
                                      height: 40,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        // Resim yüklenemezse text göster
                                        return Text(
                                          translate(
                                            'app_title',
                                            languageProvider.currentLocale,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                          backgroundColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          actionsPadding: isCompactLayout
                              ? const EdgeInsets.only(right: 8)
                              : EdgeInsets.zero,
                          // Küçük/orta ekranlarda (telefon/tablet ve dar web) logo sağda, geniş ekranlarda navigation butonları
                          actions: (isCompactLayout
                              ? [
                                  // Mobilde: logo biraz daha büyük ve sağ kenara daha yakın
                                  SizedBox(
                                    width: 80,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Transform.rotate(
                                        angle: 1.5708, // 90 derece (pi/2)
                                        child: Image.asset(
                                          'assets/images/logoCo2.png',
                                          height: 70,
                                          width: 70,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                              : [
                                  _NavBarButton(
                                    label: translate(
                                      'home',
                                      languageProvider.currentLocale,
                                    ),
                                    isSelected: _selectedIndex == 0,
                                    onPressed: () {
                                      setState(() {
                                        _selectedIndex = 0; // Anasayfa
                                      });
                                    },
                                  ),
                                  _NavBarButton(
                                    label: translate(
                                      'reports',
                                      languageProvider.currentLocale,
                                    ),
                                    isSelected: _selectedIndex == 1,
                                    onPressed: () {
                                      setState(() {
                                        _selectedIndex = 1; // Raporlar
                                      });
                                    },
                                  ),
                                  _NavBarButton(
                                    label: translate(
                                      'goals',
                                      languageProvider.currentLocale,
                                    ),
                                    isSelected: _selectedIndex == 2,
                                    onPressed: () {
                                      setState(() {
                                        _selectedIndex = 2; // Hedefler
                                      });
                                    },
                                  ),
                                  TextButton(
                                    onPressed:
                                        _openSettingsSheet, // Web'de sağ panel olarak aç
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                    child: Text(
                                      translate(
                                        'settings',
                                        languageProvider.currentLocale,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ]),
                          flexibleSpace: Builder(
                            builder: (context) {
                              final isDark = Theme.of(context).brightness ==
                                  Brightness.dark;
                              final primaryColor = isDark
                                  ? const Color(0xFF304411) // Koyu modda
                                  : const Color(0xFF48631F); // Açık modda
                              return Container(color: primaryColor);
                            },
                          ),
                          elevation: 0,
                        ),
                        body: SafeArea(
                          bottom: false,
                          child: pages[_selectedIndex],
                        ),
                        // Küçük/orta ekranlarda bottom navbar göster (telefon + tablet + dar web)
                        bottomNavigationBar: isCompactLayout
                            ? AppBottomNav(
                                selectedIndex: _selectedIndex,
                                onDestinationSelected: _onItemTapped,
                                destinations: destinations,
                              )
                            : null,
                      )
                    : LoginScreen(
                        languageProvider: _languageProvider,
                        onLoginSuccess: _handleLoginSuccess,
                      )),
          );
        },
      ),
    );
  }
}

// Modern navbar butonu - altında ince çizgi ile seçili durumu gösterir
class _NavBarButton extends StatelessWidget {
  const _NavBarButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
        // Alt çizgi - seçili olduğunda görünür
        if (isSelected)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
      ],
    );
  }
}
