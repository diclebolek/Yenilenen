import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/api_service.dart';
import '../services/global_carbon_service.dart';
import '../services/live_emission_service.dart';
import '../models/consumption_entry.dart';
import '../models/shelly_data.dart';
import '../algorithms/calculation.dart';
import '../widgets/theme_independent_info_dialog.dart';
import '../themes/app_theme.dart';
import 'dart:async';

/// Kart üzerinde ikincil gövde metni (açık tema: neredeyse siyah).
Color _goalsReadableOnCard(BuildContext context, bool isDark) =>
    isDark ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF121212);

/// Turuncu uyarı / öneri metinleri — açık temada soluk turuncu yerine koyu turuncu.
const Color _kGoalsDarkOrangeText = Color(0xFFE65100);
const Color _kGoalsDeepOrangeText = Color(0xFFBF360C);

/// Yeşil skor davranış girdileri (km / kg / L çarpanları).
enum _EnginePointKind { walk, publicTransport, recycle, water }

int _engineMultiplier(_EnginePointKind k) {
  switch (k) {
    case _EnginePointKind.walk:
      return 10;
    case _EnginePointKind.publicTransport:
      return 5;
    case _EnginePointKind.recycle:
      return 20;
    case _EnginePointKind.water:
      return 4;
  }
}

double _engineSliderMax(_EnginePointKind k) {
  switch (k) {
    case _EnginePointKind.walk:
      return 50.0;
    case _EnginePointKind.publicTransport:
      return 120.0;
    case _EnginePointKind.recycle:
      return 50.0;
    case _EnginePointKind.water:
      return 200.0;
  }
}

