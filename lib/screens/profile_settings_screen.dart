import 'package:flutter/material.dart';
import '../services/postgres_service.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../widgets/app_nav.dart';

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
      // Demo için sabit veriler - gerçek uygulamada API'den gelecek
      setState(() {
        _currentUser = {
          'kullanici_id': 1,
          'eposta': 'admin@teknoloji.com',
          'rol': 'sahip',
          'isletme_id': 1,
        };
        _currentBusiness = {
          'isletme_id': 1,
          'ad': 'Demo İşletme',
          'sektor_id': 1,
        };

        _businessNameController.text = _currentBusiness!['ad'];
        _emailController.text = _currentUser!['eposta'];
        _selectedSektorId = _currentBusiness!['sektor_id'];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kullanıcı bilgileri yüklenirken hata oluştu: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sektörler yüklenirken hata oluştu: $e'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İşletme bilgileri başarıyla güncellendi'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onProfileUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşletme bilgileri güncellenirken hata oluştu: $e'),
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
      // E-posta değişikliği
      try {
        await PostgresService.instance.updateUserEmail(
          kullaniciId: _currentUser!['kullanici_id'],
          newEmail: _emailController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('E-posta başarıyla güncellendi'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('E-posta güncellenirken hata oluştu: $e'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Yeni şifreler eşleşmiyor'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      try {
        await PostgresService.instance.updateUserPassword(
          kullaniciId: _currentUser!['kullanici_id'],
          currentPassword: _passwordController.text,
          newPassword: _newPasswordController.text,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Şifre başarıyla güncellendi'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Şifre alanlarını temizle
        _passwordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Şifre güncellenirken hata oluştu: $e'),
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
    final double width = MediaQuery.of(context).size.width;
    final bool isCompactLayout = width < 1100;

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
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
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
                      fontWeight: FontWeight.normal,
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // İşletme Bilgileri Kartı
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.business, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              translate('business_info', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // İşletme Adı
                        TextFormField(
                          controller: _businessNameController,
                          decoration: InputDecoration(
                            labelText: translate('business_name', locale),
                            prefixIcon: const Icon(Icons.business_outlined),
                            border: const OutlineInputBorder(),
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
                            prefixIcon: const Icon(Icons.category_outlined),
                            border: const OutlineInputBorder(),
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
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _updateBusinessInfo,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(
                              _isLoading
                                  ? translate('updating', locale)
                                  : translate('update_business_info', locale),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Kullanıcı Bilgileri Kartı
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Kullanıcı Bilgileri',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // E-posta
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'E-posta gereklidir';
                            }
                            if (!RegExp(
                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                            ).hasMatch(value)) {
                              return 'Geçerli bir e-posta adresi girin';
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
                            labelText: 'Mevcut Şifre (şifre değiştirmek için)',
                            prefixIcon: const Icon(Icons.lock_outlined),
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
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Yeni Şifre
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPassword,
                          decoration: InputDecoration(
                            labelText: 'Yeni Şifre',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureNewPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureNewPassword = !_obscureNewPassword;
                                });
                              },
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value != null &&
                                value.isNotEmpty &&
                                value.length < 6) {
                              return 'Şifre en az 6 karakter olmalıdır';
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
                            labelText: 'Yeni Şifre Tekrar',
                            prefixIcon: const Icon(Icons.lock_outlined),
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
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_newPasswordController.text.isNotEmpty &&
                                value != _newPasswordController.text) {
                              return 'Şifreler eşleşmiyor';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Güncelle Butonu
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _updateUserInfo,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(
                              _isLoading
                                  ? 'Güncelleniyor...'
                                  : 'Kullanıcı Bilgilerini Güncelle',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
      // Mobilde bottom navbar göster - Ayarlar seçili
      bottomNavigationBar: isCompactLayout
          ? AppBottomNav(
              selectedIndex: 3, // Settings sayfası index'i - seçili görünecek
              onDestinationSelected: (index) {
                // Settings (index 3) seçiliyse hiçbir şey yapma
                if (index == 3) {
                  return;
                }
                // Diğer sayfalara gitmek için önce geri dön
                Navigator.of(context).pop();
                // Eğer callback varsa, main.dart'taki _selectedIndex'i değiştir
                if (widget.onNavigationRequested != null) {
                  widget.onNavigationRequested!(index);
                }
              },
              destinations: destinations,
            )
          : null,
    );
  }
}
