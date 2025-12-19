import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import '../widgets/info_flip_card.dart';
import '../widgets/hero_donate_banner.dart';
import '../widgets/bill_scanner.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/weather_service.dart';

/// Home screen showing title, tips, and weather placeholder.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
    this.languageProvider,
  });

  final void Function(bool isDark) onToggleTheme; // kept for Settings usage
  final ThemeMode themeMode; // kept for summary card and other UI
  final LanguageProvider? languageProvider;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _tipsController;
  late final PageController _heroController;
  double _currentPage = 0;
  double _heroCurrentPage = 0;
  Timer? _autoScrollTimer;
  Timer? _heroAutoScrollTimer;
  double? _dailyEmissionKg; // son hesaplanan günlük emisyon

  // Listener'ları sakla (dispose için)
  late final VoidCallback _tipsListener;
  late final VoidCallback _heroListener;

  // Hava durumu verileri
  final WeatherService _weatherService = WeatherService();
  Map<String, dynamic>? _currentWeather;
  List<Map<String, dynamic>>? _weatherForecast;
  Map<String, dynamic>? _airQuality;
  double? _carbonIntensity;
  bool _isLoadingWeather = true;

  @override
  void initState() {
    super.initState();
    _tipsController = PageController(viewportFraction: 0.82);
    _heroController = PageController();

    // Listener'ları oluştur ve sakla
    _tipsListener = () {
      final newPage = _tipsController.page ?? 0;
      if ((newPage - _currentPage).abs() > 0.01) {
        setState(() {
          _currentPage = newPage;
        });
      }
    };

    _heroListener = () {
      final newPage = _heroController.page ?? 0;
      if ((newPage - _heroCurrentPage).abs() > 0.01) {
        setState(() {
          _heroCurrentPage = newPage;
        });
      }
    };

    _tipsController.addListener(_tipsListener);
    _heroController.addListener(_heroListener);

    // Hero slider'ı belirli aralıklarla otomatik kaydır
    _heroAutoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final int current = (_heroController.page ?? 0).round();
      const int heroCount = 3; // hero görsellerinde 3 görsel var
      final int next = (current + 1) % heroCount;
      _heroController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });

    // İpuçları kartlarını belirli aralıklarla otomatik kaydır
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final int current = (_tipsController.page ?? 0).round();
      const int tipsCount = 3; // tips listesinde 3 kart var
      final int next = (current + 1) % tipsCount;
      _tipsController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });

    // Hava durumu verilerini yükle
    _loadWeatherData();
  }

  /// Hava durumu verilerini yükle
  Future<void> _loadWeatherData() async {
    setState(() => _isLoadingWeather = true);

    try {
      // İstanbul için hava durumu verilerini çek
      final weather = await _weatherService.getWeatherData('Istanbul,TR');
      final forecast = await _weatherService.getWeatherForecast('Istanbul,TR');
      final aqi = await _weatherService.getAirQuality(
        'Istanbul',
        'Istanbul',
        'Turkey',
      );
      final carbonIntensity = await _weatherService.getCarbonIntensity('TR');

      if (mounted) {
        setState(() {
          _currentWeather = weather;
          _weatherForecast = forecast;
          _airQuality = aqi;
          _carbonIntensity = carbonIntensity;
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingWeather = false);
      }
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _heroAutoScrollTimer?.cancel();
    _tipsController.removeListener(_tipsListener);
    _heroController.removeListener(_heroListener);
    _tipsController.dispose();
    _heroController.dispose();
    super.dispose();
  }

  // Tips widget'larını cache'le (locale değişmediği sürece yeniden oluşturma)
  List<Widget>? _cachedTips;
  Locale? _cachedLocale;

  List<Widget> _getTips(Locale locale) {
    if (_cachedTips != null && _cachedLocale == locale) {
      return _cachedTips!;
    }
    _cachedLocale = locale;
    _cachedTips = [
      InfoFlipCard(
        frontTitle: translate('lighting', locale),
        frontSummary: translate('lighting_tip', locale),
        backDetails: translate('lighting_details', locale),
        languageProvider: widget.languageProvider,
      ),
      InfoFlipCard(
        frontTitle: translate('hvac', locale),
        frontSummary: translate('hvac_tip', locale),
        backDetails: translate('hvac_details', locale),
        languageProvider: widget.languageProvider,
      ),
      InfoFlipCard(
        frontTitle: translate('logistics', locale),
        frontSummary: translate('logistics_tip', locale),
        backDetails: translate('logistics_details', locale),
        languageProvider: widget.languageProvider,
      ),
    ];
    return _cachedTips!;
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final textColor = Theme.of(context).colorScheme.onSurface;

    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final tips = _getTips(locale);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
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
              // Hero Slider - Sadece görseller (geniş ekranda daha yüksek)
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth >= 900;
                  // Web/geniş ekranda görselin rahat sığması için yüksekliği artır
                  final double heroHeight = isWide ? 360 : 200;
                  return SizedBox(
                    height: heroHeight,
                    child: PageView.builder(
                      controller: _heroController,
                      itemCount: 3,
                      itemBuilder: (context, index) {
                        final images = [
                          'assets/images/herosectionafis.jpg',
                          'assets/images/herosectionafis2.jpg',
                          'assets/images/herosectionafis3.jpg',
                        ];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              images[index],
                              fit: isWide ? BoxFit.contain : BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Hero slider indicator dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final selected = (_heroCurrentPage.round() == i);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected ? 12 : 8,
                    height: selected ? 12 : 8,
                    decoration: BoxDecoration(
                      color: selected
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.5)
                                : Colors.black.withValues(alpha: 0.4)),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              // Ağaç bağışı bölümü için görsel ve CTA
              HeroDonateBanner(
                imageAssetPath: 'assets/images/olive-drab_small.webp',
                languageProvider: widget.languageProvider,
              ),
              const SizedBox(height: 16),
              // İşletme karşılaştırma tablosu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    translate('business_comparison_title', locale),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    translate('see_all', locale),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _BusinessComparisonTable(locale: locale, isDark: isDark),
              const SizedBox(height: 16),
              // Fatura tarama başlığı
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    translate('bill_scanning_title', locale),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    translate('see_all', locale),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Fatura tarama kartı
              BillScannerCard(
                languageProvider: widget.languageProvider,
                onCalculated: (value) =>
                    setState(() => _dailyEmissionKg = value),
              ),
              const SizedBox(height: 16),
              // GNÇ tarzında başlık
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    translate('energy_tips_title', locale),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    translate('see_all', locale),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth >= 900;
                  if (isWide) {
                    // Geniş ekran: kartları ortala ve sabit genişlik ver
                    return Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: tips
                            .map(
                              (w) => SizedBox(
                                width: 300,
                                height: 190,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: w,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  }
                  // Mobil/tablet: mevcut PageView
                  return Column(
                    children: [
                      SizedBox(
                        height: 190,
                        child: PageView.builder(
                          controller: _tipsController,
                          allowImplicitScrolling: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: tips.length,
                          padEnds: false,
                          clipBehavior: Clip.none,
                          itemBuilder: (context, index) {
                            final distance = (_currentPage - index).abs();
                            final scale = (1 - (distance * 0.12)).clamp(
                              0.88,
                              1.0,
                            );
                            final isSelected = distance == 0;
                            final opacity = isSelected ? 1.0 : 0.6;
                            final height = isSelected ? 190.0 : 150.0;

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              height: height,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 220),
                                opacity: opacity,
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 220),
                                  scale: scale,
                                  child: tips[index],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(tips.length, (i) {
                          final selected = (_currentPage.round() == i);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: selected ? 10 : 8,
                            height: selected ? 10 : 8,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
              // Hava durumu bölümü başlığı
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    translate('weather_energy_title', locale),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    translate('see_all', locale),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Hava durumu kartları
              LayoutBuilder(
                builder: (context, constraints) {
                  final double screenWidth = constraints.maxWidth;
                  final double cardHeight = screenWidth > 600 ? 160 : 140;
                  final double cardWidth = screenWidth > 600 ? 180 : 160;

                  // Gerçek hava durumu verilerini kullan veya placeholder
                  final List<Map<String, dynamic>> weatherCards;
                  if (_weatherForecast != null &&
                      _weatherForecast!.isNotEmpty) {
                    weatherCards = [
                      {
                        'title': translate('today', locale),
                        'temp':
                            '${_currentWeather?['temperature']?.toStringAsFixed(0) ?? 24}°C',
                        'condition':
                            _currentWeather?['condition'] ??
                            translate('sunny', locale),
                        'icon': _getWeatherIcon(
                          _currentWeather?['icon'] ?? '01d',
                        ),
                        'tip': _getWeatherTip(
                          _currentWeather?['condition'] ?? 'Clear',
                          locale,
                        ),
                        'color': _getWeatherColor(
                          _currentWeather?['icon'] ?? '01d',
                        ),
                      },
                      if (_weatherForecast!.isNotEmpty)
                        {
                          'title': translate('tomorrow', locale),
                          'temp':
                              '${_weatherForecast![0]['temperature']?.toStringAsFixed(0) ?? 18}°C',
                          'condition':
                              _weatherForecast![0]['condition'] ??
                              translate('cloudy', locale),
                          'icon': _getWeatherIcon(
                            _weatherForecast![0]['icon'] ?? '02d',
                          ),
                          'tip': _getWeatherTip(
                            _weatherForecast![0]['condition'] ?? 'Clouds',
                            locale,
                          ),
                          'color': _getWeatherColor(
                            _weatherForecast![0]['icon'] ?? '02d',
                          ),
                        },
                      if (_weatherForecast!.length > 1)
                        {
                          'title': translate('week', locale),
                          'temp':
                              '${_weatherForecast![1]['temperature']?.toStringAsFixed(0) ?? 22}°C',
                          'condition':
                              _weatherForecast![1]['condition'] ??
                              translate('mixed', locale),
                          'icon': _getWeatherIcon(
                            _weatherForecast![1]['icon'] ?? '03d',
                          ),
                          'tip': _getWeatherTip(
                            _weatherForecast![1]['condition'] ?? 'Clouds',
                            locale,
                          ),
                          'color': _getWeatherColor(
                            _weatherForecast![1]['icon'] ?? '03d',
                          ),
                        },
                    ];
                  } else {
                    // Placeholder veriler
                    weatherCards = [
                      {
                        'title': translate('today', locale),
                        'temp': '24°C',
                        'condition': translate('sunny', locale),
                        'icon': Icons.wb_sunny,
                        'tip': translate('solar_ideal', locale),
                        'color': Colors.orange,
                      },
                      {
                        'title': translate('tomorrow', locale),
                        'temp': '18°C',
                        'condition': translate('cloudy', locale),
                        'icon': Icons.cloud,
                        'tip': translate('natural_light_decrease', locale),
                        'color': Colors.blue,
                      },
                      {
                        'title': translate('week', locale),
                        'temp': '22°C',
                        'condition': translate('mixed', locale),
                        'icon': Icons.wb_cloudy,
                        'tip': translate('hvac_usage_increase', locale),
                        'color': Colors.green,
                      },
                    ];
                  }

                  return SizedBox(
                    height: cardHeight,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: weatherCards.length,
                      itemBuilder: (context, index) {
                        final card = weatherCards[index];
                        return Container(
                          width: cardWidth,
                          margin: const EdgeInsets.only(right: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        (Theme.of(context).brightness ==
                                            Brightness.dark)
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                card['icon'] as IconData,
                                                color: card['color'] as Color,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  card['title'] as String,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            card['temp'] as String,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            card['condition'] as String,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.8),
                                                ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        card['tip'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: card['color'] as Color,
                                              fontWeight: FontWeight.w500,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
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
              const SizedBox(height: 16),
              // Gerçek zamanlı iklim verileri
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.public,
                            color: Colors.tealAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _isLoadingWeather
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        translate(
                                          'climate_realtime_title',
                                          locale,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          _InfoChip(
                                            label: translate('city', locale),
                                            value:
                                                _currentWeather?['city'] ??
                                                'İstanbul',
                                          ),
                                          _InfoChip(
                                            label: translate(
                                              'temperature',
                                              locale,
                                            ),
                                            value: _currentWeather != null
                                                ? '${_currentWeather!['temperature']?.toStringAsFixed(0) ?? 24}°C'
                                                : '24°C',
                                          ),
                                          _InfoChip(
                                            label: translate('aqi', locale),
                                            value: _airQuality != null
                                                ? '${_airQuality!['aqi'] ?? 78} (${_airQuality!['aqiText'] ?? 'Orta'})'
                                                : '78 (Orta)',
                                          ),
                                          _InfoChip(
                                            label: translate(
                                              'carbon_intensity',
                                              locale,
                                            ),
                                            value: _carbonIntensity != null
                                                ? '${_carbonIntensity!.toStringAsFixed(0)} gCO₂/kWh'
                                                : '420 gCO₂/kWh',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            translate(
                                              'climate_data_source_hint',
                                              locale,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.75),
                                                ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.refresh,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                            onPressed: _loadWeatherData,
                                            tooltip: 'Yenile',
                                          ),
                                        ],
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
              // Emisyon farkındalık / karşılaştırma (placeholder hesap)
              _EmissionComparisonCard(
                userDailyEmissionKg: _dailyEmissionKg ?? 12.0,
                nationalAvgKg: 15.0,
                globalAvgKg: 15.0,
                locale: locale,
              ),
              const SizedBox(height: 16),
              // Eşdeğer görselleştirme
              _EquivalentsCard(
                dailyEmissionKg: _dailyEmissionKg ?? 12.0,
                locale: locale,
              ),
              // Eski alıntı görsel bloğu kaldırıldı (yukarıda blur olarak gösteriliyor)
            ],
          ),
        ],
      ),
    );
  }

  /// Hava durumu ikonunu OpenWeatherMap icon kodundan döndür
  IconData _getWeatherIcon(String iconCode) {
    // OpenWeatherMap icon kodları: 01d, 02d, 03d, 04d, 09d, 10d, 11d, 13d, 50d
    if (iconCode.contains('01')) {
      return Icons.wb_sunny; // Açık
    }
    if (iconCode.contains('02')) {
      return Icons.wb_cloudy; // Az bulutlu
    }
    if (iconCode.contains('03') || iconCode.contains('04')) {
      return Icons.cloud; // Bulutlu
    }
    if (iconCode.contains('09') || iconCode.contains('10')) {
      return Icons.grain; // Yağmurlu
    }
    if (iconCode.contains('11')) {
      return Icons.flash_on; // Fırtına
    }
    if (iconCode.contains('13')) {
      return Icons.ac_unit; // Karlı
    }
    if (iconCode.contains('50')) {
      return Icons.blur_on; // Sisli
    }
    return Icons.wb_sunny; // Varsayılan
  }

  /// Hava durumu rengini icon kodundan döndür
  Color _getWeatherColor(String iconCode) {
    if (iconCode.contains('01')) {
      return Colors.orange; // Açık
    }
    if (iconCode.contains('02')) {
      return Colors.blue.shade300; // Az bulutlu
    }
    if (iconCode.contains('03') || iconCode.contains('04')) {
      return Colors.blue; // Bulutlu
    }
    if (iconCode.contains('09') || iconCode.contains('10')) {
      return Colors.blue.shade700; // Yağmurlu
    }
    if (iconCode.contains('11')) {
      return Colors.purple; // Fırtına
    }
    if (iconCode.contains('13')) {
      return Colors.cyan; // Karlı
    }
    if (iconCode.contains('50')) {
      return Colors.grey; // Sisli
    }
    return Colors.orange; // Varsayılan
  }

  /// Hava durumuna göre enerji ipucu döndür
  String _getWeatherTip(String? condition, Locale locale) {
    if (condition == null) return translate('solar_ideal', locale);

    final conditionLower = condition.toLowerCase();
    if (conditionLower.contains('clear') || conditionLower.contains('açık')) {
      return translate('solar_ideal', locale);
    } else if (conditionLower.contains('cloud') ||
        conditionLower.contains('bulut')) {
      return translate('natural_light_decrease', locale);
    } else if (conditionLower.contains('rain') ||
        conditionLower.contains('yağmur')) {
      return translate('hvac_usage_increase', locale);
    } else if (conditionLower.contains('snow') ||
        conditionLower.contains('kar')) {
      return translate('hvac_usage_increase', locale);
    } else {
      return translate('hvac_usage_increase', locale);
    }
  }
}

// Basit bilgi çipi
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Emisyon karşılaştırma kartı
class _EmissionComparisonCard extends StatelessWidget {
  const _EmissionComparisonCard({
    required this.userDailyEmissionKg,
    required this.nationalAvgKg,
    required this.globalAvgKg,
    required this.locale,
  });

  final double userDailyEmissionKg;
  final double nationalAvgKg;
  final double globalAvgKg;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final double diffVsGlobal =
        ((userDailyEmissionKg - globalAvgKg) / globalAvgKg) * 100;
    final bool isLower = diffVsGlobal < 0;
    final String percentText = '${diffVsGlobal.abs().toStringAsFixed(0)}%';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isLower ? Icons.trending_down : Icons.trending_up,
                      color: isLower ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      translate('emission_awareness_title', locale),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _InfoChip(
                      label: translate('you', locale),
                      value:
                          '${userDailyEmissionKg.toStringAsFixed(1)} kg CO₂e/gün',
                    ),
                    const SizedBox(width: 10),
                    _InfoChip(
                      label: translate('national_avg', locale),
                      value: nationalAvgKg.toStringAsFixed(1),
                    ),
                    const SizedBox(width: 10),
                    _InfoChip(
                      label: translate('global_avg', locale),
                      value: globalAvgKg.toStringAsFixed(1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isLower
                      ? '${translate('your_emission_is', locale)} $percentText ${translate('below_world_avg', locale)}'
                      : '${translate('your_emission_is', locale)} $percentText ${translate('above_world_avg', locale)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Eşdeğer görselleştirme kartı
class _EquivalentsCard extends StatelessWidget {
  const _EquivalentsCard({required this.dailyEmissionKg, required this.locale});

  final double dailyEmissionKg;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    // Basit dönüşüm katsayıları (yaklaşık)
    const double carKgPerKm = 0.120; // kg CO2e / km (binek araç)
    const double flightKgPerKm = 0.255; // kg CO2e / km (uçak, kişi başı)
    const double treeKgPerYear = 21.0; // 1 ağaç yıllık CO2 tutumu
    final double treeKgPerDay = treeKgPerYear / 365.0;

    final int trees = (dailyEmissionKg / treeKgPerDay).round();
    final int carKm = (dailyEmissionKg / carKgPerKm).round();
    final int flightKm = (dailyEmissionKg / flightKgPerKm).round();

    Widget metric(IconData icon, Color color, String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.equalizer, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    Text(
                      translate('impact_equivalents_title', locale),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    metric(
                      Icons.forest,
                      Colors.lightGreenAccent,
                      translate('trees_equivalent', locale),
                      '$trees ${translate('trees', locale)}',
                    ),
                    const SizedBox(width: 12),
                    metric(
                      Icons.directions_car,
                      Colors.cyanAccent,
                      translate('car_km_equivalent', locale),
                      '$carKm km',
                    ),
                    const SizedBox(width: 12),
                    metric(
                      Icons.flight_takeoff,
                      Colors.pinkAccent,
                      translate('flight_km_equivalent', locale),
                      '$flightKm km',
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

// İşletme karşılaştırma tablosu widget'ı
class _BusinessComparisonTable extends StatelessWidget {
  const _BusinessComparisonTable({required this.locale, required this.isDark});

  final Locale locale;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Örnek işletme verileri
    final List<Map<String, dynamic>> businesses = [
      {
        'name': 'Teknoloji Şirketi A',
        'emission': 2.5,
        'industryAvg': 3.2,
        'status': 'better',
      },
      {
        'name': 'İmalat Firması B',
        'emission': 4.8,
        'industryAvg': 4.1,
        'status': 'worse',
      },
      {
        'name': 'Hizmet Şirketi C',
        'emission': 1.9,
        'industryAvg': 1.9,
        'status': 'same',
      },
      {
        'name': translate('your_business', locale),
        'emission': 3.1,
        'industryAvg': 3.2,
        'status': 'better',
        'isHighlighted': true,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 600;

        if (isWide) {
          // Geniş ekran: tam tablo
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Tablo başlıkları
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              '#',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              translate('business_name', locale),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('monthly_emission', locale),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('industry_avg', locale),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Durum',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      // Tablo satırları
                      ...businesses.asMap().entries.map((entry) {
                        final int index = entry.key;
                        final business = entry.value;
                        final bool isHighlighted =
                            business['isHighlighted'] == true;
                        final String status = business['status'] as String;

                        Color statusColor;
                        String statusText;
                        switch (status) {
                          case 'better':
                            statusColor = Colors.greenAccent;
                            statusText = translate('better_than_avg', locale);
                            break;
                          case 'worse':
                            statusColor = Colors.redAccent;
                            statusText = translate('worse_than_avg', locale);
                            break;
                          default:
                            statusColor = Colors.blueAccent;
                            statusText = translate('same_as_avg', locale);
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isHighlighted
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${index + 1}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  business['name'] as String,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${business['emission']} ${translate('tonnes_co2e_monthly', locale)}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${business['industryAvg']} ${translate('tonnes_co2e_monthly', locale)}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      status == 'better'
                                          ? Icons.trending_down
                                          : status == 'worse'
                                          ? Icons.trending_up
                                          : Icons.trending_flat,
                                      color: statusColor,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        statusText,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: statusColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          // Mobil: tablo formatında (küçük ekran için optimize edilmiş)
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Tablo başlıkları (mobil için küçük)
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              '#',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              translate('business_name', locale),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('monthly_emission', locale),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('industry_avg', locale),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Durum',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 6),
                      // Tablo satırları (mobil için küçük)
                      ...businesses.asMap().entries.map((entry) {
                        final int index = entry.key;
                        final business = entry.value;
                        final bool isHighlighted =
                            business['isHighlighted'] == true;
                        final String status = business['status'] as String;

                        Color statusColor;
                        String statusText;
                        switch (status) {
                          case 'better':
                            statusColor = Colors.greenAccent;
                            statusText = translate('better_than_avg', locale);
                            break;
                          case 'worse':
                            statusColor = Colors.redAccent;
                            statusText = translate('worse_than_avg', locale);
                            break;
                          default:
                            statusColor = Colors.blueAccent;
                            statusText = translate('same_as_avg', locale);
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: isHighlighted
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${index + 1}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  business['name'] as String,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${business['emission']} ${translate('tonnes_co2e_monthly', locale)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${business['industryAvg']} ${translate('tonnes_co2e_monthly', locale)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontWeight: isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      status == 'better'
                                          ? Icons.trending_down
                                          : status == 'worse'
                                          ? Icons.trending_up
                                          : Icons.trending_flat,
                                      color: statusColor,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 2),
                                    Expanded(
                                      child: Text(
                                        statusText,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: statusColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      },
    );
  }
}
