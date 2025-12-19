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
import 'widgets/app_nav.dart';
import 'providers/language_provider.dart';
import 'localization/translations.dart';
import 'services/postgres_service.dart';
import 'services/firebase_realtime_service.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseRealtimeService.instance.initialize();
    debugPrint('Firebase başarıyla başlatıldı');
  } catch (e) {
    debugPrint('Firebase başlatma hatası: $e');
    // Firebase hatası olsa bile uygulama çalışmaya devam eder
  }

  // PostgreSQL bağlantısını asenkron başlat (uygulama başlangıcını geciktirmemek için)
  // Timeout ile hızlı başlatma
  PostgresService.instance
      .connect()
      .timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint(
            'PostgreSQL bağlantısı zaman aşımına uğradı (devam ediliyor)',
          );
          return;
        },
      )
      .catchError((e) {
        debugPrint('PostgreSQL bağlantı hatası: $e');
        // Uygulama yine de çalışır, sadece veritabanı işlemleri başarısız olur
      });

  runApp(const CarbonFootprintApp());
}

/// Root widget configuring Material 3, theming, and bottom navigation.
class CarbonFootprintApp extends StatefulWidget {
  const CarbonFootprintApp({super.key});

  @override
  State<CarbonFootprintApp> createState() => _CarbonFootprintAppState();
}

class _CarbonFootprintAppState extends State<CarbonFootprintApp> {
  // Dialog ve sayfa geçişleri için güvenli Navigator erişimi
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ThemeMode _themeMode = ThemeMode.system;
  int _selectedIndex = 0;
  final LanguageProvider _languageProvider = LanguageProvider();
  bool _isLoggedIn = false; // Login durumu

  // Font scale ayarı - global olarak tutulacak
  double _fontScale = 1.0;

  bool get _isDark => _themeMode == ThemeMode.dark;

  void _toggleThemeMode(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _updateFontScale(double scale) {
    setState(() {
      _fontScale = scale;
    });
  }

  void _handleLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
    });
  }

  void _handleLogout() {
    setState(() {
      _isLoggedIn = false;
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
        // Mobilde daha geniş (ekranın %90'ı), büyük ekranlarda %50
        final double panelWidth = size.width < 600
            ? size.width * 0.9
            : size.width * 0.5; // sayfanın ortasına kadar
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
                      isDarkMode: _isDark,
                      onToggleTheme: _toggleThemeMode,
                      transparentBackground: true,
                      languageProvider: _languageProvider,
                      fontScale: _fontScale,
                      onFontScaleChanged: _updateFontScale,
                      onLogout: _handleLogout,
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

    // Language provider'ı başlat
    _languageProvider.initialize();

    // Platform ve ekran tabanlı belirleme
    final double width = MediaQuery.of(context).size.width;
    // Telefon + tablet gibi küçük/orta layout'larda (web dahil) davranış
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
          isDarkMode: _isDark,
          onToggleTheme: _toggleThemeMode,
          languageProvider: _languageProvider,
          fontScale: _fontScale,
          onFontScaleChanged: _updateFontScale,
          onLogout: _handleLogout,
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
            home: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(_fontScale)),
              child: _isLoggedIn
                  ? Scaffold(
                      extendBody: true,
                      extendBodyBehindAppBar: true,
                      appBar: AppBar(
                        title: Text(
                          translate(
                            'app_title',
                            languageProvider.currentLocale,
                          ),
                        ),
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        // Küçük/orta ekranlarda (telefon/tablet ve dar web) gizle; geniş ekranlarda göster
                        actions: !isCompactLayout
                            ? [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedIndex = 0; // Anasayfa
                                    });
                                  },
                                  child: Text(
                                    translate(
                                      'home',
                                      languageProvider.currentLocale,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedIndex = 1; // Raporlar
                                    });
                                  },
                                  child: Text(
                                    translate(
                                      'reports',
                                      languageProvider.currentLocale,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedIndex = 2; // Hedefler
                                    });
                                  },
                                  child: Text(
                                    translate(
                                      'goals',
                                      languageProvider.currentLocale,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                TextButton(
                                  onPressed:
                                      _openSettingsSheet, // Web'de sağ panel olarak aç
                                  child: Text(
                                    translate(
                                      'settings',
                                      languageProvider.currentLocale,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ]
                            : null,
                        flexibleSpace: Builder(
                          builder: (context) {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
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
                    ),
            ),
          );
        },
      ),
    );
  }
}
