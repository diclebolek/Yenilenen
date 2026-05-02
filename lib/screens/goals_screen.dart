import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/api_service.dart';
import '../services/global_carbon_service.dart';
import '../models/consumption_entry.dart';
import '../algorithms/calculation.dart';
import 'dart:async';

/// Şablon satırı — hedef ekleme diyaloğu için (tema ile uyumlu chip seçimi).
class _GoalAddTemplate {
  const _GoalAddTemplate({
    required this.storageType,
    required this.titleKey,
    required this.defaultUnit,
    required this.icon,
    required this.iconString,
    required this.trackingHelpKey,
    this.defaultTarget = '',
  });

  /// Firebase / ilerleme mantığında kullanılan tip (`custom` = kullanıcı başlığı).
  final String storageType;
  final String titleKey;
  final String defaultUnit;
  final IconData icon;
  final String iconString;
  final String trackingHelpKey;
  final String defaultTarget;
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.languageProvider});

  final LanguageProvider? languageProvider;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  static const List<_GoalAddTemplate> _kGoalAddTemplates = <_GoalAddTemplate>[
    _GoalAddTemplate(
      storageType: 'electricity_saving',
      titleKey: 'monthly_electricity_saving',
      defaultUnit: '%',
      icon: Icons.electrical_services,
      iconString: 'electrical_services',
      trackingHelpKey: 'goal_tracking_auto',
      defaultTarget: '20',
    ),
    _GoalAddTemplate(
      storageType: 'co2_reduction',
      titleKey: 'co2_emission_reduction',
      defaultUnit: 'kg',
      icon: Icons.eco,
      iconString: 'eco',
      trackingHelpKey: 'goal_tracking_auto',
      defaultTarget: '15',
    ),
    _GoalAddTemplate(
      storageType: 'water_saving',
      titleKey: 'water_saving',
      defaultUnit: '%',
      icon: Icons.water_drop,
      iconString: 'water_drop',
      trackingHelpKey: 'goal_tracking_auto',
      defaultTarget: '25',
    ),
    _GoalAddTemplate(
      storageType: 'waste_reduction',
      titleKey: 'waste_reduction',
      defaultUnit: 'kg',
      icon: Icons.recycling,
      iconString: 'recycling',
      trackingHelpKey: 'goal_tracking_waste',
      defaultTarget: '10',
    ),
    _GoalAddTemplate(
      storageType: 'custom',
      titleKey: 'goal_template_renewable',
      defaultUnit: 'kWh',
      icon: Icons.electric_bolt,
      iconString: 'electric_bolt',
      trackingHelpKey: 'goal_tracking_custom',
      defaultTarget: '100',
    ),
    _GoalAddTemplate(
      storageType: 'custom',
      titleKey: 'goal_template_transport',
      defaultUnit: 'km',
      icon: Icons.directions_car,
      iconString: 'directions_car',
      trackingHelpKey: 'goal_tracking_custom',
      defaultTarget: '50',
    ),
    _GoalAddTemplate(
      storageType: 'custom',
      titleKey: 'goal_template_other',
      defaultUnit: '%',
      icon: Icons.flag,
      iconString: 'flag',
      trackingHelpKey: 'goal_tracking_custom',
      defaultTarget: '10',
    ),
  ];

  final FirebaseRealtimeService _firebaseService =
      FirebaseRealtimeService.instance;
  final FirebaseAuthService _authService = FirebaseAuthService.instance;
  final ApiService _apiService = ApiService();

  int _greenScore = 0;
  List<CarbonGoal> _goals = [];
  MonthlyPrediction? _monthlyPrediction;
  bool _predictionLoading = false;
  bool _isLoading = true;
  Map<String, bool> _badges = {
    'environment_friendly': false,
    'energy_saving': false,
    'water_protector': false,
    'goal_master': false,
    'eco_warrior': false,
  };
  StreamSubscription<int>? _greenScoreSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _goalsSubscription;
  StreamSubscription<ConsumptionEntry?>? _consumptionSubscription;
  StreamSubscription<Map<String, bool>>? _badgesSubscription;

  String? get _userId => _authService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Yeşil puanı yükle
      final score = await _firebaseService.getGreenScore(_userId!);
      setState(() => _greenScore = score);

      // Yeşil puanı dinle
      _greenScoreSubscription?.cancel();
      _greenScoreSubscription =
          _firebaseService.listenToGreenScore(_userId!).listen((score) {
        if (mounted) {
          setState(() => _greenScore = score);
        }
      });

      // Hedefleri yükle
      final goalsData = await _firebaseService.getGoals(_userId!);
      if (goalsData.isEmpty) {
        // Varsayılan hedefleri oluştur
        await _createDefaultGoals();
        final defaultGoals = await _firebaseService.getGoals(_userId!);
        _updateGoalsList(defaultGoals);
      } else {
        _updateGoalsList(goalsData);
      }

      // Hedefleri dinle
      _goalsSubscription?.cancel();
      _goalsSubscription = _firebaseService.listenToGoals(_userId!).listen((
        goalsData,
      ) {
        if (mounted) {
          _updateGoalsList(goalsData);
        }
      });

      // Tüketim verilerini dinle ve hedef ilerlemelerini güncelle
      _consumptionSubscription?.cancel();
      _consumptionSubscription = _apiService.listenToFirebaseData().listen((
        consumption,
      ) {
        if (mounted && consumption != null) {
          _updateGoalProgress(consumption);
          _refreshPrediction();
        }
      });

      // Rozetleri yükle
      final badges = await _firebaseService.getBadges(_userId!);
      setState(() => _badges = badges);

      // Rozetleri dinle
      _badgesSubscription?.cancel();
      _badgesSubscription = _firebaseService.listenToBadges(_userId!).listen((
        badges,
      ) {
        if (mounted) {
          setState(() => _badges = badges);
        }
      });

      // Rozet kontrolü yap
      _checkAndUnlockBadges();
      await _refreshPrediction();
    } catch (e) {
      // Hata durumunda varsayılan hedefleri göster
      _createDefaultGoalsList();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createDefaultGoals() async {
    if (_userId == null) return;
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final defaultGoals = [
      {
        'title': translate('monthly_electricity_saving', locale),
        'target': 20.0,
        'current': 0.0,
        'monthlyChangePercent': 0.0,
        'recommendation': '',
        'unit': '%',
        'type': 'electricity_saving',
        'icon': 'electrical_services',
        'color': 0xFF304411,
      },
      {
        'title': translate('co2_emission_reduction', locale),
        'target': 15.0,
        'current': 0.0,
        'monthlyChangePercent': 0.0,
        'recommendation': '',
        'unit': 'kg',
        'type': 'co2_reduction',
        'icon': 'eco',
        'color': 0xFF48631F,
      },
      {
        'title': translate('water_saving', locale),
        'target': 25.0,
        'current': 0.0,
        'monthlyChangePercent': 0.0,
        'recommendation': '',
        'unit': '%',
        'type': 'water_saving',
        'icon': 'water_drop',
        'color': 0xFF304411,
      },
    ];

    await _firebaseService.saveGoals(_userId!, defaultGoals);
  }

  void _createDefaultGoalsList() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    setState(() {
      _goals = [
        CarbonGoal(
          id: 'default1',
          title: translate('monthly_electricity_saving', locale),
          target: 20.0,
          current: 0.0,
          monthlyChangePercent: 0.0,
          recommendation: '',
          unit: '%',
          type: 'electricity_saving',
          icon: Icons.electrical_services,
          color: const Color(0xFF304411),
        ),
        CarbonGoal(
          id: 'default2',
          title: translate('co2_emission_reduction', locale),
          target: 15.0,
          current: 0.0,
          monthlyChangePercent: 0.0,
          recommendation: '',
          unit: 'kg',
          type: 'co2_reduction',
          icon: Icons.eco,
          color: const Color(0xFF48631F),
        ),
        CarbonGoal(
          id: 'default3',
          title: translate('water_saving', locale),
          target: 25.0,
          current: 0.0,
          monthlyChangePercent: 0.0,
          recommendation: '',
          unit: '%',
          type: 'water_saving',
          icon: Icons.water_drop,
          color: const Color(0xFF304411),
        ),
      ];
    });
  }

  void _updateGoalsList(List<Map<String, dynamic>> goalsData) {
    setState(() {
      _goals = goalsData.map((data) {
        return CarbonGoal(
          id: data['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: data['title'] ?? '',
          target: (data['target'] ?? 0.0).toDouble(),
          current: (data['current'] ?? 0.0).toDouble(),
          monthlyChangePercent:
              (data['monthlyChangePercent'] ?? 0.0).toDouble(),
          recommendation: data['recommendation']?.toString() ?? '',
          unit: data['unit'] ?? '',
          type: data['type'] ?? '',
          icon: _getIconFromString(data['icon'] ?? 'eco'),
          color: Color(data['color'] ?? 0xFF304411),
        );
      }).toList();
    });
    if (_userId != null) {
      unawaited(_refreshPrediction());
    }
  }

  IconData _getIconFromString(String iconName) {
    switch (iconName) {
      case 'electrical_services':
        return Icons.electrical_services;
      case 'eco':
        return Icons.eco;
      case 'water_drop':
        return Icons.water_drop;
      case 'recycling':
        return Icons.recycling;
      case 'energy_savings_leaf':
        return Icons.energy_savings_leaf;
      case 'electric_bolt':
        return Icons.electric_bolt;
      case 'directions_car':
        return Icons.directions_car;
      default:
        return Icons.flag;
    }
  }

  Future<void> _updateGoalProgress(ConsumptionEntry consumption) async {
    if (_userId == null) return;

    try {
      final goalsData = await _firebaseService.getGoals(_userId!);
      bool updated = false;
      final locale =
          widget.languageProvider?.currentLocale ?? const Locale('tr');

      // Önceki ay verilerini al (karşılaştırma için)
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final previousMonthStart = DateTime(now.year, now.month - 1, 1);
      final previousMonthEnd =
          currentMonthStart.subtract(const Duration(days: 1));

      // Bu ayın verilerini al
      final currentMonthData = await _firebaseService.getHistoryData(
        deviceId: 'esp8266_001',
        startDate: currentMonthStart,
        endDate: now,
      );

      // Önceki ayın verilerini al
      final previousMonthData = await _firebaseService.getHistoryData(
        deviceId: 'esp8266_001',
        startDate: previousMonthStart,
        endDate: previousMonthEnd,
      );

      // Bu ayın toplam tüketimlerini hesapla
      double currentMonthElectricity = 0;
      double currentMonthWater = 0;
      double currentMonthGas = 0;
      for (var entry in currentMonthData) {
        currentMonthElectricity += entry.electricityKwh;
        currentMonthWater += entry.waterCubicMeters;
        currentMonthGas += entry.fuelLiters;
      }

      // Önceki ayın toplam tüketimlerini hesapla
      double previousMonthElectricity = 0;
      double previousMonthWater = 0;
      double previousMonthGas = 0;
      for (var entry in previousMonthData) {
        previousMonthElectricity += entry.electricityKwh;
        previousMonthWater += entry.waterCubicMeters;
        previousMonthGas += entry.fuelLiters;
      }

      final threeMonthAverages = await _calculateThreeMonthAverageReductions(
        currentMonthStart,
      );
      final electricityHourly =
          _buildHourlySums(currentMonthData, forElectricity: true);
      final waterHourly =
          _buildHourlySums(currentMonthData, forElectricity: false);

      for (var goalData in goalsData) {
        final type = goalData['type'] ?? '';
        double? newCurrent;
        double newMonthlyChangePercent = 0.0;
        final previousRecommendation =
            goalData['recommendation']?.toString() ?? '';
        var newRecommendation = previousRecommendation;
        double dynamicTarget = (goalData['target'] ?? 0.0).toDouble();

        switch (type) {
          case 'electricity_saving':
            dynamicTarget = threeMonthAverages['electricity'] ?? dynamicTarget;
            // Elektrik tasarrufu yüzdesi: (Önceki ay - Bu ay) / Önceki ay * 100
            if (previousMonthElectricity > 0) {
              final saving = previousMonthElectricity - currentMonthElectricity;
              newMonthlyChangePercent =
                  (saving / previousMonthElectricity) * 100;
              newCurrent = newMonthlyChangePercent;
              // Negatif değerler (artış) için 0 göster
              if (newCurrent < 0) newCurrent = 0;
            } else {
              newCurrent = 0.0;
              newMonthlyChangePercent = 0.0;
            }
            if (newCurrent < dynamicTarget) {
              final needed = (dynamicTarget - newCurrent).clamp(0.0, 100.0);
              newRecommendation = _buildHourlyReductionSuggestion(
                locale: locale,
                hourlySums: electricityHourly,
                neededPercent: needed,
                resourceLabelTr: 'elektrik',
                resourceLabelEn: 'electricity',
              );
            } else {
              newRecommendation = '';
            }
            break;
          case 'co2_reduction':
            dynamicTarget = threeMonthAverages['co2'] ?? dynamicTarget;
            // CO2 azaltma (kg) - gerçek emisyon faktörüyle hesapla
            // Önceki ayın CO2 emisyonu - Bu ayın CO2 emisyonu
            final previousMonthCO2 =
                previousMonthGas * Calculation.factorNaturalGasKgPerM3;
            final currentMonthCO2 =
                currentMonthGas * Calculation.factorNaturalGasKgPerM3;
            final reduction = previousMonthCO2 - currentMonthCO2;
            if (previousMonthCO2 > 0) {
              newMonthlyChangePercent = (reduction / previousMonthCO2) * 100;
            } else {
              newMonthlyChangePercent = 0.0;
            }
            // Negatif değerler (artış) için 0 göster
            newCurrent = reduction > 0 ? reduction : 0.0;
            if (newCurrent < dynamicTarget) {
              final missingKg =
                  (dynamicTarget - newCurrent).clamp(0.0, double.infinity);
              if (locale.languageCode == 'tr') {
                newRecommendation =
                    'Önceki 3 ay ortalamasına ulaşmak için bu ay yaklaşık ${missingKg.toStringAsFixed(1)} kg CO₂e daha azaltmalısınız.';
              } else {
                newRecommendation =
                    'To reach the 3-month dynamic target, reduce about ${missingKg.toStringAsFixed(1)} kg CO₂e more this month.';
              }
            } else {
              newRecommendation = '';
            }
            break;
          case 'water_saving':
            dynamicTarget = threeMonthAverages['water'] ?? dynamicTarget;
            // Su tasarrufu yüzdesi: (Önceki ay - Bu ay) / Önceki ay * 100
            if (previousMonthWater > 0) {
              final saving = previousMonthWater - currentMonthWater;
              newMonthlyChangePercent = (saving / previousMonthWater) * 100;
              newCurrent = newMonthlyChangePercent;
              // Negatif değerler (artış) için 0 göster
              if (newCurrent < 0) newCurrent = 0;
            } else {
              newCurrent = 0.0;
              newMonthlyChangePercent = 0.0;
            }
            if (newCurrent < dynamicTarget) {
              final needed = (dynamicTarget - newCurrent).clamp(0.0, 100.0);
              newRecommendation = _buildHourlyReductionSuggestion(
                locale: locale,
                hourlySums: waterHourly,
                neededPercent: needed,
                resourceLabelTr: 'su',
                resourceLabelEn: 'water',
              );
            } else {
              newRecommendation = '';
            }
            break;
          case 'waste_reduction':
          case 'custom':
            // Otomatik ilerleme yok; mevcut değer korunur
            newCurrent = null;
            newMonthlyChangePercent = 0.0;
            newRecommendation = '';
            break;
        }

        if (newCurrent != null && (goalData['current'] ?? 0.0) != newCurrent) {
          goalData['current'] = newCurrent;
          updated = true;
        }
        if ((goalData['target'] ?? 0.0) != dynamicTarget) {
          goalData['target'] = dynamicTarget;
          updated = true;
        }
        if ((goalData['monthlyChangePercent'] ?? 0.0) !=
            newMonthlyChangePercent) {
          goalData['monthlyChangePercent'] = newMonthlyChangePercent;
          updated = true;
        }
        if ((goalData['recommendation'] ?? '') != newRecommendation) {
          goalData['recommendation'] = newRecommendation;
          updated = true;
        }
      }

      if (updated) {
        await _firebaseService.saveGoals(_userId!, goalsData);
        // Hedef güncellendi, rozet kontrolü yap
        await _checkAndUnlockBadges();
      }
    } catch (e) {
      // Hata durumunda sessizce devam et
    }
  }

  Future<Map<String, double>> _calculateThreeMonthAverageReductions(
    DateTime currentMonthStart,
  ) async {
    final start =
        DateTime(currentMonthStart.year, currentMonthStart.month - 4, 1);
    final end = currentMonthStart.subtract(const Duration(days: 1));
    final entries = await _firebaseService.getHistoryData(
      deviceId: 'esp8266_001',
      startDate: start,
      endDate: end,
    );
    final monthTotals = <String, Map<String, double>>{};
    for (final entry in entries) {
      final key =
          '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}';
      final bucket = monthTotals.putIfAbsent(
        key,
        () => {'electricity': 0.0, 'water': 0.0, 'co2': 0.0},
      );
      bucket['electricity'] =
          (bucket['electricity'] ?? 0) + entry.electricityKwh;
      bucket['water'] = (bucket['water'] ?? 0) + entry.waterCubicMeters;
      bucket['co2'] = (bucket['co2'] ?? 0) +
          (entry.fuelLiters * Calculation.factorNaturalGasKgPerM3);
    }

    final keys = monthTotals.keys.toList()..sort();
    if (keys.length < 2) {
      return {'electricity': 20.0, 'water': 25.0, 'co2': 15.0};
    }

    double avgReductionFor(String metric) {
      final reductions = <double>[];
      for (int i = 1; i < keys.length; i++) {
        final prev = monthTotals[keys[i - 1]]?[metric] ?? 0.0;
        final curr = monthTotals[keys[i]]?[metric] ?? 0.0;
        if (prev > 0) {
          reductions.add(((prev - curr) / prev) * 100);
        }
      }
      if (reductions.isEmpty) {
        return metric == 'water' ? 25.0 : (metric == 'co2' ? 15.0 : 20.0);
      }
      final avg = reductions.reduce((a, b) => a + b) / reductions.length;
      final fallback =
          metric == 'water' ? 25.0 : (metric == 'co2' ? 15.0 : 20.0);
      return avg.isFinite ? avg.clamp(5.0, 40.0) : fallback;
    }

    return {
      'electricity': avgReductionFor('electricity'),
      'water': avgReductionFor('water'),
      'co2': avgReductionFor('co2'),
    };
  }

  Map<int, double> _buildHourlySums(
    List<ConsumptionEntry> entries, {
    required bool forElectricity,
  }) {
    final result = <int, double>{};
    for (final entry in entries) {
      final hour = entry.createdAt.hour;
      result[hour] = (result[hour] ?? 0) +
          (forElectricity ? entry.electricityKwh : entry.waterCubicMeters);
    }
    return result;
  }

  String _buildHourlyReductionSuggestion({
    required Locale locale,
    required Map<int, double> hourlySums,
    required double neededPercent,
    required String resourceLabelTr,
    required String resourceLabelEn,
  }) {
    if (hourlySums.isEmpty) {
      return locale.languageCode == 'tr'
          ? 'Yeterli saatlik veri oluşunca otomatik saat önerisi gösterilecek.'
          : 'Hourly suggestion will appear when enough data is available.';
    }
    final topHours = hourlySums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = topHours
        .take(2)
        .map((e) => '${e.key.toString().padLeft(2, '0')}:00')
        .join(', ');
    final percentText = neededPercent.toStringAsFixed(1);
    if (locale.languageCode == 'tr') {
      return 'Hedef için $resourceLabelTr kullanımını $top saatlerinde yaklaşık %$percentText azaltın.';
    }
    return 'To hit the target, reduce $resourceLabelEn usage by about $percentText% around $top.';
  }

  /// Raporlar ekranı ile uyumlu: ham küresel seriyi kg/gün kişi başı ölçeğine indirger.
  double _globalRawToPerCapitaDailyKg(double value) {
    if (value <= 0.0) {
      return 0.0;
    }
    if (value > 1000000000.0) {
      return value / 8000000000.0;
    }
    if (value > 1000.0) {
      return value / 2920.0;
    }
    return value;
  }

  Future<Map<DateTime, double>> _buildDailyEspCo2Totals(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final espHistory = await _firebaseService.getHistoryData(
      deviceId: 'esp8266_001',
      startDate: startDate,
      endDate: endDate,
    );
    DateTime dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
    final Map<DateTime, ConsumptionEntry> latest = {};
    for (final entry in espHistory) {
      final key = dayKey(entry.createdAt);
      final current = latest[key];
      if (current == null || entry.createdAt.isAfter(current.createdAt)) {
        latest[key] = entry;
      }
    }
    final totals = <DateTime, double>{};
    for (final e in latest.values) {
      final k = dayKey(e.createdAt);
      totals[k] = Calculation.calculateDailyEmission(e);
    }
    return totals;
  }

  Future<void> _refreshPrediction() async {
    if (_userId == null) return;
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final isTr = locale.languageCode == 'tr';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final elapsedDays = now.day.clamp(1, daysInMonth);
    final today =
        DateTime(now.year, now.month, now.day);

    if (mounted) {
      setState(() => _predictionLoading = true);
    }

    try {
      final reductionGoal = _goals.firstWhere(
        (g) => g.type == 'co2_reduction',
        orElse: () => CarbonGoal(
          id: 'fallback_co2',
          title: '',
          target: 15,
          current: 0,
          monthlyChangePercent: 0,
          recommendation: '',
          unit: 'kg',
          type: 'co2_reduction',
          icon: Icons.eco,
          color: const Color(0xFF48631F),
        ),
      );
      final double targetMonthEndKg =
          reductionGoal.target.clamp(0.0, double.infinity);

      final dailyTotals = await _buildDailyCombinedTotals(monthStart, now);
      final last7 = _lastSevenDaysSeries(dailyTotals, now);
      final double estimatedDailyAverage =
          _estimateDailyAverageFromSeries(last7);
      final double projectedMonthEnd =
          estimatedDailyAverage * daysInMonth.toDouble();

      final bool isOnTrack = targetMonthEndKg <= 0.0
          ? true
          : projectedMonthEnd <= targetMonthEndKg;
      final int remainingDays =
          (daysInMonth - elapsedDays).clamp(0, daysInMonth);

      final double gaugeEfficiency = targetMonthEndKg <= 0.0
          ? 1.0
          : math.min(
              1.0,
              targetMonthEndKg /
                  math.max(projectedMonthEnd, 1e-9),
            );

      double worldDailyRefKg = 4.1;
      try {
        final trend =
            await GlobalCarbonService().getGlobalDailyTrend();
        if (trend.isNotEmpty) {
          double sum = 0.0;
          for (final v in trend) {
            sum += _globalRawToPerCapitaDailyKg(v.toDouble());
          }
          worldDailyRefKg = sum / trend.length.toDouble();
        }
      } catch (_) {}

      final double userDaily = estimatedDailyAverage;
      final double diffWorldDaily = userDaily - worldDailyRefKg;
      final bool worldRoughlyEqual = diffWorldDaily.abs() < 1e-6;
      final bool isBetterThanWorld =
          !worldRoughlyEqual && diffWorldDaily < 0.0;
      double worldDiffPct = 0.0;
      if (worldDailyRefKg > 1e-9 && !worldRoughlyEqual) {
        worldDiffPct =
            (diffWorldDaily.abs() / worldDailyRefKg) * 100.0;
      }

      final windowStart = today.subtract(const Duration(days: 13));
      final espDaily =
          await _buildDailyEspCo2Totals(windowStart, now);

      double sumLast7Esp = 0.0;
      double sumPrev7Esp = 0.0;
      for (int i = 0; i < 7; i++) {
        final d = today.subtract(Duration(days: i));
        final key = DateTime(d.year, d.month, d.day);
        sumLast7Esp += (espDaily[key] ?? 0.0);
      }
      for (int i = 7; i < 14; i++) {
        final d = today.subtract(Duration(days: i));
        final key = DateTime(d.year, d.month, d.day);
        sumPrev7Esp += (espDaily[key] ?? 0.0);
      }

      final Map<DateTime, double> combinedWindow =
          await _buildDailyCombinedTotals(windowStart, now);
      double sumLast7Comb = 0.0;
      double sumPrev7Comb = 0.0;
      for (int i = 0; i < 7; i++) {
        final d = today.subtract(Duration(days: i));
        final key = DateTime(d.year, d.month, d.day);
        sumLast7Comb += (combinedWindow[key] ?? 0.0);
      }
      for (int i = 7; i < 14; i++) {
        final d = today.subtract(Duration(days: i));
        final key = DateTime(d.year, d.month, d.day);
        sumPrev7Comb += (combinedWindow[key] ?? 0.0);
      }

      final bool useEspWhy = sumPrev7Esp > 1e-9 || sumLast7Esp > 1e-9;
      final double deltaSrc = useEspWhy
          ? (sumPrev7Esp > 1e-9
              ? ((sumLast7Esp - sumPrev7Esp) / sumPrev7Esp) * 100.0
              : 0.0)
          : (sumPrev7Comb > 1e-9
              ? ((sumLast7Comb - sumPrev7Comb) / sumPrev7Comb) * 100.0
              : 0.0);

      final String insightWhyTr = useEspWhy
          ? (sumPrev7Esp > 1e-9
              ? 'ESP8266 tabanlı günlük emisyon (son 7 gün), önceki 7 güne göre %${deltaSrc.abs().toStringAsFixed(3)} ${deltaSrc >= 0.0 ? 'arttı' : 'azaldı'}.'
              : 'ESP8266 için henüz iki haftalık karşılaştırma için yeterli veri yok; kombine seri kullanıldı.')
          : (sumPrev7Comb > 1e-9
              ? 'Kombine ölçüm (Manuel + ESP + Shelly) bu hafta önceki haftaya göre %${deltaSrc.abs().toStringAsFixed(3)} ${deltaSrc >= 0.0 ? 'yükseldi' : 'düştü'}.'
              : 'Karşılaştırma için henüz yeterli günlük veri yok.');

      final String insightWhyEn = useEspWhy
          ? (sumPrev7Esp > 1e-9
              ? 'ESP-based daily emissions vs prior 7 days: ${deltaSrc >= 0.0 ? 'up' : 'down'} %${deltaSrc.abs().toStringAsFixed(3)}.'
              : 'Not enough ESP history for two-week compare; combined series used.')
          : (sumPrev7Comb > 1e-9
              ? 'Combined footprint vs prior week: ${deltaSrc >= 0.0 ? 'up' : 'down'} %${deltaSrc.abs().toStringAsFixed(3)}.'
              : 'Not enough daily data for comparison yet.');

      final double targetDailyPace =
          daysInMonth > 0 ? targetMonthEndKg / daysInMonth.toDouble() : 0.0;
      final double excessDaily =
          math.max(0.0, estimatedDailyAverage - targetDailyPace);
      final double tipReductionKg =
          excessDaily * remainingDays.toDouble() * 0.12;

      final String insightTipTr = excessDaily > 1e-9
          ? (tipReductionKg > 1e-9
              ? 'Günlük ortalamayı hedefe yaklaştırmak için bekleme modundaki cihazları azaltırsan tahmini ${tipReductionKg.toStringAsFixed(3)} kg CO₂e düşebilir.'
              : 'Günlük tempo hedefin biraz üzerinde; küçük verim iyileştirmeleri fark yaratır.')
          : 'Tahmini düşürmek için Shelly ile ölçülen fişleri gece kapalı tutmayı veya manuel kayıtları güncel tutmayı dene.';

      final String insightTipEn = excessDaily > 1e-9
          ? (tipReductionKg > 1e-9
              ? 'Reducing standby use could lower the forecast by about ${tipReductionKg.toStringAsFixed(3)} kg CO₂e this month.'
              : 'Daily pace is slightly above target; small efficiency gains help.')
          : 'Try powering down idle Shelly plugs overnight or updating manual logs to trim the forecast.';

      final trendText = isTr
          ? 'Son 7 gün (Manuel + ESP + Shelly) üzerinden tahmin.'
          : 'Forecast from last 7 days (Manual + ESP + Shelly).';

      if (mounted) {
        setState(() {
          _monthlyPrediction = MonthlyPrediction(
            projectedMonthEndKg: projectedMonthEnd,
            targetMonthEndKg: targetMonthEndKg,
            currentAverageKgPerDay: estimatedDailyAverage,
            daysElapsed: elapsedDays,
            daysInMonth: daysInMonth,
            remainingDays: remainingDays,
            isOnTrack: isOnTrack,
            trackMessage: isOnTrack
                ? (isTr
                    ? 'Bu gidişle hedefe ulaşırsın.'
                    : 'At this pace, you will reach the goal.')
                : (isTr
                    ? 'Bu gidişle hedefe ulaşamazsın.'
                    : 'At this pace, you may miss the goal.'),
            impactSummary: trendText,
            gaugeEfficiency: gaugeEfficiency,
            worldDiffPercent: worldDiffPct,
            isBetterThanWorldAverage: isBetterThanWorld,
            worldRoughlyEqual: worldRoughlyEqual,
            insightWhyTr: insightWhyTr,
            insightWhyEn: insightWhyEn,
            insightTipTr: insightTipTr,
            insightTipEn: insightTipEn,
          );
        });
      }
    } catch (_) {
      // Sessiz devam
    } finally {
      if (mounted) {
        setState(() => _predictionLoading = false);
      }
    }
  }

  Future<Map<DateTime, double>> _buildDailyCombinedTotals(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final espHistory = await _firebaseService.getHistoryData(
      deviceId: 'esp8266_001',
      startDate: startDate,
      endDate: endDate,
    );

    List<ConsumptionEntry> shellyHistory = [];
    try {
      final shellyData = await _apiService.getFirebaseShellyHistory(
        deviceId: 'shelly_plug_001',
        startDate: startDate,
        endDate: endDate,
      );
      shellyHistory = shellyData
          .map((item) => _apiService.shellyDataToConsumptionEntry(item))
          .toList();
    } catch (_) {}

    List<ConsumptionEntry> manualHistory = [];
    try {
      if (_userId != null) {
        manualHistory = await _firebaseService.getManualHistoryData(
          userId: _userId!,
          startDate: startDate,
          endDate: endDate,
        );
      }
    } catch (_) {}

    DateTime dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    final Map<DateTime, ConsumptionEntry> latestEsp = {};
    final Map<DateTime, ConsumptionEntry> latestShelly = {};
    final Map<DateTime, ConsumptionEntry> latestManual = {};

    void pushLatest(
      Map<DateTime, ConsumptionEntry> target,
      ConsumptionEntry entry,
    ) {
      final key = dayKey(entry.createdAt);
      final current = target[key];
      if (current == null || entry.createdAt.isAfter(current.createdAt)) {
        target[key] = entry;
      }
    }

    for (final entry in espHistory) {
      pushLatest(latestEsp, entry);
    }
    for (final entry in shellyHistory) {
      pushLatest(latestShelly, entry);
    }
    for (final entry in manualHistory) {
      pushLatest(latestManual, entry);
    }

    final allDays = <DateTime>{
      ...latestEsp.keys,
      ...latestShelly.keys,
      ...latestManual.keys,
    };

    final totals = <DateTime, double>{};
    for (final day in allDays) {
      final manual = latestManual[day];
      final esp = latestEsp[day];
      final shelly = latestShelly[day];

      if (manual != null) {
        totals[day] = Calculation.calculateDailyEmission(manual);
        continue;
      }
      if (esp != null && shelly != null) {
        final combined = ConsumptionEntry(
          electricityKwh: shelly.electricityKwh,
          waterCubicMeters: esp.waterCubicMeters,
          fuelLiters: esp.fuelLiters,
          wasteKg: (esp.wasteKg + shelly.wasteKg) / 2,
          createdAt: shelly.createdAt.isAfter(esp.createdAt)
              ? shelly.createdAt
              : esp.createdAt,
          fuelIsNaturalGasM3: esp.fuelIsNaturalGasM3,
        );
        totals[day] = Calculation.calculateDailyEmission(combined);
      } else if (esp != null) {
        totals[day] = Calculation.calculateDailyEmission(esp);
      } else if (shelly != null) {
        totals[day] = Calculation.calculateDailyEmission(shelly);
      }
    }
    return totals;
  }

  List<double> _lastSevenDaysSeries(
      Map<DateTime, double> dailyTotals, DateTime now) {
    final series = <double>[];
    for (int i = 6; i >= 0; i--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      series.add((dailyTotals[day] ?? 0.0).clamp(0.0, double.infinity));
    }
    return series;
  }

  double _estimateDailyAverageFromSeries(List<double> series) {
    final cleaned = series.map((e) => e.clamp(0.0, double.infinity)).toList();
    final indexed =
        cleaned.asMap().entries.where((entry) => entry.value > 0).toList();
    if (indexed.isEmpty) return 0.0;
    if (indexed.length == 1) return indexed.first.value;

    final tail = indexed.skip(math.max(0, indexed.length - 3)).toList();
    final weights = tail.length == 1
        ? const [1.0]
        : tail.length == 2
            ? const [0.4, 0.6]
            : const [0.2, 0.3, 0.5];
    double weighted = 0;
    double totalWeight = 0;
    for (int i = 0; i < tail.length; i++) {
      weighted += tail[i].value * weights[i];
      totalWeight += weights[i];
    }
    final weightedAvg =
        totalWeight > 0 ? (weighted / totalWeight) : tail.last.value;

    final xs = indexed.map((e) => e.key.toDouble()).toList();
    final ys = indexed.map((e) => e.value).toList();
    final xMean = xs.reduce((a, b) => a + b) / xs.length;
    final yMean = ys.reduce((a, b) => a + b) / ys.length;
    double numerator = 0;
    double denominator = 0;
    for (int i = 0; i < xs.length; i++) {
      numerator += (xs[i] - xMean) * (ys[i] - yMean);
      denominator += math.pow(xs[i] - xMean, 2).toDouble();
    }
    final slope = denominator == 0 ? 0.0 : numerator / denominator;
    final intercept = yMean - slope * xMean;
    final regressionNext = (intercept + slope * 7).clamp(0.0, double.infinity);

    return ((weightedAvg * 0.7) + (regressionNext * 0.3))
        .clamp(0.0, double.infinity);
  }

  Future<void> _awardPoints(int points) async {
    if (_userId == null) {
      // Kullanıcı giriş yapmamış, sadece local state'i güncelle
      setState(() {
        _greenScore = (_greenScore + points).clamp(0, 1000000);
      });
      return;
    }

    final newScore = (_greenScore + points).clamp(0, 1000000);
    setState(() => _greenScore = newScore);

    try {
      await _firebaseService.saveGreenScore(_userId!, newScore);
      // Rozet kontrolü yap
      await _checkAndUnlockBadges();
    } catch (e) {
      // Hata durumunda local state'i koru
    }
  }

  /// Rozet kontrolü yap ve gerekirse aç
  Future<void> _checkAndUnlockBadges() async {
    if (_userId == null) return;

    final Map<String, bool> newBadges = Map.from(_badges);
    bool hasNewBadge = false;
    String? newBadgeName;

    // Çevre Dostu: 100+ puan
    if (_greenScore >= 100 && !_badges['environment_friendly']!) {
      newBadges['environment_friendly'] = true;
      hasNewBadge = true;
      newBadgeName = 'environment_friendly';
    }

    // Enerji Tasarrufu: 200+ puan
    if (_greenScore >= 200 && !_badges['energy_saving']!) {
      newBadges['energy_saving'] = true;
      hasNewBadge = true;
      newBadgeName = 'energy_saving';
    }

    // Su Koruyucusu: 150+ puan
    if (_greenScore >= 150 && !_badges['water_protector']!) {
      newBadges['water_protector'] = true;
      hasNewBadge = true;
      newBadgeName = 'water_protector';
    }

    // Hedef Ustası: Tüm hedefleri tamamla
    final allGoalsCompleted =
        _goals.isNotEmpty && _goals.every((goal) => goal.progress >= 1.0);
    if (allGoalsCompleted && !_badges['goal_master']!) {
      newBadges['goal_master'] = true;
      hasNewBadge = true;
      newBadgeName = 'goal_master';
    }

    // Eko Savaşçı: 500+ puan
    if (_greenScore >= 500 && !_badges['eco_warrior']!) {
      newBadges['eco_warrior'] = true;
      hasNewBadge = true;
      newBadgeName = 'eco_warrior';
    }

    if (hasNewBadge) {
      setState(() => _badges = newBadges);
      try {
        await _firebaseService.saveBadges(_userId!, newBadges);
        if (mounted && newBadgeName != null) {
          _showBadgeUnlockedDialog(newBadgeName);
        }
      } catch (e) {
        // Hata durumunda sessizce devam et
      }
    }
  }

  /// Yeni rozet açıldığında dialog göster
  void _showBadgeUnlockedDialog(String badgeKey) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    String badgeTitle = '';
    IconData badgeIcon = Icons.star;

    switch (badgeKey) {
      case 'environment_friendly':
        badgeTitle = translate('environment_friendly', locale);
        badgeIcon = Icons.eco;
        break;
      case 'energy_saving':
        badgeTitle = translate('energy_saving', locale);
        badgeIcon = Icons.energy_savings_leaf;
        break;
      case 'water_protector':
        badgeTitle = translate('water_protector', locale);
        badgeIcon = Icons.water_drop;
        break;
      case 'goal_master':
        badgeTitle = translate('goal_master', locale);
        badgeIcon = Icons.emoji_events;
        break;
      case 'eco_warrior':
        badgeTitle = translate('eco_warrior', locale);
        badgeIcon = Icons.local_fire_department;
        break;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Colors.amber, Colors.orange],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(badgeIcon, color: Colors.white, size: 40),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              translate('badge_unlocked', locale),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              badgeTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(translate('ok', locale)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _greenScoreSubscription?.cancel();
    _goalsSubscription?.cancel();
    _consumptionSubscription?.cancel();
    _badgesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: null,
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: null,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // İçerik - Web için genişlik kısıtlaması
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isWide = constraints.maxWidth >= 900;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 800 : double.infinity,
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 +
                          MediaQuery.of(context).padding.bottom +
                          80, // Bottom nav bar için ekstra padding
                    ),
                    children: [
                      // Başarı rozetleri başlığı - Konteynır dışında
                      Row(
                        children: [
                          Icon(
                            Icons.emoji_events,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            translate('achievement_badges', locale),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message:
                                translate('achievement_badges_info', locale),
                            child: InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(translate(
                                        'achievement_badges', locale)),
                                    content: Text(
                                      translate(
                                          'achievement_badges_info', locale),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: Text(translate('ok', locale)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: const Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Başarı rozetleri konteynırı
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: isDark
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.1),
                                      ],
                                    ),
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.4)
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (Theme.of(context).brightness ==
                                        Brightness.dark)
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.primary,
                                width: isDark ? 1 : 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // Kazanılan rozet sayısı
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          )
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${_badges.values.where((v) => v).length}/${_badges.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Instagram story tarzı yuvarlak rozet butonları
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final bool isWide =
                                          constraints.maxWidth >= 900;
                                      if (isWide) {
                                        // Web'de rozetleri tam ortala
                                        return Center(
                                          child: Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: [
                                              _AchievementBadge(
                                                imagePath:
                                                    'assets/images/1rozet.png',
                                                title: translate(
                                                  'environment_friendly',
                                                  locale,
                                                ),
                                                isUnlocked:
                                                    true, // Çevre dostu rozeti her zaman açık
                                              ),
                                              _AchievementBadge(
                                                imagePath:
                                                    'assets/images/3rozet.png',
                                                title: translate(
                                                    'energy_saving', locale),
                                                isUnlocked:
                                                    _badges['energy_saving'] ??
                                                        false,
                                              ),
                                              _AchievementBadge(
                                                imagePath:
                                                    'assets/images/2rozet.png',
                                                title: translate(
                                                    'water_protector', locale),
                                                isUnlocked: _badges[
                                                        'water_protector'] ??
                                                    false,
                                              ),
                                              _AchievementBadge(
                                                imagePath:
                                                    'assets/images/4rozet.png',
                                                title: translate(
                                                    'goal_master', locale),
                                                isUnlocked:
                                                    _badges['goal_master'] ??
                                                        false,
                                              ),
                                              _AchievementBadge(
                                                imagePath:
                                                    'assets/images/5rozet.png',
                                                title: translate(
                                                    'eco_warrior', locale),
                                                isUnlocked:
                                                    _badges['eco_warrior'] ??
                                                        false,
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      // Mobil/tablet: yatay scroll
                                      return SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _AchievementBadge(
                                              imagePath:
                                                  'assets/images/1rozet.png',
                                              title: translate(
                                                'environment_friendly',
                                                locale,
                                              ),
                                              isUnlocked:
                                                  true, // Çevre dostu rozeti her zaman açık
                                            ),
                                            const SizedBox(width: 12),
                                            _AchievementBadge(
                                              imagePath:
                                                  'assets/images/2rozet.png',
                                              title: translate(
                                                  'energy_saving', locale),
                                              isUnlocked:
                                                  _badges['energy_saving'] ??
                                                      false,
                                            ),
                                            const SizedBox(width: 12),
                                            _AchievementBadge(
                                              imagePath:
                                                  'assets/images/3rozet.png',
                                              title: translate(
                                                  'water_protector', locale),
                                              isUnlocked:
                                                  _badges['water_protector'] ??
                                                      false,
                                            ),
                                            const SizedBox(width: 12),
                                            _AchievementBadge(
                                              imagePath:
                                                  'assets/images/4rozet.png',
                                              title: translate(
                                                  'goal_master', locale),
                                              isUnlocked:
                                                  _badges['goal_master'] ??
                                                      false,
                                            ),
                                            const SizedBox(width: 12),
                                            _AchievementBadge(
                                              imagePath:
                                                  'assets/images/5rozet.png',
                                              title: translate(
                                                  'eco_warrior', locale),
                                              isUnlocked:
                                                  _badges['eco_warrior'] ??
                                                      false,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  // Alt boşluk - üst boşlukla eşit olması için
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Gelecek Ay Beklentisi başlığı - Konteynır dışında
                      Row(
                        children: [
                          Icon(
                            Icons.auto_graph,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            locale.languageCode == 'tr'
                                ? 'Gelecek Ay Beklentisi'
                                : 'Next Month Outlook',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_userId != null) ...[
                        if (_predictionLoading && _monthlyPrediction == null)
                          _PredictionLoadingShell(isDark: isDark)
                        else if (_monthlyPrediction != null)
                          _PredictionCard(
                            prediction: _monthlyPrediction!,
                            languageProvider: widget.languageProvider,
                            loadingOverlay: _predictionLoading,
                          ),
                      ],
                      const SizedBox(height: 32),
                      // Green Score başlığı - Konteynır dışında
                      Row(
                        children: [
                          Icon(
                            Icons.energy_savings_leaf,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            translate('green_score', locale),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: translate('green_score_info', locale),
                            child: InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title:
                                        Text(translate('green_score', locale)),
                                    content: Text(
                                      translate('green_score_info', locale),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: Text(translate('ok', locale)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: const Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Green Score (Yeşil Puan) bölümü - İyileştirilmiş
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: isDark
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.1),
                                      ],
                                    ),
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.4)
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: isDark ? 1 : 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Üst: Başlık ve puan kaldı
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        translate('next_level', locale),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: (isDark
                                                      ? Colors.white
                                                      : Colors.black)
                                                  .withValues(alpha: 0.7),
                                            ),
                                      ),
                                      Text(
                                        '${100 - (_greenScore % 100)} ${translate('points_to_go', locale)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Alt: Üç kısım aynı satırda
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Sol: İlerleme çubuğu
                                      Expanded(
                                        flex: 2,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final progressValue =
                                                ((_greenScore % 100) / 100)
                                                    .clamp(
                                              0.0,
                                              1.0,
                                            );
                                            return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child:
                                                  TweenAnimationBuilder<double>(
                                                tween: Tween<double>(
                                                  begin: 0.0,
                                                  end: progressValue,
                                                ),
                                                duration: const Duration(
                                                    milliseconds: 1000),
                                                curve: Curves.easeInOut,
                                                builder:
                                                    (context, value, child) {
                                                  return Container(
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      color: Colors.white
                                                          .withValues(
                                                        alpha: 0.2,
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      clipBehavior: Clip.none,
                                                      children: [
                                                        FractionallySizedBox(
                                                          widthFactor: value,
                                                          child: Container(
                                                            decoration:
                                                                BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          10),
                                                              gradient:
                                                                  LinearGradient(
                                                                colors: [
                                                                  Colors.orange
                                                                      .shade600,
                                                                  Colors.orange
                                                                      .shade400,
                                                                  Colors.orange
                                                                      .shade300,
                                                                ],
                                                                begin: Alignment
                                                                    .centerLeft,
                                                                end: Alignment
                                                                    .centerRight,
                                                              ),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: Colors
                                                                      .orange
                                                                      .withValues(
                                                                          alpha:
                                                                              0.5),
                                                                  blurRadius: 8,
                                                                  spreadRadius:
                                                                      1,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Orta: Sanal ağaç kutucuğu (ikon + 2 rakamı)
                                      Tooltip(
                                        message:
                                            '${(_greenScore ~/ 100)} ${translate('virtual_tree', locale)}',
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: isDark
                                                ? null
                                                : LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Theme.of(
                                                        context,
                                                      )
                                                          .colorScheme
                                                          .primary
                                                          .withValues(
                                                              alpha: 0.2),
                                                      Theme.of(
                                                        context,
                                                      )
                                                          .colorScheme
                                                          .primary
                                                          .withValues(
                                                              alpha: 0.1),
                                                    ],
                                                  ),
                                            color: isDark
                                                ? Colors.black
                                                    .withValues(alpha: 0.4)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              width: 2,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.energy_savings_leaf,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                size: 20,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${(_greenScore ~/ 100)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: (isDark
                                                              ? Colors.white
                                                              : Colors.black)
                                                          .withValues(
                                                              alpha: 0.9),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Sağ: Puan kutucuğu (221 puan)
                                      Container(
                                        width: 80,
                                        height: 80,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: isDark
                                              ? null
                                              : LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Theme.of(
                                                      context,
                                                    )
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.3),
                                                    Theme.of(
                                                      context,
                                                    )
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.2),
                                                  ],
                                                ),
                                          color: isDark
                                              ? Colors.black
                                                  .withValues(alpha: 0.4)
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            width: 2,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '$_greenScore',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 20,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              translate('points', locale),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: (isDark
                                                            ? Colors.white
                                                            : Colors.black)
                                                        .withValues(alpha: 0.7),
                                                    fontSize: 9,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  // İstatistikler
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _StatCard(
                                          icon: Icons.flag,
                                          value: '${_goals.length}',
                                          label:
                                              translate('total_goals', locale),
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _StatCard(
                                          icon: Icons.check_circle,
                                          value:
                                              '${_goals.where((g) => g.progress >= 1.0).length}',
                                          label: translate(
                                              'completed_goals', locale),
                                          color: Colors.green,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _StatCard(
                                          icon: Icons.emoji_events,
                                          value:
                                              '${_badges.values.where((v) => v).length}',
                                          label: translate(
                                              'badges_earned', locale),
                                          color: Colors.amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  // Davranış eylemleri (puan kazandırır)
                                  Text(
                                    translate('earn_points', locale),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withValues(alpha: 0.8),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final bool isMobile =
                                          constraints.maxWidth < 600;
                                      if (isMobile) {
                                        // Mobil: 2x2 grid
                                        return Column(
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _ActionChip(
                                                    icon: Icons.recycling,
                                                    label: translate(
                                                        'recycle', locale),
                                                    points: 10,
                                                    onTap: () =>
                                                        _awardPoints(10),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _ActionChip(
                                                    icon: Icons.directions_walk,
                                                    label: translate(
                                                        'walk', locale),
                                                    points: 5,
                                                    onTap: () =>
                                                        _awardPoints(5),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _ActionChip(
                                                    icon: Icons.directions_bus,
                                                    label: translate(
                                                      'public_transport',
                                                      locale,
                                                    ),
                                                    points: 12,
                                                    onTap: () =>
                                                        _awardPoints(12),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _ActionChip(
                                                    icon: Icons.water_drop,
                                                    label: translate(
                                                      'save_water',
                                                      locale,
                                                    ),
                                                    points: 6,
                                                    onTap: () =>
                                                        _awardPoints(6),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      } else {
                                        // Tablet/Desktop: Yatay
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: _ActionChip(
                                                icon: Icons.recycling,
                                                label: translate(
                                                    'recycle', locale),
                                                points: 10,
                                                onTap: () => _awardPoints(10),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _ActionChip(
                                                icon: Icons.directions_walk,
                                                label:
                                                    translate('walk', locale),
                                                points: 5,
                                                onTap: () => _awardPoints(5),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _ActionChip(
                                                icon: Icons.directions_bus,
                                                label: translate(
                                                  'public_transport',
                                                  locale,
                                                ),
                                                points: 12,
                                                onTap: () => _awardPoints(12),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _ActionChip(
                                                icon: Icons.water_drop,
                                                label: translate(
                                                    'save_water', locale),
                                                points: 6,
                                                onTap: () => _awardPoints(6),
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Hedef kartları
                      if (_goals.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              translate('no_goals', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color:
                                        (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.7),
                                  ),
                            ),
                          ),
                        )
                      else
                        ..._goals.map(
                          (goal) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _GoalCard(
                              goal: goal,
                              languageProvider: widget.languageProvider,
                              onDelete: _userId != null
                                  ? () => _deleteGoal(goal.id)
                                  : null,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Yeni hedef ekleme butonu
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? [
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.1),
                                      ]
                                    : [
                                        // Açık temada yeşil tonları
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                        Theme.of(
                                          context,
                                        )
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.1),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    translate('set_new_goal', locale),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    translate('set_new_goal_help', locale),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withValues(alpha: 0.65),
                                          height: 1.35,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _userId != null
                                        ? () => _showAddGoalDialog()
                                        : null,
                                    style: ButtonStyle(
                                      minimumSize: const WidgetStatePropertyAll(
                                        Size.fromHeight(48),
                                      ),
                                      shape: WidgetStatePropertyAll(
                                        StadiumBorder(
                                          side: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add),
                                    label: Text(translate('add_goal', locale)),
                                  ),
                                  if (_userId == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        translate(
                                            'login_required_for_goals', locale),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: (isDark
                                                      ? Colors.white
                                                      : Colors.black)
                                                  .withValues(alpha: 0.6),
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGoal(String goalId) async {
    if (_userId == null) return;

    try {
      await _firebaseService.deleteGoal(_userId!, goalId);
    } catch (e) {
      if (mounted) {
        final locale =
            widget.languageProvider?.currentLocale ?? const Locale('tr');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translate(
                'goal_delete_error',
                locale,
                params: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  void _showAddGoalDialog() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final first = _kGoalAddTemplates.first;
    final titleController = TextEditingController(
      text: translate(first.titleKey, locale),
    );
    final targetController = TextEditingController(text: first.defaultTarget);
    String selectedUnit = first.defaultUnit;
    String selectedType = first.storageType;
    String selectedIconStr = first.iconString;
    int selectedTemplateIndex = 0;

    final borderColor = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyTemplate(int index) {
              final t = _kGoalAddTemplates[index];
              setDialogState(() {
                selectedTemplateIndex = index;
                selectedType = t.storageType;
                selectedUnit = t.defaultUnit;
                selectedIconStr = t.iconString;
                titleController.text = translate(t.titleKey, locale);
                targetController.text = t.defaultTarget;
              });
            }

            final helpKey =
                _kGoalAddTemplates[selectedTemplateIndex].trackingHelpKey;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.82)
                          : Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  translate('add_new_goal', locale),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close),
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            translate('goal_choose_template', locale),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final chipWidth = constraints.maxWidth > 360
                                  ? (constraints.maxWidth - 8) / 2
                                  : constraints.maxWidth;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(
                                  _kGoalAddTemplates.length,
                                  (i) {
                                    final t = _kGoalAddTemplates[i];
                                    final selected = selectedTemplateIndex == i;
                                    return SizedBox(
                                      width: chipWidth,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => applyTemplate(i),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: selected
                                                    ? borderColor
                                                    : borderColor.withValues(
                                                        alpha: 0.45,
                                                      ),
                                                width: selected ? 2 : 1,
                                              ),
                                              color: selected
                                                  ? borderColor.withValues(
                                                      alpha:
                                                          isDark ? 0.22 : 0.14,
                                                    )
                                                  : null,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  t.icon,
                                                  size: 22,
                                                  color: selected
                                                      ? borderColor
                                                      : (isDark
                                                          ? Colors.white70
                                                          : Colors.black54),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    translate(
                                                        t.titleKey, locale),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: isDark
                                                              ? Colors.white
                                                              : Colors.black,
                                                          fontWeight: selected
                                                              ? FontWeight.w600
                                                              : FontWeight.w500,
                                                          height: 1.2,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            translate(helpKey, locale),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: (isDark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.65),
                                  height: 1.3,
                                ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: titleController,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: translate('goal_title', locale),
                              filled: true,
                              fillColor: fieldFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: targetController,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: translate('target_value', locale),
                              filled: true,
                              fillColor: fieldFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              '$selectedTemplateIndex-$selectedUnit',
                            ),
                            initialValue: selectedUnit,
                            decoration: InputDecoration(
                              labelText: translate('unit', locale),
                              filled: true,
                              fillColor: fieldFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            dropdownColor:
                                isDark ? Colors.grey.shade900 : Colors.white,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            items: ['%', 'kg', 'kWh', 'L', 'm³', 'km']
                                .map(
                                  (unit) => DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => selectedUnit = value);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: Text(translate('cancel', locale)),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () async {
                                  final title = titleController.text.trim();
                                  final rawTarget =
                                      targetController.text.trim();
                                  if (title.isEmpty || rawTarget.isEmpty) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            translate(
                                              'goal_fill_required',
                                              locale,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  final target = double.tryParse(
                                    rawTarget.replaceAll(',', '.'),
                                  );
                                  if (target == null || target <= 0) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            translate(
                                              'goal_fill_required',
                                              locale,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  try {
                                    final goal = {
                                      'title': title,
                                      'target': target,
                                      'current': 0.0,
                                      'unit': selectedUnit,
                                      'type': selectedType,
                                      'icon': selectedIconStr,
                                      'color': 0xFF304411,
                                    };

                                    if (_userId != null) {
                                      await _firebaseService.addGoal(
                                        _userId!,
                                        goal,
                                      );
                                    }

                                    if (!mounted) return;
                                    if (dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            translate(
                                              'goal_add_error',
                                              locale,
                                              params: {'error': e.toString()},
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Text(translate('add', locale)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class MonthlyPrediction {
  final double projectedMonthEndKg;
  final double targetMonthEndKg;
  final double currentAverageKgPerDay;
  final int daysElapsed;
  final int daysInMonth;
  final int remainingDays;
  final bool isOnTrack;
  final String trackMessage;
  final String impactSummary;
  final double gaugeEfficiency;
  final double worldDiffPercent;
  final bool isBetterThanWorldAverage;
  final bool worldRoughlyEqual;
  final String insightWhyTr;
  final String insightWhyEn;
  final String insightTipTr;
  final String insightTipEn;

  const MonthlyPrediction({
    required this.projectedMonthEndKg,
    required this.targetMonthEndKg,
    required this.currentAverageKgPerDay,
    required this.daysElapsed,
    required this.daysInMonth,
    required this.remainingDays,
    required this.isOnTrack,
    required this.trackMessage,
    required this.impactSummary,
    required this.gaugeEfficiency,
    required this.worldDiffPercent,
    required this.isBetterThanWorldAverage,
    required this.worldRoughlyEqual,
    required this.insightWhyTr,
    required this.insightWhyEn,
    required this.insightTipTr,
    required this.insightTipEn,
  });
}

/// Tahmin bölümü ilk yüklemede iskelet + shimmer.
class _PredictionLoadingShell extends StatefulWidget {
  const _PredictionLoadingShell({required this.isDark});

  final bool isDark;

  @override
  State<_PredictionLoadingShell> createState() =>
      _PredictionLoadingShellState();
}

class _PredictionLoadingShellState extends State<_PredictionLoadingShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark ? Colors.white : Colors.black;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.2 + 2.4 * t, 0),
              end: Alignment(0.2 + 2.4 * t, 0),
              colors: [
                base.withValues(alpha: 0.06),
                base.withValues(alpha: 0.18),
                base.withValues(alpha: 0.06),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: base.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: base.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Center(
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 14,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: base.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 36,
                          width: 140,
                          decoration: BoxDecoration(
                            color: base.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: base.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: base.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({
    required this.prediction,
    this.languageProvider,
    this.loadingOverlay = false,
  });

  final MonthlyPrediction prediction;
  final LanguageProvider? languageProvider;
  final bool loadingOverlay;

  @override
  Widget build(BuildContext context) {
    final locale = languageProvider?.currentLocale ?? const Locale('tr');
    final isTr = locale.languageCode == 'tr';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final efficiencyPct = (prediction.gaugeEfficiency * 100.0);
    final String badgeLabel = prediction.worldRoughlyEqual
        ? (isTr
            ? 'Küresel günlük ortalamayla aynı hizada'
            : 'Aligned with global daily average')
        : prediction.isBetterThanWorldAverage
            ? (isTr
                ? 'Dünya Ortalamasından %${prediction.worldDiffPercent.toStringAsFixed(3)} Daha İyi'
                : '${prediction.worldDiffPercent.toStringAsFixed(3)}% better than world avg')
            : (isTr
                ? 'Dünya Ortalamasından %${prediction.worldDiffPercent.toStringAsFixed(3)} Daha Yüksek'
                : '${prediction.worldDiffPercent.toStringAsFixed(3)}% above world avg');

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: prediction.isOnTrack
                  ? Colors.green.withValues(alpha: 0.8)
                  : Colors.orange.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 108,
                    height: 108,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: prediction.gaugeEfficiency.clamp(0.0, 1.0),
                            strokeWidth: 8,
                            backgroundColor:
                                (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              prediction.isOnTrack
                                  ? Colors.greenAccent.shade400
                                  : Colors.orangeAccent.shade200,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${efficiencyPct.toStringAsFixed(3)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                            ),
                            Text(
                              isTr ? 'verim' : 'eff.',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: (isDark ? Colors.white : Colors.black)
                                        .withValues(alpha: 0.65),
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: prediction.worldRoughlyEqual
                                  ? Colors.blueGrey.shade700
                                      .withValues(alpha: 0.35)
                                  : prediction.isBetterThanWorldAverage
                                      ? Colors.green.shade700
                                          .withValues(alpha: 0.35)
                                      : Colors.deepOrange.shade800
                                          .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: prediction.worldRoughlyEqual
                                    ? Colors.blueGrey.shade400
                                        .withValues(alpha: 0.85)
                                    : prediction.isBetterThanWorldAverage
                                        ? Colors.greenAccent.shade400
                                            .withValues(alpha: 0.9)
                                        : Colors.orange.shade700
                                            .withValues(alpha: 0.85),
                              ),
                            ),
                            child: Text(
                              badgeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: prediction.worldRoughlyEqual
                                        ? Colors.blueGrey.shade100
                                        : prediction.isBetterThanWorldAverage
                                            ? Colors.lightGreenAccent.shade100
                                            : Colors.orange.shade100,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isTr ? 'Tahmini ay sonu toplamı' : 'Projected month-end',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: (isDark ? Colors.white : Colors.black)
                                        .withValues(alpha: 0.65),
                                  ),
                        ),
                        Text(
                          prediction.projectedMonthEndKg.toStringAsFixed(3),
                          style:
                              Theme.of(context).textTheme.displaySmall?.copyWith(
                                    color: isDark
                                        ? Colors.white
                                        : cs.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 34,
                                    height: 1.05,
                                  ),
                        ),
                        Text(
                          'kg CO₂e',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: (isDark ? Colors.white : Colors.black)
                                        .withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isTr
                    ? 'Hedef: ${prediction.targetMonthEndKg.toStringAsFixed(3)} kg CO₂e · Günlük tempo: ${prediction.currentAverageKgPerDay.toStringAsFixed(3)} kg/gün · Kalan gün: ${prediction.remainingDays}'
                    : 'Target: ${prediction.targetMonthEndKg.toStringAsFixed(3)} kg CO₂e · Pace: ${prediction.currentAverageKgPerDay.toStringAsFixed(3)} kg/day · Days left: ${prediction.remainingDays}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.78),
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    prediction.isOnTrack
                        ? Icons.check_circle
                        : Icons.warning_amber,
                    size: 18,
                    color: prediction.isOnTrack ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      prediction.trackMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: prediction.isOnTrack
                                ? Colors.green
                                : Colors.orange,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                prediction.impactSummary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.8),
                    ),
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _InsightMiniCard(
                        title: isTr ? 'Neden?' : 'Why?',
                        body: isTr
                            ? prediction.insightWhyTr
                            : prediction.insightWhyEn,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InsightMiniCard(
                        title: isTr ? 'Tavsiye' : 'Tip',
                        body: isTr
                            ? prediction.insightTipTr
                            : prediction.insightTipEn,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!loadingOverlay) return card;

    return Stack(
      children: [
        card,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.black.withValues(alpha: 0.25),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightMiniCard extends StatelessWidget {
  const _InsightMiniCard({
    required this.title,
    required this.body,
    required this.isDark,
  });

  final String title;
  final String body;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.88),
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class CarbonGoal {
  final String id;
  final String title;
  final double target;
  final double current;
  final double monthlyChangePercent;
  final String recommendation;
  final String unit;
  final String type;
  final IconData icon;
  final Color color;

  CarbonGoal({
    required this.id,
    required this.title,
    required this.target,
    required this.current,
    required this.monthlyChangePercent,
    required this.recommendation,
    required this.unit,
    required this.type,
    required this.icon,
    required this.color,
  });

  double get progress => (current / target).clamp(0.0, 1.0);
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, this.languageProvider, this.onDelete});

  final CarbonGoal goal;
  final LanguageProvider? languageProvider;
  final VoidCallback? onDelete;

  String _localizedGoalTitle(Locale locale) {
    switch (goal.type) {
      case 'electricity_saving':
        return translate('monthly_electricity_saving', locale);
      case 'co2_reduction':
        return translate('co2_emission_reduction', locale);
      case 'water_saving':
        return translate('water_saving', locale);
      case 'waste_reduction':
        return goal.title.trim().isNotEmpty
            ? goal.title
            : translate('waste_reduction', locale);
      default:
        return goal.title;
    }
  }

  String _monthlyComparisonText(Locale locale) {
    final bool isTr = locale.languageCode == 'tr';
    final bool reduced = goal.monthlyChangePercent >= 0;
    final value = goal.monthlyChangePercent.abs().toStringAsFixed(1);
    final subject = goal.type == 'co2_reduction'
        ? (isTr ? 'emisyon' : 'emissions')
        : (isTr ? 'kullanım' : 'usage');

    if (isTr) {
      return reduced
          ? 'Önceki aya göre $subject %$value azaldı'
          : 'Önceki aya göre $subject %$value arttı';
    }
    return reduced
        ? '$subject decreased by $value% compared to previous month'
        : '$subject increased by $value% compared to previous month';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = languageProvider?.currentLocale ?? const Locale('tr');
    final bool isCompleted = goal.progress >= 1.0;
    final localizedTitle = _localizedGoalTitle(locale);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: isCompleted
                ? null
                : (isDark
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2),
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                        ],
                      )),
            color: isCompleted
                ? Colors.green.withValues(alpha: 0.15)
                : (isDark ? Colors.black.withValues(alpha: 0.4) : null),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? Colors.green
                  : (Theme.of(context).brightness == Brightness.dark)
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.primary,
              width: isCompleted ? 2 : (isDark ? 1 : 2),
            ),
            boxShadow: isCompleted
                ? [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isCompleted)
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green.withValues(alpha: 0.2),
                            ),
                          ),
                        Icon(
                          goal.icon,
                          color: isCompleted ? Colors.green : goal.color,
                          size: 28,
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizedTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                          ),
                          if (isCompleted) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  translate('goal_completed', locale),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${goal.current.toStringAsFixed(1)}/${goal.target.toStringAsFixed(1)} ${goal.unit}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                        ),
                        Text(
                          '${(goal.progress * 100).toStringAsFixed(0)}%',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isCompleted
                                        ? Colors.green
                                        : (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: onDelete,
                        tooltip: translate('delete', locale),
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Stack(
                  children: [
                    LinearProgressIndicator(
                      value: goal.progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCompleted ? Colors.green : goal.color,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    if (isCompleted)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            gradient: LinearGradient(
                              colors: [Colors.green, Colors.green.shade300],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _monthlyComparisonText(locale),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isCompleted
                                  ? Colors.green
                                  : (isDark ? Colors.white : Colors.black)
                                      .withValues(
                                      alpha: 0.7,
                                    ),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (isCompleted)
                      const Icon(Icons.celebration,
                          color: Colors.amber, size: 18),
                  ],
                ),
                if (goal.recommendation.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    goal.recommendation,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.imagePath,
    required this.title,
    required this.isUnlocked,
  });

  final String imagePath;
  final String title;
  final bool isUnlocked;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Instagram story tarzı yuvarlak buton
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isUnlocked
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
                      ],
                    )
                  : null,
              color: isUnlocked
                  ? null
                  : Colors.grey.withValues(
                      alpha: 0.3,
                    ), // Kilitli rozetler için güzel gri ton
              border: Border.all(
                color: isUnlocked
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.withValues(alpha: 0.4),
                width: isUnlocked ? 2.5 : 2,
              ),
              boxShadow: isUnlocked
                  ? [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: ClipOval(
              child: isUnlocked
                  ? Image.asset(
                      imagePath,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.star,
                          color: Colors.white,
                          size: 32,
                        );
                      },
                    )
                  : ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.3, 0.3, 0.3, 0, 0, // R
                        0.3, 0.3, 0.3, 0, 0, // G
                        0.3, 0.3, 0.3, 0, 0, // B
                        0, 0, 0, 0.5, 0, // A (opacity)
                      ]),
                      child: Image.asset(
                        imagePath,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.star,
                            color: Colors.grey.withValues(alpha: 0.7),
                            size: 32,
                          );
                        },
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Rozet adı (küçük)
          SizedBox(
            width: 70,
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight:
                        isUnlocked ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.7,
                  ),
                  fontSize: 11,
                ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.points,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '+$points',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
