import 'package:flutter/material.dart';
import '../services/postgres_service.dart';
import '../services/firebase_auth_service.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../themes/app_theme.dart';
import '../widgets/app_nav.dart';

/// İşletme kartı vurgusu (mavi kenarlı şeffaf buton ile uyumlu).
const Color _kProfileBusinessBlue = Color(0xFF1565C0);

/// Profil ayarları sayfası - işletme bilgilerini düzenleme
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    super.key,
    required this.onProfileUpdated,
    this.languageProvider,
    this.onNavigationRequested,
  });

  final VoidCallback onProfileUpdated;
  final LanguageProvider? languageProvider;
  final void Function(int index)? onNavigationRequested;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  void _exitToUnderlyingRoute(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) {
      root.pop();
    }
  }

  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  int? _selectedSektorId;
  List<Map<String, dynamic>> _sektors = [];

  // Mevcut kullanıcı bilgileri
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _currentBusiness;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSektors();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      // Firebase'den mevcut kullanıcıyı al
      final firebaseUser = FirebaseAuthService.instance.currentUser;

      if (firebaseUser == null) {
        // Kullanıcı giriş yapmamış
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translate('login_required_first', locale)),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Firebase'den email'i al
      final email = firebaseUser.email ?? '';

      // PostgreSQL'den kullanıcı bilgilerini çekmeyi dene
      // Not: Email ile kullanıcı arama için API endpoint'i gerekli
      // Şimdilik Firebase'den email'i kullanıyoruz

      // PostgreSQL'den kullanıcı bilgilerini çek (eğer kullanıcı ID'si varsa)
      // Firebase UID'yi kullanarak PostgreSQL'de kullanıcı bulunabilir
      // Şimdilik Firebase'den gelen email'i kullanıyoruz

      setState(() {
        _currentUser = {
          'kullanici_id': 1, // PostgreSQL'den gelecek
          'eposta': email, // Firebase'den gerçek email
          'rol': 'sahip',
          'isletme_id': 1, // PostgreSQL'den gelecek
        };

        // İşletme bilgilerini PostgreSQL'den çekmeyi dene
        _loadBusinessInfo(1); // İşletme ID'si PostgreSQL'den gelecek

        _emailController.text = email;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translate(
                'user_data_load_error',
                widget.languageProvider?.currentLocale ?? const Locale('tr'),
                params: {'error': e.toString()},
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadBusinessInfo(int isletmeId) async {
    try {
      // PostgreSQL'den işletme bilgilerini çek
      final businessInfo =
          await PostgresService.instance.getBusinessInfo(isletmeId);

      if (businessInfo != null) {
        setState(() {
          _currentBusiness = businessInfo;
          _businessNameController.text = businessInfo['ad'] ?? '';
          _selectedSektorId = businessInfo['sektor_id'];
        });
      } else {
        // PostgreSQL'den veri alınamazsa, Firebase'den email'e göre varsayılan değerler
        setState(() {
          _currentBusiness = {
            'isletme_id': isletmeId,
            'ad': '', // Kullanıcıdan alınacak
            'sektor_id': null,
          };
        });
      }
    } catch (e) {
      debugPrint('İşletme bilgileri yüklenirken hata: $e');
      // Hata durumunda boş değerler
      setState(() {
        _currentBusiness = {
          'isletme_id': isletmeId,
          'ad': '',
          'sektor_id': null,
        };
      });
    }
  }

  Future<void> _loadSektors() async {
    try {
      final sektors = await PostgresService.instance.getSektors();
      setState(() {
        _sektors = sektors;
      });
    } catch (e) {
      if (mounted) {
        final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translate(
                'sectors_load_error',
                locale,
                params: {'error': e.toString()},
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _updateBusinessInfo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // İşletme bilgilerini güncelle
      await PostgresService.instance.updateBusiness(
        isletmeId: _currentBusiness!['isletme_id'],
        businessName: _businessNameController.text.trim(),
        sektorId: _selectedSektorId!,
      );

      if (mounted) {
        final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translate('business_update_success', locale)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onProfileUpdated();
      }
    } catch (e) {
      if (mounted) {
        final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translate(
                'business_update_error',
                locale,
                params: {'error': e.toString()},
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateUserInfo() async {
    if (_emailController.text.trim() != _currentUser!['eposta']) {
      // E-posta değişikliği - Firebase'de güncelle
      try {
        await FirebaseAuthService.instance.updateEmail(
          _emailController.text.trim(),
        );

        // PostgreSQL'de de güncelle (eğer bağlantı varsa)
        try {
          await PostgresService.instance.updateUserEmail(
            kullaniciId: _currentUser!['kullanici_id'],
            newEmail: _emailController.text.trim(),
          );
        } catch (e) {
          debugPrint('PostgreSQL e-posta güncelleme hatası: $e');
          // PostgreSQL hatası olsa bile Firebase güncellendi
        }

        // Yerel state'i güncelle
        setState(() {
          _currentUser!['eposta'] = _emailController.text.trim();
        });

        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translate('email_update_success_verify', locale)),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                translate(
                  'email_update_error',
                  locale,
                  params: {'error': e.toString()},
                ),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    // Şifre değişikliği
    if (_newPasswordController.text.isNotEmpty) {
      if (_newPasswordController.text != _confirmPasswordController.text) {
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translate('password_mismatch', locale)),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      try {
        // Firebase'de şifreyi güncelle
        await FirebaseAuthService.instance.updatePassword(
          currentPassword: _passwordController.text,
          newPassword: _newPasswordController.text,
        );

        // PostgreSQL'de de güncelle (eğer bağlantı varsa)
        try {
          await PostgresService.instance.updateUserPassword(
            kullaniciId: _currentUser!['kullanici_id'],
            currentPassword: _passwordController.text,
            newPassword: _newPasswordController.text,
          );
        } catch (e) {
          debugPrint('PostgreSQL şifre güncelleme hatası: $e');
          // PostgreSQL hatası olsa bile Firebase güncellendi
        }

        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translate('password_update_success', locale)),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Şifre alanlarını temizle
        _passwordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } catch (e) {
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                translate(
                  'password_update_error',
                  locale,
                  params: {'error': e.toString()},
                ),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final cs = Theme.of(context).colorScheme;
    final double width = MediaQuery.of(context).size.width;
    final bool isCompactLayout = width < 1100;
    final double maxContentW = width >= 600
        ? (width * 0.67).clamp(640.0, 1120.0)
        : double.infinity;
    final Color greenAccent = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.darkPrimaryColor
        : AppTheme.lightPrimaryColor;

    // Navigation destinations
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: translate('home', locale),
      ),
      NavigationDestination(
        icon: const Icon(Icons.insights_outlined),
        selectedIcon: const Icon(Icons.insights),
        label: translate('reports', locale),
      ),
      NavigationDestination(
        icon: const Icon(Icons.flag_outlined),
        selectedIcon: const Icon(Icons.flag),
        label: translate('goals', locale),
      ),
      if (isCompactLayout)
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: translate('settings', locale),
        ),
    ];

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leadingWidth: 0,
        title: isCompactLayout
            ? Image.asset(
                'assets/images/navbarbaslik.png',
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Resim yüklenemezse text göster
                  return Text(
                    translate('app_title', locale),
                    style: const TextStyle(color: Colors.white),
                  );
                },
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
                      errorBuilder: (context, error, stackTrace) {
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
                    errorBuilder: (context, error, stackTrace) {
                      // Resim yüklenemezse text göster
                      return Text(
                        translate('app_title', locale),
                        style: const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                ],
              ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: (isCompactLayout
            ? [
                // Mobilde: logo sağda - en sağa yanaştır
                Padding(
                  padding: EdgeInsets.zero,
                  child: Transform.rotate(
                    angle: 1.5708, // 90 derece (pi/2)
                    child: Image.asset(
                      'assets/images/logoCo2.png',
                      height: 180,
                      width: 180,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ]
            : [
                // Web'de navigation butonları
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (widget.onNavigationRequested != null) {
                          widget.onNavigationRequested!(0);
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        translate('home', locale),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (widget.onNavigationRequested != null) {
                          widget.onNavigationRequested!(1);
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        translate('reports', locale),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (widget.onNavigationRequested != null) {
                          widget.onNavigationRequested!(2);
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        translate('goals', locale),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _exitToUnderlyingRoute(context),
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
                    translate('settings', locale),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ]),
        flexibleSpace: Builder(
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
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
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 +
                  (isCompactLayout
                      ? 80 + MediaQuery.of(context).padding.bottom
                      : 0), // Bottom navbar için padding
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentW),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.business_rounded,
                                  color: _kProfileBusinessBlue,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    translate('business_info', locale),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // İşletme Adı
                            TextFormField(
                              controller: _businessNameController,
                              decoration: InputDecoration(
                                labelText: translate('business_name', locale),
                                prefixIcon: Icon(
                                  Icons.business_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.92),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return translate(
                                      'business_name_required', locale);
                                }
                                if (value.length < 2) {
                                  return translate(
                                    'business_name_min_length',
                                    locale,
                                  );
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Sektör Seçimi
                            DropdownButtonFormField<int>(
                              key: ValueKey<int?>(_selectedSektorId),
                              initialValue: _selectedSektorId,
                              decoration: InputDecoration(
                                labelText: translate('sector', locale),
                                prefixIcon: Icon(
                                  Icons.category_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.92),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: _sektors.map((sektor) {
                                return DropdownMenuItem<int>(
                                  value: sektor['sektor_id'],
                                  child: Text(sektor['ad']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedSektorId = value;
                                });
                              },
                              validator: (value) {
                                if (value == null) {
                                  return translate('select_sector', locale);
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Güncelle Butonu
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isLoading ? null : _updateBusinessInfo,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _kProfileBusinessBlue,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(
                                  _isLoading
                                      ? translate('updating', locale)
                                      : translate(
                                          'update_business_info', locale),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kProfileBusinessBlue,
                                  backgroundColor: Colors.transparent,
                                  side: const BorderSide(
                                    color: _kProfileBusinessBlue,
                                    width: 1.6,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  color: greenAccent,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    translate(
                                      'user_information_section',
                                      locale,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // E-posta
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: translate('email', locale),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.92),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return translate('email_required', locale);
                                }
                                if (!RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                ).hasMatch(value)) {
                                  return translate('email_invalid', locale);
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Mevcut Şifre
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText:
                                    translate('current_password_for_change', locale),
                                prefixIcon: Icon(
                                  Icons.lock_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.92),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Yeni Şifre
                            TextFormField(
                              controller: _newPasswordController,
                              obscureText: _obscureNewPassword,
                              decoration: InputDecoration(
                                labelText: translate('new_password', locale),
                                prefixIcon: Icon(
                                  Icons.lock_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureNewPassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureNewPassword =
                                          !_obscureNewPassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.92),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    value.length < 6) {
                                  return translate('password_min_length', locale);
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Şifre Tekrar
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              decoration: InputDecoration(
                                labelText:
                                    translate('confirm_new_password', locale),
                                prefixIcon: Icon(
                                  Icons.lock_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.92),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (_newPasswordController.text.isNotEmpty &&
                                    value != _newPasswordController.text) {
                                  return translate('password_mismatch', locale);
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Güncelle Butonu
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _updateUserInfo,
                                icon: _isLoading
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: greenAccent,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(
                                  _isLoading
                                      ? translate('updating', locale)
                                      : translate('update_user_info', locale),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: greenAccent,
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide(
                                    color: greenAccent,
                                    width: 1.6,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Mobilde bottom navbar göster - Ayarlar seçili
      bottomNavigationBar: isCompactLayout
          ? AppBottomNav(
              selectedIndex: 3,
              onDestinationSelected: (index) {
                // Ayarlar sekmesi: üst üste açılmış profil rotasından çık
                if (index == 3) {
                  _exitToUnderlyingRoute(context);
                  return;
                }
                // Önce ana navigator'da sekmeyi değiştir (dispose öncesi callback)
                widget.onNavigationRequested?.call(index);
                _exitToUnderlyingRoute(context);
              },
              destinations: destinations,
            )
          : null,
    );
  }
}
