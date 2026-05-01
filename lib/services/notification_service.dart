import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationPreferences {
  const NotificationPreferences({
    required this.weeklyReports,
    required this.monthlyReports,
    required this.goalReminders,
    required this.energyTips,
  });

  final bool weeklyReports;
  final bool monthlyReports;
  final bool goalReminders;
  final bool energyTips;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _weeklyKey = 'notifications_weekly_reports';
  static const String _monthlyKey = 'notifications_monthly_reports';
  static const String _goalKey = 'notifications_goal_reminders';
  static const String _tipsKey = 'notifications_energy_tips';

  static const int _weeklyId = 1001;
  static const int _monthlyId = 1002;
  static const int _goalId = 1003;
  static const int _tipsId = 1004;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    tz.initializeTimeZones();
    await _configureLocalTimezone();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    await requestPermissions();
    await syncSchedulesWithPreferences();
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<NotificationPreferences> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationPreferences(
      weeklyReports: prefs.getBool(_weeklyKey) ?? true,
      monthlyReports: prefs.getBool(_monthlyKey) ?? true,
      goalReminders: prefs.getBool(_goalKey) ?? true,
      energyTips: prefs.getBool(_tipsKey) ?? true,
    );
  }

  Future<void> setWeeklyReportsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_weeklyKey, enabled);
    if (kIsWeb) return;
    if (enabled) {
      await _scheduleWeeklyReport();
    } else {
      await _notifications.cancel(id: _weeklyId);
    }
  }

  Future<void> setMonthlyReportsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_monthlyKey, enabled);
    if (kIsWeb) return;
    if (enabled) {
      await _scheduleMonthlyReport();
    } else {
      await _notifications.cancel(id: _monthlyId);
    }
  }

  Future<void> setGoalRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_goalKey, enabled);
    if (kIsWeb) return;
    if (enabled) {
      await _scheduleGoalReminder();
    } else {
      await _notifications.cancel(id: _goalId);
    }
  }

  Future<void> setEnergyTipsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tipsKey, enabled);
    if (kIsWeb) return;
    if (enabled) {
      await _scheduleEnergyTip();
    } else {
      await _notifications.cancel(id: _tipsId);
    }
  }

  Future<void> syncSchedulesWithPreferences() async {
    final settings = await loadPreferences();
    if (kIsWeb) return;

    if (settings.weeklyReports) {
      await _scheduleWeeklyReport();
    } else {
      await _notifications.cancel(id: _weeklyId);
    }

    if (settings.monthlyReports) {
      await _scheduleMonthlyReport();
    } else {
      await _notifications.cancel(id: _monthlyId);
    }

    if (settings.goalReminders) {
      await _scheduleGoalReminder();
    } else {
      await _notifications.cancel(id: _goalId);
    }

    if (settings.energyTips) {
      await _scheduleEnergyTip();
    } else {
      await _notifications.cancel(id: _tipsId);
    }
  }

  Future<void> _scheduleWeeklyReport() async {
    await _notifications.zonedSchedule(
      id: _weeklyId,
      title: 'Haftalik karbon raporu hazir',
      body: 'Bu haftanin raporunu incelemek icin uygulamayi ac.',
      scheduledDate: _nextInstanceOfWeekdayTime(DateTime.monday, hour: 10),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> _scheduleMonthlyReport() async {
    await _notifications.zonedSchedule(
      id: _monthlyId,
      title: 'Aylik analiz raporu',
      body: 'Aylik karbon trend raporunuz hazir.',
      scheduledDate: _nextFirstDayOfMonth(hour: 10),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> _scheduleGoalReminder() async {
    await _notifications.zonedSchedule(
      id: _goalId,
      title: 'Hedef hatirlatmasi',
      body: 'Hedef ilerlemeni kontrol et ve bugun bir adim at.',
      scheduledDate: _nextInstanceOfTime(hour: 20),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _scheduleEnergyTip() async {
    await _notifications.zonedSchedule(
      id: _tipsId,
      title: 'Gunluk enerji ipucu',
      body: 'Bugun enerji tasarrufu icin kisa bir oneriyi gormeyi unutma.',
      scheduledDate: _nextInstanceOfTime(hour: 9),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'carbon_notifications_channel',
        'Karbon Bildirimleri',
        channelDescription: 'Karbon raporlari ve hatirlatma bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime(
    int weekday, {
    required int hour,
    int minute = 0,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfTime({required int hour, int minute = 0}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextFirstDayOfMonth({required int hour, int minute = 0}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, 1, hour, minute);
    if (scheduled.isBefore(now)) {
      if (now.month == 12) {
        scheduled = tz.TZDateTime(tz.local, now.year + 1, 1, 1, hour, minute);
      } else {
        scheduled =
            tz.TZDateTime(tz.local, now.year, now.month + 1, 1, hour, minute);
      }
    }
    return scheduled;
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timezoneName = timezoneInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }
}
