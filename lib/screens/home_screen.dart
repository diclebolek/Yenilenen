import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import '../widgets/info_flip_card.dart';
import '../widgets/hero_donate_banner.dart';
import '../widgets/bill_scanner.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/weather_service.dart';
import '../services/api_service.dart';
import '../services/global_carbon_service.dart';
import '../services/carbon_data_service.dart';

/// Ana sayfa bölüm aralığı ve kart içi boşluk (diğer ekranlarla uyumlu ritim).
/// Önceki konteynır ile sonraki başlık arası; başlık ile altındaki konteynır arası ayrı.
const double _kHomeSectionGap = 56;
const double _kHomeTitleBelowGap = 56;
const EdgeInsets _kHomeCardPadding = EdgeInsets.all(16);

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
  PageController? _tipsControllerWeb; // Web için ayrı controller
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

  // Karbon emisyon ortalamaları (gerçek veriler)
  final GlobalCarbonService _globalCarbonService = GlobalCarbonService();
  final CarbonDataService _carbonDataService = CarbonDataService.instance;
  double? _globalAverageKg;
  double? _nationalAverageKg;

  // Shelly Plug S için eklenen değişkenler
  final ApiService _apiService = ApiService();
  final String _shellyDeviceId = 'shelly_plug_001';

  @override
  void initState() {
    super.initState();
    // İlk slider ile aynı içerik genişliği: tam genişlik sayfa
    _tipsController = PageController(viewportFraction: 1.0);
    _heroController = PageController();

    // Listener'ları oluştur ve sakla
    _tipsListener = () {
      // Hem mobil hem web controller için sayfa değişikliğini kontrol et
      double? newPage;

      // Hangi controller aktifse onun sayfasını al
      // Önce web controller'ı kontrol et (varsa ve aktifse)
      if (_tipsControllerWeb != null && _tipsControllerWeb!.hasClients) {
        try {
          final webPage = _tipsControllerWeb!.page;
          if (webPage != null) {
            newPage = webPage;
            // Web için yuvarlanmış değeri kullan (viewportFraction nedeniyle)
            final roundedPage = webPage.round().toDouble();
            if ((roundedPage - _currentPage).abs() > 0.1) {
              if (mounted) {
                setState(() {
                  _currentPage = roundedPage;
                });
              }
            }
          }
        } catch (e) {
          // Web controller henüz hazır değilse mobil controller'ı kullan
        }
      }

      // Web controller yoksa veya sayfa alınamazsa mobil controller'ı kullan
      if (newPage == null && _tipsController.hasClients) {
        try {
          final mobilePage = _tipsController.page;
          if (mobilePage != null) {
            newPage = mobilePage;
            // Sayfa değiştiyse güncelle
            if ((mobilePage - _currentPage).abs() > 0.001) {
              if (mounted) {
                setState(() {
                  _currentPage = mobilePage;
                });
              }
            }
          }
        } catch (e) {
          // Mobil controller henüz hazır değilse varsayılan değer
        }
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

      try {
        if (_heroController.hasClients) {
          final double? currentPage = _heroController.page;
          if (currentPage != null) {
            final int current = currentPage.round();
            const int heroCount = 3; // hero görsellerinde 3 görsel var
            final int next = (current + 1) % heroCount;
            _heroController.animateToPage(
              next,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
            );
          }
        }
      } catch (e) {
        // Sessiz: hero otomatik kaydırma hatası
      }
    });

    // İpuçları kartlarını belirli aralıklarla otomatik kaydır
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;

      try {
        final locale =
            widget.languageProvider?.currentLocale ?? const Locale('tr');
        final int tipsCount =
            _getTipsData(locale).length; // tips listesindeki kart sayısı

        if (tipsCount == 0) return; // Kart yoksa işlem yapma

        // Controller'lardan gerçek sayfa değerlerini al (daha güvenilir)
        int? mobileCurrentPage;
        int? webCurrentPage;

        if (_tipsController.hasClients) {
          try {
            mobileCurrentPage = _tipsController.page?.round();
          } catch (e) {
            // Controller hazır değil
          }
        }

        if (_tipsControllerWeb != null && _tipsControllerWeb!.hasClients) {
          try {
            webCurrentPage = _tipsControllerWeb!.page?.round();
          } catch (e) {
            // Controller hazır değil
          }
        }

        // Fallback: _currentPage kullan (eğer controller'dan alınamazsa)
        final int fallbackPage = _currentPage.round();
        final int currentPage =
            webCurrentPage ?? mobileCurrentPage ?? fallbackPage;
        final int nextPage = (currentPage + 1) % tipsCount;

        // Mobil controller için
        if (_tipsController.hasClients && mobileCurrentPage != null) {
          try {
            // Sadece sayfa değişmemişse animasyon yap
            if (mobileCurrentPage == currentPage) {
              _tipsController.animateToPage(
                nextPage,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } catch (e) {
            // Controller hazır değil veya animasyon iptal
          }
        }

        // Web controller için (varsa)
        if (_tipsControllerWeb != null && _tipsControllerWeb!.hasClients) {
          try {
            // Controller'dan gerçek sayfa değerini al
            final double? webPage = _tipsControllerWeb!.page;
            final int actualWebPage =
                webPage?.round() ?? (webCurrentPage ?? fallbackPage);

            // Animasyon devam ediyor mu kontrol et (sayfa değeri tam sayı değilse animasyon devam ediyor)
            final bool isAnimating =
                webPage != null && (webPage - actualWebPage).abs() > 0.1;

            if (!isAnimating && actualWebPage == currentPage) {
              // Animasyon yok ve sayfa değişmemiş, yeni animasyon başlat
              _tipsControllerWeb!.animateToPage(
                nextPage,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubic, // Web için daha akıcı curve
              );
            }
          } catch (e) {
            // Controller henüz hazır değil
          }
        }
      } catch (e) {
        // Sessiz: ipuçları otomatik kaydırma
      }
    });

    // Hava durumu verilerini yükle
    _loadWeatherData();
    _loadAverageEmissions();

    // Shelly'yi başlat (IP ADRESİNİZİ BURAYA YAZIN!)
    _initializeShelly();
  }

  /// Shelly Plug S'yi başlat
  Future<void> _initializeShelly() async {
    // ⚠️ KENDİ IP ADRESİNİZİ YAZIN!
    _apiService.initializeShelly(
      deviceIp: '192.168.137.57', // 👈 Shelly cihazınızın IP adresi
      deviceId: _shellyDeviceId,
    );

    // Bağlantı kontrolü ve ilk veriyi çek
    try {
      // Bağlantı kontrolünü atla, direkt veri çekmeyi dene
      // (Bazı durumlarda checkConnection başarısız olabilir ama veri çekilebilir)
      try {
        await _apiService.getShellyData(saveToFirebase: true);
      } catch (dataError) {
        // Veri çekme başarısız, bağlantı kontrolü yap
        final connected = await _apiService.checkShellyConnection();
        if (!connected) {
          // Bilinçli olarak sessiz geçiyoruz: bağlantı kurulamazsa widget içi
          // fallback akışı veri çekmeyi sonraki döngülerde tekrar deniyor.
        } else {
          // Bağlantı var ama veri yoksa arka plan denemeleri devam eder.
        }
      }
    } catch (e) {
      // Hata olsa bile devam et (cihaz daha sonra bağlanabilir)
      // Sessiz: terminal gürültüsünü azaltmak için burada log basmıyoruz.
    }
  }

  /// Hava durumu verilerini yükle
  Future<void> _loadWeatherData() async {
    setState(() => _isLoadingWeather = true);

    try {
      // Sakarya için hava durumu verilerini çek
      final weather = await _weatherService.getWeatherData('Sakarya,TR');
      final forecast = await _weatherService.getWeatherForecast('Sakarya,TR');
      final aqi = await _weatherService.getAirQuality(
        'Sakarya',
        'Sakarya',
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

  /// Gerçek karbon emisyon ortalamalarını yükle (Our World in Data'dan)
  Future<void> _loadAverageEmissions() async {
    try {
      // Paralel olarak hem global hem ulusal ortalamaları çek
      final globalAvg = await _globalCarbonService.getGlobalAveragePerPerson();
      final nationalAvg = await _carbonDataService.getTurkeyAverage();

      if (mounted) {
        setState(() {
          _globalAverageKg = globalAvg;
          _nationalAverageKg = nationalAvg;
        });
      }
    } catch (e) {
      // Hata durumunda CarbonDataService'den sabit değerleri kullan
      if (mounted) {
        setState(() {
          _globalAverageKg = 4.1; // Dünya ortalaması (kg/gün)
          _nationalAverageKg = 6.8; // Türkiye ortalaması (kg/gün)
        });
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
    _tipsControllerWeb?.removeListener(_tipsListener);
    _tipsControllerWeb?.dispose();
    _heroController.dispose();
    super.dispose();
  }

  // Tips verilerini cache'le (locale değişmediği sürece yeniden oluşturma)
  List<Map<String, String>>? _cachedTipsData;
  Locale? _cachedLocale;

  List<Map<String, String>> _getTipsData(Locale locale) {
    if (_cachedTipsData != null && _cachedLocale == locale) {
      return _cachedTipsData!;
    }
    _cachedLocale = locale;
    _cachedTipsData = [
      {
        'title': translate('water_saving', locale),
        'summary': translate('water_saving_tip', locale),
        'details': translate('water_saving_details', locale),
      },
      {
        'title': translate('hvac', locale),
        'summary': translate('hvac_tip', locale),
        'details': translate('hvac_details', locale),
      },
      {
        'title': translate('logistics', locale),
        'summary': translate('logistics_tip', locale),
        'details': translate('logistics_details', locale),
      },
      {
        'title': translate('lighting', locale),
        'summary': translate('lighting_tip', locale),
        'details': translate('lighting_details', locale),
      },
      {
        'title': translate('waste_reduction', locale),
        'summary': translate('waste_reduction_tip', locale),
        'details': translate('waste_reduction_details', locale),
      },
      {
        'title': translate('transportation', locale),
        'summary': translate('transportation_tip', locale),
        'details': translate('transportation_details', locale),
      },
    ];
    return _cachedTipsData!;
  }

  /// Seçili duruma göre InfoFlipCard widget'ı oluştur
  Widget _buildTipCard(int index, bool isSelected, Locale locale) {
    final tipsData = _getTipsData(locale);
    if (index >= 0 && index < tipsData.length) {
      final data = tipsData[index];
      return InfoFlipCard(
        frontTitle: data['title']!,
        frontSummary: data['summary']!,
        backDetails: data['details']!,
        languageProvider: widget.languageProvider,
        isSelected: isSelected,
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _getTips(Locale locale) {
    final tipsData = _getTipsData(locale);
    return tipsData.map((data) {
      return InfoFlipCard(
        frontTitle: data['title']!,
        frontSummary: data['summary']!,
        backDetails: data['details']!,
        languageProvider: widget.languageProvider,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final textColor = Theme.of(context).colorScheme.onSurface;

    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final tips = _getTips(locale);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final TextStyle homeTitleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.white : Colors.black,
      height: 1.2,
    );
    final TextStyle homeSubStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      color: isDark ? Colors.white70 : Colors.black87,
      height: 1.35,
    );
    final double homeHorizontalPad =
        MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    return Scaffold(
      appBar: null,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // İçerik
            ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                homeHorizontalPad,
                16,
                homeHorizontalPad,
                16 +
                    MediaQuery.of(context).padding.bottom +
                    80, // Bottom nav bar için ekstra padding
              ),
              children: [
                // Hero Slider - Sadece görseller (geniş ekranda daha yüksek)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isWide = constraints.maxWidth > 600;
                    final double screenHeight =
                        MediaQuery.of(context).size.height;
                    final double mobileHeight =
                        (screenHeight * 0.25).clamp(180.0, 320.0);
                    final double wideHeightFromAspect =
                        constraints.maxWidth / (16 / 9);
                    final double heroHeight = isWide
                        ? wideHeightFromAspect.clamp(220.0, 740.0)
                        : mobileHeight;
                    return SizedBox(
                      height: heroHeight,
                      child: PageView.builder(
                        controller: _heroController,
                        itemCount: 3,
                        itemBuilder: (context, index) {
                          final images = [
                            'assets/images/herosectionafis.png',
                            'assets/images/herosectionafis2.png',
                            'assets/images/herosectionafis3.png',
                          ];
                          return Container(
                            margin: EdgeInsets.zero,
                            decoration: BoxDecoration(
                              borderRadius: isWide
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(12),
                              boxShadow: isWide
                                  ? null
                                  : [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: isWide
                                ? Image.asset(
                                    images[index],
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    alignment: Alignment.center,
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      images[index],
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      alignment: Alignment.center,
                                    ),
                                  ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: _kHomeSectionGap),
                // Ağaç bağışı bölümü için görsel ve CTA
                HeroDonateBanner(
                  imageAssetPath: 'assets/images/olive-drab_small.webp',
                  languageProvider: widget.languageProvider,
                ),
                const SizedBox(height: _kHomeSectionGap),
                // İşletme karşılaştırma tablosu
                Text(
                  translate('business_comparison_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                _BusinessComparisonTable(locale: locale, isDark: isDark),
                const SizedBox(height: _kHomeSectionGap),
                // Fatura tarama başlığı
                Text(
                  translate('bill_scanning_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                // Fatura tarama kartı
                BillScannerCard(
                  languageProvider: widget.languageProvider,
                  onCalculated: (value) =>
                      setState(() => _dailyEmissionKg = value),
                ),
                const SizedBox(height: _kHomeSectionGap),
                // GNÇ tarzında başlık
                Text(
                  translate('energy_tips_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isWide = constraints.maxWidth >= 900;
                    final double tipsCarouselHeight =
                        (MediaQuery.of(context).size.height * 0.26)
                            .clamp(230.0, 330.0);
                    if (isWide) {
                      // Geniş ekran: horizontal slider, tek satırda kaydırılabilir
                      _tipsControllerWeb ??=
                          PageController(viewportFraction: 1.0)
                            ..addListener(_tipsListener);
                      return Column(
                        children: [
                          SizedBox(
                            height: tipsCarouselHeight,
                            child: PageView.builder(
                              controller: _tipsControllerWeb,
                              allowImplicitScrolling:
                                  false, // Web'de daha güvenilir
                              physics:
                                  const PageScrollPhysics(), // Web için daha akıcı
                              scrollDirection: Axis.horizontal,
                              itemCount: tips.length,
                              padEnds:
                                  true, // Son sayfada da kaydırma için padding
                              clipBehavior: Clip.none,
                              onPageChanged: (index) {
                                if (mounted) {
                                  setState(() {
                                    _currentPage = index.toDouble();
                                  });
                                }
                              },
                              itemBuilder: (context, index) {
                                // Yuvarlanmış sayfa değerini kullan (daha güvenilir)
                                final roundedPage = _currentPage.round();
                                final isSelected = roundedPage ==
                                    index; // Yuvarlanmış değerle karşılaştır
                                final scale = isSelected ? 1.0 : 0.85;
                                final opacity = isSelected ? 1.0 : 0.5;
                                final height = isSelected
                                    ? tipsCarouselHeight
                                    : (tipsCarouselHeight * 0.88);

                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  height: height,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: isSelected ? 0 : 6,
                                    vertical: isSelected ? 0 : 15,
                                  ),
                                  decoration: isSelected
                                      ? BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        )
                                      : null,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 250),
                                    opacity: opacity,
                                    child: AnimatedScale(
                                      duration:
                                          const Duration(milliseconds: 250),
                                      curve: Curves.easeOutCubic,
                                      scale: scale,
                                      child: Padding(
                                        padding: EdgeInsets.zero,
                                        child: ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                            sigmaX: isSelected ? 0 : 1.2,
                                            sigmaY: isSelected ? 0 : 1.2,
                                          ),
                                          child: _buildTipCard(
                                              index, isSelected, locale),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Üç nokta indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(tips.length, (i) {
                              final selected = (_currentPage.round() == i);
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                width: selected ? 12 : 8,
                                height: selected ? 12 : 8,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    }
                    // Mobil/tablet: mevcut PageView
                    return Column(
                      children: [
                        SizedBox(
                          height: tipsCarouselHeight,
                          child: PageView.builder(
                            controller: _tipsController,
                            allowImplicitScrolling: true,
                            physics: const PageScrollPhysics(),
                            itemCount: tips.length,
                            padEnds: false,
                            clipBehavior: Clip.none,
                            onPageChanged: (index) {
                              if (mounted) {
                                setState(() {
                                  _currentPage = index.toDouble();
                                });
                              }
                            },
                            itemBuilder: (context, index) {
                              // Yuvarlanmış sayfa değerini kullan (daha güvenilir)
                              final roundedPage = _currentPage.round();
                              final isSelected = roundedPage ==
                                  index; // Yuvarlanmış değerle karşılaştır
                              final scale = isSelected ? 1.0 : 0.85;
                              final opacity = isSelected ? 1.0 : 0.5;
                              final height = isSelected
                                  ? tipsCarouselHeight
                                  : (tipsCarouselHeight * 0.85);

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: height,
                                decoration: isSelected
                                    ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                      )
                                    : null,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 150),
                                  opacity: opacity,
                                  child: AnimatedScale(
                                    duration: const Duration(milliseconds: 150),
                                    scale: scale,
                                    child: ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                        sigmaX: isSelected ? 0 : 1.2,
                                        sigmaY: isSelected ? 0 : 1.2,
                                      ),
                                      child: _buildTipCard(
                                          index, isSelected, locale),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Üç nokta indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(tips.length, (i) {
                            final selected = (_currentPage.round() == i);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: selected ? 12 : 8,
                              height: selected ? 12 : 8,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
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
                const SizedBox(height: _kHomeSectionGap),
                // Hava durumu bölümü başlığı ve şehir adı - Konteynır dışında
                Text(
                  translate('weather_energy_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: 10),
                Text(
                  _currentWeather != null && _currentWeather!['city'] != null
                      ? _currentWeather!['city']
                      : 'Sakarya',
                  style: homeSubStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                // Hava durumu bölümü - Konteynır
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
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
                                  ).colorScheme.primary.withValues(alpha: 0.2),
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                ],
                              ),
                        color:
                            isDark ? Colors.black.withValues(alpha: 0.4) : null,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              (Theme.of(context).brightness == Brightness.dark)
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.primary,
                          width: isDark ? 1 : 2,
                        ),
                      ),
                      child: Padding(
                        padding: _kHomeCardPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hava durumu kartları
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final double screenWidth = constraints.maxWidth;
                                final double cardHeight =
                                    screenWidth > 600 ? 160 : 140;
                                final double cardWidth =
                                    screenWidth > 600 ? 180 : 160;

                                // Gerçek hava durumu verilerini kullan veya placeholder
                                final List<Map<String, dynamic>> weatherCards;
                                if (_weatherForecast != null &&
                                    _weatherForecast!.isNotEmpty) {
                                  weatherCards = [
                                    {
                                      'title': translate('today', locale),
                                      'temp':
                                          '${_currentWeather?['temperature']?.toStringAsFixed(0) ?? 24}°C',
                                      'condition': _localizeWeatherCondition(
                                        _currentWeather?['condition'],
                                        locale,
                                      ),
                                      'icon': _getWeatherIcon(
                                        _currentWeather?['icon'] ?? '01d',
                                      ),
                                      'tip': _getWeatherTip(
                                        _currentWeather?['condition'] ??
                                            'Clear',
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
                                        'condition': _weatherForecast![0]
                                                    ['condition'] !=
                                                null
                                            ? _localizeWeatherCondition(
                                                _weatherForecast![0]
                                                    ['condition'] as String?,
                                                locale,
                                              )
                                            : translate('cloudy', locale),
                                        'icon': _getWeatherIcon(
                                          _weatherForecast![0]['icon'] ?? '02d',
                                        ),
                                        'tip': _getWeatherTip(
                                          _weatherForecast![0]['condition'] ??
                                              'Clouds',
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
                                        'condition': _weatherForecast![1]
                                                    ['condition'] !=
                                                null
                                            ? _localizeWeatherCondition(
                                                _weatherForecast![1]
                                                    ['condition'] as String?,
                                                locale,
                                              )
                                            : translate('mixed', locale),
                                        'icon': _getWeatherIcon(
                                          _weatherForecast![1]['icon'] ?? '03d',
                                        ),
                                        'tip': _getWeatherTip(
                                          _weatherForecast![1]['condition'] ??
                                              'Clouds',
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
                                      'tip': translate(
                                          'natural_light_decrease', locale),
                                      'color': Colors.blue,
                                    },
                                    {
                                      'title': translate('week', locale),
                                      'temp': '22°C',
                                      'condition': translate('mixed', locale),
                                      'icon': Icons.wb_cloudy,
                                      'tip': translate(
                                          'hvac_usage_increase', locale),
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
                                        margin:
                                            const EdgeInsets.only(right: 12),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 25, sigmaY: 25),
                                            child: Container(
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
                                                  color: (Theme.of(context)
                                                              .brightness ==
                                                          Brightness.dark)
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                  width: isDark ? 1 : 2,
                                                ),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              card['icon']
                                                                  as IconData,
                                                              color:
                                                                  card['color']
                                                                      as Color,
                                                              size: 20,
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            Expanded(
                                                              child: Text(
                                                                card['title']
                                                                    as String,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleSmall
                                                                    ?.copyWith(
                                                                      color: isDark
                                                                          ? Colors
                                                                              .white
                                                                          : Colors
                                                                              .black,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Text(
                                                          card['temp']
                                                              as String,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .headlineSmall
                                                                  ?.copyWith(
                                                                    color: isDark
                                                                        ? Colors
                                                                            .white
                                                                        : Colors
                                                                            .black,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                        ),
                                                        Text(
                                                          card['condition']
                                                              as String,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    color: isDark
                                                                        ? Colors.white.withValues(
                                                                            alpha:
                                                                                0.8)
                                                                        : Colors
                                                                            .black
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
                                                            color: card['color']
                                                                as Color,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: _kHomeSectionGap),
                // Gerçek zamanlı iklim verileri
                Text(
                  translate('climate_realtime_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
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
                                  ).colorScheme.primary.withValues(alpha: 0.2),
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                ],
                              ),
                        color:
                            isDark ? Colors.black.withValues(alpha: 0.4) : null,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              (Theme.of(context).brightness == Brightness.dark)
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.primary,
                          width: isDark ? 1 : 2,
                        ),
                      ),
                      child: Padding(
                        padding: _kHomeCardPadding,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Şehir bilgisi - daha belirgin
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.tealAccent
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                              Icons.location_city,
                                              color: Colors.tealAccent,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                translate('city', locale),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: isDark
                                                          ? Colors.white
                                                              .withValues(
                                                                  alpha: 0.7)
                                                          : Colors.black,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Sakarya',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.refresh,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                        onPressed: _loadWeatherData,
                                        tooltip: translate('refresh', locale),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.1),
                                          padding: const EdgeInsets.all(8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // İklim verileri - grid düzeni
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final bool isWide =
                                          constraints.maxWidth > 600;
                                      if (isWide) {
                                        // Geniş ekran: 3 sütunlu grid
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: _ClimateInfoCard(
                                                icon: Icons.thermostat,
                                                iconColor: Colors.orangeAccent,
                                                label: translate(
                                                    'temperature', locale),
                                                value: _currentWeather != null
                                                    ? '${_currentWeather!['temperature']?.toStringAsFixed(0) ?? 24}°C'
                                                    : '24°C',
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _ClimateInfoCard(
                                                icon: Icons.air,
                                                iconColor: Colors.blueAccent,
                                                label: translate('aqi', locale),
                                                value: _airQuality != null
                                                    ? '${_airQuality!['aqi'] ?? 78} (${_localizeAqiText(_airQuality!['aqiText'] as String?, locale)})'
                                                    : '78 (${translate('aqi_moderate', locale)})',
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _ClimateInfoCard(
                                                icon: Icons.eco,
                                                iconColor: Colors.greenAccent,
                                                label: translate(
                                                    'carbon_intensity', locale),
                                                value: _carbonIntensity != null
                                                    ? '${_carbonIntensity!.toStringAsFixed(0)} gCO₂/kWh'
                                                    : '420 gCO₂/kWh',
                                              ),
                                            ),
                                          ],
                                        );
                                      } else {
                                        // Mobil: dikey düzen
                                        return Column(
                                          children: [
                                            _ClimateInfoCard(
                                              icon: Icons.thermostat,
                                              iconColor: Colors.orangeAccent,
                                              label: translate(
                                                  'temperature', locale),
                                              value: _currentWeather != null
                                                  ? '${_currentWeather!['temperature']?.toStringAsFixed(0) ?? 24}°C'
                                                  : '24°C',
                                            ),
                                            const SizedBox(height: 12),
                                            _ClimateInfoCard(
                                              icon: Icons.air,
                                              iconColor: Colors.blueAccent,
                                              label: translate('aqi', locale),
                                              value: _airQuality != null
                                                  ? '${_airQuality!['aqi'] ?? 78} (${_localizeAqiText(_airQuality!['aqiText'] as String?, locale)})'
                                                  : '78 (${translate('aqi_moderate', locale)})',
                                            ),
                                            const SizedBox(height: 12),
                                            _ClimateInfoCard(
                                              icon: Icons.eco,
                                              iconColor: Colors.greenAccent,
                                              label: translate(
                                                  'carbon_intensity', locale),
                                              value: _carbonIntensity != null
                                                  ? '${_carbonIntensity!.toStringAsFixed(0)} gCO₂/kWh'
                                                  : '420 gCO₂/kWh',
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
                const SizedBox(height: _kHomeSectionGap),
                // Emisyon farkındalık / karşılaştırma (placeholder hesap)
                Text(
                  translate('emission_awareness_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                _EmissionComparisonCard(
                  userDailyEmissionKg: _dailyEmissionKg ?? 12.0,
                  nationalAvgKg: _nationalAverageKg ?? 6.8,
                  globalAvgKg: _globalAverageKg ?? 4.1,
                  locale: locale,
                ),
                const SizedBox(height: _kHomeSectionGap),
                // Eşdeğer görselleştirme
                Text(
                  translate('impact_equivalents_title', locale),
                  style: homeTitleStyle,
                ),
                const SizedBox(height: _kHomeTitleBelowGap),
                _EquivalentsCard(
                  dailyEmissionKg: _dailyEmissionKg ?? 12.0,
                  locale: locale,
                ),
                // Eski alıntı görsel bloğu kaldırıldı (yukarıda blur olarak gösteriliyor)
              ],
            ),
          ],
        ),
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

  String _localizeWeatherCondition(String? condition, Locale locale) {
    if (condition == null || condition.isEmpty) {
      return translate('sunny', locale);
    }
    final value = condition.toLowerCase();
    if (value.contains('clear') || value.contains('açık')) {
      return translate('sunny', locale);
    }
    if (value.contains('cloud') || value.contains('bulut')) {
      return translate('cloudy', locale);
    }
    if (value.contains('rain') || value.contains('yağmur')) {
      return translate('cloudy', locale);
    }
    if (value.contains('snow') || value.contains('kar')) {
      return translate('mixed', locale);
    }
    return condition;
  }

  String _localizeAqiText(String? aqiText, Locale locale) {
    if (aqiText == null || aqiText.isEmpty) {
      return translate('aqi_moderate', locale);
    }
    final value = aqiText.toLowerCase();
    if (value.contains('iyi') || value.contains('good')) {
      return translate('aqi_good', locale);
    }
    if (value.contains('orta') || value == 'moderate') {
      return translate('aqi_moderate', locale);
    }
    if (value.contains('hassas') || value.contains('sensitive')) {
      return translate('aqi_unhealthy_sensitive', locale);
    }
    if (value.contains('çok sağlıksız') || value.contains('very unhealthy')) {
      return translate('aqi_very_unhealthy', locale);
    }
    if (value.contains('sağlıksız') || value == 'unhealthy') {
      return translate('aqi_unhealthy', locale);
    }
    if (value.contains('tehlikeli') || value.contains('hazardous')) {
      return translate('aqi_hazardous', locale);
    }
    return aqiText;
  }
}

// İklim bilgisi kartı - daha kullanıcı dostu
class _ClimateInfoCard extends StatelessWidget {
  const _ClimateInfoCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
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
            gradient: isDark
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
                  ),
            color: isDark ? Colors.black.withValues(alpha: 0.4) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary,
              width: isDark ? 1 : 2,
            ),
          ),
          child: Padding(
            padding: _kHomeCardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // İklim verileri gibi grid düzeni
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isWide = constraints.maxWidth > 600;
                    if (isWide) {
                      // Geniş ekran: 3 sütunlu grid
                      return Row(
                        children: [
                          Expanded(
                            child: _ClimateInfoCard(
                              icon: Icons.person,
                              iconColor: Colors.blueAccent,
                              label: translate('you', locale),
                              value:
                                  '${userDailyEmissionKg.toStringAsFixed(1)} ${translate('kg_per_day', locale)}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ClimateInfoCard(
                              icon: Icons.flag,
                              iconColor: Colors.orangeAccent,
                              label: translate('national_avg', locale),
                              value:
                                  '${nationalAvgKg.toStringAsFixed(1)} ${translate('kg_per_day', locale)}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ClimateInfoCard(
                              icon: Icons.public,
                              iconColor: Colors.greenAccent,
                              label: translate('global_avg', locale),
                              value:
                                  '${globalAvgKg.toStringAsFixed(1)} ${translate('kg_per_day', locale)}',
                            ),
                          ),
                        ],
                      );
                    } else {
                      // Mobil: dikey düzen
                      return Column(
                        children: [
                          _ClimateInfoCard(
                            icon: Icons.person,
                            iconColor: Colors.blueAccent,
                            label: translate('you', locale),
                            value:
                                '${userDailyEmissionKg.toStringAsFixed(1)} ${translate('kg_per_day', locale)}',
                          ),
                          const SizedBox(height: 12),
                          _ClimateInfoCard(
                            icon: Icons.flag,
                            iconColor: Colors.orangeAccent,
                            label: translate('national_avg', locale),
                            value:
                                '${nationalAvgKg.toStringAsFixed(1)} ${translate('kg_per_day', locale)}',
                          ),
                          const SizedBox(height: 12),
                          _ClimateInfoCard(
                            icon: Icons.public,
                            iconColor: Colors.greenAccent,
                            label: translate('global_avg', locale),
                            value:
                                '${globalAvgKg.toStringAsFixed(1)} ${translate('kg_per_day', locale)}',
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  isLower
                      ? '${translate('your_emission_is', locale)} $percentText ${translate('below_world_avg', locale)}'
                      : '${translate('your_emission_is', locale)} $percentText ${translate('above_world_avg', locale)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white : Colors.black,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // Basit dönüşüm katsayıları (yaklaşık)
    const double carKgPerKm = 0.120; // kg CO2e / km (binek araç)
    const double flightKgPerKm = 0.255; // kg CO2e / km (uçak, kişi başı)
    const double treeKgPerYear = 21.0; // 1 ağaç yıllık CO2 tutumu
    const double treeKgPerDay = treeKgPerYear / 365.0;

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
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
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
                            color: isDark ? Colors.white : Colors.black,
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
                      color: isDark ? Colors.white : Colors.black,
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
            gradient: isDark
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
                  ),
            color: isDark ? Colors.black.withValues(alpha: 0.4) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary,
              width: isDark ? 1 : 2,
            ),
          ),
          child: Padding(
            padding: _kHomeCardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  gradient: isDark
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
                        ),
                  color: isDark ? Colors.black.withValues(alpha: 0.3) : null,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (Theme.of(context).brightness == Brightness.dark)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primary,
                    width: isDark ? 1 : 2,
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              translate('business_name', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('monthly_emission', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('industry_avg', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Durum',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: isDark ? Colors.white24 : Colors.black26),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.8)
                                            : Colors.black
                                                .withValues(alpha: 0.8),
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
                  gradient: isDark
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
                        ),
                  color: isDark ? Colors.black.withValues(alpha: 0.3) : null,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (Theme.of(context).brightness == Brightness.dark)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primary,
                    width: isDark ? 1 : 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Tablo başlıkları
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              '#',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              translate('business_name', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('monthly_emission', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              translate('industry_avg', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Durum',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(color: isDark ? Colors.white24 : Colors.black26),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.8)
                                            : Colors.black
                                                .withValues(alpha: 0.8),
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
