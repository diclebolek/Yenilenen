import 'package:flutter/material.dart';
import '../providers/language_provider.dart';
import '../localization/translations.dart';
import 'profile_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
    this.transparentBackground = false,
    this.languageProvider,
    this.fontScale = 1.0,
    this.onFontScaleChanged,
    this.onLogout,
    this.onNavigationRequested,
  });

  final bool isDarkMode;
  final void Function(bool isDark) onToggleTheme;
  final bool transparentBackground;
  final LanguageProvider? languageProvider;
  final double fontScale;
  final void Function(double scale)? onFontScaleChanged;
  final VoidCallback? onLogout;
  final void Function(int index)? onNavigationRequested;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Bildirim ayarları
  bool _weeklyReports = true;
  bool _monthlyReports = true;
  bool _goalReminders = true;
  bool _energyTips = true;

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final Color? bgColor = widget.transparentBackground
        ? Colors.transparent
        : (isLight ? Theme.of(context).colorScheme.primary : null);

    // Responsive genişlik hesaplama
    final screenWidth = MediaQuery.of(context).size.width;
    final mobileWidth = screenWidth * 0.95; // Mobilde %95 - daha geniş
    final maxWidth = mobileWidth; // Desktop'ta maksimum mobildeki %95 değeri
    final containerWidth = screenWidth < 600 ? mobileWidth : maxWidth;

    return Scaffold(
      appBar: null,
      backgroundColor: bgColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: containerWidth,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dil ayarı kartı
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.language_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.languageProvider?.isEnglish == true
                                  ? 'English'
                                  : 'Türkçe',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              widget.languageProvider?.toggleLanguage();
                            },
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(
                              widget.languageProvider?.isEnglish == true
                                  ? 'TR'
                                  : 'EN',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Profil ayarları kartı
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              translate(
                                'profile_settings',
                                widget.languageProvider?.currentLocale ??
                                    const Locale('tr'),
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              final locale =
                                  widget.languageProvider?.currentLocale ??
                                      const Locale('tr');
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ProfileSettingsScreen(
                                    onProfileUpdated: () {
                                      // Profil güncellendiğinde yapılacak işlemler
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            translate(
                                              'profile_updated',
                                              locale,
                                            ),
                                          ),
                                          backgroundColor: Colors.green,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    languageProvider: widget.languageProvider,
                                    onNavigationRequested:
                                        widget.onNavigationRequested,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit),
                            label: Text(
                              translate(
                                'edit',
                                widget.languageProvider?.currentLocale ??
                                    const Locale('tr'),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tema ayarı kartı
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.brightness_6_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              translate(
                                'dark_mode',
                                widget.languageProvider?.currentLocale ??
                                    const Locale('tr'),
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Switch(
                            value: widget.isDarkMode,
                            onChanged: widget.onToggleTheme,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Font boyutu ayarı kartı
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.text_fields),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  translate(
                                    'font_size',
                                    widget.languageProvider?.currentLocale ??
                                        const Locale('tr'),
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '${(widget.fontScale * 100).round()}%',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: widget.fontScale > 0.8
                                    ? () {
                                        final newScale =
                                            (widget.fontScale - 0.1).clamp(
                                          0.8,
                                          1.5,
                                        );
                                        widget.onFontScaleChanged?.call(
                                          newScale,
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.remove),
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: widget.fontScale,
                                  min: 0.8,
                                  max: 1.5,
                                  divisions: 7,
                                  onChanged: (value) {
                                    widget.onFontScaleChanged?.call(value);
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: widget.fontScale < 1.5
                                    ? () {
                                        final newScale =
                                            (widget.fontScale + 0.1).clamp(
                                          0.8,
                                          1.5,
                                        );
                                        widget.onFontScaleChanged?.call(
                                          newScale,
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.add),
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.2),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Bildirim ayarları kartı
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.notifications_outlined),
                              const SizedBox(width: 8),
                              Text(
                                translate(
                                  'notification_settings',
                                  widget.languageProvider?.currentLocale ??
                                      const Locale('tr'),
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Haftalık raporlar
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      translate(
                                        'weekly_reports',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      translate(
                                        'weekly_reports_desc',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _weeklyReports,
                                onChanged: (value) {
                                  setState(() {
                                    _weeklyReports = value;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Aylık raporlar
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      translate(
                                        'monthly_reports',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      translate(
                                        'monthly_reports_desc',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _monthlyReports,
                                onChanged: (value) {
                                  setState(() {
                                    _monthlyReports = value;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Hedef hatırlatmaları
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      translate(
                                        'goal_reminders',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      translate(
                                        'goal_reminders_desc',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _goalReminders,
                                onChanged: (value) {
                                  setState(() {
                                    _goalReminders = value;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Enerji ipuçları
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      translate(
                                        'energy_tips_notifications',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      translate(
                                        'energy_tips_desc',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _energyTips,
                                onChanged: (value) {
                                  setState(() {
                                    _energyTips = value;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Çıkış yap butonu
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showLogoutDialog();
                          },
                          icon: const Icon(Icons.logout),
                          label: Text(
                            translate(
                              'logout',
                              widget.languageProvider?.currentLocale ??
                                  const Locale('tr'),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
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

  void _showLogoutDialog() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(translate('logout', locale)),
          content: Text(translate('logout_confirmation', locale)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(translate('cancel', locale)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onLogout?.call();

                // Başarı mesajı göster
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(translate('logout_success', locale)),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(translate('logout', locale)),
            ),
          ],
        );
      },
    );
  }
}
