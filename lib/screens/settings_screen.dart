import 'package:flutter/material.dart';
import '../providers/language_provider.dart';
import '../localization/translations.dart';
import 'profile_settings_screen.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
    this.transparentBackground = false,
    this.languageProvider,
    this.onLogout,
    this.onNavigationRequested,
  });

  final bool isDarkMode;
  final void Function(bool isDark) onToggleTheme;
  final bool transparentBackground;
  final LanguageProvider? languageProvider;
  final VoidCallback? onLogout;
  final void Function(int index)? onNavigationRequested;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkModeLocal = false;

  // Bildirim ayarları
  bool _weeklyReports = true;
  bool _monthlyReports = true;
  bool _goalReminders = true;
  bool _energyTips = true;
  bool _dailySensorSummary = true;

  @override
  void initState() {
    super.initState();
    _isDarkModeLocal = widget.isDarkMode;
    _loadNotificationPreferences();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode) {
      _isDarkModeLocal = widget.isDarkMode;
    }
  }

  Future<void> _loadNotificationPreferences() async {
    await NotificationService.instance.initialize();
    final prefs = await NotificationService.instance.loadPreferences();
    if (!mounted) return;
    setState(() {
      _weeklyReports = prefs.weeklyReports;
      _monthlyReports = prefs.monthlyReports;
      _goalReminders = prefs.goalReminders;
      _energyTips = prefs.energyTips;
      _dailySensorSummary = prefs.dailySensorSummary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final Color? bgColor = widget.transparentBackground
        ? Colors.transparent
        : (isLight ? Theme.of(context).colorScheme.primary : null);

    return Scaffold(
      appBar: null,
      backgroundColor: bgColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
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
                                            duration:
                                                const Duration(seconds: 2),
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
                              value: _isDarkModeLocal,
                              onChanged: (value) {
                                setState(() {
                                  _isDarkModeLocal = value;
                                });
                                widget.onToggleTheme(value);
                              },
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
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Haftalık raporlar
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  onChanged: (value) async {
                                    setState(() {
                                      _weeklyReports = value;
                                    });
                                    await NotificationService.instance
                                        .setWeeklyReportsEnabled(value);
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  onChanged: (value) async {
                                    setState(() {
                                      _monthlyReports = value;
                                    });
                                    await NotificationService.instance
                                        .setMonthlyReportsEnabled(value);
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  onChanged: (value) async {
                                    setState(() {
                                      _goalReminders = value;
                                    });
                                    await NotificationService.instance
                                        .setGoalRemindersEnabled(value);
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  onChanged: (value) async {
                                    setState(() {
                                      _energyTips = value;
                                    });
                                    await NotificationService.instance
                                        .setEnergyTipsEnabled(value);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        translate(
                                          'daily_sensor_summary',
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
                                          'daily_sensor_summary_desc',
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
                                  value: _dailySensorSummary,
                                  onChanged: (value) async {
                                    setState(() {
                                      _dailySensorSummary = value;
                                    });
                                    await NotificationService.instance
                                        .setDailySensorSummaryEnabled(value);
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
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _showLogoutDialog();
                            },
                            icon: const Icon(Icons.logout, color: Colors.red),
                            label: Text(
                              translate(
                                'logout',
                                widget.languageProvider?.currentLocale ??
                                    const Locale('tr'),
                              ),
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.red,
                              side: const BorderSide(
                                color: Colors.red,
                                width: 1.5,
                              ),
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