double? _parseLocaleDouble(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Hızlı ayar kaydırıcısı — Material 3'te iz kaybolmasını önlemek için altta sabit çubuk.
class _QuickSetSlider extends StatelessWidget {
  const _QuickSetSlider({
    required this.value,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    const trackColor = AppTheme.infoDialogForeground;
    final inactiveColor = trackColor.withValues(alpha: 0.28);
    final clamped = value.clamp(0.0, max);
    final fraction = max > 0 ? (clamped / max).clamp(0.0, 1.0) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 80;
        return SizedBox(
          height: 44,
          width: trackWidth,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    width: math.max(0, trackWidth - 24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: inactiveColor),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction,
                          child: const ColoredBox(color: trackColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 10,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  disabledActiveTrackColor: Colors.transparent,
                  disabledInactiveTrackColor: Colors.transparent,
                  thumbColor: trackColor,
                  overlayColor: WidgetStateColor.resolveWith(
                    (states) => trackColor.withValues(
                      alpha: states.contains(WidgetState.pressed) ? 0.22 : 0.12,
                    ),
                  ),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: clamped,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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

/// [ReportsScreen] E/M toggle ile aynı anahtar (SharedPreferences).
const String _kPrefsReportsUseEspData = 'prefs_reports_use_esp_data';

/// Gelecek Ay Beklentisi kartından belirlenen toplam emisyon azaltma % hedefi.
const String _kPrefsOutlookCo2ReductionPercent =
    'prefs_outlook_co2_reduction_percent';
const String _kGreenScoreFreshStartKey = 'gs_fresh_start_jun2026_v2';

Map<String, bool> _defaultGreenScoreBadges() => {
      'environment_friendly': false,
      'energy_saving': false,
      'water_protector': false,
      'goal_master': false,
      'eco_warrior': false,
    };

int _greenScoreLevel(int score) => (score ~/ 100) + 1;

/// Günlük emisyon üst sınırı (Shelly/ESP sıçramalarını ay sonu tahminine taşımamak için).
const double _kMaxPlausibleDailyKgCo2e = 80.0;

/// CO₂ azaltma hedefi varsayılanı: toplam emisyonda kullanıcının belirlediği %.
const double _kDefaultCo2ReductionGoalPercent = 5.0;

/// Eski kayıtlarda hedef bazen doğrudan aylık kg CO₂e üst sınırı olarak tutulur (≥50).
const double _kOutlookLegacyMonthlyCapKg = 50.0;

/// Önceki ay / tempo verisi yokken Gelecek Ay Beklentisi yedek üst sınırı.
const double _kOutlookFallbackMonthlyCapKg = 450.0;

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
      defaultUnit: '%',
      icon: Icons.eco,
      iconString: 'eco',
      trackingHelpKey: 'goal_tracking_co2_percent',
      defaultTarget: '5',
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
  final LiveEmissionService _liveEmission = LiveEmissionService.instance;

  int _greenScore = 0;
  List<CarbonGoal> _goals = [];
  MonthlyPrediction? _monthlyPrediction;
  bool _predictionLoading = true;
  bool _isLoading = true;

  /// Gelecek Ay Beklentisi konteynerinden yönetilen azaltma hedefi (%).
  double _outlookCo2ReductionPercent = _kDefaultCo2ReductionGoalPercent;

  /// Gelecek ay tahminiyle aynı kaynak: son 7 günün tahmini günlük kg CO₂e.
  double _userDailyEmissionKg = 0;

  /// Kişi başı referans (kg/gün) — `GlobalCarbonService` + dönüştürme.
  double _worldDailyRefKg = 4.1;

  /// Haftalık yürüyüş km toplamı (Pazartesi 00:00’tan itibaren).
  double _weekWalkKmTotal = 0;
  bool _weekWalkBonusClaimed = false;
  Map<String, bool> _badges = _defaultGreenScoreBadges();
  StreamSubscription<int>? _greenScoreSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _goalsSubscription;
  StreamSubscription<ConsumptionEntry?>? _consumptionSubscription;
  StreamSubscription<Map<String, bool>>? _badgesSubscription;
  SharedPreferences? _prefs;

  String? get _userId => _authService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _liveEmission.addListener(_onLiveGaugeUpdated);
    unawaited(
      SharedPreferences.getInstance().then((prefs) {
        if (mounted) setState(() => _prefs = prefs);
      }),
    );
    _loadData();
  }

  void _onLiveGaugeUpdated() {
    if (_liveEmission.gaugeDailyKgCo2e != null) {
      unawaited(_refreshPrediction());
    }
  }

  Future<void> _loadOutlookCo2ReductionPercent() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_kPrefsOutlookCo2ReductionPercent);
    if (stored != null && stored.isFinite && stored > 0) {
      if (mounted) {
        setState(
          () => _outlookCo2ReductionPercent = stored.clamp(0.1, 95.0),
        );
      }
      return;
    }
    final co2Goals =
        _goals.where((g) => g.type == 'co2_reduction').toList();
    if (co2Goals.isNotEmpty) {
      final g = co2Goals.first;
      final seeded = g.unit == '%'
          ? g.target.clamp(0.1, 95.0)
          : _kDefaultCo2ReductionGoalPercent;
      if (mounted) {
        setState(() => _outlookCo2ReductionPercent = seeded);
      }
      await prefs.setDouble(_kPrefsOutlookCo2ReductionPercent, seeded);
    }
  }

  Future<void> _saveOutlookCo2ReductionPercent(double percent) async {
    final value = percent.clamp(0.1, 95.0);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefsOutlookCo2ReductionPercent, value);
    if (mounted) {
      setState(() => _outlookCo2ReductionPercent = value);
    }
    await _syncCo2ReductionGoalFromOutlookPercent(value);
    await _refreshPrediction();
  }

  Future<void> _syncCo2ReductionGoalFromOutlookPercent(double percent) async {
    if (_userId == null) return;
    try {
      final goalsData = await _firebaseService.getGoals(_userId!);
      final index = goalsData.indexWhere(
        (g) => (g['type'] ?? '') == 'co2_reduction',
      );
      if (index >= 0) {
        goalsData[index]['target'] = percent;
        goalsData[index]['unit'] = '%';
        await _firebaseService.saveGoals(_userId!, goalsData);
      } else {
        final locale =
            widget.languageProvider?.currentLocale ?? const Locale('tr');
        await _firebaseService.addGoal(_userId!, {
          'title': translate('co2_emission_reduction', locale),
          'target': percent,
          'current': 0.0,
          'unit': '%',
          'type': 'co2_reduction',
          'icon': 'eco',
          'color': 0xFF48631F,
        });
      }
    } catch (_) {}
  }

  Future<void> _showOutlookReductionTargetDialog() async {
    if (!mounted) return;
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final isTr = locale.languageCode == 'tr';
    final controller = TextEditingController(
      text: _outlookCo2ReductionPercent.toStringAsFixed(1),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(translate('outlook_set_reduction_target', locale)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                translate('outlook_set_reduction_target_body', locale),
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: translate('outlook_reduction_percent_label', locale),
                  hintText: translate('goal_co2_percent_hint', locale),
                  suffixText: '%',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(translate('cancel', locale)),
            ),
            FilledButton(
              onPressed: () async {
                final raw = controller.text.trim().replaceAll(',', '.');
                final value = double.tryParse(raw);
                if (value == null || value < 0.1 || value > 95) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        translate('goal_co2_percent_range', locale),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await _saveOutlookCo2ReductionPercent(value);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isTr
                            ? 'Azaltma hedefi %${value.toStringAsFixed(1)} olarak kaydedildi.'
                            : 'Reduction target saved as ${value.toStringAsFixed(1)}%.',
                      ),
                    ),
                  );
                }
              },
              child: Text(translate('ok', locale)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadData() async {
    await _resetGreenScoreProgressIfNeeded();

    if (_userId == null) {
      await _refreshWeeklyWalkState();
      await _loadOutlookCo2ReductionPercent();
      await _refreshPrediction();
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      setState(
        () => _badges = _firebaseService.mergeBadgeDefaults(badges),
      );

      // Rozetleri dinle
      _badgesSubscription?.cancel();
      _badgesSubscription = _firebaseService.listenToBadges(_userId!).listen((
        badges,
      ) {
        if (mounted) {
          setState(
            () => _badges = _firebaseService.mergeBadgeDefaults(badges),
          );
        }
      });

      // Rozet kontrolü yap
      _checkAndUnlockBadges();
      await _refreshWeeklyWalkState();
      await _loadOutlookCo2ReductionPercent();
    } catch (e) {
      // Hata durumunda varsayılan hedefleri göster
      _createDefaultGoalsList();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      unawaited(_refreshPrediction());
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
        'target': _kDefaultCo2ReductionGoalPercent,
        'current': 0.0,
        'monthlyChangePercent': 0.0,
        'recommendation': '',
        'unit': '%',
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
          target: _kDefaultCo2ReductionGoalPercent,
          current: 0.0,
          monthlyChangePercent: 0.0,
          recommendation: '',
          unit: '%',
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
      for (var entry in currentMonthData) {
        currentMonthElectricity += entry.electricityKwh;
        currentMonthWater += entry.waterCubicMeters;
      }

      // Önceki ayın toplam tüketimlerini hesapla
      double previousMonthElectricity = 0;
      double previousMonthWater = 0;
      for (var entry in previousMonthData) {
        previousMonthElectricity += entry.electricityKwh;
        previousMonthWater += entry.waterCubicMeters;
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
            // Kullanıcının girdiği % hedefi korunur (otomatik üzerine yazılmaz).
            var co2Unit = (goalData['unit'] ?? '%').toString();
            dynamicTarget = (goalData['target'] ?? _kDefaultCo2ReductionGoalPercent)
                .toDouble();
            final previousMonthCO2 =
                _sumHistoryMonthCo2Kg(previousMonthData);
            // Eski kg kayıtlarını (ör. 15 kg) toplam emisyona göre %'ye taşı.
            if (co2Unit == 'kg' &&
                dynamicTarget < _kOutlookLegacyMonthlyCapKg &&
                previousMonthCO2 > 1e-9) {
              dynamicTarget =
                  ((dynamicTarget / previousMonthCO2) * 100).clamp(0.1, 95.0);
              goalData['unit'] = '%';
              goalData['target'] = dynamicTarget;
              co2Unit = '%';
              updated = true;
            } else if (_isCo2GoalPercentUnit(co2Unit)) {
              dynamicTarget = dynamicTarget.clamp(0.1, 95.0);
            }
            final currentMonthCO2 = _sumHistoryMonthCo2Kg(currentMonthData);
            if (previousMonthCO2 > 0) {
              final reductionPct =
                  ((previousMonthCO2 - currentMonthCO2) / previousMonthCO2) *
                      100;
              newMonthlyChangePercent = reductionPct;
              newCurrent = reductionPct;
              if (newCurrent < 0) newCurrent = 0;
            } else {
              newCurrent = 0.0;
              newMonthlyChangePercent = 0.0;
            }
            final targetPercent = _co2ReductionTargetPercent(
              target: dynamicTarget,
              unit: co2Unit,
              baselineKg: previousMonthCO2,
            );
            if (newCurrent < targetPercent) {
              final missingPct =
                  (targetPercent - newCurrent).clamp(0.0, 100.0);
              if (locale.languageCode == 'tr') {
                newRecommendation =
                    'Toplam emisyon hedefiniz için önceki aya göre yaklaşık %${missingPct.toStringAsFixed(1)} daha azaltmanız gerekiyor.';
              } else {
                newRecommendation =
                    'To hit your total emission goal, cut about ${missingPct.toStringAsFixed(1)}% more vs last month.';
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
        if (type != 'co2_reduction' &&
            (goalData['target'] ?? 0.0) != dynamicTarget) {
          goalData['target'] = dynamicTarget;
          updated = true;
        }
        if (type == 'co2_reduction' &&
            _isCo2GoalPercentUnit((goalData['unit'] ?? '%').toString()) &&
            (goalData['target'] ?? 0.0) != dynamicTarget) {
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
    return _espReadingsToDailyKgCo2e(espHistory);
  }

  /// Raporlar / E modundaki gibi: ESP su+gaz + Shelly kWh farkı (geçmişten).
  Future<double> _estimateLiveEspShellyKgCo2eToday() async {
    double kg = 0.0;
    try {
      final esp = await _firebaseService.getLatestData('esp8266_001');
      if (esp != null) {
        kg += esp.waterCubicMeters * Calculation.factorWaterKgPerM3;
        kg += Calculation.fuelEmissionKgCo2e(esp);
      }
    } catch (_) {}

    try {
      final now = DateTime.now();
      final hist = await _apiService.getFirebaseShellyHistory(
        deviceId: 'shelly_plug_001',
        startDate: now.subtract(const Duration(days: 4)),
        endDate: now,
      );
      if (hist.length >= 2) {
        hist.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final last = hist.last;
        final prev = hist[hist.length - 2];
        final gap = last.timestamp.difference(prev.timestamp);
        if (gap <= const Duration(hours: 36)) {
          final delta = (last.energyKwh - prev.energyKwh).clamp(0.0, 80.0);
          kg += delta * Calculation.factorElectricityKgPerKwh;
        }
      }
    } catch (_) {}

    return kg.clamp(0.0, _kMaxPlausibleDailyKgCo2e);
  }

  List<double> _lastNDaysSeries(
    Map<DateTime, double> dailyTotals,
    DateTime today,
    int n,
  ) {
    final series = <double>[];
    for (int i = n - 1; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      series.add((dailyTotals[day] ?? 0.0).clamp(0.0, double.infinity));
    }
    return series;
  }

  MonthlyPrediction _buildFallbackMonthlyPrediction({
    required bool isTr,
    required DateTime now,
    required double dailyKg,
    required double targetMonthEndKg,
  }) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final elapsedDays = now.day.clamp(1, daysInMonth);
    final remainingDays = (daysInMonth - elapsedDays).clamp(0, daysInMonth);
    const paceEps = 1e-9;
    final clampedDaily = _clampPlausibleDailyKg(dailyKg);
    final hasForecastBasis = clampedDaily > paceEps;
    final projectedMonthEnd = hasForecastBasis
        ? clampedDaily * elapsedDays + clampedDaily * remainingDays
        : 0.0;
    final isOnTrack =
        !hasForecastBasis || projectedMonthEnd <= targetMonthEndKg;
    final gaugeEfficiency = !hasForecastBasis
        ? 0.0
        : math.min(
            1.0, targetMonthEndKg / math.max(projectedMonthEnd, paceEps));

    return MonthlyPrediction(
      projectedMonthEndKg: projectedMonthEnd,
      targetMonthEndKg: targetMonthEndKg,
      currentAverageKgPerDay: clampedDaily,
      daysElapsed: elapsedDays,
      daysInMonth: daysInMonth,
      remainingDays: remainingDays,
      isOnTrack: isOnTrack,
      isLowConfidence: true,
      trackMessage: !hasForecastBasis
          ? (isTr
              ? 'Tahmin için sensör veya manuel veri bekleniyor.'
              : 'Waiting for sensor or manual data for forecast.')
          : isOnTrack
              ? (isTr
                  ? 'Bu gidişle hedefe ulaşırsın.'
                  : 'At this pace, you will reach the goal.')
              : (isTr
                  ? 'Bu gidişle hedefe ulaşamazsın.'
                  : 'At this pace, you may miss the goal.'),
      impactSummary: isTr
          ? 'Raporlar göstergesi veya son sensör verisi ile güncellendi.'
          : 'Updated from reports gauge or latest sensor data.',
      gaugeEfficiency: gaugeEfficiency,
      worldDiffPercent: 0.0,
      isBetterThanWorldAverage: false,
      worldRoughlyEqual: true,
      insightWhyTr: isTr
          ? 'Canlı gauge değeri veya yedek tahmin kullanıldı.'
          : 'Live gauge value or fallback forecast used.',
      insightWhyEn: 'Live gauge value or fallback forecast used.',
      insightTipTr: isTr
          ? 'Raporlar ekranındaki E modunu açık tutun veya manuel kayıt ekleyin.'
          : 'Keep E mode on in Reports or add manual entries.',
      insightTipEn: 'Keep E mode on in Reports or add manual entries.',
    );
  }

  Future<void> _refreshPrediction() async {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final isTr = locale.languageCode == 'tr';
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final elapsedDays = now.day.clamp(1, daysInMonth);
    final today = DateTime(now.year, now.month, now.day);

    if (mounted) {
      setState(() => _predictionLoading = true);
    }

    try {
      final double co2GoalTarget = _outlookCo2ReductionPercent;
      const String co2GoalUnit = '%';

      final prefs = await SharedPreferences.getInstance();
      final bool useEspSensorMode =
          prefs.getBool(_kPrefsReportsUseEspData) ?? true;

      // Ay başı yerine son 30 gün: seyrek Firebase geçmişinde de örnek yakalar
      final rollingStart = today.subtract(const Duration(days: 29));
      final dailyTotals = useEspSensorMode
          ? await _buildDailyEspShellyTotals(rollingStart, now)
          : await _buildDailyCombinedTotals(rollingStart, now);

      const double paceEps = 1e-9;

      if (useEspSensorMode) {
        await _liveEmission.bootstrapFromFirebase(
          firebase: _firebaseService,
          api: _apiService,
          shellyDeviceId: 'shelly_plug_001',
        );
        var liveKg = await _estimateLiveEspShellyKgCo2eToday();
        final gaugeKg = _liveEmission.gaugeDailyKgCo2e;
        if (gaugeKg != null && gaugeKg > liveKg) {
          liveKg = gaugeKg;
        }
        if (liveKg <= paceEps) {
          liveKg = _liveEmission.combinedLiveKgCo2e();
        }
        if (liveKg > paceEps) {
          dailyTotals[today] = _clampPlausibleDailyKg(liveKg);
        }
      }

      final last7 = _lastSevenDaysSeries(dailyTotals, now)
          .map(_clampPlausibleDailyKg)
          .toList();
      final last30 = _lastNDaysSeries(dailyTotals, today, 30)
          .map(_clampPlausibleDailyKg)
          .toList();

      final forecast = _computeMonthlyForecast(
        dailyTotals: dailyTotals,
        today: today,
        elapsedDays: elapsedDays,
        remainingDays: (daysInMonth - elapsedDays).clamp(0, daysInMonth),
        last7: last7,
        last30: last30,
      );

      final double estimatedDailyAverage = forecast.dailyPaceKg;
      final double projectedMonthEnd = forecast.projectedMonthEndKg;
      final bool hasForecastBasis = forecast.hasForecastBasis;
      final bool isLowConfidence = forecast.isLowConfidence;
      final int remainingDays =
          (daysInMonth - elapsedDays).clamp(0, daysInMonth);

      double worldDailyRefKg = 4.1;
      try {
        final trend = await GlobalCarbonService().getGlobalDailyTrend();
        if (trend.isNotEmpty) {
          double sum = 0.0;
          for (final v in trend) {
            sum += _globalRawToPerCapitaDailyKg(v.toDouble());
          }
          worldDailyRefKg = sum / trend.length.toDouble();
        }
      } catch (_) {}

      final double targetMonthEndKg = await _resolveOutlookMonthEndTargetKg(
        co2GoalTarget: co2GoalTarget,
        co2GoalUnit: co2GoalUnit,
        today: today,
        useEspSensorMode: useEspSensorMode,
        dailyPaceKg: estimatedDailyAverage,
        worldDailyRefKg: worldDailyRefKg,
      );

      final bool isOnTrack = !hasForecastBasis
          ? true
          : targetMonthEndKg <= 0.0
              ? true
              : projectedMonthEnd <= targetMonthEndKg;

      // Veri yokken (günlük ortalama ~0) halkayı %100 dolu gösterme; hedef yoksa nötr 1.0
      final double gaugeEfficiency = targetMonthEndKg <= 0.0
          ? 1.0
          : (!hasForecastBasis
              ? 0.0
              : math.min(
                  1.0,
                  targetMonthEndKg / math.max(projectedMonthEnd, paceEps),
                ));

      final double userDaily = estimatedDailyAverage;
      final double diffWorldDaily = userDaily - worldDailyRefKg;
      final bool worldRoughlyEqual =
          !hasForecastBasis || diffWorldDaily.abs() < 0.05;
      final bool isBetterThanWorld =
          hasForecastBasis && !worldRoughlyEqual && diffWorldDaily < 0.0;
      double worldDiffPct = 0.0;
      if (hasForecastBasis && worldDailyRefKg > 1e-9 && !worldRoughlyEqual) {
        worldDiffPct = (diffWorldDaily.abs() / worldDailyRefKg) * 100.0;
        if (!worldDiffPct.isFinite) worldDiffPct = 0.0;
        worldDiffPct = worldDiffPct.clamp(0.0, 200.0);
      }

      final windowStart = today.subtract(const Duration(days: 13));
      final espDaily = await _buildDailyEspCo2Totals(windowStart, now);

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

      final Map<DateTime, double> combinedWindow = useEspSensorMode
          ? await _buildDailyEspShellyTotals(windowStart, now)
          : await _buildDailyCombinedTotals(windowStart, now);
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
      final double rawDelta = useEspWhy
          ? (sumPrev7Esp > 1e-9
              ? ((sumLast7Esp - sumPrev7Esp) / sumPrev7Esp) * 100.0
              : 0.0)
          : (sumPrev7Comb > 1e-9
              ? ((sumLast7Comb - sumPrev7Comb) / sumPrev7Comb) * 100.0
              : 0.0);
      final double deltaSrc =
          rawDelta.isFinite ? rawDelta.clamp(-100.0, 100.0) : 0.0;

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

      final trendText = !hasForecastBasis
          ? (isTr
              ? 'Henüz yeterli günlük veri yok.'
              : 'Not enough daily data yet.')
          : isLowConfidence
              ? (isTr
                  ? 'Bu ay ${forecast.daysWithDataInMonth} günlük kayıt; tahmin kabaca gösteriliyor.'
                  : 'Only ${forecast.daysWithDataInMonth} day(s) this month; forecast is approximate.')
              : useEspSensorMode
                  ? (isTr
                      ? 'Bu ay ${forecast.daysWithDataInMonth} günlük kayıt; E modu (ESP + Shelly) ile ay sonu tahmini.'
                      : '${forecast.daysWithDataInMonth} day(s) this month; month-end forecast from E mode (ESP + Shelly).')
                  : (isTr
                      ? 'Bu ay ${forecast.daysWithDataInMonth} günlük kayıt; manuel + sensör verisiyle tahmin.'
                      : '${forecast.daysWithDataInMonth} day(s) this month; forecast from manual + sensor data.');

      String trackMessage;
      if (!hasForecastBasis) {
        trackMessage = isTr
            ? 'Tahmin için sensör veya manuel veri bekleniyor.'
            : 'Waiting for sensor or manual data for forecast.';
      } else if (isLowConfidence) {
        trackMessage = isOnTrack
            ? (isTr
                ? 'Az veriyle kabaca hedefe uygun görünüyor; veri arttıkça netleşir.'
                : 'Looks roughly on track with limited data; forecast will refine.')
            : (isTr
                ? 'Az veri var; tahmin güvenilir değil, hedefi kaçırabilirsiniz.'
                : 'Limited data; forecast is uncertain, goal may be missed.');
      } else {
        trackMessage = isOnTrack
            ? (isTr
                ? 'Bu gidişle hedefe ulaşırsın.'
                : 'At this pace, you will reach the goal.')
            : (isTr
                ? 'Bu gidişle hedefe ulaşamazsın.'
                : 'At this pace, you may miss the goal.');
      }

      if (mounted) {
        setState(() {
          _userDailyEmissionKg = estimatedDailyAverage;
          _worldDailyRefKg = worldDailyRefKg;
          _monthlyPrediction = MonthlyPrediction(
            projectedMonthEndKg: projectedMonthEnd,
            targetMonthEndKg: targetMonthEndKg,
            currentAverageKgPerDay: estimatedDailyAverage,
            daysElapsed: elapsedDays,
            daysInMonth: daysInMonth,
            remainingDays: remainingDays,
            isOnTrack: isOnTrack,
            isLowConfidence: isLowConfidence,
            trackMessage: trackMessage,
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
      if (mounted) {
        final gaugeKg = _liveEmission.gaugeDailyKgCo2e ?? 0.0;
        final fallbackDaily =
            gaugeKg > 1e-9 ? gaugeKg : _liveEmission.combinedLiveKgCo2e();
        final co2GoalTarget = _outlookCo2ReductionPercent;
        const co2GoalUnit = '%';
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final baseline = fallbackDaily * daysInMonth;
        final percent = _co2ReductionTargetPercent(
          target: co2GoalTarget,
          unit: co2GoalUnit,
          baselineKg: baseline,
        );
        final fallbackTarget = co2GoalUnit == 'kg' &&
                co2GoalTarget >= _kOutlookLegacyMonthlyCapKg
            ? co2GoalTarget
            : math.max(1.0, baseline * (1 - percent / 100));
        setState(() {
          _monthlyPrediction = _buildFallbackMonthlyPrediction(
            isTr: isTr,
            now: now,
            dailyKg: fallbackDaily,
            targetMonthEndKg: fallbackTarget > 1e-9
                ? fallbackTarget
                : _kOutlookFallbackMonthlyCapKg,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _predictionLoading = false);
      }
    }
  }

  double _clampPlausibleDailyKg(double kg) {
    if (!kg.isFinite || kg <= 0) return 0.0;
    return kg.clamp(0.0, _kMaxPlausibleDailyKgCo2e);
  }

  double _sumMonthTotalKg(
    Map<DateTime, double> dailyTotals,
    int year,
    int month,
  ) {
    final lastDay = DateTime(year, month + 1, 0).day;
    var sum = 0.0;
    for (var d = 1; d <= lastDay; d++) {
      final day = DateTime(year, month, d);
      sum += _clampPlausibleDailyKg(dailyTotals[day] ?? 0);
    }
    return sum;
  }

  bool _isCo2GoalPercentUnit(String unit) =>
      unit == '%' || unit.toLowerCase() == 'percent';

  /// Toplam aylık CO₂e (kg): elektrik + gaz + su + atık.
  double _sumHistoryMonthCo2Kg(List<ConsumptionEntry> entries) {
    var electricity = 0.0;
    var water = 0.0;
    var gas = 0.0;
    var waste = 0.0;
    for (final entry in entries) {
      electricity += entry.electricityKwh;
      water += entry.waterCubicMeters;
      gas += entry.fuelLiters;
      waste += entry.wasteKg;
    }
    return electricity * Calculation.factorElectricityKgPerKwh +
        gas * Calculation.factorNaturalGasKgPerM3 +
        water * Calculation.factorWaterKgPerM3 +
        waste * Calculation.factorWasteKgPerKg;
  }

  /// Kullanıcı hedefi (% veya eski kg kayıtları) → azaltma yüzdesi.
  double _co2ReductionTargetPercent({
    required double target,
    required String unit,
    double baselineKg = 0,
  }) {
    if (_isCo2GoalPercentUnit(unit)) {
      return target.clamp(0.1, 95.0);
    }
    if (unit == 'kg' && baselineKg > 1e-9) {
      return ((target / baselineKg) * 100).clamp(0.1, 95.0);
    }
    return _kDefaultCo2ReductionGoalPercent;
  }

  /// Gelecek Ay Beklentisi: önceki ay toplam × (1 − hedef %).
  Future<double> _resolveOutlookMonthEndTargetKg({
    required double co2GoalTarget,
    required String co2GoalUnit,
    required DateTime today,
    required bool useEspSensorMode,
    required double dailyPaceKg,
    required double worldDailyRefKg,
  }) async {
    const paceEps = 1e-9;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    if (co2GoalUnit == 'kg' && co2GoalTarget >= _kOutlookLegacyMonthlyCapKg) {
      return co2GoalTarget;
    }

    final prevMonth = DateTime(today.year, today.month - 1, 1);
    final prevMonthEnd = DateTime(today.year, today.month, 0);
    final prevDaily = useEspSensorMode
        ? await _buildDailyEspShellyTotals(prevMonth, prevMonthEnd)
        : await _buildDailyCombinedTotals(prevMonth, prevMonthEnd);

    var baseline = _sumMonthTotalKg(
      prevDaily,
      prevMonth.year,
      prevMonth.month,
    );

    if (baseline <= paceEps) {
      if (dailyPaceKg > paceEps) {
        baseline = dailyPaceKg * daysInMonth;
      } else if (worldDailyRefKg > paceEps) {
        baseline = worldDailyRefKg * daysInMonth;
      } else {
        return _kOutlookFallbackMonthlyCapKg;
      }
    }

    final percent = _co2ReductionTargetPercent(
      target: co2GoalTarget,
      unit: co2GoalUnit,
      baselineKg: baseline,
    );
    return math.max(1.0, baseline * (1 - percent / 100));
  }

  DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Map<DateTime, double> _espReadingsToDailyKgCo2e(List<ConsumptionEntry> raw) {
    if (raw.isEmpty) return {};
    final sorted = List<ConsumptionEntry>.from(raw)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final totals = <DateTime, double>{};

    for (int i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final cur = sorted[i];
      if (cur.createdAt.difference(prev.createdAt) >
          const Duration(hours: 48)) {
        continue;
      }
      final delta = ConsumptionEntry(
        electricityKwh: 0,
        waterCubicMeters:
            math.max(0, cur.waterCubicMeters - prev.waterCubicMeters),
        fuelLiters: math.max(0, cur.fuelLiters - prev.fuelLiters),
        wasteKg: math.max(0, cur.wasteKg - prev.wasteKg),
        createdAt: cur.createdAt,
        fuelIsNaturalGasM3: cur.fuelIsNaturalGasM3,
      );
      final kg =
          _clampPlausibleDailyKg(Calculation.calculateDailyEmission(delta));
      if (kg > 1e-9) {
        final key = _dayKey(cur.createdAt);
        totals[key] = (totals[key] ?? 0) + kg;
      }
    }

    return totals;
  }

  /// Ay içi gerçek toplam + kalan günler için muhafazakâr günlük tempo.
  ({
    double monthToDateKg,
    int daysWithDataInMonth,
    double dailyPaceKg,
    double projectedMonthEndKg,
    bool hasForecastBasis,
    bool isLowConfidence,
  }) _computeMonthlyForecast({
    required Map<DateTime, double> dailyTotals,
    required DateTime today,
    required int elapsedDays,
    required int remainingDays,
    required List<double> last7,
    required List<double> last30,
  }) {
    const paceEps = 1e-9;
    var monthToDateKg = 0.0;
    var daysWithDataInMonth = 0;

    for (int d = 1; d <= elapsedDays; d++) {
      final day = DateTime(today.year, today.month, d);
      final v = _clampPlausibleDailyKg(dailyTotals[day] ?? 0);
      if (v > paceEps) {
        monthToDateKg += v;
        daysWithDataInMonth++;
      }
    }

    double dailyPaceKg = 0.0;
    if (daysWithDataInMonth >= 2) {
      dailyPaceKg = monthToDateKg / daysWithDataInMonth;
    } else if (daysWithDataInMonth == 1) {
      dailyPaceKg = monthToDateKg;
    } else {
      dailyPaceKg = _medianNonZeroDaily(last7);
      if (dailyPaceKg <= paceEps) {
        dailyPaceKg = _medianNonZeroDaily(last30);
      }
      if (dailyPaceKg <= paceEps) {
        dailyPaceKg = _estimateDailyAverageFromSeries(last7);
      }
    }
    dailyPaceKg = _clampPlausibleDailyKg(dailyPaceKg);

    final hasForecastBasis = monthToDateKg > paceEps || dailyPaceKg > paceEps;
    final projectedMonthEndKg = hasForecastBasis
        ? monthToDateKg + dailyPaceKg * remainingDays.toDouble()
        : 0.0;
    final isLowConfidence = daysWithDataInMonth < 2;

    return (
      monthToDateKg: monthToDateKg,
      daysWithDataInMonth: daysWithDataInMonth,
      dailyPaceKg: dailyPaceKg,
      projectedMonthEndKg: projectedMonthEndKg,
      hasForecastBasis: hasForecastBasis,
      isLowConfidence: isLowConfidence,
    );
  }

  double _medianNonZeroDaily(List<double> series) {
    final nz = series.where((e) => e > 1e-12).toList()..sort();
    if (nz.isEmpty) return 0.0;
    final mid = nz.length ~/ 2;
    return nz.length.isOdd ? nz[mid] : (nz[mid - 1] + nz[mid]) / 2.0;
  }

  /// E modu: yalnızca ESP su/gaz + Shelly elektrik (delta); manuel kayıt yok.
  Future<Map<DateTime, double>> _buildDailyEspShellyTotals(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final espHistory = await _firebaseService.getHistoryData(
      deviceId: 'esp8266_001',
      startDate: startDate,
      endDate: endDate,
    );

    List<ShellyData> shellyRaw = [];
    try {
      shellyRaw = await _apiService.getFirebaseShellyHistory(
        deviceId: 'shelly_plug_001',
        startDate: startDate,
        endDate: endDate,
      );
    } catch (_) {}

    final espDaily = _espReadingsToDailyKgCo2e(espHistory);
    final Map<DateTime, double> shellyKwhByDay = {};
    for (final entry
        in _apiService.shellyDataListToDeltaConsumptionEntries(shellyRaw)) {
      final key = _dayKey(entry.createdAt);
      shellyKwhByDay[key] = (shellyKwhByDay[key] ?? 0.0) + entry.electricityKwh;
    }

    final allDays = <DateTime>{...espDaily.keys, ...shellyKwhByDay.keys};
    final totals = <DateTime, double>{};
    for (final day in allDays) {
      final shellyKg =
          (shellyKwhByDay[day] ?? 0.0) * Calculation.factorElectricityKgPerKwh;
      final espKg = espDaily[day] ?? 0.0;
      totals[day] = _clampPlausibleDailyKg(shellyKg + espKg);
    }
    return totals;
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

    List<ShellyData> shellyRaw = [];
    try {
      shellyRaw = await _apiService.getFirebaseShellyHistory(
        deviceId: 'shelly_plug_001',
        startDate: startDate,
        endDate: endDate,
      );
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

    final espDaily = _espReadingsToDailyKgCo2e(espHistory);

    DateTime dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    final Map<DateTime, ConsumptionEntry> latestManual = {};
    final Map<DateTime, double> shellyKwhByDay = {};

    for (final entry
        in _apiService.shellyDataListToDeltaConsumptionEntries(shellyRaw)) {
      final key = dayKey(entry.createdAt);
      shellyKwhByDay[key] = (shellyKwhByDay[key] ?? 0.0) + entry.electricityKwh;
    }

    void pushLatestManual(ConsumptionEntry entry) {
      final key = dayKey(entry.createdAt);
      final current = latestManual[key];
      if (current == null || entry.createdAt.isAfter(current.createdAt)) {
        latestManual[key] = entry;
      }
    }

    for (final entry in manualHistory) {
      pushLatestManual(entry);
    }

    final allDays = <DateTime>{
      ...espDaily.keys,
      ...latestManual.keys,
      ...shellyKwhByDay.keys,
    };

    final totals = <DateTime, double>{};
    for (final day in allDays) {
      final manual = latestManual[day];
      if (manual != null) {
        totals[day] =
            _clampPlausibleDailyKg(Calculation.calculateDailyEmission(manual));
        continue;
      }

      final espKg = espDaily[day] ?? 0.0;
      final shellyKg =
          (shellyKwhByDay[day] ?? 0.0) * Calculation.factorElectricityKgPerKwh;
      if (espKg > 1e-12 || shellyKg > 1e-12) {
        totals[day] = _clampPlausibleDailyKg(espKg + shellyKg);
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
    final nz =
        series.map(_clampPlausibleDailyKg).where((v) => v > 1e-9).toList();
    if (nz.isEmpty) return 0.0;
    if (nz.length == 1) return nz.first;
    nz.sort();
    final mid = nz.length ~/ 2;
    return nz.length.isOdd ? nz[mid] : (nz[mid - 1] + nz[mid]) / 2.0;
  }

  Future<void> _resetGreenScoreProgressIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kGreenScoreFreshStartKey) == true) return;

    final uid = _userId ?? 'guest';
    for (final key in prefs.getKeys()) {
      if (key.startsWith('gs_') && key.contains(uid)) {
        await prefs.remove(key);
      }
    }

    if (!mounted) return;
    setState(() {
      _greenScore = 0;
      _badges = _defaultGreenScoreBadges();
      _weekWalkKmTotal = 0;
      _weekWalkBonusClaimed = false;
    });

    if (_userId != null) {
      try {
        await _firebaseService.saveGreenScore(_userId!, 0);
        await _firebaseService.saveBadges(_userId!, _defaultGreenScoreBadges());
      } catch (_) {}
    }

    await prefs.setBool(_kGreenScoreFreshStartKey, true);
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

  String _mondayDateKey(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final monday = day.subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshWeeklyWalkState() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _userId ?? 'guest';
    final mon = _mondayDateKey(DateTime.now());
    final km = prefs.getDouble('gs_wk_km_${uid}_$mon') ?? 0.0;
    final bon = prefs.getBool('gs_wk_bonus_${uid}_$mon') ?? false;
    if (!mounted) return;
    setState(() {
      _weekWalkKmTotal = km;
      _weekWalkBonusClaimed = bon;
    });
  }

  /// Yürüyüş km ekler; 10 km eşiği ilk kez aşılırsa 100 puan döner.
  Future<int> _applyWalkKmAndMaybeWeeklyBonus(double kmDelta) async {
    if (kmDelta <= 0) return 0;
    final prefs = await SharedPreferences.getInstance();
    final uid = _userId ?? 'guest';
    final mon = _mondayDateKey(DateTime.now());
    final kmKey = 'gs_wk_km_${uid}_$mon';
    final bonKey = 'gs_wk_bonus_${uid}_$mon';
    final oldKm = prefs.getDouble(kmKey) ?? 0.0;
    final newKm = oldKm + kmDelta;
    await prefs.setDouble(kmKey, newKm);
    var bonus = 0;
    final already = prefs.getBool(bonKey) ?? false;
    if (!already && oldKm < 10.0 && newKm >= 10.0 - 1e-9) {
      await prefs.setBool(bonKey, true);
      bonus = 100;
    }
    await _refreshWeeklyWalkState();
    return bonus;
  }

  /// Günlük salınım dünya ortalamasının altındaysa günde bir kez 50 puan.
  Future<int> _maybeSavingsBonusPoints() async {
    if (_userId == null) return 0;
    if (_worldDailyRefKg <= 0) return 0;
    if (_userDailyEmissionKg >= _worldDailyRefKg - 1e-9) return 0;
    final prefs = await SharedPreferences.getInstance();
    final uid = _userId ?? 'guest';
    final dayKey = DateTime.now().toIso8601String().split('T').first;
    final k = 'gs_sav_${uid}_$dayKey';
    if (prefs.getBool(k) == true) return 0;
    await prefs.setBool(k, true);
    return 50;
  }

  void _openEarnPointsDialog({
    required String titleKey,
    required IconData icon,
    required _EnginePointKind kind,
  }) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _showEarnPointsEngineeringDialog(
          titleKey: titleKey,
          icon: icon,
          kind: kind,
        ),
      );
    });
  }

  Future<void> _showEarnPointsEngineeringDialog({
    required String titleKey,
    required IconData icon,
    required _EnginePointKind kind,
  }) async {
    if (!mounted) return;

    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final mult = _engineMultiplier(kind);
    final maxSlide = _engineSliderMax(kind);
    final uid = _userId ?? 'guest';
    final dayKey = DateTime.now().toIso8601String().split('T').first;
    final prefs = _prefs;
    final savingsUsedToday =
        prefs?.getBool('gs_sav_${uid}_$dayKey') ?? false;
    final savingsEligible = _userId != null &&
        _worldDailyRefKg > 0 &&
        _userDailyEmissionKg < _worldDailyRefKg - 1e-9;

    final amount = await showDialog<double>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _EarnPointsDialog(
        titleKey: titleKey,
        icon: icon,
        kind: kind,
        locale: locale,
        mult: mult,
        maxSlide: maxSlide,
        savingsUsedToday: savingsUsedToday,
        savingsEligible: savingsEligible,
        userLoggedIn: _userId != null,
        weekWalkKmTotal: _weekWalkKmTotal,
        weekWalkBonusClaimed: _weekWalkBonusClaimed,
      ),
    );

    if (!mounted || amount == null || amount <= 0) return;

    var total = (amount * mult).round();
    if (kind == _EnginePointKind.walk) {
      total += await _applyWalkKmAndMaybeWeeklyBonus(amount);
    }
    total += await _maybeSavingsBonusPoints();
    await _awardPoints(total);
    await _refreshWeeklyWalkState();
  }

  /// Rozet kontrolü yap ve gerekirse aç
  Future<void> _checkAndUnlockBadges() async {
    if (_userId == null) return;

    final Map<String, bool> newBadges = Map.from(_badges);
    bool hasNewBadge = false;
    String? newBadgeName;

    // Çevre Dostu: 100+ puan
    if (_greenScore >= 100 && !(_badges['environment_friendly'] ?? false)) {
      newBadges['environment_friendly'] = true;
      hasNewBadge = true;
      newBadgeName = 'environment_friendly';
    }

    // Enerji Tasarrufu: 200+ puan
    if (_greenScore >= 200 && !(_badges['energy_saving'] ?? false)) {
      newBadges['energy_saving'] = true;
      hasNewBadge = true;
      newBadgeName = 'energy_saving';
    }

    // Su Koruyucusu: 150+ puan
    if (_greenScore >= 150 && !(_badges['water_protector'] ?? false)) {
      newBadges['water_protector'] = true;
      hasNewBadge = true;
      newBadgeName = 'water_protector';
    }

    // Hedef Ustası: Tüm hedefleri tamamla
    final allGoalsCompleted =
        _goals.isNotEmpty && _goals.every((goal) => goal.progress >= 1.0);
    if (allGoalsCompleted && !(_badges['goal_master'] ?? false)) {
      newBadges['goal_master'] = true;
      hasNewBadge = true;
      newBadgeName = 'goal_master';
    }

    // Eko Savaşçı: 500+ puan
    if (_greenScore >= 500 && !(_badges['eco_warrior'] ?? false)) {
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
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFFF6F00),
                          Color(0xFFE65100),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x73E65100),
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
                    color: _kGoalsDeepOrangeText,
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
    _liveEmission.removeListener(_onLiveGaugeUpdated);
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
    // LayoutBuilder + ListView (özellikle web) performLayout içinde yeniden girişe
    // yol açabiliyor; genişlik için MediaQuery kullan.
    final double layoutWidth = MediaQuery.sizeOf(context).width;
    final bool isWideLayout = layoutWidth >= 900;
    final double goalsContentMaxWidth = isWideLayout
        ? (kIsWeb ? (layoutWidth * 0.67).clamp(720.0, 1480.0) : 800.0)
        : double.infinity;
    final double horizontalPagePadding = layoutWidth < 360 ? 12.0 : 16.0;

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
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: goalsContentMaxWidth,
              ),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPagePadding,
                  16,
                  horizontalPagePadding,
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
                      Expanded(
                        child: Text(
                          translate('achievement_badges', locale),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                        ),
                      ),
                      Tooltip(
                        message: translate('achievement_badges_info', locale),
                        child: InkWell(
                          onTap: () {
                            showThemeIndependentInfoDialog(
                              context,
                              title: translate('achievement_badges', locale),
                              body:
                                  translate('achievement_badges_info', locale),
                              okLabel: translate('ok', locale),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: const Icon(
                            Icons.info_outline,
                            size: 20,
                            color: _kGoalsDeepOrangeText,
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
                                      borderRadius: BorderRadius.circular(12),
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
                              if (isWideLayout)
                                Center(
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _AchievementBadge(
                                        imagePath: 'assets/images/1rozet.png',
                                        title: translate(
                                          'environment_friendly',
                                          locale,
                                        ),
                                        isUnlocked:
                                            true, // Çevre dostu rozeti her zaman açık
                                      ),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/3rozet.png',
                                        title:
                                            translate('energy_saving', locale),
                                        isUnlocked:
                                            _badges['energy_saving'] ?? false,
                                      ),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/2rozet.png',
                                        title: translate(
                                            'water_protector', locale),
                                        isUnlocked:
                                            _badges['water_protector'] ?? false,
                                      ),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/4rozet.png',
                                        title: translate('goal_master', locale),
                                        isUnlocked:
                                            _badges['goal_master'] ?? false,
                                      ),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/5rozet.png',
                                        title: translate('eco_warrior', locale),
                                        isUnlocked:
                                            _badges['eco_warrior'] ?? false,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _AchievementBadge(
                                        imagePath: 'assets/images/1rozet.png',
                                        title: translate(
                                          'environment_friendly',
                                          locale,
                                        ),
                                        isUnlocked:
                                            true, // Çevre dostu rozeti her zaman açık
                                      ),
                                      const SizedBox(width: 12),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/2rozet.png',
                                        title:
                                            translate('energy_saving', locale),
                                        isUnlocked:
                                            _badges['energy_saving'] ?? false,
                                      ),
                                      const SizedBox(width: 12),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/3rozet.png',
                                        title: translate(
                                            'water_protector', locale),
                                        isUnlocked:
                                            _badges['water_protector'] ?? false,
                                      ),
                                      const SizedBox(width: 12),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/4rozet.png',
                                        title: translate('goal_master', locale),
                                        isUnlocked:
                                            _badges['goal_master'] ?? false,
                                      ),
                                      const SizedBox(width: 12),
                                      _AchievementBadge(
                                        imagePath: 'assets/images/5rozet.png',
                                        title: translate('eco_warrior', locale),
                                        isUnlocked:
                                            _badges['eco_warrior'] ?? false,
                                      ),
                                    ],
                                  ),
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
                      Expanded(
                        child: Text(
                          translate('next_month_outlook', locale),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                        ),
                      ),
                      Tooltip(
                        message: translate('next_month_outlook_info', locale),
                        child: InkWell(
                          onTap: () {
                            showThemeIndependentInfoDialog(
                              context,
                              title: translate('next_month_outlook', locale),
                              body:
                                  translate('next_month_outlook_info', locale),
                              okLabel: translate('ok', locale),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: const Icon(
                            Icons.info_outline,
                            size: 20,
                            color: _kGoalsDeepOrangeText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_predictionLoading && _monthlyPrediction == null)
                    _PredictionLoadingShell(isDark: isDark)
                  else if (_monthlyPrediction != null)
                    _PredictionCard(
                      prediction: _monthlyPrediction!,
                      reductionTargetPercent: _outlookCo2ReductionPercent,
                      languageProvider: widget.languageProvider,
                      loadingOverlay: _predictionLoading,
                      onEditReductionTarget: _showOutlookReductionTargetDialog,
                    )
                  else
                    _PredictionRetryCard(
                      isDark: isDark,
                      locale: locale,
                      onRetry: _refreshPrediction,
                    ),
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
                      Expanded(
                        child: Text(
                          translate('green_score', locale),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                        ),
                      ),
                      Tooltip(
                        message: translate('green_score_info', locale),
                        child: InkWell(
                          onTap: () {
                            showThemeIndependentInfoDialog(
                              context,
                              title: translate('green_score', locale),
                              body: translate('green_score_info', locale),
                              okLabel: translate('ok', locale),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: const Icon(
                            Icons.info_outline,
                            size: 20,
                            color: _kGoalsDeepOrangeText,
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
                              // Seviye: kısa progress çubuğu solda, başlık yanında; altta özet + kutular
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final progressValue =
                                      ((_greenScore % 100) / 100).clamp(
                                    0.0,
                                    1.0,
                                  );
                                  final level = _greenScoreLevel(_greenScore);
                                  final trackBg = isDark
                                      ? Colors.white.withValues(alpha: 0.18)
                                      : AppTheme.infoDialogForeground
                                          .withValues(alpha: 0.16);
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Text(
                                              translate(
                                                'current_level',
                                                locale,
                                                params: {'level': '$level'},
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${100 - (_greenScore % 100)} ${translate('points_to_go', locale)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: _kGoalsDeepOrangeText,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween<double>(
                                            begin: 0.0,
                                            end: progressValue,
                                          ),
                                          duration: const Duration(
                                            milliseconds: 1000,
                                          ),
                                          curve: Curves.easeInOut,
                                          builder: (context, value, child) {
                                            return Container(
                                              height: 12,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                color: trackBg,
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: FractionallySizedBox(
                                                alignment: Alignment.centerLeft,
                                                widthFactor: value,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.deepOrange
                                                            .shade800,
                                                        Colors.deepOrange
                                                            .shade600,
                                                        Colors.deepOrange
                                                            .shade500,
                                                      ],
                                                      begin:
                                                          Alignment.centerLeft,
                                                      end:
                                                          Alignment.centerRight,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.deepOrange
                                                            .withValues(
                                                                alpha: 0.45),
                                                        blurRadius: 8,
                                                        spreadRadius: 1,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.65),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Text(
                                            translate(
                                              'next_level',
                                              locale,
                                              params: {
                                                'level': '${level + 1}',
                                              },
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                                top: 2,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${_greenScore % 100}/100',
                                                    style: Theme.of(
                                                      context,
                                                    )
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                  ),
                                                  Text(
                                                    translate(
                                                      'points',
                                                      locale,
                                                    ),
                                                    style: Theme.of(
                                                      context,
                                                    )
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color:
                                                              _goalsReadableOnCard(
                                                            context,
                                                            isDark,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
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
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
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
                                                                  : Colors
                                                                      .black)
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
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        Theme.of(
                                                          context,
                                                        )
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                                alpha: 0.3),
                                                        Theme.of(
                                                          context,
                                                        )
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                                alpha: 0.2),
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
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                                            .withValues(
                                                                alpha: 0.7),
                                                        fontSize: 9,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 20),
                              // İstatistikler
                              Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.flag,
                                      value: '${_goals.length}',
                                      label: translate('total_goals', locale),
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.check_circle,
                                      value:
                                          '${_goals.where((g) => g.progress >= 1.0).length}',
                                      label:
                                          translate('completed_goals', locale),
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.emoji_events,
                                      value:
                                          '${_badges.values.where((v) => v).length}',
                                      label: translate('badges_earned', locale),
                                      color: _kGoalsDarkOrangeText,
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
                                      color: _goalsReadableOnCard(
                                        context,
                                        isDark,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.45),
                                  ),
                                  color: (isDark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.06),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.flag_circle_outlined,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            translate(
                                              'weekly_challenge_title',
                                              locale,
                                            ),
                                            textAlign: TextAlign.left,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 15),
                                    Text(
                                      translate(
                                        'weekly_challenge_walk_desc',
                                        locale,
                                      ),
                                      textAlign: TextAlign.left,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            height: 1.35,
                                            color: _goalsReadableOnCard(
                                              context,
                                              isDark,
                                            ),
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        minHeight: 8,
                                        value: (_weekWalkKmTotal / 10.0)
                                            .clamp(0.0, 1.0),
                                        backgroundColor: (isDark
                                                ? Colors.white
                                                : Colors.black)
                                            .withValues(alpha: 0.12),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      translate(
                                        'weekly_progress_km',
                                        locale,
                                        params: {
                                          'current': _weekWalkKmTotal
                                              .toStringAsFixed(1),
                                          'target': '10',
                                        },
                                      ),
                                      textAlign: TextAlign.left,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: _goalsReadableOnCard(
                                              context,
                                              isDark,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
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
                                                rateSubtitle: translate(
                                                  'recycle_points_rate',
                                                  locale,
                                                  params: {
                                                    'multiplier': '20',
                                                  },
                                                ),
                                                onTap: () => _openEarnPointsDialog(
                                                  titleKey: 'recycle',
                                                  icon: Icons.recycling,
                                                  kind:
                                                      _EnginePointKind.recycle,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _ActionChip(
                                                icon: Icons.directions_walk,
                                                label:
                                                    translate('walk', locale),
                                                rateSubtitle: translate(
                                                  'walk_points_rate',
                                                  locale,
                                                  params: {
                                                    'multiplier': '10',
                                                  },
                                                ),
                                                onTap: () => _openEarnPointsDialog(
                                                  titleKey: 'walk',
                                                  icon: Icons.directions_walk,
                                                  kind: _EnginePointKind.walk,
                                                ),
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
                                                rateSubtitle: translate(
                                                  'bus_points_rate',
                                                  locale,
                                                  params: {
                                                    'multiplier': '5',
                                                  },
                                                ),
                                                onTap: () => _openEarnPointsDialog(
                                                  titleKey: 'public_transport',
                                                  icon: Icons.directions_bus,
                                                  kind: _EnginePointKind
                                                      .publicTransport,
                                                ),
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
                                                rateSubtitle: translate(
                                                  'water_points_rate',
                                                  locale,
                                                  params: {
                                                    'multiplier': '4',
                                                  },
                                                ),
                                                onTap: () => _openEarnPointsDialog(
                                                  titleKey: 'save_water',
                                                  icon: Icons.water_drop,
                                                  kind: _EnginePointKind.water,
                                                ),
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
                                            label: translate('recycle', locale),
                                            rateSubtitle: translate(
                                              'recycle_points_rate',
                                              locale,
                                              params: {
                                                'multiplier': '20',
                                              },
                                            ),
                                            onTap: () => _openEarnPointsDialog(
                                              titleKey: 'recycle',
                                              icon: Icons.recycling,
                                              kind: _EnginePointKind.recycle,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _ActionChip(
                                            icon: Icons.directions_walk,
                                            label: translate('walk', locale),
                                            rateSubtitle: translate(
                                              'walk_points_rate',
                                              locale,
                                              params: {
                                                'multiplier': '10',
                                              },
                                            ),
                                            onTap: () => _openEarnPointsDialog(
                                              titleKey: 'walk',
                                              icon: Icons.directions_walk,
                                              kind: _EnginePointKind.walk,
                                            ),
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
                                            rateSubtitle: translate(
                                              'bus_points_rate',
                                              locale,
                                              params: {
                                                'multiplier': '5',
                                              },
                                            ),
                                            onTap: () => _openEarnPointsDialog(
                                              titleKey: 'public_transport',
                                              icon: Icons.directions_bus,
                                              kind: _EnginePointKind
                                                  .publicTransport,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _ActionChip(
                                            icon: Icons.water_drop,
                                            label:
                                                translate('save_water', locale),
                                            rateSubtitle: translate(
                                              'water_points_rate',
                                              locale,
                                              params: {
                                                'multiplier': '4',
                                              },
                                            ),
                                            onTap: () => _openEarnPointsDialog(
                                              titleKey: 'save_water',
                                              icon: Icons.water_drop,
                                              kind: _EnginePointKind.water,
                                            ),
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
                                color: _goalsReadableOnCard(context, isDark),
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
                  // Yeni hedef — başlık konteynır dışında
                  Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          translate('set_new_goal', locale),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                                translate('set_new_goal_help', locale),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _goalsReadableOnCard(
                                        context,
                                        isDark,
                                      ),
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
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
                selectedUnit = t.storageType == 'co2_reduction'
                    ? '%'
                    : t.defaultUnit;
                selectedIconStr = t.iconString;
                titleController.text = translate(t.titleKey, locale);
                targetController.text = t.defaultTarget;
              });
            }

            final bool co2PercentGoal = selectedType == 'co2_reduction';
            final List<String> unitChoices = co2PercentGoal
                ? const ['%']
                : const ['%', 'kg', 'kWh', 'L', 'm³', 'km'];

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
                                color: isDark ? Colors.white70 : Colors.black87,
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
                                                          : Colors.black87),
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
                              hintText: co2PercentGoal
                                  ? translate('goal_co2_percent_hint', locale)
                                  : null,
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
                            items: unitChoices
                                .map(
                                  (unit) => DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                                )
                                .toList(),
                            onChanged: co2PercentGoal
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setDialogState(
                                        () => selectedUnit = value,
                                      );
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
                                  if (selectedType == 'co2_reduction' &&
                                      (target < 0.1 || target > 95)) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            translate(
                                              'goal_co2_percent_range',
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
                                      'unit': selectedType == 'co2_reduction'
                                          ? '%'
                                          : selectedUnit,
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
  final bool isLowConfidence;
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
    this.isLowConfidence = false,
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

/// Tahmin yüklenemediğinde yeniden dene kartı.
class _PredictionRetryCard extends StatelessWidget {
  const _PredictionRetryCard({
    required this.isDark,
    required this.locale,
    required this.onRetry,
  });

  final bool isDark;
  final Locale locale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.35) : null,
            gradient: isDark
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                    ],
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: isDark ? 1 : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('sensor_data_waiting', locale),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(translate('refresh', locale)),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            gradient: widget.isDark
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                    ],
                  ),
            color: widget.isDark ? Colors.black.withValues(alpha: 0.4) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: widget.isDark ? 1 : 2,
            ),
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

/// Tahmin kartındaki kg ve benzeri değerler için okunabilir binlik ayracı (TR: 1.234,567 / EN: 1,234.567).
String _formatDecimalWithSeparators(
  double value,
  Locale locale, {
  int fractionDigits = 3,
}) {
  final bool tr = locale.languageCode == 'tr';
  final String sepThousands = tr ? '.' : ',';
  final String sepDecimal = tr ? ',' : '.';

  final fixed = value.abs().toStringAsFixed(fractionDigits);
  final parts = fixed.split('.');
  String intPart = parts[0];
  final String frac = parts.length > 1 ? parts[1] : '';
  final bool negative = value < 0;

  if (intPart.startsWith('-')) {
    intPart = intPart.substring(1);
  }

  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) {
      buf.write(sepThousands);
    }
    buf.write(intPart[i]);
  }
  final String numStr = buf.toString();
  final String dec = frac.isNotEmpty ? '$sepDecimal$frac' : '';
  final String sign = negative ? '-' : '';
  return '$sign$numStr$dec';
}

/// Geniş kart: yan yana gösterge + metin; dar kart: gösterge üstte, alt alta içgörü kartları.
const double _kPredictionSideBySideBreakpoint = 520;
const double _kInsightCardsColumnBreakpoint = 440;

Widget _outlookTargetEditorRow(
  BuildContext context, {
  required double reductionTargetPercent,
  required Locale locale,
  required bool isTr,
  required bool isDark,
  required VoidCallback? onEdit,
}) {
  final TextStyle? base = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _goalsReadableOnCard(context, isDark),
        fontWeight: FontWeight.w600,
      );
  final safePercent = reductionTargetPercent.isFinite && reductionTargetPercent > 0
      ? reductionTargetPercent.clamp(0.1, 95.0)
      : _kDefaultCo2ReductionGoalPercent;
  final pctFmt = _formatDecimalWithSeparators(
    safePercent,
    locale,
    fractionDigits: 1,
  );
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            isTr
                ? 'Toplam emisyon azaltma hedefiniz: %$pctFmt'
                : 'Your total emission cut target: $pctFmt%',
            style: base,
          ),
        ),
        if (onEdit != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: translate('outlook_edit_target', locale),
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: _kGoalsDeepOrangeText,
            onPressed: onEdit,
          ),
      ],
    ),
  );
}

Widget _predictionMetaLine(
  BuildContext context, {
  required MonthlyPrediction prediction,
  required Locale locale,
  required bool isTr,
  required bool isDark,
}) {
  final TextStyle? base = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _goalsReadableOnCard(context, isDark),
        fontWeight: FontWeight.w600,
      );
  final String targetFmt = _formatDecimalWithSeparators(
    prediction.targetMonthEndKg,
    locale,
    fractionDigits: prediction.targetMonthEndKg >= 100 ? 0 : 1,
  );
  final String paceFmt = _formatDecimalWithSeparators(
    prediction.currentAverageKgPerDay,
    locale,
    fractionDigits: 2,
  );

  return Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 8,
    children: [
      Text(
        isTr ? 'Ay sonu üst sınır: ' : 'Month-end cap: ',
        style: base,
      ),
      Text(targetFmt, style: base),
      const SizedBox(width: 8),
      Text('kg CO₂e', style: base),
      Text(' · ', style: base),
      Text(isTr ? 'Günlük tempo: ' : 'Pace: ', style: base),
      Text(paceFmt, style: base),
      const SizedBox(width: 8),
      Text(isTr ? 'kg/gün' : 'kg/day', style: base),
      Text(' · ', style: base),
      Text(
        isTr
            ? 'Kalan gün: ${prediction.remainingDays}'
            : 'Days left: ${prediction.remainingDays}',
        style: base,
      ),
    ],
  );
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({
    required this.prediction,
    required this.reductionTargetPercent,
    this.languageProvider,
    this.loadingOverlay = false,
    this.onEditReductionTarget,
  });

  final MonthlyPrediction prediction;
  final double reductionTargetPercent;
  final LanguageProvider? languageProvider;
  final bool loadingOverlay;
  final VoidCallback? onEditReductionTarget;

  @override
  Widget build(BuildContext context) {
    final locale = languageProvider?.currentLocale ?? const Locale('tr');
    final isTr = locale.languageCode == 'tr';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final double gaugeSafe = prediction.gaugeEfficiency.isFinite
        ? prediction.gaugeEfficiency.clamp(0.0, 1.0)
        : 0.0;
    final efficiencyPct = gaugeSafe * 100.0;
    final double screenW = MediaQuery.sizeOf(context).width;
    final double cardOuterPad = screenW < 360 ? 16.0 : 24.0;
    final String worldDiffFmt = prediction.worldDiffPercent >= 200.0
        ? '200+'
        : _formatDecimalWithSeparators(
            prediction.worldDiffPercent,
            locale,
            fractionDigits: 1,
          );
    final String badgeLabel = prediction.worldRoughlyEqual
        ? (isTr
            ? 'Küresel günlük ortalamayla aynı hizada'
            : 'Aligned with global daily average')
        : prediction.isBetterThanWorldAverage
            ? (isTr
                ? 'Dünya Ortalamasından %$worldDiffFmt Daha İyi'
                : '$worldDiffFmt% better than world avg')
            : (isTr
                ? 'Dünya Ortalamasından %$worldDiffFmt Daha Yüksek'
                : '$worldDiffFmt% above world avg');

    final Color unitColor = isDark ? Colors.white70 : Colors.black87;
    final bool noPaceData = prediction.currentAverageKgPerDay <= 1e-9;

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.all(cardOuterPad),
          decoration: BoxDecoration(
            gradient: isDark
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                    ],
                  ),
            color: isDark ? Colors.black.withValues(alpha: 0.4) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: isDark ? 1 : 2,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double cw = constraints.maxWidth;
              final bool sideBySide = cw >= _kPredictionSideBySideBreakpoint;
              final bool insightColumn = cw < _kInsightCardsColumnBreakpoint;

              final double gaugeSize = sideBySide
                  ? (((cw - 12) * 2 / 5) - 8).clamp(120.0, 220.0)
                  : (cw * 0.42).clamp(110.0, 200.0);
              final double gaugeStroke =
                  (gaugeSize / 108.0 * 8.0).clamp(6.0, 12.0);

              Widget gaugeBox() {
                return SizedBox(
                  width: gaugeSize,
                  height: gaugeSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: gaugeSafe,
                          strokeWidth: gaugeStroke,
                          backgroundColor:
                              (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            prediction.isOnTrack
                                ? Colors.greenAccent.shade400
                                : Colors.deepOrange.shade600,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_formatDecimalWithSeparators(efficiencyPct, locale, fractionDigits: 1)}%',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w800,
                                  fontSize: gaugeSize >= 170 ? 14 : 12,
                                ),
                          ),
                          Text(
                            isTr ? 'hedef uyumu' : 'goal fit',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: _goalsReadableOnCard(context, isDark),
                                  fontWeight: FontWeight.w600,
                                  fontSize: gaugeSize >= 170 ? 11 : 10,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              Widget rightTexts() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: prediction.worldRoughlyEqual
                            ? Colors.blueGrey.shade700.withValues(alpha: 0.35)
                            : prediction.isBetterThanWorldAverage
                                ? Colors.green.shade700.withValues(alpha: 0.35)
                                : Colors.deepOrange.shade800
                                    .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: prediction.worldRoughlyEqual
                              ? Colors.blueGrey.shade400.withValues(alpha: 0.85)
                              : prediction.isBetterThanWorldAverage
                                  ? Colors.greenAccent.shade400
                                      .withValues(alpha: 0.9)
                                  : Colors.deepOrange.shade800
                                      .withValues(alpha: 0.9),
                        ),
                      ),
                      child: Text(
                        badgeLabel,
                        softWrap: true,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: prediction.worldRoughlyEqual
                                  ? Colors.blueGrey.shade100
                                  : prediction.isBetterThanWorldAverage
                                      ? Colors.lightGreenAccent.shade100
                                      : (isDark
                                          ? Colors.orange.shade100
                                          : _kGoalsDeepOrangeText),
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        isTr ? 'Tahmini ay sonu toplamı' : 'Projected month-end',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _goalsReadableOnCard(context, isDark),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, c2) {
                        final projStr = noPaceData
                            ? '—'
                            : _formatDecimalWithSeparators(
                                prediction.projectedMonthEndKg,
                                locale,
                                fractionDigits:
                                    prediction.projectedMonthEndKg >= 100
                                        ? 0
                                        : 1,
                              );
                        final double valueFont =
                            (c2.maxWidth * 0.095).clamp(20.0, 36.0);
                        final unitFont = (valueFont * 0.42).clamp(12.0, 16.0);
                        final valueStyle =
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  color: isDark ? Colors.white : cs.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: valueFont,
                                  height: 1.05,
                                );
                        final unitStyle =
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: unitColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: unitFont,
                                );
                        return Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                projStr,
                                style: valueStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (!noPaceData)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text('kg CO₂e', style: unitStyle),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (noPaceData) ...[
                      const SizedBox(height: 6),
                      Text(
                        isTr
                            ? 'Tahmin için son günlerde günlük emisyon verisi gerekir (Manuel, ESP veya Shelly).'
                            : 'Need recent daily emissions (manual, ESP, or Shelly) to forecast.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _goalsReadableOnCard(context, isDark),
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _outlookTargetEditorRow(
                      context,
                      reductionTargetPercent: reductionTargetPercent,
                      locale: locale,
                      isTr: isTr,
                      isDark: isDark,
                      onEdit: onEditReductionTarget,
                    ),
                    const SizedBox(height: 10),
                    _predictionMetaLine(
                      context,
                      prediction: prediction,
                      locale: locale,
                      isTr: isTr,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          prediction.isOnTrack
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          size: 18,
                          color: prediction.isOnTrack
                              ? Colors.green.shade700
                              : _kGoalsDarkOrangeText,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            prediction.trackMessage,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: prediction.isOnTrack
                                      ? (isDark
                                          ? Colors.greenAccent.shade200
                                          : const Color(0xFF1B5E20))
                                      : (isDark
                                          ? Colors.deepOrange.shade200
                                          : _kGoalsDarkOrangeText),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      prediction.impactSummary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _goalsReadableOnCard(context, isDark),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sideBySide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Center(child: gaugeBox()),
                        ),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: rightTexts()),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: gaugeBox()),
                        SizedBox(height: screenW < 360 ? 12 : 16),
                        rightTexts(),
                      ],
                    ),
                  SizedBox(height: screenW < 360 ? 10 : 12),
                  if (insightColumn)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InsightMiniCard(
                          title: isTr ? 'Neden?' : 'Why?',
                          body: isTr
                              ? prediction.insightWhyTr
                              : prediction.insightWhyEn,
                          isDark: isDark,
                          fillVerticalSpace: false,
                        ),
                        SizedBox(height: screenW < 360 ? 10 : 12),
                        _InsightMiniCard(
                          title: isTr ? 'Tavsiye' : 'Tip',
                          body: isTr
                              ? prediction.insightTipTr
                              : prediction.insightTipEn,
                          isDark: isDark,
                          fillVerticalSpace: false,
                        ),
                      ],
                    )
                  else
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
                              fillVerticalSpace: true,
                            ),
                          ),
                          SizedBox(width: screenW < 360 ? 10 : 12),
                          Expanded(
                            child: _InsightMiniCard(
                              title: isTr ? 'Tavsiye' : 'Tip',
                              body: isTr
                                  ? prediction.insightTipTr
                                  : prediction.insightTipEn,
                              isDark: isDark,
                              fillVerticalSpace: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
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
    this.fillVerticalSpace = true,
  });

  final String title;
  final String body;
  final bool isDark;

  /// Yan yana [IntrinsicHeight]+[Row] için tam yükseklik; dar ekranda alt alta dizilirken false.
  final bool fillVerticalSpace;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    final box = Container(
      width: double.infinity,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Align(
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
            SizedBox(height: pad > 12 ? 6 : 4),
            Text(
              body,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _goalsReadableOnCard(context, isDark),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
    if (!fillVerticalSpace) return box;
    return SizedBox.expand(child: box);
  }
}

bool _isCompactGoalCardLayout(String type) {
  return type == 'electricity_saving' ||
      type == 'co2_reduction' ||
      type == 'water_saving';
}

String? _goalInfoTranslationKey(String type) {
  switch (type) {
    case 'electricity_saving':
      return 'goal_info_electricity_saving';
    case 'co2_reduction':
      return 'goal_info_co2_reduction';
    case 'water_saving':
      return 'goal_info_water_saving';
    default:
      return null;
  }
}

/// Elektrik / CO₂ / su hedef kartlarında kısa dikey ilerleme çubuğu.
class _CompactGoalProgressBar extends StatelessWidget {
  const _CompactGoalProgressBar({
    required this.progress,
    required this.isCompleted,
    required this.fillColor,
  });

  final double progress;
  final bool isCompleted;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    final double p = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: 12,
      height: 92,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: p,
                widthFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: isCompleted
                        ? LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.green,
                              Colors.green.shade300,
                            ],
                          )
                        : null,
                    color: isCompleted ? null : fillColor,
                  ),
                ),
              ),
            ),
          ],
        ),
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
    final String? infoKey = _goalInfoTranslationKey(goal.type);
    final bool compactLayout = _isCompactGoalCardLayout(goal.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          localizedTitle,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                        ),
                      ),
                      if (infoKey != null)
                        IconButton(
                          icon: const Icon(
                            Icons.info_outline,
                            size: 22,
                            color: _kGoalsDarkOrangeText,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () {
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(localizedTitle),
                                content: SingleChildScrollView(
                                  child: Text(translate(infoKey, locale)),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text(translate('ok', locale)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
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
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
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
                              Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.2),
                              Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                            ],
                          )),
                color: isCompleted
                    ? Colors.green.withValues(alpha: 0.15)
                    : (isDark ? Colors.black.withValues(alpha: 0.4) : null),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCompleted
                      ? Colors.green
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (compactLayout)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${translate('goal_progress_label', locale)} · ${(goal.progress * 100).toStringAsFixed(0)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: _goalsReadableOnCard(
                                      context,
                                      isDark,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${goal.current.toStringAsFixed(1)}/${goal.target.toStringAsFixed(1)} ${goal.unit}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                ),
                                Text(
                                  '${(goal.progress * 100).toStringAsFixed(0)}%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isCompleted
                                            ? (isDark
                                                ? Colors.greenAccent.shade200
                                                : const Color(0xFF1B5E20))
                                            : _goalsReadableOnCard(
                                                context,
                                                isDark,
                                              ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                            if (onDelete != null)
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                onPressed: onDelete,
                                tooltip: translate('delete', locale),
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: compactLayout ? 12 : 14),
                    if (compactLayout) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CompactGoalProgressBar(
                            progress: goal.progress,
                            isCompleted: isCompleted,
                            fillColor: goal.color,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _monthlyComparisonText(locale),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: isCompleted
                                                  ? (isDark
                                                      ? Colors
                                                          .greenAccent.shade200
                                                      : const Color(
                                                          0xFF1B5E20,
                                                        ))
                                                  : _goalsReadableOnCard(
                                                      context,
                                                      isDark,
                                                    ),
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                            ),
                                      ),
                                    ),
                                    if (isCompleted)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.celebration,
                                            color: Color(0xFFF57C00), size: 18),
                                      ),
                                  ],
                                ),
                                if (goal.recommendation.trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    goal.recommendation,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: _kGoalsDarkOrangeText,
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Stack(
                        children: [
                          LinearProgressIndicator(
                            value: goal.progress.clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
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
                                    colors: [
                                      Colors.green,
                                      Colors.green.shade300,
                                    ],
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isCompleted
                                        ? (isDark
                                            ? Colors.greenAccent.shade200
                                            : const Color(0xFF1B5E20))
                                        : _goalsReadableOnCard(
                                            context,
                                            isDark,
                                          ),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          if (isCompleted)
                            const Icon(Icons.celebration,
                                color: Color(0xFFF57C00), size: 18),
                        ],
                      ),
                      if (goal.recommendation.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          goal.recommendation,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _kGoalsDarkOrangeText,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
                  color: _goalsReadableOnCard(context, isDark),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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

class _EarnPointsDialog extends StatefulWidget {
  const _EarnPointsDialog({
    required this.titleKey,
    required this.icon,
    required this.kind,
    required this.locale,
    required this.mult,
    required this.maxSlide,
    required this.savingsUsedToday,
    required this.savingsEligible,
    required this.userLoggedIn,
    required this.weekWalkKmTotal,
    required this.weekWalkBonusClaimed,
  });

  final String titleKey;
  final IconData icon;
  final _EnginePointKind kind;
  final Locale locale;
  final int mult;
  final double maxSlide;
  final bool savingsUsedToday;
  final bool savingsEligible;
  final bool userLoggedIn;
  final double weekWalkKmTotal;
  final bool weekWalkBonusClaimed;

  @override
  State<_EarnPointsDialog> createState() => _EarnPointsDialogState();
}

class _EarnPointsDialogState extends State<_EarnPointsDialog> {
  late final TextEditingController _controller;
  double _sliderVal = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _sliderDivisions {
    if (widget.maxSlide < 1) return 1;
    return widget.maxSlide <= 50
        ? widget.maxSlide.round().clamp(1, 50)
        : 48;
  }

  ThemeData get _earnTheme => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: AppTheme.infoDialogForeground,
          onPrimary: Colors.white,
          surface: AppTheme.infoDialogBackground,
          onSurface: AppTheme.infoDialogForeground,
          secondary: AppTheme.lightPrimaryColor,
          onSecondary: Colors.white,
          surfaceContainerHighest: AppTheme.infoDialogForeground,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppTheme.infoDialogForeground,
          inactiveTrackColor:
              AppTheme.infoDialogForeground.withValues(alpha: 0.28),
          thumbColor: AppTheme.infoDialogForeground,
          trackHeight: 8,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppTheme.infoDialogForeground.withValues(alpha: 0.35),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppTheme.infoDialogForeground.withValues(alpha: 0.35),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(
              color: AppTheme.infoDialogForeground,
              width: 1.8,
            ),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final parsed = _parseLocaleDouble(_controller.text);
    final amt = ((parsed ?? 0) > 0) ? parsed! : 0.0;
    final basePts = (amt * widget.mult).round();
    final previewSavings =
        (widget.savingsEligible && !widget.savingsUsedToday) ? 50 : 0;
    final nextWalkKm = widget.kind == _EnginePointKind.walk
        ? widget.weekWalkKmTotal + amt
        : widget.weekWalkKmTotal;
    final previewWeekly = widget.kind == _EnginePointKind.walk &&
            !widget.weekWalkBonusClaimed &&
            widget.weekWalkKmTotal < 10.0 &&
            nextWalkKm >= 10.0 - 1e-9
        ? 100
        : 0;
    final totalPreview = basePts + previewSavings + previewWeekly;

    final explainKey = switch (widget.kind) {
      _EnginePointKind.walk => 'earn_points_dialog_explain_walk',
      _EnginePointKind.publicTransport => 'earn_points_dialog_explain_bus',
      _EnginePointKind.recycle => 'earn_points_dialog_explain_recycle',
      _EnginePointKind.water => 'earn_points_dialog_explain_water',
    };
    final questionKey = switch (widget.kind) {
      _EnginePointKind.walk => 'how_many_km_today',
      _EnginePointKind.publicTransport => 'how_many_km_today',
      _EnginePointKind.recycle => 'how_many_kg_recycled',
      _EnginePointKind.water => 'how_many_liters_water_saved',
    };

    return Theme(
      data: _earnTheme,
      child: Dialog(
        backgroundColor: AppTheme.infoDialogBackground,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        translate(widget.titleKey, widget.locale),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.58,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          translate(
                            explainKey,
                            widget.locale,
                            params: {'multiplier': '${widget.mult}'},
                          ),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.35,
                                  ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          translate(questionKey, widget.locale),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _controller,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            hintText:
                                translate('numeric_entry_hint', widget.locale),
                          ),
                          onChanged: (s) {
                            final p = _parseLocaleDouble(s);
                            setState(() {
                              if (p != null &&
                                  p >= 0 &&
                                  p <= widget.maxSlide + 1e-9) {
                                _sliderVal = p.clamp(0.0, widget.maxSlide);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 15),
                        Text(
                          translate('slider_quick_set', widget.locale),
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.infoDialogForeground.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: _QuickSetSlider(
                            value: _sliderVal.clamp(0.0, widget.maxSlide),
                            max: widget.maxSlide,
                            divisions: _sliderDivisions,
                            onChanged: (v) {
                              setState(() {
                                _sliderVal = v;
                                _controller.text =
                                    widget.kind == _EnginePointKind.recycle
                                        ? v.toStringAsFixed(2)
                                        : v.toStringAsFixed(1);
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          translate(
                            'points_total_label',
                            widget.locale,
                            params: {'points': '$totalPreview'},
                          ),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (widget.kind == _EnginePointKind.walk) ...[
                          const SizedBox(height: 15),
                          Text(
                            translate(
                              'weekly_progress_km',
                              widget.locale,
                              params: {
                                'current':
                                    widget.weekWalkKmTotal.toStringAsFixed(1),
                                'target': '10',
                              },
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.weekWalkBonusClaimed
                                ? translate(
                                    'weekly_bonus_claimed',
                                    widget.locale,
                                  )
                                : translate(
                                    'weekly_bonus_pending',
                                    widget.locale,
                                  ),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 15),
                        Text(
                          !widget.userLoggedIn
                              ? translate(
                                  'savings_bonus_requires_login',
                                  widget.locale,
                                )
                              : widget.savingsUsedToday
                                  ? translate(
                                      'savings_bonus_used_today',
                                      widget.locale,
                                    )
                                  : widget.savingsEligible
                                      ? translate(
                                          'savings_bonus_available',
                                          widget.locale,
                                          params: {'points': '50'},
                                        )
                                      : translate(
                                          'savings_bonus_not_eligible',
                                          widget.locale,
                                        ),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(translate('cancel', widget.locale)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final v = _parseLocaleDouble(_controller.text);
                        if (v == null || v <= 0) return;
                        Navigator.of(context).pop(v);
                      },
                      child: Text(
                        translate('log_action_confirm', widget.locale),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.rateSubtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String rateSubtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rateSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _goalsReadableOnCard(context, isDark),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.add_circle_outline,
                size: 22,
                color: primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
