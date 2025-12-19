import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/api_service.dart';
import '../models/consumption_entry.dart';
import 'dart:async';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.languageProvider});

  final LanguageProvider? languageProvider;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final FirebaseRealtimeService _firebaseService =
      FirebaseRealtimeService.instance;
  final FirebaseAuthService _authService = FirebaseAuthService.instance;
  final ApiService _apiService = ApiService();

  int _greenScore = 0;
  List<CarbonGoal> _goals = [];
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
        'unit': '%',
        'type': 'electricity_saving',
        'icon': 'electrical_services',
        'color': 0xFF304411,
      },
      {
        'title': translate('co2_emission_reduction', locale),
        'target': 15.0,
        'current': 0.0,
        'unit': 'kg',
        'type': 'co2_reduction',
        'icon': 'eco',
        'color': 0xFF48631F,
      },
      {
        'title': translate('water_saving', locale),
        'target': 25.0,
        'current': 0.0,
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
          unit: data['unit'] ?? '',
          type: data['type'] ?? '',
          icon: _getIconFromString(data['icon'] ?? 'eco'),
          color: Color(data['color'] ?? 0xFF304411),
        );
      }).toList();
    });
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
      default:
        return Icons.flag;
    }
  }

  Future<void> _updateGoalProgress(ConsumptionEntry consumption) async {
    if (_userId == null) return;

    try {
      final goalsData = await _firebaseService.getGoals(_userId!);
      bool updated = false;

      for (var goalData in goalsData) {
        final type = goalData['type'] ?? '';
        double? newCurrent;

        switch (type) {
          case 'electricity_saving':
            // Elektrik tasarrufu yüzdesi hesapla (basit örnek)
            // Gerçek hesaplama için önceki ay verileriyle karşılaştırılmalı
            break;
          case 'co2_reduction':
            // CO2 azaltma (kg) - tüketim verilerinden hesapla
            // Basit örnek: fuel (CO2 ppm) değerinden kg'a çevir
            if (consumption.fuelLiters > 0) {
              newCurrent = consumption.fuelLiters * 0.001; // Basit dönüşüm
            }
            break;
          case 'water_saving':
            // Su tasarrufu yüzdesi hesapla
            // Gerçek hesaplama için önceki ay verileriyle karşılaştırılmalı
            break;
        }

        if (newCurrent != null && (goalData['current'] ?? 0.0) != newCurrent) {
          goalData['current'] = newCurrent;
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
                      gradient: LinearGradient(
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
          // İçerik
          ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 +
                  MediaQuery.of(context).padding.bottom +
                  80, // Bottom nav bar için ekstra padding
            ),
            children: [
              // Başarı rozetleri - En üstte gösteriliyor
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                    .titleMedium
                                    ?.copyWith(
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const Spacer(),
                              // Kazanılan rozet sayısı
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.2),
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
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _AchievementBadge(
                                  icon: Icons.eco,
                                  title: translate(
                                    'environment_friendly',
                                    locale,
                                  ),
                                  isUnlocked:
                                      _badges['environment_friendly'] ?? false,
                                ),
                                const SizedBox(width: 12),
                                _AchievementBadge(
                                  icon: Icons.energy_savings_leaf,
                                  title: translate('energy_saving', locale),
                                  isUnlocked: _badges['energy_saving'] ?? false,
                                ),
                                const SizedBox(width: 12),
                                _AchievementBadge(
                                  icon: Icons.water_drop,
                                  title: translate('water_protector', locale),
                                  isUnlocked:
                                      _badges['water_protector'] ?? false,
                                ),
                                const SizedBox(width: 12),
                                _AchievementBadge(
                                  icon: Icons.emoji_events,
                                  title: translate('goal_master', locale),
                                  isUnlocked: _badges['goal_master'] ?? false,
                                ),
                                const SizedBox(width: 12),
                                _AchievementBadge(
                                  icon: Icons.local_fire_department,
                                  title: translate('eco_warrior', locale),
                                  isUnlocked: _badges['eco_warrior'] ?? false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Green Score (Yeşil Puan) bölümü - İyileştirilmiş
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
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
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.energy_savings_leaf,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      translate('green_score', locale),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${(_greenScore ~/ 100)} ${translate('virtual_tree', locale)}',
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
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '$_greenScore',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
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
                                            fontSize: 10,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // İlerleme çubuğu
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: ((_greenScore % 100) / 100).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  minHeight: 12,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.2,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.primary,
                                  ),
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
                                  label: translate('completed_goals', locale),
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
                                  color: (isDark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final bool isMobile = constraints.maxWidth < 600;
                              if (isMobile) {
                                // Mobil: 2x2 grid
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _ActionChip(
                                            icon: Icons.recycling,
                                            label: translate('recycle', locale),
                                            points: 10,
                                            onTap: () => _awardPoints(10),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _ActionChip(
                                            icon: Icons.directions_walk,
                                            label: translate('walk', locale),
                                            points: 5,
                                            onTap: () => _awardPoints(5),
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
                                            onTap: () => _awardPoints(12),
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
                                            onTap: () => _awardPoints(6),
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
                                        points: 10,
                                        onTap: () => _awardPoints(10),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _ActionChip(
                                        icon: Icons.directions_walk,
                                        label: translate('walk', locale),
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
                                        label: translate('save_water', locale),
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: (isDark ? Colors.white : Colors.black)
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
                      onDelete:
                          _userId != null ? () => _deleteGoal(goal.id) : null,
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
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1,
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
                                  color: isDark ? Colors.white : Colors.black,
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
                                translate('login_required_for_goals', locale),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          (isDark ? Colors.white : Colors.black)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hedef silinirken hata oluştu: $e')),
        );
      }
    }
  }

  void _showAddGoalDialog() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final titleController = TextEditingController();
    final targetController = TextEditingController();
    String selectedUnit = '%';
    String selectedType = 'electricity_saving';
    IconData selectedIcon = Icons.flag;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(translate('add_new_goal', locale)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: translate('goal_title', locale),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: targetController,
                  decoration: InputDecoration(
                    labelText: translate('target_value', locale),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  decoration: InputDecoration(
                    labelText: translate('unit', locale),
                    border: const OutlineInputBorder(),
                  ),
                  items: ['%', 'kg', 'kWh', 'L', 'm³']
                      .map(
                        (unit) =>
                            DropdownMenuItem(value: unit, child: Text(unit)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedUnit = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: InputDecoration(
                    labelText: translate('goal_type', locale),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    'electricity_saving',
                    'co2_reduction',
                    'water_saving',
                    'waste_reduction',
                  ]
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(translate(type, locale)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedType = value;
                        // Tip değişince ikonu güncelle
                        switch (value) {
                          case 'electricity_saving':
                            selectedIcon = Icons.electrical_services;
                            break;
                          case 'co2_reduction':
                            selectedIcon = Icons.eco;
                            break;
                          case 'water_saving':
                            selectedIcon = Icons.water_drop;
                            break;
                          case 'waste_reduction':
                            selectedIcon = Icons.recycling;
                            break;
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(translate('cancel', locale)),
            ),
            FilledButton(
              onPressed: () async {
                if (titleController.text.isEmpty ||
                    targetController.text.isEmpty) {
                  return;
                }

                try {
                  final goal = {
                    'title': titleController.text,
                    'target': double.parse(targetController.text),
                    'current': 0.0,
                    'unit': selectedUnit,
                    'type': selectedType,
                    'icon': _getIconStringFromIcon(selectedIcon),
                    'color': 0xFF304411,
                  };

                  if (_userId != null) {
                    await _firebaseService.addGoal(_userId!, goal);
                  }

                  if (mounted) {
                    Navigator.of(this.context).pop();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('Hedef eklenirken hata oluştu: $e'),
                      ),
                    );
                  }
                }
              },
              child: Text(translate('add', locale)),
            ),
          ],
        ),
      ),
    );
  }

  String _getIconStringFromIcon(IconData icon) {
    if (icon == Icons.electrical_services) return 'electrical_services';
    if (icon == Icons.eco) return 'eco';
    if (icon == Icons.water_drop) return 'water_drop';
    if (icon == Icons.recycling) return 'recycling';
    if (icon == Icons.energy_savings_leaf) return 'energy_savings_leaf';
    return 'flag';
  }
}

class CarbonGoal {
  final String id;
  final String title;
  final double target;
  final double current;
  final String unit;
  final String type;
  final IconData icon;
  final Color color;

  CarbonGoal({
    required this.id,
    required this.title,
    required this.target,
    required this.current,
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = languageProvider?.currentLocale ?? const Locale('tr');
    final bool isCompleted = goal.progress >= 1.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? Colors.green
                  : Theme.of(context).colorScheme.primary,
              width: isCompleted ? 2 : 1,
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
                            goal.title,
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
                                Icon(
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
                    Text(
                      '${(goal.progress * 100).toStringAsFixed(1)}% ${translate('completed', locale)}',
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
                    if (isCompleted)
                      Icon(Icons.celebration, color: Colors.amber, size: 18),
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

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.icon,
    required this.title,
    required this.isUnlocked,
  });

  final IconData icon;
  final String title;
  final bool isUnlocked;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            child: Icon(
              icon,
              color: isUnlocked
                  ? Colors.white
                  : Colors.grey.withValues(
                      alpha: 0.7,
                    ), // Kilitli rozetler için gri ikon
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          // Rozet adı (küçük)
          SizedBox(
            width: 70,
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? (isUnlocked
                            ? Colors.white
                            : Colors.grey.withValues(alpha: 0.6))
                        : (isUnlocked
                            ? Colors.black
                            : Colors.grey.withValues(alpha: 0.6)),
                    fontWeight:
                        isUnlocked ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 11,
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
