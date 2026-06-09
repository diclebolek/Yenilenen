import 'dart:async';
import 'dart:developer' show log;
import 'dart:typed_data' show ByteData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:ui' show ImageFilter;
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/consumption_form.dart';
import '../widgets/realtime_esp_data_widget.dart';
import '../widgets/realtime_shelly_data_widget.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../services/api_service.dart';
import '../services/global_carbon_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/live_emission_service.dart';
import '../models/consumption_entry.dart';
import '../models/shelly_data.dart';
import '../algorithms/calculation.dart';
import '../widgets/theme_independent_info_dialog.dart';

/// Kart içi metin ve grafik alanı — tüm panellerde aynı.
const EdgeInsets _kReportsCardInnerPadding = EdgeInsets.all(16);

/// Ana bölüm sarmalayıcıları — yatay boşluk [ListView] padding ile verilir (taşmayı önler).
const EdgeInsets _kReportsSectionOuterPadding =
    EdgeInsets.symmetric(vertical: 8);

/// Kartlar arası dikey aralık.
const double _kReportsSectionGap = 20;

/// Hedefler tahmini ile senkron (E/M toggle).
const String _kPrefsReportsUseEspData = 'prefs_reports_use_esp_data';

/// Shelly `energyKwh` alanı **kümülatif** sayaçtır; her kayıt için bir önceki örneğe
/// göre tüketilen kWh (delta) ile [ConsumptionEntry] üretir — günlük emisyon için.
/// Raporlar ekranı ile aynı: Shelly kümülatif sayaç → ardışık fark (kg CO₂e hesabı için).
List<ConsumptionEntry> _shellyDataListToDeltaConsumptionEntries(
  List<ShellyData> raw,
) =>
    ApiService().shellyDataListToDeltaConsumptionEntries(raw);

/// Asset'teki “.ttf” dosyası gerçekten sfnt/OpenType başlığı taşıyor mu (HTML/404 yerine).
/// Aksi halde [pw.Font.ttf] veya sonradan glif üretimi `FormatException` (UTF-8) fırlatabilir.
bool _byteDataLooksLikeSfntFont(ByteData data) {
  final n = data.lengthInBytes;
  if (n < 12) return false;
  final a = data.getUint8(0);
  final b = data.getUint8(1);
  final c = data.getUint8(2);
  final d = data.getUint8(3);
  // TrueType / OpenType glyf
  if (a == 0x00 && b == 0x01 && c == 0x00 && d == 0x00) return true;
  // TrueType 2.0
  if (a == 0x00 && b == 0x00 && c == 0x01 && d == 0x00) return true;
  // OpenType CFF: "OTTO"
  if (a == 0x4f && b == 0x54 && c == 0x54 && d == 0x4f) return true;
  // TrueType collection: "ttcf"
  if (a == 0x74 && b == 0x74 && c == 0x63 && d == 0x66) return true;
  return false;
}

/// Gösterge içi punto (beyaz daire üzerinde koyu metin; rapor tipografisinden ayrı).
const double _kGaugeCenterValueSize = 18;
const double _kGaugeCenterValueSizeMobile = 22;
const double _kGaugeCenterAuxSize = 12;
const double _kGaugeCenterAuxSizeMobile = 12;
const double _kGaugeToggleLabelSize = 16;
const double _kGaugeToggleLabelSizeMobile = 13;
const double _kGaugeToggleScaleWide = 1.15;
const double _kGaugeToggleScaleMobile = 0.72;
const double _kGaugeToggleRowHeight = 48;
const double _kGaugeToggleRowHeightMobile = 32;
const double _kGaugeToggleSpacingMobile = 8;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.languageProvider});

  final LanguageProvider? languageProvider;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _InputMode { none, manual, raspberry }

class _ReportsScreenState extends State<ReportsScreen> {
  // Terminal gürültüsünü azaltmak için ekran içi debug logları kapalı tutuyoruz.
  void debugPrint(String? message, {int? wrapWidth}) {}

  /// PDF metinleri için (null = uygulama dili).
  Locale? _pdfExportLocaleOverride;
  pw.ThemeData? _cachedPdfUnicodeTheme;

  Locale _localeForPdfExport() =>
      _pdfExportLocaleOverride ??
      widget.languageProvider?.currentLocale ??
      const Locale('tr');

  /// SegmentedButton seçimi: override yoksa geçerli uygulama diline göre 'tr' | 'en'.
  String _pdfExportLocaleSegmentSelection() {
    if (_pdfExportLocaleOverride != null) {
      return _pdfExportLocaleOverride!.languageCode == 'tr' ? 'tr' : 'en';
    }
    final code = widget.languageProvider?.currentLocale.languageCode ?? 'tr';
    return code == 'tr' ? 'tr' : 'en';
  }

  Future<pw.ThemeData?> _tryPdfThemeFromAssets(
    String regularAsset,
    String boldAsset,
  ) async {
    try {
      final regularData = await rootBundle.load(regularAsset);
      final boldData = await rootBundle.load(boldAsset);
      if (!_byteDataLooksLikeSfntFont(regularData) ||
          !_byteDataLooksLikeSfntFont(boldData)) {
        return null;
      }
      final regular = pw.Font.ttf(regularData);
      final bold = pw.Font.ttf(boldData);
      return pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      );
    } catch (_) {
      return null;
    }
  }

  /// Türkçe için TTF. Repoda Noto dosyaları bazen HTML placeholder olabiliyor; önce geçerli
  /// OpenSans denenir. Hiçbiri yüklenmezse yerleşik Helvetica (Türkçe glif eksik olabilir).
  Future<pw.ThemeData> _pdfUnicodeTheme() async {
    if (_cachedPdfUnicodeTheme != null) return _cachedPdfUnicodeTheme!;

    const candidates = <List<String>>[
      ['fonts/OpenSans-Regular.ttf', 'fonts/OpenSans-Bold.ttf'],
      ['assets/fonts/OpenSans-Regular.ttf', 'assets/fonts/OpenSans-Bold.ttf'],
      ['fonts/NotoSans-Regular.ttf', 'fonts/NotoSans-Bold.ttf'],
      ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf'],
    ];

    for (final paths in candidates) {
      final theme = await _tryPdfThemeFromAssets(paths[0], paths[1]);
      if (theme != null) {
        _cachedPdfUnicodeTheme = theme;
        return theme;
      }
    }

    _cachedPdfUnicodeTheme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );
    return _cachedPdfUnicodeTheme!;
  }

  ButtonStyle _pdfLangSegmentedStyle(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      foregroundColor: WidgetStateProperty.all<Color>(accent),
      iconColor: WidgetStateProperty.all<Color>(accent),
      backgroundColor:
          WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withValues(alpha: 0.22);
        }
        return accent.withValues(alpha: 0.08);
      }),
      side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        final double a = states.contains(WidgetState.selected) ? 0.55 : 0.35;
        return BorderSide(color: accent.withValues(alpha: a));
      }),
    );
  }

  double? _lastCalculatedKgCo2e;
  double? _manualCalculatedKgCo2e; // Manuel hesaplama sonucu
  ConsumptionEntry?
      _manualEntry; // Manuel giriş verisi (kategori dağılımı için)
  ConsumptionEntry? _espEntry; // ESP ham verisi (su+gaz için)
  ConsumptionEntry? _shellyEntry; // Shelly ham verisi (elektrik için)
  bool _useEspData =
      true; // Varsayılan E (ESP/Shelly); Gauge ve pasta bu moda göre
  _InputMode _selectedMode = _InputMode.none;
  final FirebaseRealtimeService _firebaseService =
      FirebaseRealtimeService.instance;
  List<double> _dailyEmissions = [
    0,
    0,
    0,
    0,
    0,
    0,
    0
  ]; // Son 7 gün (ESP verileri)
  List<double> _manualDailyEmissions = [
    0,
    0,
    0,
    0,
    0,
    0,
    0
  ]; // Son 7 gün (Manuel veriler)
  Map<String, double> _categoryDistribution = {
    'electricity': 0.0,
    'gas': 0.0,
    'water': 0.0,
    'waste': 0.0,
  };
  String? _selectedLegendCategory;
  bool _isLoadingTrends = false;
  StreamSubscription<ConsumptionEntry?>? _espDataSubscription;
  StreamSubscription<ShellyData?>? _shellyDataSubscription;
  final ApiService _apiService = ApiService();
  final String _shellyDeviceId = 'shelly_plug_001';

  /// Shelly sayacı kümülatif; emisyon için oturum içi tüketilen kWh (delta toplamı)
  double _shellySessionKwhConsumed = 0;
  double? _shellyPrevMeterKwh;
  DateTime? _shellyConsumptionDayStart;
  final GlobalCarbonService _globalCarbonService = GlobalCarbonService();
  bool _showGlobalTrend = false; // Kişisel mi dünya geneli mi?
  List<double> _globalDailyTrends = [0, 0, 0, 0, 0, 0, 0];

  /// -1: gelecek hafta (yalnızca tahmini çizgi), 0: bu hafta, 1+: geçmiş haftalar
  int _weekOffset = 0;
  // Ülke verileri - karşılaştırma için
  Map<String, List<double>> _countryTrends = {};
  // Her ülke için veri kaynağını takip et (true = gerçek veri, false = placeholder)
  Map<String, bool> _countryDataSources = {};
  final bool _showCountryComparison =
      true; // Ülke karşılaştırması gösterilsin mi?

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getBool(_kPrefsReportsUseEspData);
      if (saved != null && mounted) {
        setState(() => _useEspData = saved);
      }
    });
    _loadTrendData();
    _loadGlobalTrendData();
    // Ülke verilerini yükle - öncelikli olarak
    _loadCountryTrends().then((_) {
      debugPrint(
          'Ülke verileri yükleme tamamlandı: ${_countryTrends.length} ülke');
    });
    // ESP verilerini real-time dinle ve otomatik güncelle
    _listenToEspData();
    _loadInitialEspDataFromFirebase();
    // Shelly'yi başlat
    _initializeShelly();
    // Shelly verilerini real-time dinle ve otomatik güncelle
    _listenToShellyData();
  }

  /// Ülke verilerini yükle (karşılaştırma için)
  Future<void> _loadCountryTrends() async {
    try {
      // Popüler ülkelerin verilerini yükle
      final countries = {
        'Türkiye': 'TUR',
        'ABD': 'USA',
        'Çin': 'CHN',
        'Almanya': 'DEU',
        'Fransa': 'FRA',
        'İngiltere': 'GBR',
      };

      // Önce tüm ülkeler için placeholder veriler yükle (hızlı görünürlük için)
      final Map<String, List<double>> trends = {};
      final Map<String, bool> dataSources = {};
      for (var entry in countries.entries) {
        trends[entry.key] = _getPlaceholderCountryData(entry.key);
        dataSources[entry.key] = false; // Başlangıçta placeholder
      }

      // State'i güncelle - placeholder verilerle başla
      if (mounted) {
        setState(() {
          _countryTrends = trends;
          _countryDataSources = dataSources;
        });
        debugPrint('Placeholder veriler yüklendi: ${trends.length} ülke');
      }
      // Şimdi API'den gerçek verileri yüklemeyi dene
      for (var entry in countries.entries) {
        try {
          debugPrint('🔄 ${entry.key} (${entry.value}) verisi yükleniyor...');
          final trend = await _globalCarbonService
              .getCountryDailyTrend(entry.value)
              .timeout(const Duration(seconds: 10));

          // Veri başarıyla yüklendiyse ve geçerli değerlere sahipse kullan
          // Tüm değerlerin 0'dan büyük olması ve ortalama değerin mantıklı olması gerekiyor
          final avgValue = trend.isNotEmpty
              ? (trend.reduce((a, b) => a + b) / trend.length)
              : 0.0;
          final hasValidData = trend.isNotEmpty &&
              trend.any((e) => e > 0.1) &&
              avgValue > 0.5 && // Ortalama en az 0.5 kg/gün olmalı
              avgValue <
                  50.0; // Ortalama en fazla 50 kg/gün olmalı (makul üst sınır)

          // Placeholder verilerle karşılaştır - eğer çok benziyorsa muhtemelen placeholder
          final placeholderData = _getPlaceholderCountryData(entry.key);
          final placeholderAvg =
              placeholderData.reduce((a, b) => a + b) / placeholderData.length;
          final isLikelyPlaceholder = (avgValue - placeholderAvg).abs() <
              0.1; // Ortalama değerler çok yakınsa

          if (hasValidData && !isLikelyPlaceholder) {
            trends[entry.key] = trend;
            dataSources[entry.key] = true; // Gerçek veri
            debugPrint(
                '✅ ${entry.key} GERÇEK VERİ API\'den yüklendi: ilk=${trend.first.toStringAsFixed(2)}, ortalama=${avgValue.toStringAsFixed(2)}, son=${trend.last.toStringAsFixed(2)}');
          } else {
            // Veri boş, 0, çok küçük veya placeholder gibi görünüyorsa placeholder kullan (zaten yüklü)
            debugPrint(
                '⚠️ ${entry.key} PLACEHOLDER VERİ kullanılıyor (API verisi geçersiz veya placeholder benzeri: ilk=${trend.isNotEmpty ? trend.first.toStringAsFixed(2) : "yok"}, ortalama=${avgValue.toStringAsFixed(2)}, geçerli=$hasValidData, placeholder benzeri=$isLikelyPlaceholder)');
          }
        } catch (e) {
          // Hata durumunda placeholder veri kullan (zaten yüklü)
          debugPrint(
              '⚠️ ${entry.key} PLACEHOLDER VERİ kullanılıyor (hata: $e)');
        }
      }

      // State'i güncelle - gerçek verilerle güncelle
      if (mounted) {
        setState(() {
          _countryTrends = trends;
          _countryDataSources = dataSources;
        });
        debugPrint('Yüklenen ülke sayısı: ${trends.length}');
        trends.forEach((country, data) {
          final isReal = dataSources[country] ?? false;
          debugPrint(
              '$country: ${data.length} veri noktası, ortalama: ${data.isNotEmpty ? (data.reduce((a, b) => a + b) / data.length).toStringAsFixed(2) : "0"}, kaynak: ${isReal ? "GERÇEK" : "PLACEHOLDER"}');
        });
      }
    } catch (e) {
      debugPrint('Ülke verileri yükleme hatası: $e');
    }
  }

  /// Ülke için placeholder veri oluştur (hata durumunda kullanılır)
  List<double> _getPlaceholderCountryData(String countryName) {
    // Ülkelere göre farklı ortalama kişi başı günlük CO2 emisyonları (kg/gün)
    final countryAverages = {
      'Türkiye': 4.2,
      'ABD': 15.5,
      'Çin': 7.4,
      'Almanya': 8.9,
      'Fransa': 8.0,
      'İngiltere': 7.8,
    };

    final avgDaily = countryAverages[countryName] ?? 4.5;

    // Son 7 gün için hafif değişkenlik gösteren trend
    return [
      avgDaily * 0.98,
      avgDaily * 0.99,
      avgDaily * 1.0,
      avgDaily * 1.01,
      avgDaily * 0.99,
      avgDaily * 1.02,
      avgDaily * 1.0,
    ];
  }

  /// Dünya geneli trend verilerini yükle
  Future<void> _loadGlobalTrendData() async {
    try {
      final globalTrends = await _globalCarbonService.getGlobalDailyTrend();
      if (mounted) {
        setState(() {
          _globalDailyTrends = globalTrends;
        });
      }
    } catch (e) {
      debugPrint('Dünya geneli trend yükleme hatası: $e');
    }
  }

  /// Ülke çizgilerini oluştur (grafik için)
  List<LineChartBarData> _buildCountryLines(
      List<double> userData, double maxY) {
    if (_countryTrends.isEmpty) {
      debugPrint('_buildCountryLines: _countryTrends boş!');
      return [];
    }

    debugPrint('_buildCountryLines: ${_countryTrends.length} ülke verisi var');

    // Ülke renkleri
    final countryColors = {
      'Türkiye': Colors.blue,
      'ABD': Colors.red,
      'Çin': Colors.orange,
      'Almanya': Colors.yellow,
      'Fransa': Colors.purple,
      'İngiltere': Colors.teal,
    };

    final List<LineChartBarData> countryLines = [];

    // Kullanıcı verilerinin ortalama ve max değerlerini hesapla (normalizasyon için)
    final userMax =
        userData.isNotEmpty ? userData.reduce((a, b) => a > b ? a : b) : 0.0;
    final userAvg = userData.isNotEmpty
        ? userData.reduce((a, b) => a + b) / userData.length
        : 0.0;

    // Ülke verilerinin max değerini hesapla
    final countryMax = _countryTrends.values
        .expand((e) => e)
        .fold(0.0, (a, b) => a > b ? a : b);

    // Normalizasyon faktörü: Kullanıcı verileriyle ülke verilerini karşılaştırılabilir hale getir
    // Eğer kullanıcı verileri çok yüksekse, ülke verilerini ölçeklendir
    // Ülke verileri kişi başı günlük değerler (4-15 kg), kullanıcı verileri toplam değerler olabilir
    // Ülke verilerini kullanıcı verilerinin görünür bir aralığına ölçeklendir
    double scaleFactor = 1.0;
    if (userMax > 0 && countryMax > 0 && userMax > countryMax * 20) {
      // Kullanıcı verileri çok yüksekse, ülke verilerini kullanıcı max'inin %10-20'si aralığına ölçeklendir
      final targetMax = userMax * 0.15; // Kullanıcı max'inin %15'i
      scaleFactor = targetMax / countryMax;
      debugPrint(
          '📊 Ölçeklendirme uygulanıyor: targetMax=$targetMax, scaleFactor=$scaleFactor');
    } else {
      debugPrint(
          '📊 Ölçeklendirme gerekmiyor: userMax=$userMax, countryMax=$countryMax');
    }

    debugPrint(
        '📊 Normalizasyon: userMax=$userMax, userAvg=$userAvg, countryMax=$countryMax, scaleFactor=$scaleFactor');

    // Her ülke için farklı bir yükseklik offset'i belirle (çizgilerin üst üste binmemesi için)
    // maxY'ye göre offset hesapla - böylece çizgiler daha iyi ayrılır
    // Offset'ler maxY'nin %8'i kadar base offset ile hesaplanıyor
    final baseOffset = maxY * 0.08; // maxY'nin %8'i kadar base offset
    final countryOffsets = {
      'Türkiye': 0.0,
      'ABD': baseOffset * 1.0, // maxY'nin %8'i kadar yukarı
      'Çin': baseOffset * 2.0, // maxY'nin %16'sı kadar yukarı
      'Almanya': baseOffset * 3.0, // maxY'nin %24'ü kadar yukarı
      'Fransa': baseOffset * 4.0, // maxY'nin %32'si kadar yukarı
      'İngiltere': baseOffset * 5.0, // maxY'nin %40'ı kadar yukarı (en yüksek)
    };

    // En yüksek offset değerini logla (debug için)
    final maxOffsetValue = baseOffset * 5.0;
    debugPrint(
        '📊 Offset hesaplama: baseOffset=${baseOffset.toStringAsFixed(2)}, maxOffset=${maxOffsetValue.toStringAsFixed(2)} (maxY=$maxY)');

    // Her ülke için bir çizgi oluştur
    int countryIndex = 0;
    _countryTrends.forEach((countryName, countryData) {
      // Ülke verilerini normalize et (kullanıcı verileriyle aynı ölçekte)
      final normalizedCountryData =
          countryData.map((e) => _toDoubleSafe(e) * scaleFactor).toList();

      // Bu ülke için offset değerini al
      final offset =
          countryOffsets[countryName] ?? (userMax * 0.02 * countryIndex);

      final color =
          countryColors[countryName] ?? Colors.grey.withValues(alpha: 0.5);

      // Veri kontrolü
      final hasValidData = normalizedCountryData.isNotEmpty &&
          normalizedCountryData.any((e) => e > 0);

      debugPrint(
          '$countryName: ${normalizedCountryData.length} veri, geçerli: $hasValidData, ilk değer: ${normalizedCountryData.isNotEmpty ? normalizedCountryData.first.toStringAsFixed(2) : "yok"}');

      // Veri değerlerini kontrol et ve logla (offset ekle)
      final spots = List.generate(
        7,
        (index) {
          final baseValue = normalizedCountryData.isNotEmpty &&
                  index < normalizedCountryData.length
              ? normalizedCountryData[index].clamp(0.0, double.infinity)
              : 0.0;
          // Offset ekle - her ülke farklı yükseklikte görünsün
          final value = baseValue + offset;
          return FlSpot(index.toDouble(), value);
        },
      );

      // Tüm noktaların değerlerini logla
      final valuesStr = spots.map((s) => s.y.toStringAsFixed(2)).join(', ');
      final maxValue = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      final minValue = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      debugPrint(
          '📊 $countryName çizgi noktaları (offset: ${offset.toStringAsFixed(2)}): [$valuesStr] | Min: ${minValue.toStringAsFixed(2)}, Max: ${maxValue.toStringAsFixed(2)}');

      countryIndex++;

      countryLines.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3.0, // Çizgi kalınlığını daha da artırdık
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true, // Ülke çizgilerinde nokta göster
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4, // Nokta boyutunu artırdık
                color: color,
                strokeWidth: 2,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: false, // Ülke çizgilerinde alan gösterme
          ),
        ),
      );
    });

    debugPrint('_buildCountryLines: ${countryLines.length} çizgi oluşturuldu');
    return countryLines;
  }

  double _toDoubleSafe(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Legend: tahmini (API placeholder) seri için kısa kesik çizgi örneği
  Widget _legendDashedSwatch(Color color, {double barHeight = 3}) {
    BoxDecoration dec() => BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 5, height: barHeight, decoration: dec()),
        const SizedBox(width: 3),
        Container(width: 5, height: barHeight, decoration: dec()),
        const SizedBox(width: 3),
        Container(width: 5, height: barHeight, decoration: dec()),
      ],
    );
  }

  /// Legend item widget'ı oluştur
  Widget _buildLegendItem(
    String label,
    Color color, {
    required TextStyle labelStyle,
    bool? isRealData,
    bool showDataSourceIcon = true,
  }) {
    final isReal = isRealData ?? true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: labelStyle.copyWith(fontWeight: FontWeight.w500),
        ),
        if (showDataSourceIcon && isRealData != null) ...[
          const SizedBox(width: 4),
          Icon(
            isReal ? Icons.check_circle : Icons.info_outline,
            size: 12,
            color: isReal
                ? Colors.green.withValues(alpha: 0.8)
                : Colors.orange.withValues(alpha: 0.8),
          ),
        ],
      ],
    );
  }

  /// Ülke rengini getir
  Color _getCountryColor(String countryName) {
    final countryColors = {
      'Türkiye': Colors.blue,
      'ABD': Colors.red,
      'Çin': Colors.orange,
      'Almanya': Colors.yellow,
      'Fransa': Colors.purple,
      'İngiltere': Colors.teal,
    };
    return countryColors[countryName] ?? Colors.grey;
  }

  Future<void> _initializeShelly() async {
    debugPrint('🔌 Shelly başlatılıyor... IP: 192.168.137.57');
    _apiService.initializeShelly(
      deviceIp: '192.168.137.57',
      deviceId: _shellyDeviceId,
    );
    try {
      debugPrint('📡 Shelly verisi çekiliyor...');
      await _apiService.getShellyData(saveToFirebase: true);
      debugPrint('✅ Shelly verisi başarıyla alındı!');
    } catch (e) {
      // Hata olsa bile devam et
      debugPrint('❌ Shelly bağlantı hatası: $e');
      debugPrint('🔍 Bağlantı kontrolü yapılıyor...');
      try {
        final connected = await _apiService.checkShellyConnection();
        if (connected) {
          debugPrint(
              '✅ Bağlantı başarılı ama veri çekilemedi. Tekrar denenecek...');
        } else {
          debugPrint('❌ Shelly cihazına bağlanılamadı!');
          debugPrint('📋 Kontrol listesi:');
          debugPrint('   1. IP adresi doğru mu? (192.168.137.57)');
          debugPrint('   2. Cihaz aynı WiFi ağında mı?');
          debugPrint('   3. Cihaz çalışıyor mu? (LED ışığı yanıyor mu?)');
          debugPrint('   4. Firewall/Antivirus engelliyor olabilir');
          debugPrint(
              '   5. Tarayıcıda http://192.168.137.57/status adresini açmayı deneyin');
        }
      } catch (checkError) {
        debugPrint('❌ Bağlantı kontrolü hatası: $checkError');
      }
    }
  }

  @override
  void dispose() {
    _espDataSubscription?.cancel();
    _shellyDataSubscription?.cancel();
    super.dispose();
  }

  double? _gaugeDisplayKgCo2e() {
    if (!_useEspData) {
      final manual = _manualCalculatedKgCo2e;
      return (manual != null && manual > 0) ? manual : null;
    }
    final live = _lastCalculatedKgCo2e;
    if (live != null && live > 0) return live;
    if (_dailyEmissions.length == 7 && _dailyEmissions[6] > 0) {
      return _dailyEmissions[6];
    }
    return null;
  }

  void _syncGaugeToLiveEmissionService() {
    LiveEmissionService.instance.publishGaugeDailyKg(
      _gaugeDisplayKgCo2e(),
      useEspMode: _useEspData,
    );
  }

  /// ESP verilerini real-time dinle ve emisyonu otomatik hesapla
  void _listenToEspData() {
    _espDataSubscription?.cancel(); // Önceki subscription'ı iptal et
    _espDataSubscription =
        _firebaseService.listenToEsp8266Data('esp8266_001').listen((entry) {
      if (entry != null && mounted) {
        LiveEmissionService.instance.setEspEntry(entry);
        // ESP ham verisini sakla (su+gaz için)
        setState(() {
          _espEntry = entry;
          // Eğer ESP verisi seçiliyse, Shelly elektrik + ESP su+gaz toplamını göster
          if (_useEspData) {
            _updateCombinedEmission();
          }
        });
      }
    });
  }

  /// Açılışta Firebase'deki son ESP kaydını çek (stream gecikmesine karşı).
  Future<void> _loadInitialEspDataFromFirebase() async {
    try {
      final entry = await _firebaseService.getLatestData('esp8266_001');
      if (entry != null && mounted) {
        LiveEmissionService.instance.setEspEntry(entry);
        setState(() {
          _espEntry = entry;
          if (_useEspData) {
            _updateCombinedEmission();
          }
        });
      }
    } catch (e) {
      debugPrint('İlk ESP verisi yüklenemedi: $e');
    }
  }

  /// Shelly verilerini real-time dinle ve emisyonu otomatik hesapla
  void _listenToShellyData() {
    _shellyDataSubscription?.cancel(); // Önceki subscription'ı iptal et
    _shellyDataSubscription = _apiService
        .listenToFirebaseShellyData(_shellyDeviceId)
        .listen((shellyData) {
      if (shellyData != null && mounted) {
        _registerShellyMeterDelta(shellyData);
        final entry = _apiService.shellyDataToConsumptionEntry(shellyData);
        LiveEmissionService.instance.ingestShellyReading(shellyData, entry);
        // Shelly ham verisini sakla (ör. hata ayıklama); kWh alanı kümülatiftir
        setState(() {
          _shellyEntry = entry;
          // Eğer ESP verisi seçiliyse, Shelly elektrik + ESP su+gaz toplamını göster
          if (_useEspData) {
            _updateCombinedEmission();
          }
        });
      }
    });
  }

  void _onGaugeToggleChanged(bool value) {
    setState(() {
      _useEspData = value;
      if (value) {
        _resetShellyMeterBaseline();
        _updateCombinedEmission();
      } else {
        if (_manualCalculatedKgCo2e != null && _manualEntry != null) {
          _lastCalculatedKgCo2e = _manualCalculatedKgCo2e;
          if (_manualDailyEmissions.length == 7) {
            _manualDailyEmissions[6] = _manualCalculatedKgCo2e!;
            debugPrint(
              '📊 Toggle Manuel: Manuel grafikteki bugünün değeri güncellendi: ${_manualCalculatedKgCo2e!.toStringAsFixed(2)} kg CO2e',
            );
          }
          _updateCategoryDistributionFromEntry(_manualEntry!);
        }
      }
    });
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_kPrefsReportsUseEspData, value),
    );
    if (!value &&
        (_manualCalculatedKgCo2e == null || _manualEntry == null)) {
      _loadManualDataFromFirebase();
    }
    _loadTrendData();
    _syncGaugeToLiveEmissionService();
  }

  void _resetShellyMeterBaseline() {
    _shellySessionKwhConsumed = 0;
    _shellyPrevMeterKwh = null;
    final n = DateTime.now();
    _shellyConsumptionDayStart = DateTime(n.year, n.month, n.day);
  }

  /// Kümülatif Shelly sayacından (energyKwh) ardışık farkla tüketilen kWh biriktirir.
  void _registerShellyMeterDelta(ShellyData d) {
    final meter = d.energyKwh;
    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    if (_shellyConsumptionDayStart == null ||
        _shellyConsumptionDayStart != dayStart) {
      _shellySessionKwhConsumed = 0;
      _shellyPrevMeterKwh = null;
      _shellyConsumptionDayStart = dayStart;
    }
    if (_shellyPrevMeterKwh == null) {
      _shellyPrevMeterKwh = meter;
      return;
    }
    final delta = meter - _shellyPrevMeterKwh!;
    if (delta < -1e-9) {
      _shellyPrevMeterKwh = meter;
      return;
    }
    _shellySessionKwhConsumed += delta;
    _shellyPrevMeterKwh = meter;
  }

  /// Firebase'den en son manuel veriyi yükle
  Future<void> _loadManualDataFromFirebase() async {
    try {
      final userId = FirebaseAuthService.instance.currentUser?.uid;
      if (userId != null) {
        final manualLatestEntry =
            await _firebaseService.getLatestManualData(userId);
        if (manualLatestEntry != null && mounted) {
          setState(() {
            _manualEntry = manualLatestEntry;
            _manualCalculatedKgCo2e =
                Calculation.calculateDailyEmission(manualLatestEntry);
            // Manuel veri seçiliyse, gauge'ı güncelle
            if (!_useEspData) {
              _lastCalculatedKgCo2e = _manualCalculatedKgCo2e;
              // Grafikteki bugünün değerini de güncelle (manuel veriler listesine)
              if (_manualDailyEmissions.length == 7) {
                _manualDailyEmissions[6] = _manualCalculatedKgCo2e!;
              }
              // Kategori dağılımını güncelle
              _updateCategoryDistributionFromEntry(manualLatestEntry);
            }
            debugPrint(
                '📊 Manuel hesaplama değerleri yüklendi: ${_manualCalculatedKgCo2e!.toStringAsFixed(2)} kg CO2e');
            _syncGaugeToLiveEmissionService();
          });
        } else {
          debugPrint('📊 Manuel veri bulunamadı');
        }
      }
    } catch (e) {
      debugPrint('Manuel veri yükleme hatası: $e');
    }
  }

  /// ESP ve Shelly verilerini topla ve gauge'ı güncelle (E modu, kg CO₂e).
  /// Shelly sayacı kümülatiftir; elektrik emisyonu [_shellySessionKwhConsumed] (delta toplamı) ile hesaplanır.
  void _updateCombinedEmission() {
    double totalEmission = 0.0;

    // Shelly: yalnızca oturum içi tüketilen kWh (kümülatif sayaç × emisyon faktörü yapılmaz)
    if (_shellyEntry != null) {
      final electricityEmission =
          _shellySessionKwhConsumed * Calculation.factorElectricityKgPerKwh;
      totalEmission += electricityEmission;
      debugPrint(
        '📊 Shelly Elektrik (delta toplamı): ${_shellySessionKwhConsumed.toStringAsFixed(4)} kWh × ${Calculation.factorElectricityKgPerKwh} = ${electricityEmission.toStringAsFixed(3)} kg CO2e',
      );
    }

    // ESP'den sadece su+gaz emisyonu (elektrik ve atık hariç)
    if (_espEntry != null) {
      final waterEmission =
          _espEntry!.waterCubicMeters * Calculation.factorWaterKgPerM3;
      final fuelEmission = Calculation.fuelEmissionKgCo2e(_espEntry!);
      final espWaterGasEmission = waterEmission + fuelEmission;
      totalEmission += espWaterGasEmission;
      debugPrint(
        '📊 ESP Su+Gaz: Su=${_espEntry!.waterCubicMeters.toStringAsFixed(2)} m³ × ${Calculation.factorWaterKgPerM3} = ${waterEmission.toStringAsFixed(2)} kg, Gaz=${_espEntry!.fuelLiters.toStringAsFixed(2)} m³ × ${Calculation.factorNaturalGasKgPerM3} = ${fuelEmission.toStringAsFixed(2)} kg, Toplam=${espWaterGasEmission.toStringAsFixed(2)} kg CO2e',
      );
    }

    // Toplam emisyonu gauge'a aktar
    _lastCalculatedKgCo2e = totalEmission > 0 ? totalEmission : null;

    // Grafikteki bugünün değerini (son gün, index 6) anlık hesaplanan değerle güncelle
    if (mounted &&
        _lastCalculatedKgCo2e != null &&
        _dailyEmissions.length == 7) {
      setState(() {
        // Bugünün değerini anlık hesaplanan değerle güncelle (son gün = index 6)
        _dailyEmissions[6] = _lastCalculatedKgCo2e!;
        debugPrint(
          '📊 Grafikteki bugünün değeri güncellendi: ${_lastCalculatedKgCo2e!.toStringAsFixed(2)} kg CO2e',
        );
      });
    }

    // ESP verilerinden kategori dağılımını güncelle
    _updateCategoryDistributionFromEsp();

    debugPrint(
      '📊 Anlık CO2 Hesaplaması (Toggle ESP): Shelly Elektrik + ESP Su+Gaz = ${totalEmission.toStringAsFixed(2)} kg CO2e',
    );
    _syncGaugeToLiveEmissionService();
  }

  /// Manuel entry'den kategori dağılımını güncelle
  void _updateCategoryDistributionFromEntry(ConsumptionEntry entry) {
    final electricityEmission =
        entry.electricityKwh * Calculation.factorElectricityKgPerKwh;
    final gasEmission = Calculation.fuelEmissionKgCo2e(entry);
    final waterEmission =
        entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
    final wasteEmission = entry.wasteKg * Calculation.factorWasteKgPerKg;

    final totalEmission =
        electricityEmission + gasEmission + waterEmission + wasteEmission;

    if (totalEmission > 0 && mounted) {
      double electricityPercent = (electricityEmission / totalEmission * 100);
      double gasPercent = (gasEmission / totalEmission * 100);
      double waterPercent = (waterEmission / totalEmission * 100);
      double wastePercent = (wasteEmission / totalEmission * 100);

      // Minimum %2 göster (görünürlük için)
      const double minPercent = 2.0;
      double nonZeroTotal = 0;
      int zeroCount = 0;

      if (electricityPercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += electricityPercent;
      }
      if (waterPercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += waterPercent;
      }
      if (gasPercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += gasPercent;
      }
      if (wastePercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += wastePercent;
      }

      if (zeroCount > 0 && nonZeroTotal > 0) {
        final double remaining = 100 - (minPercent * zeroCount);
        if (electricityPercent > 0) {
          electricityPercent = (electricityPercent / nonZeroTotal) * remaining;
        } else {
          electricityPercent = minPercent;
        }
        if (waterPercent > 0) {
          waterPercent = (waterPercent / nonZeroTotal) * remaining;
        } else {
          waterPercent = minPercent;
        }
        if (gasPercent > 0) {
          gasPercent = (gasPercent / nonZeroTotal) * remaining;
        } else {
          gasPercent = minPercent;
        }
        if (wastePercent > 0) {
          wastePercent = (wastePercent / nonZeroTotal) * remaining;
        } else {
          wastePercent = minPercent;
        }
      }

      setState(() {
        _categoryDistribution = {
          'electricity': electricityPercent,
          'gas': gasPercent,
          'water': waterPercent,
          'waste': wastePercent,
        };
      });

      debugPrint(
        '📊 Manuel kategori dağılımı güncellendi: E=${electricityPercent.toStringAsFixed(1)}%, G=${gasPercent.toStringAsFixed(1)}%, S=${waterPercent.toStringAsFixed(1)}%, A=${wastePercent.toStringAsFixed(1)}%',
      );
    } else if (mounted) {
      setState(() {
        _categoryDistribution = {
          'electricity': 0.0,
          'gas': 0.0,
          'water': 0.0,
          'waste': 0.0,
        };
      });
    }
  }

  /// ESP verilerinden kategori dağılımını güncelle
  void _updateCategoryDistributionFromEsp() {
    double totalElectricity = 0.0;
    double totalGas = 0.0;
    double totalWater = 0.0;
    double totalWaste = 0.0;

    // Shelly'den elektrik (kümülatif değil, oturum delta toplamı)
    if (_shellyEntry != null) {
      totalElectricity +=
          _shellySessionKwhConsumed * Calculation.factorElectricityKgPerKwh;
    }

    // ESP'den su ve gaz
    if (_espEntry != null) {
      totalWater +=
          _espEntry!.waterCubicMeters * Calculation.factorWaterKgPerM3;
      totalGas += Calculation.fuelEmissionKgCo2e(_espEntry!);
      totalWaste += _espEntry!.wasteKg * Calculation.factorWasteKgPerKg;
    }

    final totalEmission = totalElectricity + totalGas + totalWater + totalWaste;

    if (totalEmission > 0 && mounted) {
      double electricityPercent = (totalElectricity / totalEmission * 100);
      double gasPercent = (totalGas / totalEmission * 100);
      double waterPercent = (totalWater / totalEmission * 100);
      double wastePercent = (totalWaste / totalEmission * 100);

      // Minimum %2 göster (görünürlük için)
      const double minPercent = 2.0;
      double nonZeroTotal = 0;
      int zeroCount = 0;

      if (electricityPercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += electricityPercent;
      }
      if (waterPercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += waterPercent;
      }
      if (gasPercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += gasPercent;
      }
      if (wastePercent == 0) {
        zeroCount++;
      } else {
        nonZeroTotal += wastePercent;
      }

      if (zeroCount > 0 && nonZeroTotal > 0) {
        final double remaining = 100 - (minPercent * zeroCount);
        if (electricityPercent > 0) {
          electricityPercent = (electricityPercent / nonZeroTotal) * remaining;
        } else {
          electricityPercent = minPercent;
        }
        if (waterPercent > 0) {
          waterPercent = (waterPercent / nonZeroTotal) * remaining;
        } else {
          waterPercent = minPercent;
        }
        if (gasPercent > 0) {
          gasPercent = (gasPercent / nonZeroTotal) * remaining;
        } else {
          gasPercent = minPercent;
        }
        if (wastePercent > 0) {
          wastePercent = (wastePercent / nonZeroTotal) * remaining;
        } else {
          wastePercent = minPercent;
        }
      }

      setState(() {
        _categoryDistribution = {
          'electricity': electricityPercent,
          'gas': gasPercent,
          'water': waterPercent,
          'waste': wastePercent,
        };
      });

      debugPrint(
        '📊 ESP kategori dağılımı güncellendi: E=${electricityPercent.toStringAsFixed(1)}%, G=${gasPercent.toStringAsFixed(1)}%, S=${waterPercent.toStringAsFixed(1)}%, A=${wastePercent.toStringAsFixed(1)}%',
      );
    }
  }

  /// Son 7 günün verilerini Firebase'den çek ve grafik için hazırla
  /// Hem ESP hem de Shelly verilerini birleştirir
  Future<void> _loadTrendData() async {
    if (!mounted) return; // Widget dispose edilmişse işlemi durdur
    if (_weekOffset == -1) {
      await _loadNextWeekForecastOnly();
      return;
    }
    setState(() => _isLoadingTrends = true);
    try {
      final now = DateTime.now().subtract(Duration(days: _weekOffset * 7));
      final startDate = now.subtract(const Duration(days: 7));
      final endDate = now;
      final userId = FirebaseAuthService.instance.currentUser?.uid;

      ConsumptionEntry? liveEspEntry;
      List<ConsumptionEntry> espHistoryData = [];
      List<ConsumptionEntry> shellyHistoryData = [];
      List<ConsumptionEntry> manualHistoryData = [];

      // Paralel yükleme: canlı ESP + üç Firebase geçmişi aynı anda (önceki sıralı bekleme yok).
      Future<void> loadLiveEsp() async {
        if (_weekOffset != 0) return;
        try {
          final liveEsp = await _apiService.fetchEspConsumptionOrNull(
            saveToFirebase: true,
          );
          if (liveEsp != null) {
            liveEspEntry = liveEsp;
            debugPrint(
              '📡 ESP canlı veri alındı: Gaz=${liveEsp.fuelLiters.toStringAsFixed(3)} m³, Su=${liveEsp.waterCubicMeters.toStringAsFixed(3)} m³',
            );
          } else {
            debugPrint(
              '⚠️ ESP canlı veri alınamadı, Firebase history/latest ile devam ediliyor.',
            );
          }
        } catch (e) {
          debugPrint('⚠️ ESP canlı veri çekme hatası: $e');
        }
      }

      Future<void> loadEspHistory() async {
        espHistoryData = await _firebaseService
            .getHistoryData(
              deviceId: 'esp8266_001',
              startDate: startDate,
              endDate: endDate,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => <ConsumptionEntry>[],
            );
      }

      Future<void> loadShellyHistory() async {
        try {
          final shellyDataList = await _apiService
              .getFirebaseShellyHistory(
                deviceId: _shellyDeviceId,
                startDate: startDate,
                endDate: endDate,
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => <ShellyData>[],
              );
          shellyHistoryData =
              _shellyDataListToDeltaConsumptionEntries(shellyDataList);
        } catch (e) {
          debugPrint('Shelly geçmiş veri hatası: $e');
        }
      }

      Future<void> loadManualHistory() async {
        manualHistoryData = [];
        if (userId == null) return;
        try {
          manualHistoryData = await _firebaseService
              .getManualHistoryData(
                userId: userId,
                startDate: startDate,
                endDate: endDate,
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => <ConsumptionEntry>[],
              );
          debugPrint(
              '📊 Manuel geçmiş veri yüklendi: ${manualHistoryData.length} kayıt');
        } catch (e) {
          debugPrint('Manuel geçmiş veri hatası: $e');
        }
      }

      await Future.wait([
        loadLiveEsp(),
        loadEspHistory(),
        loadShellyHistory(),
        loadManualHistory(),
      ]);

      if (!mounted) return; // Widget dispose edilmişse işlemi durdur

      // ESP, Shelly ve Manuel verilerini birleştir
      List<ConsumptionEntry> historyData = [
        ...espHistoryData,
        ...shellyHistoryData,
        ...manualHistoryData,
      ];

      // ESP'den canlı veri geldiyse mutlaka kaynak listeye ekle (Firebase latest
      // eski/bozuk olsa bile trend hesabı güncel değeri kullanabilsin).
      final liveEsp = liveEspEntry;
      if (liveEsp != null) {
        historyData.add(liveEsp);
      }

      // Eğer history'de veri yoksa, latest verilerini de kontrol et
      if (historyData.isEmpty) {
        if (_weekOffset > 0) {
          if (mounted) {
            setState(() {
              _dailyEmissions = [0, 0, 0, 0, 0, 0, 0];
              _manualDailyEmissions = [0, 0, 0, 0, 0, 0, 0];
              _isLoadingTrends = false;
            });
          }
          return;
        }
        try {
          // ESP latest verisini al
          final espLatestEntry =
              await _firebaseService.getLatestData('esp8266_001');

          // Shelly latest verisini al
          ConsumptionEntry? shellyLatestEntry;
          try {
            final latestShellyData =
                await _firebaseService.getLatestShellyData(_shellyDeviceId);
            if (latestShellyData != null) {
              // Tek anlık kümülatif sayaçla emisyon yapılmaz; bootstrap için elektrik 0
              shellyLatestEntry = ConsumptionEntry(
                electricityKwh: 0,
                waterCubicMeters: 0,
                fuelLiters: 0,
                wasteKg: 0,
                createdAt: latestShellyData.timestamp,
                fuelIsNaturalGasM3: true,
              );
            }
          } catch (e) {
            debugPrint('Shelly latest veri hatası: $e');
          }

          // Manuel latest verisini al
          ConsumptionEntry? manualLatestEntry;
          try {
            final userId = FirebaseAuthService.instance.currentUser?.uid;
            if (userId != null) {
              manualLatestEntry =
                  await _firebaseService.getLatestManualData(userId);
              if (manualLatestEntry != null) {
                debugPrint('📊 Manuel latest veri yüklendi');
                // Manuel hesaplama değerlerini güncelle
                if (mounted) {
                  setState(() {
                    _manualEntry = manualLatestEntry;
                    _manualCalculatedKgCo2e =
                        Calculation.calculateDailyEmission(manualLatestEntry!);
                    debugPrint(
                        '📊 Manuel hesaplama değerleri yüklendi: ${_manualCalculatedKgCo2e!.toStringAsFixed(2)} kg CO2e');
                  });
                }
              }
            }
          } catch (e) {
            debugPrint('Manuel latest veri hatası: $e');
          }

          if (espLatestEntry != null && mounted) {
            // Geçersiz timestamp kaynaklı 1970 kayıtlarını ve cok eski latest'i alma.
            final isStaleLatest = espLatestEntry.createdAt.year < 2020 ||
                now.difference(espLatestEntry.createdAt).inDays > 30;
            if (isStaleLatest) {
              debugPrint(
                '⚠️ ESP latest kaydı eski/geçersiz göründüğü için atlandı: ${espLatestEntry.createdAt}',
              );
            } else {
              // ESP latest verisini bugün olarak ekle
              historyData.add(ConsumptionEntry(
                electricityKwh: espLatestEntry.electricityKwh,
                waterCubicMeters: espLatestEntry.waterCubicMeters,
                fuelLiters: espLatestEntry.fuelLiters,
                wasteKg: espLatestEntry.wasteKg,
                createdAt: DateTime.now(), // Bugün olarak işaretle
                fuelIsNaturalGasM3: espLatestEntry.fuelIsNaturalGasM3,
              ));
            }
          }

          // Shelly latest verisini de ekle
          // ÖNEMLİ: ESP ve Shelly aynı elektriği ölçüyor olabilir, toplama!
          // En son (en güncel) veriyi kullan
          if (shellyLatestEntry != null && mounted) {
            if (historyData.isNotEmpty) {
              // ESP verisi varsa, hangisi daha güncelse onu kullan
              final lastEntry = historyData.last;
              if (shellyLatestEntry.createdAt.isAfter(lastEntry.createdAt)) {
                // Shelly verisi daha güncel, onu kullan
                historyData[historyData.length - 1] = shellyLatestEntry;
                debugPrint(
                    '📅 Shelly verisi ESP verisinden daha güncel, Shelly kullanıldı');
              } else {
                // ESP verisi daha güncel, ESP'yi koru
                debugPrint(
                    '📅 ESP verisi Shelly verisinden daha güncel, ESP korundu');
              }
            } else {
              // Sadece Shelly verisi varsa
              historyData.add(shellyLatestEntry);
            }
          }

          // Manuel latest verisini de ekle (en güncel olanı kullan)
          if (manualLatestEntry != null && mounted) {
            if (historyData.isNotEmpty) {
              // Mevcut veriler varsa, hangisi daha güncelse onu kullan
              final lastEntry = historyData.last;
              if (manualLatestEntry.createdAt.isAfter(lastEntry.createdAt)) {
                // Manuel verisi daha güncel, onu kullan
                historyData[historyData.length - 1] = manualLatestEntry;
                debugPrint(
                    '📅 Manuel verisi diğer verilerden daha güncel, Manuel kullanıldı');
              } else {
                debugPrint(
                    '📅 Mevcut veri Manuel verisinden daha güncel, mevcut veri korundu');
              }
            } else {
              // Sadece Manuel verisi varsa
              historyData.add(manualLatestEntry);
            }
          }

          if (historyData.isEmpty) {
            // Veri yoksa, varsayılan değerleri kullan
            if (mounted) {
              setState(() {
                _dailyEmissions = [0, 0, 0, 0, 0, 0, 0];
                _isLoadingTrends = false;
              });
            }
            return;
          }
        } catch (e) {
          // Latest verisi alınamazsa varsayılan değerleri kullan
          if (mounted) {
            setState(() {
              _dailyEmissions = [0, 0, 0, 0, 0, 0, 0];
              _isLoadingTrends = false;
            });
          }
          return;
        }
      }

      // Günlere göre grupla - her gün için en son (en güncel) veriyi kullan
      // ÖNEMLİ: Aynı günde birden fazla kayıt varsa, en son kaydı kullan
      // Çünkü her kayıt günlük toplam tüketimi temsil eder, toplanmamalı!
      debugPrint('📊 ========== VERİ KAYNAĞI ANALİZİ ==========');
      debugPrint('📊 Toplam ${historyData.length} veri kaydı bulundu');
      debugPrint('📊 ESP kayıt sayısı: ${espHistoryData.length}');
      debugPrint('📊 Shelly kayıt sayısı: ${shellyHistoryData.length}');
      debugPrint('📊 Manuel kayıt sayısı: ${manualHistoryData.length}');

      // ESP ve Shelly verilerini ayrı ayrı logla
      if (espHistoryData.isNotEmpty) {
        debugPrint('📊 ESP Verileri:');
        for (var entry in espHistoryData) {
          debugPrint(
              '   ${entry.createdAt}: E=${entry.electricityKwh.toStringAsFixed(2)} kWh, Y=${entry.fuelLiters.toStringAsFixed(2)} L, S=${entry.waterCubicMeters.toStringAsFixed(2)} m³');
        }
      }
      if (shellyHistoryData.isNotEmpty) {
        debugPrint('📊 Shelly Verileri:');
        for (var entry in shellyHistoryData) {
          debugPrint(
              '   ${entry.createdAt}: E=${entry.electricityKwh.toStringAsFixed(2)} kWh, Y=${entry.fuelLiters.toStringAsFixed(2)} L, S=${entry.waterCubicMeters.toStringAsFixed(2)} m³');
        }
      }
      if (manualHistoryData.isNotEmpty) {
        debugPrint('📊 Manuel Verileri:');
        for (var entry in manualHistoryData) {
          debugPrint(
              '   ${entry.createdAt}: E=${entry.electricityKwh.toStringAsFixed(2)} kWh, Y=${entry.fuelLiters.toStringAsFixed(2)} L, S=${entry.waterCubicMeters.toStringAsFixed(2)} m³, A=${entry.wasteKg.toStringAsFixed(2)} kg');
        }
      }

      // Önce ESP ve Shelly verilerini günlere göre grupla
      final Map<int, ConsumptionEntry?> espDailyData = {};
      final Map<int, ConsumptionEntry?> shellyDailyData = {};
      final Map<int, ConsumptionEntry?> manualDailyData = {};

      // Veri kaynaklarını belirlemek için timestamp set'leri oluştur
      final espTimestamps =
          espHistoryData.map((e) => e.createdAt.millisecondsSinceEpoch).toSet();
      final shellyTimestamps = shellyHistoryData
          .map((e) => e.createdAt.millisecondsSinceEpoch)
          .toSet();
      final manualTimestamps = manualHistoryData
          .map((e) => e.createdAt.millisecondsSinceEpoch)
          .toSet();

      // Verileri tarihe göre sırala (en eski -> en yeni)
      historyData.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // Her veriyi kaynağına göre günlere ayır
      for (var entry in historyData) {
        final difference = now.difference(entry.createdAt);
        final dayIndex = difference.inDays;

        if (dayIndex >= 0 && dayIndex < 7) {
          final timestamp = entry.createdAt.millisecondsSinceEpoch;

          if (espTimestamps.contains(timestamp)) {
            // ESP verisi - en güncel olanı kullan
            if (!espDailyData.containsKey(dayIndex) ||
                entry.createdAt.isAfter(espDailyData[dayIndex]!.createdAt)) {
              espDailyData[dayIndex] = entry;
            }
          } else if (shellyTimestamps.contains(timestamp)) {
            // Shelly verisi - en güncel olanı kullan
            if (!shellyDailyData.containsKey(dayIndex) ||
                entry.createdAt.isAfter(shellyDailyData[dayIndex]!.createdAt)) {
              shellyDailyData[dayIndex] = entry;
            }
          } else if (manualTimestamps.contains(timestamp)) {
            // Manuel verisi - en güncel olanı kullan
            if (!manualDailyData.containsKey(dayIndex) ||
                entry.createdAt.isAfter(manualDailyData[dayIndex]!.createdAt)) {
              manualDailyData[dayIndex] = entry;
            }
          }
        }
      }

      // ESP + Shelly birleşimi (manuel bu seriye dahil edilmez — kişisel sensör trendi)
      final Map<int, ConsumptionEntry> sensorDailyData = {};
      final Map<int, int> sensorDailyDataCount = {};
      final Map<int, List<String>> sensorDailyDataSources = {};

      for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
        final espEntry = espDailyData[dayIndex];
        final shellyEntry = shellyDailyData[dayIndex];

        if (espEntry != null && shellyEntry != null) {
          final combinedEntry = ConsumptionEntry(
            electricityKwh: shellyEntry.electricityKwh,
            waterCubicMeters: espEntry.waterCubicMeters,
            fuelLiters: espEntry.fuelLiters,
            wasteKg: (espEntry.wasteKg + shellyEntry.wasteKg) / 2,
            createdAt: shellyEntry.createdAt.isAfter(espEntry.createdAt)
                ? shellyEntry.createdAt
                : espEntry.createdAt,
            fuelIsNaturalGasM3: espEntry.fuelIsNaturalGasM3,
          );
          sensorDailyData[dayIndex] = combinedEntry;
          sensorDailyDataCount[dayIndex] = 2;
          sensorDailyDataSources[dayIndex] = ['ESP', 'Shelly'];
          debugPrint('📅 Gün $dayIndex: ESP + Shelly birleştirildi:');
          debugPrint(
              '   ESP: E=${espEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${espEntry.fuelLiters.toStringAsFixed(2)} L, S=${espEntry.waterCubicMeters.toStringAsFixed(2)} m³');
          debugPrint(
              '   Shelly: E=${shellyEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${shellyEntry.fuelLiters.toStringAsFixed(2)} L, S=${shellyEntry.waterCubicMeters.toStringAsFixed(2)} m³');
          debugPrint(
              '   Birleşik: E=${combinedEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${combinedEntry.fuelLiters.toStringAsFixed(2)} L, S=${combinedEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        } else if (espEntry != null) {
          sensorDailyData[dayIndex] = espEntry;
          sensorDailyDataCount[dayIndex] = 1;
          sensorDailyDataSources[dayIndex] = ['ESP'];
          debugPrint(
              '📅 Gün $dayIndex: Sadece ESP verisi: E=${espEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${espEntry.fuelLiters.toStringAsFixed(2)} L, S=${espEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        } else if (shellyEntry != null) {
          sensorDailyData[dayIndex] = shellyEntry;
          sensorDailyDataCount[dayIndex] = 1;
          sensorDailyDataSources[dayIndex] = ['Shelly'];
          debugPrint(
              '📅 Gün $dayIndex: Sadece Shelly verisi: E=${shellyEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${shellyEntry.fuelLiters.toStringAsFixed(2)} L, S=${shellyEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        }
      }

      // Özet bilgi
      debugPrint('📊 ========== GÜNLÜK VERİ ÖZETİ ==========');
      sensorDailyDataCount.forEach((day, count) {
        final sources = sensorDailyDataSources[day] ?? [];
        final entry = sensorDailyData[day]!;
        final emission = Calculation.calculateDailyEmission(entry);
        debugPrint('📅 Gün $day (${6 - day} gün önce):');
        debugPrint('   Kayıt sayısı: $count');
        debugPrint('   Kaynaklar: ${sources.join(", ")}');
        debugPrint(
            '   Elektrik: ${entry.electricityKwh.toStringAsFixed(2)} kWh');
        debugPrint('   Yakıt: ${entry.fuelLiters.toStringAsFixed(2)} L');
        debugPrint('   Su: ${entry.waterCubicMeters.toStringAsFixed(2)} m³');
        debugPrint('   Atık: ${entry.wasteKg.toStringAsFixed(2)} kg');
        debugPrint('   TOPLAM EMİSYON: ${emission.toStringAsFixed(2)} kg CO2e');
        if (count > 1) {
          debugPrint(
              '   ⚠️ Bu gün için $count kayıt bulundu, en güncel olan kullanıldı');
        }
        if (emission > 50) {
          debugPrint('   ⚠️⚠️⚠️ ÇOK YÜKSEK DEĞER! Normal: 4-15 kg/gün');
        }
      });
      debugPrint('📊 =========================================');

      // Sensör serisi boş ama geçmiş listede veri varsa: yalnızca ESP/Shelly kaynaklı
      // son kayıt (manuel hariç) bugüne yansıtılsın
      if (sensorDailyData.isEmpty && historyData.isNotEmpty) {
        ConsumptionEntry? latestSensor;
        for (var i = historyData.length - 1; i >= 0; i--) {
          final e = historyData[i];
          final ts = e.createdAt.millisecondsSinceEpoch;
          if (espTimestamps.contains(ts) || shellyTimestamps.contains(ts)) {
            latestSensor = e;
            break;
          }
        }
        if (latestSensor != null) {
          sensorDailyData[0] = ConsumptionEntry(
            electricityKwh: latestSensor.electricityKwh,
            waterCubicMeters: latestSensor.waterCubicMeters,
            fuelLiters: latestSensor.fuelLiters,
            wasteKg: latestSensor.wasteKg,
            createdAt: DateTime.now(),
            fuelIsNaturalGasM3: latestSensor.fuelIsNaturalGasM3,
          );
          debugPrint(
              '📅 Sensör günlük eşleşmesi yok; en son sensör kaydı bugüne taşındı');
        }
      }

      // Manuel veriler zaten yukarıda işlendi (manualDailyData map'inde)

      // ESP/Shelly verileri için günlük emisyonları hesapla
      final List<double> emissions = [];
      // Manuel veriler için ayrı günlük emisyonları hesapla
      final List<double> manualEmissions = [];
      double totalElectricity = 0;
      double totalGas = 0;
      double totalWater = 0;
      double totalWaste = 0;

      // ESP/Shelly verileri için döngü (yalnızca sensör serisi — manuel hariç)
      for (int i = 6; i >= 0; i--) {
        // En eski günden en yeni güne (Pazartesi'den Pazar'a)
        if (sensorDailyData.containsKey(i)) {
          final entry = sensorDailyData[i]!;
          final emission = Calculation.calculateDailyEmission(entry);

          // Debug: Detaylı emisyon bilgisi
          final electricityEmission =
              entry.electricityKwh * Calculation.factorElectricityKgPerKwh;
          final fuelEmission = Calculation.fuelEmissionKgCo2e(entry);
          final waterEmission =
              entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
          final wasteEmission = entry.wasteKg * Calculation.factorWasteKgPerKg;

          debugPrint('📊 Gün ${6 - i} emisyon detayı:');
          debugPrint(
              '   Elektrik: ${entry.electricityKwh.toStringAsFixed(2)} kWh × 0.233 = ${electricityEmission.toStringAsFixed(2)} kg CO2e');
          debugPrint(
              '   Yakıt: ${entry.fuelLiters.toStringAsFixed(2)} ${entry.fuelIsNaturalGasM3 ? "m³×${Calculation.factorNaturalGasKgPerM3}" : "L×${Calculation.factorFuelKgPerLiter}"} = ${fuelEmission.toStringAsFixed(2)} kg CO2e');
          debugPrint(
              '   Su: ${entry.waterCubicMeters.toStringAsFixed(2)} m³ × 0.344 = ${waterEmission.toStringAsFixed(2)} kg CO2e');
          debugPrint(
              '   Atık: ${entry.wasteKg.toStringAsFixed(2)} kg × 1.9 = ${wasteEmission.toStringAsFixed(2)} kg CO2e');
          debugPrint('   TOPLAM: ${emission.toStringAsFixed(2)} kg CO2e');
          debugPrint('   ⚠️ Normal değer: 4-15 kg/gün (kişi başı)');

          emissions.add(emission);

          // Kategori dağılımı için sadece bugünün (i == 0) verilerini topla
          if (i == 0) {
            totalElectricity +=
                entry.electricityKwh * Calculation.factorElectricityKgPerKwh;
            totalGas += Calculation.fuelEmissionKgCo2e(entry);
            totalWater +=
                entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
            totalWaste += entry.wasteKg * Calculation.factorWasteKgPerKg;
          }
        } else {
          emissions.add(0.0);
        }
      }

      // Manuel veriler için döngü
      double manualTotalElectricity = 0.0;
      double manualTotalGas = 0.0;
      double manualTotalWater = 0.0;
      double manualTotalWaste = 0.0;

      for (int i = 6; i >= 0; i--) {
        if (manualDailyData.containsKey(i)) {
          final entry = manualDailyData[i]!;
          final emission = Calculation.calculateDailyEmission(entry);
          manualEmissions.add(emission);

          // Manuel veriler için kategori dağılımı için sadece bugünün (i == 0) verilerini topla
          if (i == 0) {
            manualTotalElectricity +=
                entry.electricityKwh * Calculation.factorElectricityKgPerKwh;
            manualTotalGas += Calculation.fuelEmissionKgCo2e(entry);
            manualTotalWater +=
                entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
            manualTotalWaste += entry.wasteKg * Calculation.factorWasteKgPerKg;
          }
        } else {
          manualEmissions.add(0.0);
        }
      }

      // Kategori yüzdelerini hesapla (ESP verileri için)
      final double totalEmission =
          totalElectricity + totalGas + totalWater + totalWaste;

      // Manuel veriler için kategori yüzdelerini hesapla
      final double manualTotalEmission = manualTotalElectricity +
          manualTotalGas +
          manualTotalWater +
          manualTotalWaste;

      if (!mounted) return; // Widget dispose edilmişse işlemi durdur

      final double todaySensorEmission = sensorDailyData.containsKey(0)
          ? Calculation.calculateDailyEmission(sensorDailyData[0]!)
          : 0.0;
      final double todayManualEmission = manualDailyData.containsKey(0)
          ? Calculation.calculateDailyEmission(manualDailyData[0]!)
          : 0.0;

      double? gaugeKgCo2eForState() {
        if (_useEspData) {
          return todaySensorEmission > 0 ? todaySensorEmission : null;
        }
        if (todayManualEmission > 0) return todayManualEmission;
        final m = _manualCalculatedKgCo2e;
        if (m != null && m > 0) return m;
        return null;
      }

      if (totalEmission > 0 || manualTotalEmission > 0) {
        double electricityPercent = 0.0;
        double gasPercent = 0.0;
        double waterPercent = 0.0;
        double wastePercent = 0.0;

        if (totalEmission > 0) {
          electricityPercent = (totalElectricity / totalEmission * 100);
          gasPercent = (totalGas / totalEmission * 100);
          waterPercent = (totalWater / totalEmission * 100);
          wastePercent = (totalWaste / totalEmission * 100);

          const double minPercent = 2.0;
          double nonZeroTotal = 0;
          int zeroCount = 0;

          if (electricityPercent == 0) {
            zeroCount++;
          } else {
            nonZeroTotal += electricityPercent;
          }
          if (waterPercent == 0) {
            zeroCount++;
          } else {
            nonZeroTotal += waterPercent;
          }
          if (gasPercent == 0) {
            zeroCount++;
          } else {
            nonZeroTotal += gasPercent;
          }
          if (wastePercent == 0) {
            zeroCount++;
          } else {
            nonZeroTotal += wastePercent;
          }

          if (zeroCount > 0 && nonZeroTotal > 0) {
            final double remaining = 100 - (minPercent * zeroCount);

            if (electricityPercent > 0) {
              electricityPercent =
                  (electricityPercent / nonZeroTotal) * remaining;
            } else {
              electricityPercent = minPercent;
            }

            if (waterPercent > 0) {
              waterPercent = (waterPercent / nonZeroTotal) * remaining;
            } else {
              waterPercent = minPercent;
            }

            if (gasPercent > 0) {
              gasPercent = (gasPercent / nonZeroTotal) * remaining;
            } else {
              gasPercent = minPercent;
            }

            if (wastePercent > 0) {
              wastePercent = (wastePercent / nonZeroTotal) * remaining;
            } else {
              wastePercent = minPercent;
            }
          }
        }

        // Manuel veriler için kategori yüzdelerini hesapla
        double manualElectricityPercent = 0.0;
        double manualGasPercent = 0.0;
        double manualWaterPercent = 0.0;
        double manualWastePercent = 0.0;

        if (manualTotalEmission > 0) {
          manualElectricityPercent =
              (manualTotalElectricity / manualTotalEmission * 100);
          manualGasPercent = (manualTotalGas / manualTotalEmission * 100);
          manualWaterPercent = (manualTotalWater / manualTotalEmission * 100);
          manualWastePercent = (manualTotalWaste / manualTotalEmission * 100);

          // Minimum %2 göster (görünürlük için)
          const double minPercent = 2.0;
          double manualNonZeroTotal = 0;
          int manualZeroCount = 0;

          if (manualElectricityPercent == 0) {
            manualZeroCount++;
          } else {
            manualNonZeroTotal += manualElectricityPercent;
          }
          if (manualWaterPercent == 0) {
            manualZeroCount++;
          } else {
            manualNonZeroTotal += manualWaterPercent;
          }
          if (manualGasPercent == 0) {
            manualZeroCount++;
          } else {
            manualNonZeroTotal += manualGasPercent;
          }
          if (manualWastePercent == 0) {
            manualZeroCount++;
          } else {
            manualNonZeroTotal += manualWastePercent;
          }

          if (manualZeroCount > 0 && manualNonZeroTotal > 0) {
            final double remaining = 100 - (minPercent * manualZeroCount);
            if (manualElectricityPercent > 0) {
              manualElectricityPercent =
                  (manualElectricityPercent / manualNonZeroTotal) * remaining;
            } else {
              manualElectricityPercent = minPercent;
            }
            if (manualWaterPercent > 0) {
              manualWaterPercent =
                  (manualWaterPercent / manualNonZeroTotal) * remaining;
            } else {
              manualWaterPercent = minPercent;
            }
            if (manualGasPercent > 0) {
              manualGasPercent =
                  (manualGasPercent / manualNonZeroTotal) * remaining;
            } else {
              manualGasPercent = minPercent;
            }
            if (manualWastePercent > 0) {
              manualWastePercent =
                  (manualWastePercent / manualNonZeroTotal) * remaining;
            } else {
              manualWastePercent = minPercent;
            }
          }
        }

        setState(() {
          _dailyEmissions = emissions;
          _manualDailyEmissions = manualEmissions;
          if (_useEspData) {
            if (totalEmission > 0) {
              _categoryDistribution = {
                'electricity': electricityPercent,
                'gas': gasPercent,
                'water': waterPercent,
                'waste': wastePercent,
              };
            } else {
              _categoryDistribution = {
                'electricity': 25.0,
                'gas': 25.0,
                'water': 25.0,
                'waste': 25.0,
              };
            }
          } else if (manualTotalEmission > 0) {
            _categoryDistribution = {
              'electricity': manualElectricityPercent,
              'gas': manualGasPercent,
              'water': manualWaterPercent,
              'waste': manualWastePercent,
            };
          } else {
            _categoryDistribution = {
              'electricity': 25.0,
              'gas': 25.0,
              'water': 25.0,
              'waste': 25.0,
            };
          }
          _lastCalculatedKgCo2e = gaugeKgCo2eForState();
          _isLoadingTrends = false;
        });
      } else {
        setState(() {
          _dailyEmissions = emissions;
          _manualDailyEmissions = manualEmissions;
          _categoryDistribution = {
            'electricity': 25.0,
            'gas': 25.0,
            'water': 25.0,
            'waste': 25.0,
          };
          _lastCalculatedKgCo2e = gaugeKgCo2eForState();
          _isLoadingTrends = false;
        });
      }
      if (mounted && _useEspData) {
        _updateCombinedEmission();
      }
      _syncGaugeToLiveEmissionService();
    } catch (e) {
      // Hata durumunda varsayılan değerleri kullan
      if (mounted) {
        setState(() {
          _dailyEmissions = [0, 0, 0, 0, 0, 0, 0];
          _manualDailyEmissions = [0, 0, 0, 0, 0, 0, 0];
          _isLoadingTrends = false;
        });
      }
    }
  }

  /// Gelecek hafta görünümü: önce bu haftanın gerçek serisini yükler, sonra ortalama ile
  /// düz tahmini seri üretir (ölçülmemiş günler için gerçek çizgi gösterilmez).
  Future<void> _loadNextWeekForecastOnly() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTrends = true;
      _weekOffset = 0;
    });
    await _loadTrendData();
    if (!mounted) return;
    final espVals = List<double>.from(_dailyEmissions);
    final manVals = List<double>.from(_manualDailyEmissions);
    final double espAvg =
        espVals.isEmpty ? 0.0 : espVals.fold<double>(0, (a, b) => a + b) / 7.0;
    final double manAvg =
        manVals.isEmpty ? 0.0 : manVals.fold<double>(0, (a, b) => a + b) / 7.0;
    setState(() {
      _weekOffset = -1;
      _dailyEmissions = List<double>.filled(7, espAvg);
      _manualDailyEmissions = List<double>.filled(7, manAvg);
      _lastCalculatedKgCo2e = null;
      _manualCalculatedKgCo2e = null;
    });
  }

  Future<void> _generateCarbonPdfReport({required bool monthly}) async {
    final locale = _localeForPdfExport();
    try {
      final pdfTheme = await _pdfUnicodeTheme();
      final now = DateTime.now();
      final title = monthly
          ? translate('pdf_monthly_report_title', locale)
          : translate('pdf_weekly_report_title', locale);
      final periodLabel = monthly
          ? '${now.year}-${now.month.toString().padLeft(2, '0')}'
          : '${translate('week', locale)} ${_isoWeekNumber(now)}';

      final activeDailyData =
          _useEspData ? _dailyEmissions : _manualDailyEmissions;
      final List<double> sourceData = activeDailyData.length == 7
          ? List<double>.from(
              activeDailyData.map((e) => e.isFinite ? e : 0.0),
            )
          : List<double>.filled(7, 0);
      final todayValue =
          _useEspData ? _lastCalculatedKgCo2e : _manualCalculatedKgCo2e;
      if (todayValue != null && todayValue.isFinite && sourceData.length == 7) {
        sourceData[6] = todayValue;
      }

      final weeklyTotal = sourceData.fold<double>(
        0,
        (sum, e) => sum + (e.isFinite ? e : 0),
      );
      final weeklyAverage =
          sourceData.isEmpty ? 0.0 : weeklyTotal / sourceData.length;
      final monthlyEstimate = weeklyTotal * 4.0;
      final selectedTotal = monthly ? monthlyEstimate : weeklyTotal;
      final selectedAverage = monthly ? monthlyEstimate / 30.0 : weeklyAverage;
      final safeTotal = selectedTotal.isFinite ? selectedTotal : 0.0;
      final safeAverage = selectedAverage.isFinite ? selectedAverage : 0.0;

      final activeCategoryDistribution = _activeCategoryDistribution();
      // E (ESP + Shelly): PDF'te yalnızca elektrik / su / doğalgaz; atık satırı yok; yüzdeler 3 kategoriye göre normalize
      final List<List<String>> categoryRows = _useEspData
          ? _buildPdfCategoryRowsSensorMode(
              locale,
              safeTotal,
              activeCategoryDistribution,
            )
          : [
              _buildCategoryRowForPdf(
                translate('electricity_label', locale),
                activeCategoryDistribution['electricity'] ?? 0,
                safeTotal,
              ),
              _buildCategoryRowForPdf(
                translate('water_label', locale),
                activeCategoryDistribution['water'] ?? 0,
                safeTotal,
              ),
              _buildCategoryRowForPdf(
                translate('gas_label', locale),
                activeCategoryDistribution['gas'] ?? 0,
                safeTotal,
              ),
              _buildCategoryRowForPdf(
                translate('waste_label', locale),
                activeCategoryDistribution['waste'] ?? 0,
                safeTotal,
              ),
            ];

      pw.Widget pdfBulletLine(String line) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
              pw.Expanded(
                child: pw.Text(
                  line,
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.25),
                ),
              ),
            ],
          ),
        );
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            theme: pdfTheme,
          ),
          build: (context) => [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${translate('pdf_period', locale)}: $periodLabel',
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.Text(
              '${translate('pdf_generated_at', locale)}: ${now.toIso8601String().substring(0, 16)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    translate('pdf_iso_summary', locale),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pdfBulletLine(
                    '${translate('pdf_total_emission', locale)}: ${safeTotal.toStringAsFixed(2)} kg CO2e',
                  ),
                  pdfBulletLine(
                    '${translate('pdf_average_emission', locale)}: ${safeAverage.toStringAsFixed(2)} kg CO2e',
                  ),
                  pdfBulletLine(
                    '${translate('pdf_methodology_note', locale)}: ${translate('pdf_methodology_value', locale)}',
                  ),
                  pdfBulletLine(
                    '${translate('pdf_boundary_note', locale)}: ${translate('pdf_boundary_value', locale)}',
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              translate('pdf_category_breakdown', locale),
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                translate('pdf_table_category', locale),
                translate('pdf_table_percent', locale),
                translate('pdf_table_kgco2e', locale),
              ],
              data: categoryRows,
              border: pw.TableBorder.all(color: PdfColors.grey400),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              translate('pdf_disclaimer', locale),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        name:
            monthly ? 'carbon-monthly-report.pdf' : 'carbon-weekly-report.pdf',
        onLayout: (format) async => pdf.save(),
      );
    } catch (e, st) {
      log(
        'PDF export failed',
        name: 'ReportsScreen',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      final isTr = locale.languageCode == 'tr';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTr ? 'PDF oluşturulamadı: $e' : 'Could not create PDF: $e',
          ),
        ),
      );
    }
  }

  /// PDF — [ReportsScreen] E (ESP + Shelly): atık satırı yok; pasta ile uyumlu yüzdeler üç kaleme bölünür.
  List<List<String>> _buildPdfCategoryRowsSensorMode(
    Locale locale,
    double totalKg,
    Map<String, double> dist,
  ) {
    final double e = (dist['electricity'] ?? 0).clamp(0.0, 100.0);
    final double w = (dist['water'] ?? 0).clamp(0.0, 100.0);
    final double g = (dist['gas'] ?? 0).clamp(0.0, 100.0);
    final double sum = e + w + g;
    final double pe;
    final double pw;
    final double pg;
    if (sum > 1e-9) {
      pe = (e / sum) * 100.0;
      pw = (w / sum) * 100.0;
      pg = (g / sum) * 100.0;
    } else {
      pe = 0;
      pw = 0;
      pg = 0;
    }
    return [
      _buildCategoryRowForPdf(
        translate('electricity_label', locale),
        pe,
        totalKg,
      ),
      _buildCategoryRowForPdf(
        translate('water_label', locale),
        pw,
        totalKg,
      ),
      _buildCategoryRowForPdf(
        translate('gas_label', locale),
        pg,
        totalKg,
      ),
    ];
  }

  List<String> _buildCategoryRowForPdf(
    String label,
    double percent,
    double totalKg,
  ) {
    final shareKg = totalKg * (percent / 100);
    return [
      label,
      '${_formatPercent(percent)}%',
      _formatKgForPdf(shareKg),
    ];
  }

  String _formatPercent(double percent) {
    if (percent <= 0) return '0.0';
    if (percent < 0.1) return percent.toStringAsFixed(3);
    if (percent < 1) return percent.toStringAsFixed(2);
    if (percent < 10) return percent.toStringAsFixed(1);
    return percent.toStringAsFixed(0);
  }

  String _formatKgForPdf(double kg) {
    if (kg <= 0) return '0.00';
    if (kg < 0.01) return kg.toStringAsFixed(4);
    if (kg < 0.1) return kg.toStringAsFixed(3);
    return kg.toStringAsFixed(2);
  }

  int _isoWeekNumber(DateTime date) {
    final thursday =
        date.add(Duration(days: 4 - (date.weekday == 7 ? 0 : date.weekday)));
    final firstDayOfYear = DateTime(thursday.year, 1, 1);
    final dayOfYear = thursday.difference(firstDayOfYear).inDays + 1;
    return ((dayOfYear - 1) ~/ 7) + 1;
  }

  Map<String, double> _distributionFromEmissions({
    required double electricity,
    required double gas,
    required double water,
    required double waste,
  }) {
    final total = electricity + gas + water + waste;
    if (total <= 0) {
      return {
        'electricity': 0.0,
        'gas': 0.0,
        'water': 0.0,
        'waste': 0.0,
      };
    }

    double electricityPercent = (electricity / total) * 100;
    double gasPercent = (gas / total) * 100;
    double waterPercent = (water / total) * 100;
    double wastePercent = (waste / total) * 100;

    const double minVisiblePercent = 2.0;
    final percents = <String, double>{
      'electricity': electricityPercent,
      'gas': gasPercent,
      'water': waterPercent,
      'waste': wastePercent,
    };
    final positiveKeys =
        percents.entries.where((e) => e.value > 0).map((e) => e.key).toList();
    if (positiveKeys.isNotEmpty) {
      final effectiveMin = (100.0 / positiveKeys.length) < minVisiblePercent
          ? (100.0 / positiveKeys.length)
          : minVisiblePercent;
      final boostedKeys = positiveKeys
          .where((k) => (percents[k] ?? 0.0) < effectiveMin)
          .toList();
      if (boostedKeys.isNotEmpty) {
        final unboostedKeys =
            positiveKeys.where((k) => !boostedKeys.contains(k)).toList();
        final boostedTotal = effectiveMin * boostedKeys.length;
        final remaining = (100.0 - boostedTotal).clamp(0.0, 100.0);
        final unboostedOriginalTotal = unboostedKeys.fold<double>(
          0.0,
          (sum, k) => sum + (percents[k] ?? 0.0),
        );

        for (final key in boostedKeys) {
          percents[key] = effectiveMin;
        }

        if (unboostedKeys.isNotEmpty && unboostedOriginalTotal > 0) {
          for (final key in unboostedKeys) {
            final original = percents[key] ?? 0.0;
            percents[key] = (original / unboostedOriginalTotal) * remaining;
          }
        }
      }
    }

    electricityPercent = percents['electricity'] ?? 0.0;
    gasPercent = percents['gas'] ?? 0.0;
    waterPercent = percents['water'] ?? 0.0;
    wastePercent = percents['waste'] ?? 0.0;

    return {
      'electricity': electricityPercent,
      'gas': gasPercent,
      'water': waterPercent,
      'waste': wastePercent,
    };
  }

  Map<String, double> _manualCategoryDistribution() {
    final entry = _manualEntry;
    if (entry == null) {
      return {
        'electricity': 0.0,
        'gas': 0.0,
        'water': 0.0,
        'waste': 0.0,
      };
    }
    return _distributionFromEmissions(
      electricity: entry.electricityKwh * Calculation.factorElectricityKgPerKwh,
      gas: Calculation.fuelEmissionKgCo2e(entry),
      water: entry.waterCubicMeters * Calculation.factorWaterKgPerM3,
      waste: entry.wasteKg * Calculation.factorWasteKgPerKg,
    );
  }

  Map<String, double> _sensorCategoryDistribution() {
    final espEntry = _espEntry;
    if (espEntry == null && _shellyEntry == null) {
      return {
        'electricity': 0.0,
        'gas': 0.0,
        'water': 0.0,
        'waste': 0.0,
      };
    }
    return _distributionFromEmissions(
      electricity:
          _shellySessionKwhConsumed * Calculation.factorElectricityKgPerKwh,
      gas: espEntry == null ? 0.0 : Calculation.fuelEmissionKgCo2e(espEntry),
      water: espEntry == null
          ? 0.0
          : espEntry.waterCubicMeters * Calculation.factorWaterKgPerM3,
      waste: espEntry == null
          ? 0.0
          : espEntry.wasteKg * Calculation.factorWasteKgPerKg,
    );
  }

  Map<String, double> _activeCategoryDistribution() {
    final liveDistribution = _useEspData
        ? _sensorCategoryDistribution()
        : _manualCategoryDistribution();
    final liveTotal =
        liveDistribution.values.fold<double>(0.0, (sum, v) => sum + v);
    if (liveTotal > 0) return liveDistribution;
    return Map<String, double>.from(_categoryDistribution);
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    final activeCategoryDistribution = _activeCategoryDistribution();
    final TextStyle headerStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily,
      height: 1.2,
    );
    final TextStyle subStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      color: Colors.white70,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      height: 1.35,
    );
    // Üst/alt simetrik iç boşluk; alt bölüm için alt gezinme + güvenli alan.
    final media = MediaQuery.of(context);
    final double bottomPadding = media.padding.bottom;
    const double bottomNavReserve = 80;
    final double reportHorizontalPad = media.size.width < 360 ? 12.0 : 16.0;
    final EdgeInsets listViewPadding = EdgeInsets.only(
      top: 16,
      left: reportHorizontalPad,
      right: reportHorizontalPad,
      bottom: 16 + bottomPadding + bottomNavReserve,
    );

    // Web: Stack + LayoutBuilder + ListView bazen hit-test / mouse_tracker assert;
    // genişlik MediaQuery ile (Hedefler ekranındaki gibi).
    final double reportViewportW = media.size.width;
    final bool isWide = reportViewportW >= 900;
    final double gaugeSectionMaxHeight =
        (media.size.height * 0.62).clamp(280.0, 460.0);
    final double gaugeSize = isWide
        ? 260.0
        : (reportViewportW * 0.65).clamp(220.0, 270.0);
    final double headerHeight =
        (gaugeSectionMaxHeight - (gaugeSize * 0.32)).clamp(90.0, 160.0);

    return Scaffold(
      appBar: null,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Sayfanın tamamında arka plan görseli
            Image.asset('assets/images/bckgrnd2.jpeg', fit: BoxFit.cover),
            // İçerik
            Theme(
              // Tüm TextTheme renklerini beyaza uygula (başlıklar dahil)
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.apply(
                      bodyColor: Colors.white,
                      displayColor: Colors.white,
                    ),
              ),
              child: Material(
                color: Colors.transparent,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isWide ? 900 : double.infinity,
                      ),
                      child: RepaintBoundary(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          clipBehavior: isWide ? Clip.hardEdge : Clip.none,
                          padding: listViewPadding,
                          children: [
                            Padding(
                              padding: _kReportsSectionOuterPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          translate(
                                            'calculated_daily_emission',
                                            locale,
                                          ),
                                          style: headerStyle,
                                        ),
                                      ),
                                      _ReportsRoundInfoIcon(
                                        onTap: () => _showGaugeInfoDialog(
                                            context, locale),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (isWide) ...[
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        SizedBox(height: headerHeight),
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: -(gaugeSize / 3),
                                          child: Center(
                                            child: _FootprintGauge(
                                              kgCo2e: _lastCalculatedKgCo2e,
                                              size: gaugeSize,
                                              isMobileLayout: false,
                                              languageProvider:
                                                  widget.languageProvider,
                                              useEspData: _useEspData,
                                              centerStatusOverride: _useEspData &&
                                                      _lastCalculatedKgCo2e ==
                                                          null
                                                  ? translate(
                                                      'sensor_data_waiting',
                                                      locale,
                                                    )
                                                  : null,
                                              onToggleChanged: _onGaugeToggleChanged,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: gaugeSize / 3 + 32),
                                  ] else ...[
                                    Center(
                                      child: _FootprintGauge(
                                        kgCo2e: _lastCalculatedKgCo2e,
                                        size: gaugeSize,
                                        isMobileLayout: true,
                                        languageProvider:
                                            widget.languageProvider,
                                        useEspData: _useEspData,
                                        centerStatusOverride: _useEspData &&
                                                _lastCalculatedKgCo2e == null
                                            ? translate(
                                                'sensor_data_waiting',
                                                locale,
                                              )
                                            : null,
                                        onToggleChanged: _onGaugeToggleChanged,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () => setState(
                                            () => _selectedMode =
                                                _InputMode.manual,
                                          ),
                                          style: ButtonStyle(
                                            minimumSize:
                                                const WidgetStatePropertyAll(
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
                                          icon: const Icon(Icons.edit_note),
                                          label: Text(
                                            translate('manual_entry', locale),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => setState(
                                            () => _selectedMode =
                                                _selectedMode ==
                                                        _InputMode.raspberry
                                                    ? _InputMode.none
                                                    : _InputMode.raspberry,
                                          ),
                                          style: ButtonStyle(
                                            minimumSize:
                                                const WidgetStatePropertyAll(
                                              Size.fromHeight(48),
                                            ),
                                            foregroundColor:
                                                const WidgetStatePropertyAll(
                                              Colors.white,
                                            ),
                                            backgroundColor: _selectedMode ==
                                                    _InputMode.raspberry
                                                ? WidgetStatePropertyAll(
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.3),
                                                  )
                                                : null,
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
                                          icon: const Icon(Icons.sensors),
                                          label: const Text('ESP8266'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: _kReportsSectionGap),
                            // Manual Data Input - cam efekti (blur) + yarı saydam siyah zemin
                            if (_selectedMode == _InputMode.manual)
                              Padding(
                                padding: _kReportsSectionOuterPadding,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 18, sigmaY: 18),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.28),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Padding(
                                        padding: _kReportsCardInnerPadding,
                                        child: ConsumptionForm(
                                          onCalculated: (valueKgCo2e) {
                                            setState(() {
                                              _manualCalculatedKgCo2e =
                                                  valueKgCo2e;
                                              // Eğer manuel veri seçiliyse, gauge'ı güncelle
                                              if (!_useEspData) {
                                                _lastCalculatedKgCo2e =
                                                    valueKgCo2e;
                                                // Grafikteki bugünün değerini de güncelle (manuel veriler listesine)
                                                if (_manualDailyEmissions
                                                        .length ==
                                                    7) {
                                                  _manualDailyEmissions[6] =
                                                      valueKgCo2e;
                                                  debugPrint(
                                                    '📊 Manuel hesaplama: Manuel grafikteki bugünün değeri güncellendi: ${valueKgCo2e.toStringAsFixed(2)} kg CO2e',
                                                  );
                                                }
                                              }
                                              _syncGaugeToLiveEmissionService();
                                            });
                                          },
                                          onEntryCalculated:
                                              (valueKgCo2e, entry) {
                                            // Manuel entry'yi sakla (kategori dağılımı için)
                                            setState(() {
                                              _manualEntry = entry;
                                              _manualCalculatedKgCo2e =
                                                  valueKgCo2e;
                                              // Eğer manuel veri seçiliyse, kategori dağılımını güncelle
                                              if (!_useEspData) {
                                                _updateCategoryDistributionFromEntry(
                                                    entry);
                                              }
                                            });
                                          },
                                          languageProvider:
                                              widget.languageProvider,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // ESP8266 + Shelly: E (ESP/Shelly) seçiliyken her zaman; ayrıca ESP8266 butonuna basılırsa da
                            if (_selectedMode == _InputMode.raspberry ||
                                _useEspData) ...[
                              Padding(
                                padding: _kReportsSectionOuterPadding,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: BackdropFilter(
                                    filter:
                                        ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Padding(
                                        padding: _kReportsCardInnerPadding,
                                        child: RealtimeEspDataWidget(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: _kReportsSectionGap),
                              // Shelly Plug S Anlık Veriler - ESP'nin altında
                              Padding(
                                padding: _kReportsSectionOuterPadding,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: BackdropFilter(
                                    filter:
                                        ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.1),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.25),
                                            blurRadius: 12,
                                            spreadRadius: 0,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: _kReportsCardInnerPadding,
                                        child: RealtimeShellyDataWidget(
                                          apiService: _apiService,
                                          deviceId: _shellyDeviceId,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: _kReportsSectionGap),
                            Padding(
                              padding: _kReportsSectionOuterPadding,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: ClipRect(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 8, sigmaY: 8),
                                        child: Container(
                                          color: Colors.black
                                              .withValues(alpha: 0.12),
                                          child: Padding(
                                            padding: _kReportsCardInnerPadding,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            _showGlobalTrend
                                                                ? translate(
                                                                    'global_trend',
                                                                    locale)
                                                                : translate(
                                                                    'daily_trends',
                                                                    locale),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: headerStyle,
                                                          ),
                                                        ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            alignment: Alignment
                                                                .centerRight,
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                IconButton(
                                                                  onPressed:
                                                                      () {
                                                                    if (_showGlobalTrend) {
                                                                      _loadGlobalTrendData();
                                                                    } else {
                                                                      _loadTrendData();
                                                                    }
                                                                  },
                                                                  icon:
                                                                      const Icon(
                                                                    Icons
                                                                        .refresh,
                                                                    size: 20,
                                                                  ),
                                                                  color: Colors
                                                                      .white70,
                                                                  tooltip:
                                                                      translate(
                                                                    'refresh',
                                                                    locale,
                                                                  ),
                                                                  visualDensity:
                                                                      const VisualDensity(
                                                                    horizontal:
                                                                        -3,
                                                                    vertical:
                                                                        -3,
                                                                  ),
                                                                  constraints:
                                                                      const BoxConstraints(
                                                                    minWidth:
                                                                        30,
                                                                    minHeight:
                                                                        30,
                                                                  ),
                                                                  padding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                ),
                                                                const SizedBox(
                                                                    width: 12),
                                                                Text(
                                                                  _showGlobalTrend
                                                                      ? translate(
                                                                          'global_trend',
                                                                          locale)
                                                                      : translate(
                                                                          'personal_trend',
                                                                          locale),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      subStyle,
                                                                ),
                                                                const SizedBox(
                                                                    width: 10),
                                                                Transform.scale(
                                                                  scale: 0.92,
                                                                  child: Switch(
                                                                    value:
                                                                        _showGlobalTrend,
                                                                    onChanged:
                                                                        (value) {
                                                                      setState(
                                                                          () {
                                                                        _showGlobalTrend =
                                                                            value;
                                                                      });
                                                                    },
                                                                    activeThumbColor:
                                                                        Colors
                                                                            .green,
                                                                    materialTapTargetSize:
                                                                        MaterialTapTargetSize
                                                                            .shrinkWrap,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Divider(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.3),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    // Çizgi grafiği
                                                    _isLoadingTrends
                                                        ? const SizedBox(
                                                            height: 200,
                                                            child: Center(
                                                              child:
                                                                  CircularProgressIndicator(),
                                                            ),
                                                          )
                                                        : (((_showGlobalTrend
                                                                            ? _globalDailyTrends
                                                                            : (_useEspData
                                                                                ? _dailyEmissions
                                                                                : _manualDailyEmissions))
                                                                        .isEmpty ||
                                                                    (_showGlobalTrend
                                                                            ? _globalDailyTrends
                                                                            : (_useEspData
                                                                                ? _dailyEmissions
                                                                                : _manualDailyEmissions))
                                                                        .every((e) =>
                                                                            e ==
                                                                            0)) &&
                                                                !(_showCountryComparison &&
                                                                    !_showGlobalTrend &&
                                                                    _countryTrends
                                                                        .isNotEmpty))
                                                            ? SizedBox(
                                                                height: 200,
                                                                child: Center(
                                                                  child: Text(
                                                                    translate(
                                                                        'no_data_available',
                                                                        locale),
                                                                    style:
                                                                        subStyle,
                                                                  ),
                                                                ),
                                                              )
                                                            : Builder(
                                                                key: ValueKey(
                                                                    'trend_chart_${_useEspData}_$_showGlobalTrend$_weekOffset'), // Hafta / mod değişince yeniden çiz
                                                                builder:
                                                                    (context) {
                                                                  List<double>
                                                                      ensureSevenDays(
                                                                          List<double>
                                                                              values) {
                                                                    final safe =
                                                                        values
                                                                            .map(
                                                                              (e) => _toDoubleSafe(e),
                                                                            )
                                                                            .toList();
                                                                    if (safe.length >=
                                                                        7) {
                                                                      return safe.sublist(
                                                                          safe.length -
                                                                              7);
                                                                    }
                                                                    return [
                                                                      ...List<double>.filled(
                                                                          7 - safe.length,
                                                                          0.0),
                                                                      ...safe,
                                                                    ];
                                                                  }

                                                                  double toPerCapitaDailyKg(
                                                                      double
                                                                          value) {
                                                                    if (value <=
                                                                        0) {
                                                                      return 0.0;
                                                                    }
                                                                    // Heuristik dönüşüm:
                                                                    // Çok büyük değerleri dünya toplamından kişi başı günlük ortalamaya çevir.
                                                                    // 8 milyar kişi varsayımıyla.
                                                                    if (value >
                                                                        1000000000) {
                                                                      return value /
                                                                          8000000000;
                                                                    }
                                                                    // Milyon ton/yıl benzeri seri için kişi başı günlük yaklaşıma indirgeme.
                                                                    if (value >
                                                                        1000) {
                                                                      return value /
                                                                          2920.0;
                                                                    }
                                                                    return value;
                                                                  }

                                                                  final selectedPersonalDaily =
                                                                      _useEspData
                                                                          ? _dailyEmissions
                                                                          : _manualDailyEmissions;
                                                                  final personalSeries =
                                                                      ensureSevenDays(
                                                                    selectedPersonalDaily
                                                                        .map((e) =>
                                                                            _toDoubleSafe(e))
                                                                        .toList(),
                                                                  );
                                                                  // Gauge'da gösterilen güncel değer ile grafikteki bugünün değeri senkron olsun.
                                                                  final double?
                                                                      todayPersonalValue =
                                                                      _lastCalculatedKgCo2e ??
                                                                          (_useEspData
                                                                              ? null
                                                                              : _manualCalculatedKgCo2e);
                                                                  if (_weekOffset !=
                                                                          -1 &&
                                                                      todayPersonalValue !=
                                                                          null &&
                                                                      personalSeries
                                                                              .length ==
                                                                          7) {
                                                                    personalSeries[
                                                                            6] =
                                                                        _toDoubleSafe(
                                                                            todayPersonalValue);
                                                                  }

                                                                  final globalRawSeries =
                                                                      ensureSevenDays(
                                                                    _globalDailyTrends
                                                                        .map((e) =>
                                                                            _toDoubleSafe(e))
                                                                        .toList(),
                                                                  );
                                                                  final globalPerCapitaSeries =
                                                                      globalRawSeries
                                                                          .map(
                                                                            (e) =>
                                                                                toPerCapitaDailyKg(e),
                                                                          )
                                                                          .toList();

                                                                  List<double>
                                                                      globalPlottedSeries =
                                                                      globalPerCapitaSeries;
                                                                  List<double>
                                                                      personalPlottedSeries =
                                                                      personalSeries;

                                                                  if (_showGlobalTrend) {
                                                                    final combined =
                                                                        [
                                                                      ...globalPerCapitaSeries,
                                                                      ...personalSeries,
                                                                    ];
                                                                    final minCombined = combined.reduce((a,
                                                                            b) =>
                                                                        a < b
                                                                            ? a
                                                                            : b);
                                                                    final maxCombined = combined.reduce((a,
                                                                            b) =>
                                                                        a > b
                                                                            ? a
                                                                            : b);
                                                                    final range =
                                                                        (maxCombined -
                                                                                minCombined)
                                                                            .abs();
                                                                    if (range >
                                                                        0) {
                                                                      globalPlottedSeries = globalPerCapitaSeries
                                                                          .map((e) =>
                                                                              ((e - minCombined) / range) *
                                                                              100.0)
                                                                          .toList();
                                                                      personalPlottedSeries = personalSeries
                                                                          .map((e) =>
                                                                              ((e - minCombined) / range) *
                                                                              100.0)
                                                                          .toList();
                                                                      // Çok düşük ama sıfır olmayan kişisel değerleri görünür tut.
                                                                      personalPlottedSeries = personalPlottedSeries
                                                                          .asMap()
                                                                          .entries
                                                                          .map(
                                                                              (entry) {
                                                                        final rawValue =
                                                                            personalSeries[entry.key];
                                                                        final plotted =
                                                                            entry.value;
                                                                        if (rawValue >
                                                                                0 &&
                                                                            plotted <
                                                                                1.0) {
                                                                          return 1.0;
                                                                        }
                                                                        return plotted;
                                                                      }).toList();
                                                                    } else {
                                                                      globalPlottedSeries =
                                                                          List<double>.filled(
                                                                              7,
                                                                              50.0);
                                                                      personalPlottedSeries =
                                                                          List<double>.filled(
                                                                              7,
                                                                              50.0);
                                                                    }
                                                                  }

                                                                  // Ana seri: global modda dünya verisi, kişisel modda kişisel veri
                                                                  final normalizedData =
                                                                      _showGlobalTrend
                                                                          ? globalPlottedSeries
                                                                          : personalSeries;

                                                                  // Maksimum değeri hesapla (kullanıcı + ülke verileri)
                                                                  final allValues =
                                                                      [
                                                                    ...normalizedData,
                                                                    if (_showGlobalTrend)
                                                                      ...personalPlottedSeries,
                                                                    if (_showCountryComparison &&
                                                                        !_showGlobalTrend)
                                                                      ..._countryTrends
                                                                          .values
                                                                          .expand((e) =>
                                                                              e),
                                                                  ];

                                                                  // Debug: Değerleri logla
                                                                  final userMax = normalizedData
                                                                          .isNotEmpty
                                                                      ? normalizedData.reduce((a,
                                                                              b) =>
                                                                          a > b
                                                                              ? a
                                                                              : b)
                                                                      : 0.0;
                                                                  final userMin = normalizedData
                                                                          .isNotEmpty
                                                                      ? normalizedData
                                                                          .where((e) =>
                                                                              e >
                                                                              0)
                                                                          .fold(
                                                                              double.infinity,
                                                                              (a, b) => a < b ? a : b)
                                                                      : 0.0;
                                                                  final userAvg = normalizedData
                                                                          .isNotEmpty
                                                                      ? normalizedData.reduce((a, b) =>
                                                                              a +
                                                                              b) /
                                                                          normalizedData
                                                                              .length
                                                                      : 0.0;

                                                                  debugPrint(
                                                                      '📊 Kullanıcı Verileri Analizi:');
                                                                  debugPrint(
                                                                      '   Min: ${userMin.toStringAsFixed(2)} kg CO2e');
                                                                  debugPrint(
                                                                      '   Max: ${userMax.toStringAsFixed(2)} kg CO2e');
                                                                  debugPrint(
                                                                      '   Ortalama: ${userAvg.toStringAsFixed(2)} kg CO2e');
                                                                  debugPrint(
                                                                      '   Tüm değerler: ${normalizedData.map((e) => e.toStringAsFixed(2)).join(", ")}');

                                                                  if (_showCountryComparison &&
                                                                      !_showGlobalTrend &&
                                                                      _countryTrends
                                                                          .isNotEmpty) {
                                                                    final countryMax = _countryTrends
                                                                        .values
                                                                        .expand(
                                                                            (e) =>
                                                                                e)
                                                                        .fold(
                                                                            0.0,
                                                                            (a, b) => a > b
                                                                                ? a
                                                                                : b);
                                                                    debugPrint(
                                                                        '📈 Ülke max: $countryMax kg CO2e');
                                                                  }

                                                                  // Grafik ölçeğini hesapla
                                                                  // Kullanıcı verilerinin max değerini kullan, ama çok yüksekse sınırla
                                                                  double maxY;
                                                                  if (allValues
                                                                          .isEmpty ||
                                                                      allValues.every(
                                                                          (e) =>
                                                                              e ==
                                                                              0)) {
                                                                    maxY =
                                                                        _showGlobalTrend
                                                                            ? 100
                                                                            : 10;
                                                                  } else {
                                                                    final maxValue = allValues.reduce((a,
                                                                            b) =>
                                                                        a > b
                                                                            ? a
                                                                            : b);

                                                                    // Ülke çizgileri için offset hesapla (eğer ülke karşılaştırması açıksa)
                                                                    // Offset'ler maxY'ye bağlı olduğu için iteratif hesaplama yapıyoruz
                                                                    double
                                                                        maxOffset =
                                                                        0.0;
                                                                    if (_showCountryComparison &&
                                                                        !_showGlobalTrend &&
                                                                        _countryTrends
                                                                            .isNotEmpty) {
                                                                      // İteratif hesaplama: offset'ler maxY'ye bağlı, maxY offset'e bağlı
                                                                      // İlk tahmin: maxValue'ya göre maxY tahmin et (offset olmadan)
                                                                      double tempMaxY = maxValue > 100
                                                                          ? (maxValue *
                                                                              1.15)
                                                                          : (maxValue *
                                                                              1.2);

                                                                      // İkinci iterasyon: Offset'i hesapla ve maxY'yi güncelle
                                                                      for (int i =
                                                                              0;
                                                                          i < 3;
                                                                          i++) {
                                                                        // 3 iterasyon yeterli
                                                                        final baseOffset =
                                                                            tempMaxY *
                                                                                0.08;
                                                                        maxOffset =
                                                                            baseOffset *
                                                                                5.0; // İngiltere offset'i (en yüksek)

                                                                        // Offset'i hesaba katarak maxY'yi yeniden hesapla
                                                                        tempMaxY = maxValue > 100
                                                                            ? ((maxValue + maxOffset) *
                                                                                1.15)
                                                                            : ((maxValue + maxOffset) *
                                                                                1.2);
                                                                      }

                                                                      // Son offset değerini al
                                                                      final finalBaseOffset =
                                                                          tempMaxY *
                                                                              0.08;
                                                                      maxOffset =
                                                                          finalBaseOffset *
                                                                              5.0;
                                                                    }

                                                                    // Eğer max değer çok yüksekse (100+ kg), grafik ölçeğini optimize et
                                                                    if (_showGlobalTrend) {
                                                                      maxY =
                                                                          100.0;
                                                                    } else if (maxValue >
                                                                        100) {
                                                                      // Çok yüksek değerler için daha iyi ölçeklendirme
                                                                      // Max değerin %15'i kadar padding ekle + offset için ekstra alan
                                                                      maxY = ((maxValue + maxOffset) *
                                                                              1.15)
                                                                          .clamp(
                                                                              1.0,
                                                                              double.infinity);
                                                                      debugPrint(
                                                                          '⚠️ Yüksek değer tespit edildi (${maxValue.toStringAsFixed(2)} kg), offset: ${maxOffset.toStringAsFixed(2)}, ölçek optimize edildi: maxY=$maxY');
                                                                    } else {
                                                                      // Normal değerler için standart padding (%20) + offset için ekstra alan
                                                                      maxY = ((maxValue + maxOffset) *
                                                                              1.2)
                                                                          .clamp(
                                                                              1.0,
                                                                              double.infinity);
                                                                      debugPrint(
                                                                          '📊 Normal değer, offset: ${maxOffset.toStringAsFixed(2)}, maxY=$maxY');
                                                                    }
                                                                  }

                                                                  const double
                                                                      minY =
                                                                      0.0;
                                                                  final yRange =
                                                                      (maxY - minY)
                                                                          .abs();
                                                                  final yInterval =
                                                                      yRange > 0
                                                                          ? yRange /
                                                                              5
                                                                          : 1.0;

                                                                  debugPrint(
                                                                      '📈 Grafik maxY: $maxY, minY: $minY (kullanıcı verileri: ${normalizedData.length} nokta)');

                                                                  final hasUserData =
                                                                      normalizedData.any(
                                                                          (e) =>
                                                                              e >
                                                                              0);
                                                                  final hasCountryData = _showCountryComparison &&
                                                                      !_showGlobalTrend &&
                                                                      _countryTrends
                                                                          .isNotEmpty;

                                                                  return Stack(
                                                                    clipBehavior:
                                                                        Clip.none,
                                                                    children: [
                                                                      SizedBox(
                                                                        height:
                                                                            200,
                                                                        child:
                                                                            LineChart(
                                                                          LineChartData(
                                                                            lineTouchData:
                                                                                LineTouchData(
                                                                              enabled: true,
                                                                              touchTooltipData: LineTouchTooltipData(
                                                                                getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                                                                  if (_showGlobalTrend) {
                                                                                    final rawIndex = touchedSpots.first.x.toInt();
                                                                                    final pointIndex = rawIndex.clamp(0, 6);
                                                                                    final personalRawKg = personalSeries[pointIndex];
                                                                                    final personalText = personalRawKg < 1 ? '${(personalRawKg * 1000).toStringAsFixed(3)} g' : '${personalRawKg.toStringAsFixed(3)} kg';
                                                                                    final List<LineTooltipItem> items = [
                                                                                      LineTooltipItem(
                                                                                        'Dünya Geneli: ${globalPerCapitaSeries[pointIndex].toStringAsFixed(2)}',
                                                                                        const TextStyle(
                                                                                          color: Color(0xFFFFF176),
                                                                                          fontWeight: FontWeight.bold,
                                                                                          fontSize: 12,
                                                                                        ),
                                                                                      ),
                                                                                      LineTooltipItem(
                                                                                        '\n${_weekOffset == -1 ? "Tahmini — " : ""}Sizin Veriniz: $personalText',
                                                                                        const TextStyle(
                                                                                          color: Colors.pinkAccent,
                                                                                          fontWeight: FontWeight.bold,
                                                                                          fontSize: 12,
                                                                                        ),
                                                                                      ),
                                                                                    ];
                                                                                    return items;
                                                                                  }

                                                                                  return touchedSpots.map((LineBarSpot touchedSpot) {
                                                                                    final lineIndex = touchedSpot.barIndex;
                                                                                    String label;
                                                                                    Color color;
                                                                                    final userLineIndex = hasCountryData ? _countryTrends.length : 0;
                                                                                    if (hasUserData && lineIndex == userLineIndex) {
                                                                                      label = _weekOffset == -1 ? 'Tahmini (gelecek hafta)' : 'Sizin Verileriniz';
                                                                                      color = Colors.pinkAccent;
                                                                                    } else {
                                                                                      final countryNames = _countryTrends.keys.toList();
                                                                                      final countryIndex = lineIndex;
                                                                                      if (countryIndex < countryNames.length) {
                                                                                        label = countryNames[countryIndex];
                                                                                        color = _getCountryColor(countryNames[countryIndex]);
                                                                                      } else {
                                                                                        label = 'Veri';
                                                                                        color = Colors.grey;
                                                                                      }
                                                                                    }
                                                                                    final value = touchedSpot.y.toStringAsFixed(1);
                                                                                    return LineTooltipItem(
                                                                                      '$label: $value',
                                                                                      TextStyle(
                                                                                        color: color,
                                                                                        fontWeight: FontWeight.bold,
                                                                                        fontSize: 12,
                                                                                      ),
                                                                                    );
                                                                                  }).toList();
                                                                                },
                                                                                tooltipBgColor: Colors.black.withValues(alpha: 0.95),
                                                                                tooltipRoundedRadius: 8,
                                                                                tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                                                tooltipMargin: 4,
                                                                                fitInsideHorizontally: true,
                                                                                fitInsideVertically: true,
                                                                              ),
                                                                              handleBuiltInTouches: true,
                                                                            ),
                                                                            gridData:
                                                                                FlGridData(
                                                                              show: true,
                                                                              drawVerticalLine: true,
                                                                              horizontalInterval: yInterval,
                                                                              verticalInterval: 1,
                                                                              getDrawingHorizontalLine: (value) {
                                                                                return FlLine(
                                                                                  color: Colors.white.withValues(
                                                                                    alpha: 0.1,
                                                                                  ),
                                                                                  strokeWidth: 1,
                                                                                );
                                                                              },
                                                                              getDrawingVerticalLine: (value) {
                                                                                return FlLine(
                                                                                  color: Colors.white.withValues(
                                                                                    alpha: 0.1,
                                                                                  ),
                                                                                  strokeWidth: 1,
                                                                                );
                                                                              },
                                                                            ),
                                                                            titlesData:
                                                                                FlTitlesData(
                                                                              show: true,
                                                                              rightTitles: const AxisTitles(
                                                                                sideTitles: SideTitles(
                                                                                  showTitles: false,
                                                                                ),
                                                                              ),
                                                                              topTitles: const AxisTitles(
                                                                                sideTitles: SideTitles(
                                                                                  showTitles: false,
                                                                                ),
                                                                              ),
                                                                              bottomTitles: AxisTitles(
                                                                                sideTitles: SideTitles(
                                                                                  showTitles: true,
                                                                                  reservedSize: 34,
                                                                                  interval: 1,
                                                                                  getTitlesWidget: (
                                                                                    double value,
                                                                                    TitleMeta meta,
                                                                                  ) {
                                                                                    final axisDayStyle = subStyle;
                                                                                    Widget text;
                                                                                    switch (value.toInt()) {
                                                                                      case 0:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'mon',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      case 1:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'tue',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      case 2:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'wed',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      case 3:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'thu',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      case 4:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'fri',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      case 5:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'sat',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      case 6:
                                                                                        text = Text(
                                                                                          translate(
                                                                                            'sun',
                                                                                            locale,
                                                                                          ),
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                      default:
                                                                                        text = Text(
                                                                                          '',
                                                                                          style: axisDayStyle,
                                                                                        );
                                                                                        break;
                                                                                    }
                                                                                    return SideTitleWidget(
                                                                                      axisSide: meta.axisSide,
                                                                                      space: 8,
                                                                                      child: text,
                                                                                    );
                                                                                  },
                                                                                ),
                                                                              ),
                                                                              leftTitles: AxisTitles(
                                                                                sideTitles: SideTitles(
                                                                                  showTitles: true,
                                                                                  interval: yInterval,
                                                                                  getTitlesWidget: (
                                                                                    double value,
                                                                                    TitleMeta meta,
                                                                                  ) {
                                                                                    String label;
                                                                                    if (_showGlobalTrend) {
                                                                                      label = '${value.toInt()}%';
                                                                                    } else {
                                                                                      // Sadece sayı göster (birim yok)
                                                                                      label = '${value.toInt()}';
                                                                                    }
                                                                                    return Padding(
                                                                                      padding: const EdgeInsets.only(right: 8),
                                                                                      child: Text(
                                                                                        label,
                                                                                        style: subStyle.copyWith(
                                                                                          shadows: const [
                                                                                            Shadow(
                                                                                              color: Colors.black,
                                                                                              blurRadius: 3,
                                                                                              offset: Offset(1, 1),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                        textAlign: TextAlign.right,
                                                                                      ),
                                                                                    );
                                                                                  },
                                                                                  reservedSize: 50,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            borderData:
                                                                                FlBorderData(
                                                                              show: true,
                                                                              border: Border.all(
                                                                                color: Colors.white.withValues(alpha: 0.2),
                                                                              ),
                                                                            ),
                                                                            minX:
                                                                                0,
                                                                            maxX:
                                                                                6,
                                                                            minY:
                                                                                minY,
                                                                            maxY:
                                                                                maxY.toDouble(),
                                                                            lineBarsData: [
                                                                              if (_showGlobalTrend && normalizedData.isNotEmpty)
                                                                                LineChartBarData(
                                                                                  spots: List.generate(
                                                                                    7,
                                                                                    (index) => FlSpot(
                                                                                      index.toDouble(),
                                                                                      normalizedData.isNotEmpty && index < normalizedData.length ? _toDoubleSafe(normalizedData[index]).clamp(0.0, double.infinity) : 0.0,
                                                                                    ),
                                                                                  ),
                                                                                  isCurved: true,
                                                                                  gradient: const LinearGradient(
                                                                                    colors: [
                                                                                      Color(0xFFFFF176),
                                                                                      Color(0xFFFFE082),
                                                                                    ],
                                                                                  ),
                                                                                  barWidth: 4.0,
                                                                                  isStrokeCapRound: true,
                                                                                  dotData: FlDotData(
                                                                                    show: true,
                                                                                    getDotPainter: (
                                                                                      spot,
                                                                                      percent,
                                                                                      barData,
                                                                                      index,
                                                                                    ) {
                                                                                      return FlDotCirclePainter(
                                                                                        radius: 5,
                                                                                        color: const Color(0xFFFFF176),
                                                                                        strokeWidth: 2.0,
                                                                                        strokeColor: const Color(0xFF222222),
                                                                                      );
                                                                                    },
                                                                                  ),
                                                                                  belowBarData: BarAreaData(
                                                                                    show: true,
                                                                                    gradient: LinearGradient(
                                                                                      colors: [
                                                                                        const Color(0xFFFFF176).withValues(alpha: 0.18),
                                                                                        const Color(0xFFFFE082).withValues(alpha: 0.06),
                                                                                      ],
                                                                                      begin: Alignment.topCenter,
                                                                                      end: Alignment.bottomCenter,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              // Ülke karşılaştırma çizgileri
                                                                              if (hasCountryData)
                                                                                ..._buildCountryLines(normalizedData, maxY.toDouble()),
                                                                              // Kullanıcının kendi verileri (en üst katman)
                                                                              if (hasUserData || _showGlobalTrend)
                                                                                LineChartBarData(
                                                                                  spots: List.generate(
                                                                                    7,
                                                                                    (index) => FlSpot(
                                                                                      index.toDouble(),
                                                                                      personalPlottedSeries.isNotEmpty && index < personalPlottedSeries.length ? _toDoubleSafe(personalPlottedSeries[index]).clamp(0.0, double.infinity) : 0.0,
                                                                                    ),
                                                                                  ),
                                                                                  isCurved: true,
                                                                                  gradient: const LinearGradient(
                                                                                    colors: [
                                                                                      Colors.pinkAccent,
                                                                                      Colors.pink,
                                                                                    ],
                                                                                  ),
                                                                                  barWidth: 4.8,
                                                                                  isStrokeCapRound: true,
                                                                                  dashArray: _weekOffset == -1 ? const <int>[10, 7] : null,
                                                                                  dotData: FlDotData(
                                                                                    show: true,
                                                                                    getDotPainter: (
                                                                                      spot,
                                                                                      percent,
                                                                                      barData,
                                                                                      index,
                                                                                    ) {
                                                                                      return FlDotCirclePainter(
                                                                                        radius: 5,
                                                                                        color: Colors.pinkAccent,
                                                                                        strokeWidth: 2.2,
                                                                                        strokeColor: const Color(0xFF222222),
                                                                                      );
                                                                                    },
                                                                                  ),
                                                                                  belowBarData: BarAreaData(
                                                                                    show: _weekOffset != -1,
                                                                                    gradient: LinearGradient(
                                                                                      colors: [
                                                                                        Colors.pinkAccent.withValues(alpha: 0.18),
                                                                                        Colors.pink.withValues(alpha: 0.06),
                                                                                      ],
                                                                                      begin: Alignment.topCenter,
                                                                                      end: Alignment.bottomCenter,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  );
                                                                },
                                                              ),
                                                    if (!_showGlobalTrend) ...[
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          IconButton(
                                                            onPressed: () {
                                                              setState(() {
                                                                _weekOffset +=
                                                                    1;
                                                              });
                                                              _loadTrendData();
                                                            },
                                                            tooltip:
                                                                'Önceki hafta',
                                                            icon: const Icon(
                                                              Icons
                                                                  .arrow_back_ios_new,
                                                              size: 18,
                                                            ),
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                          Text(
                                                            _weekOffset == -1
                                                                ? 'Gelecek hafta (tahmini)'
                                                                : _weekOffset ==
                                                                        0
                                                                    ? 'Bu hafta'
                                                                    : '$_weekOffset. hafta önce',
                                                            style: subStyle,
                                                          ),
                                                          IconButton(
                                                            onPressed:
                                                                _weekOffset > -1
                                                                    ? () {
                                                                        setState(
                                                                            () {
                                                                          _weekOffset -=
                                                                              1;
                                                                        });
                                                                        _loadTrendData();
                                                                      }
                                                                    : null,
                                                            tooltip:
                                                                'Sonraki hafta',
                                                            icon: const Icon(
                                                              Icons
                                                                  .arrow_forward_ios,
                                                              size: 18,
                                                            ),
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                    // Legend (açıklama) - ülke çizgileri için
                                                    if (_showCountryComparison &&
                                                        !_showGlobalTrend &&
                                                        _countryTrends
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                top: 12,
                                                                bottom: 8),
                                                        child: Wrap(
                                                          spacing: 16,
                                                          runSpacing: 8,
                                                          alignment:
                                                              WrapAlignment
                                                                  .center,
                                                          children: [
                                                            // Kullanıcının kendi verisi
                                                            if ((_showGlobalTrend
                                                                        ? _globalDailyTrends
                                                                        : (_useEspData
                                                                            ? _dailyEmissions
                                                                            : _manualDailyEmissions))
                                                                    .any((e) =>
                                                                        e >
                                                                        0) ||
                                                                (_useEspData
                                                                        ? _lastCalculatedKgCo2e
                                                                        : _manualCalculatedKgCo2e) !=
                                                                    null)
                                                              _buildLegendItem(
                                                                _weekOffset ==
                                                                        -1
                                                                    ? 'Sizin Verileriniz (tahmini)'
                                                                    : 'Sizin Verileriniz',
                                                                Colors
                                                                    .pinkAccent,
                                                                labelStyle:
                                                                    subStyle,
                                                              ),
                                                            // Ülke verileri
                                                            ..._countryTrends
                                                                .keys
                                                                .map(
                                                              (countryName) =>
                                                                  _buildLegendItem(
                                                                countryName,
                                                                _getCountryColor(
                                                                    countryName),
                                                                labelStyle:
                                                                    subStyle,
                                                                isRealData:
                                                                    _countryDataSources[
                                                                            countryName] ??
                                                                        false,
                                                                showDataSourceIcon:
                                                                    false,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    // Veri kaynağı açıklaması
                                                    if (_showCountryComparison &&
                                                        !_showGlobalTrend &&
                                                        _countryTrends
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                top: 4,
                                                                bottom: 8),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Container(
                                                              width: 14,
                                                              height: 3,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .pinkAccent,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            2),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 5),
                                                            Text(
                                                              translate(
                                                                'real_data',
                                                                locale,
                                                              ),
                                                              style: subStyle,
                                                            ),
                                                            const SizedBox(
                                                                width: 14),
                                                            _legendDashedSwatch(
                                                              Colors
                                                                  .orangeAccent,
                                                              barHeight: 3,
                                                            ),
                                                            const SizedBox(
                                                                width: 5),
                                                            Text(
                                                              translate(
                                                                'estimated_data',
                                                                locale,
                                                              ),
                                                              style: subStyle,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      _showGlobalTrend
                                                          ? translate(
                                                              'global_trend_description',
                                                              locale)
                                                          : translate(
                                                              'last_7_days_trend',
                                                              locale),
                                                      textAlign:
                                                          TextAlign.start,
                                                      style: subStyle,
                                                    ),
                                                    // Y ekseni açıklaması
                                                    if (!_showGlobalTrend)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 4),
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Text(
                                                            'X ekseni: Son 7 gün (Pzt-Paz)  |  Y ekseni: kg CO2e',
                                                            style: subStyle,
                                                            textAlign:
                                                                TextAlign.start,
                                                          ),
                                                        ),
                                                      ),
                                                    if (_showGlobalTrend)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 4),
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Text(
                                                            'X ekseni: Son 7 gün (Pzt-Paz)  |  Y ekseni: normalize endeks (%)',
                                                            style: subStyle,
                                                            textAlign:
                                                                TextAlign.start,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: _kReportsSectionGap),
                            Padding(
                              padding: _kReportsSectionOuterPadding,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    child: Padding(
                                      padding: _kReportsCardInnerPadding,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  translate(
                                                    'category_distribution',
                                                    locale,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: headerStyle,
                                                ),
                                              ),
                                              _ReportsRoundInfoIcon(
                                                onTap: () =>
                                                    _showCategoryDistributionInfoDialog(
                                                  context,
                                                  locale,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Divider(
                                            color: Colors.white
                                                .withValues(alpha: 0.3),
                                          ),
                                          const SizedBox(height: 8),
                                          LayoutBuilder(
                                            builder:
                                                (context, chartConstraints) {
                                              final bool compactChart =
                                                  chartConstraints.maxWidth <
                                                      430;
                                              final double pieSize =
                                                  compactChart
                                                      ? (chartConstraints
                                                                  .maxWidth *
                                                              0.55)
                                                          .clamp(130.0, 180.0)
                                                      : 180.0;

                                              final bool includeWasteSlice =
                                                  !_useEspData;
                                              final List<PieChartSectionData>
                                                  pieSections = [
                                                // Elektrik - Turuncu
                                                PieChartSectionData(
                                                  color: Colors.orange,
                                                  value:
                                                      activeCategoryDistribution[
                                                              'electricity'] ??
                                                          0.0,
                                                  title: (activeCategoryDistribution[
                                                                  'electricity'] ??
                                                              0.0) >
                                                          0
                                                      ? '${_formatPercent(activeCategoryDistribution['electricity'] ?? 0.0)}%'
                                                      : '',
                                                  radius: 50,
                                                  titleStyle: subStyle.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                // Su - Mavi
                                                PieChartSectionData(
                                                  color: Colors.blue,
                                                  value:
                                                      activeCategoryDistribution[
                                                              'water'] ??
                                                          0.0,
                                                  title: (activeCategoryDistribution[
                                                                  'water'] ??
                                                              0.0) >
                                                          0
                                                      ? '${_formatPercent(activeCategoryDistribution['water'] ?? 0.0)}%'
                                                      : '',
                                                  radius: 50,
                                                  titleStyle: subStyle.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                // Gaz — #47009C
                                                PieChartSectionData(
                                                  color:
                                                      const Color(0xFF47009C),
                                                  value:
                                                      activeCategoryDistribution[
                                                              'gas'] ??
                                                          0.0,
                                                  title: (activeCategoryDistribution[
                                                                  'gas'] ??
                                                              0.0) >
                                                          0
                                                      ? '${_formatPercent(activeCategoryDistribution['gas'] ?? 0.0)}%'
                                                      : '',
                                                  radius: 50,
                                                  titleStyle: subStyle.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ];
                                              if (includeWasteSlice) {
                                                pieSections.add(
                                                  PieChartSectionData(
                                                    color: const Color(
                                                      0xFF6D4C41,
                                                    ),
                                                    value:
                                                        activeCategoryDistribution[
                                                                'waste'] ??
                                                            0.0,
                                                    title: (activeCategoryDistribution[
                                                                    'waste'] ??
                                                                0.0) >
                                                            0
                                                        ? '${_formatPercent(activeCategoryDistribution['waste'] ?? 0.0)}%'
                                                        : '',
                                                    radius: 50,
                                                    titleStyle:
                                                        subStyle.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                );
                                              }

                                              final Widget pieChart = SizedBox(
                                                width: pieSize,
                                                height: pieSize,
                                                child: PieChart(
                                                  PieChartData(
                                                    pieTouchData: PieTouchData(
                                                      touchCallback: (
                                                        FlTouchEvent event,
                                                        pieTouchResponse,
                                                      ) {
                                                        // Dokunma etkileşimi
                                                      },
                                                    ),
                                                    borderData: FlBorderData(
                                                      show: false,
                                                    ),
                                                    sectionsSpace: 2,
                                                    centerSpaceRadius: 40,
                                                    sections: pieSections,
                                                  ),
                                                ),
                                              );

                                              final Widget legend = Column(
                                                crossAxisAlignment: compactChart
                                                    ? CrossAxisAlignment.center
                                                    : CrossAxisAlignment.start,
                                                children: [
                                                  _LegendDot(
                                                    label:
                                                        '${translate('electricity_label', locale)}${_selectedLegendCategory == 'electricity' ? ' (${_formatPercent(activeCategoryDistribution['electricity'] ?? 0.0)}%)' : ''}',
                                                    color: Colors.orange,
                                                    labelStyle: subStyle,
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedLegendCategory =
                                                            _selectedLegendCategory ==
                                                                    'electricity'
                                                                ? null
                                                                : 'electricity';
                                                      });
                                                    },
                                                  ),
                                                  const SizedBox(height: 8),
                                                  _LegendDot(
                                                    label:
                                                        '${translate('water_label', locale)}${_selectedLegendCategory == 'water' ? ' (${_formatPercent(activeCategoryDistribution['water'] ?? 0.0)}%)' : ''}',
                                                    color: Colors.blue,
                                                    labelStyle: subStyle,
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedLegendCategory =
                                                            _selectedLegendCategory ==
                                                                    'water'
                                                                ? null
                                                                : 'water';
                                                      });
                                                    },
                                                  ),
                                                  const SizedBox(height: 8),
                                                  _LegendDot(
                                                    label:
                                                        '${translate('gas_label', locale)}${_selectedLegendCategory == 'gas' ? ' (${_formatPercent(activeCategoryDistribution['gas'] ?? 0.0)}%)' : ''}',
                                                    color:
                                                        const Color(0xFF47009C),
                                                    labelStyle: subStyle,
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedLegendCategory =
                                                            _selectedLegendCategory ==
                                                                    'gas'
                                                                ? null
                                                                : 'gas';
                                                      });
                                                    },
                                                  ),
                                                  if (!_useEspData) ...[
                                                    const SizedBox(height: 8),
                                                    _LegendDot(
                                                      label:
                                                          '${translate('waste_label', locale)}${_selectedLegendCategory == 'waste' ? ' (${_formatPercent(activeCategoryDistribution['waste'] ?? 0.0)}%)' : ''}',
                                                      color: const Color(
                                                        0xFF6D4C41,
                                                      ),
                                                      labelStyle: subStyle,
                                                      onTap: () {
                                                        setState(() {
                                                          _selectedLegendCategory =
                                                              _selectedLegendCategory ==
                                                                      'waste'
                                                                  ? null
                                                                  : 'waste';
                                                        });
                                                      },
                                                    ),
                                                  ],
                                                ],
                                              );

                                              if (compactChart) {
                                                return Column(
                                                  children: [
                                                    Center(child: pieChart),
                                                    const SizedBox(height: 12),
                                                    legend,
                                                  ],
                                                );
                                              }

                                              return Row(
                                                children: [
                                                  pieChart,
                                                  const SizedBox(width: 16),
                                                  Expanded(child: legend),
                                                ],
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            translate(
                                              'carbon_footprint_distribution',
                                              locale,
                                            ),
                                            style: subStyle,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: _kReportsSectionGap),
                            Padding(
                              padding: _kReportsSectionOuterPadding,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    child: Padding(
                                      padding: _kReportsCardInnerPadding,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  translate(
                                                    'pdf_reporting_title',
                                                    locale,
                                                  ),
                                                  style: headerStyle,
                                                ),
                                              ),
                                              _ReportsRoundInfoIcon(
                                                onTap: () =>
                                                    _showPdfReportingInfoDialog(
                                                  context,
                                                  locale,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Divider(
                                            color: Colors.white
                                                .withValues(alpha: 0.3),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            translate(
                                                'pdf_reporting_desc', locale),
                                            style: subStyle,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            translate(
                                                'pdf_export_language', locale),
                                            style: subStyle,
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            child: SegmentedButton<String>(
                                              multiSelectionEnabled: false,
                                              showSelectedIcon: false,
                                              segments: [
                                                ButtonSegment<String>(
                                                  value: 'tr',
                                                  label: Text(
                                                    translate(
                                                      'pdf_lang_tr',
                                                      locale,
                                                    ),
                                                  ),
                                                ),
                                                ButtonSegment<String>(
                                                  value: 'en',
                                                  label: Text(
                                                    translate(
                                                      'pdf_lang_en',
                                                      locale,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              selected: {
                                                _pdfExportLocaleSegmentSelection(),
                                              },
                                              onSelectionChanged:
                                                  (Set<String> selection) {
                                                if (selection.isEmpty) return;
                                                final v = selection.first;
                                                setState(() {
                                                  switch (v) {
                                                    case 'tr':
                                                      _pdfExportLocaleOverride =
                                                          const Locale('tr');
                                                      break;
                                                    case 'en':
                                                      _pdfExportLocaleOverride =
                                                          const Locale('en');
                                                      break;
                                                  }
                                                });
                                              },
                                              style: _pdfLangSegmentedStyle(
                                                  context),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          LayoutBuilder(
                                            builder:
                                                (context, buttonConstraints) {
                                              final bool stackButtons =
                                                  buttonConstraints.maxWidth <
                                                      430;
                                              if (stackButtons) {
                                                return Wrap(
                                                  spacing: 10,
                                                  runSpacing: 10,
                                                  children: [
                                                    SizedBox(
                                                      width: buttonConstraints
                                                          .maxWidth,
                                                      child: FilledButton.icon(
                                                        onPressed: () =>
                                                            _generateCarbonPdfReport(
                                                                monthly: false),
                                                        icon: const Icon(Icons
                                                            .picture_as_pdf),
                                                        label: Text(translate(
                                                            'pdf_weekly_button',
                                                            locale)),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: buttonConstraints
                                                          .maxWidth,
                                                      child: FilledButton.icon(
                                                        onPressed: () =>
                                                            _generateCarbonPdfReport(
                                                                monthly: true),
                                                        icon: const Icon(Icons
                                                            .picture_as_pdf_outlined),
                                                        label: Text(translate(
                                                            'pdf_monthly_button',
                                                            locale)),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }

                                              return Row(
                                                children: [
                                                  Expanded(
                                                    child: FilledButton.icon(
                                                      onPressed: () =>
                                                          _generateCarbonPdfReport(
                                                              monthly: false),
                                                      icon: const Icon(
                                                          Icons.picture_as_pdf),
                                                      label: Text(translate(
                                                          'pdf_weekly_button',
                                                          locale)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: FilledButton.icon(
                                                      onPressed: () =>
                                                          _generateCarbonPdfReport(
                                                              monthly: true),
                                                      icon: const Icon(Icons
                                                          .picture_as_pdf_outlined),
                                                      label: Text(translate(
                                                          'pdf_monthly_button',
                                                          locale)),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Turuncu çerçeveli bilgi ikonu — başlığın sağında; tüm bilgi pencereleri [showThemeIndependentInfoDialog].
const Color _kGaugeInfoIconColor = Color(0xFFFFA500);

class _ReportsRoundInfoIcon extends StatelessWidget {
  const _ReportsRoundInfoIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kGaugeInfoIconColor,
                  width: 1.5,
                ),
                color: Colors.transparent,
              ),
              child: const Center(
                child: Text(
                  'i',
                  style: TextStyle(
                    color: _kGaugeInfoIconColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showGaugeInfoDialog(BuildContext context, Locale locale) {
  showThemeIndependentInfoDialog(
    context,
    title: translate('gauge_info_title', locale),
    body: translate('gauge_info_body', locale),
    okLabel: translate('ok', locale),
  );
}

void _showCategoryDistributionInfoDialog(BuildContext context, Locale locale) {
  showThemeIndependentInfoDialog(
    context,
    title: translate('category_distribution_info_title', locale),
    body: translate('category_distribution_info_body', locale),
    okLabel: translate('ok', locale),
  );
}

void _showPdfReportingInfoDialog(BuildContext context, Locale locale) {
  showThemeIndependentInfoDialog(
    context,
    title: translate('pdf_reporting_title', locale),
    body: translate('pdf_reporting_desc', locale),
    okLabel: translate('ok', locale),
  );
}

class _FootprintGauge extends StatelessWidget {
  const _FootprintGauge({
    required this.kgCo2e,
    required this.size,
    this.isMobileLayout = false,
    this.toggleBelowRing = false,
    this.languageProvider,
    this.useEspData = false,
    this.onToggleChanged,
    this.centerStatusOverride,
  });

  final double? kgCo2e;
  final double size;
  final bool isMobileLayout;
  final bool toggleBelowRing;
  final LanguageProvider? languageProvider;
  final bool useEspData;
  final ValueChanged<bool>? onToggleChanged;

  /// Sensör modunda değer yokken [sensor_data_waiting] vb. gösterilir.
  final String? centerStatusOverride;

  @override
  Widget build(BuildContext context) {
    final locale = languageProvider?.currentLocale ?? const Locale('tr');
    // Tüm hesaplamalar kg CO₂e; gösterim: ≥1000 kg → ton; 1–999 kg → kg; 0<…<1 kg → g
    final double kg = centerStatusOverride != null
        ? 0.0
        : (kgCo2e ?? 0).clamp(0.0, double.infinity);
    final bool showTonnes = kg >= 1000;
    final String valueText;
    final String unitKey;
    if (showTonnes) {
      final double t = kg / 1000.0;
      valueText = t >= 100
          ? t.toStringAsFixed(0)
          : t >= 10
              ? t.toStringAsFixed(1)
              : t.toStringAsFixed(2);
      unitKey = 'tonnes_co2e';
    } else if (kg == 0) {
      valueText = '0.0';
      unitKey = 'kg_co2e';
    } else if (kg < 1) {
      final double g = kg * 1000.0;
      valueText = g >= 100
          ? g.toStringAsFixed(0)
          : g >= 10
              ? g.toStringAsFixed(1)
              : g >= 1
                  ? g.toStringAsFixed(2)
                  : g.toStringAsFixed(3);
      unitKey = 'g_co2e';
    } else {
      valueText = kg >= 100
          ? kg.toStringAsFixed(0)
          : kg >= 10
              ? kg.toStringAsFixed(1)
              : kg.toStringAsFixed(2);
      unitKey = 'kg_co2e';
    }
    // Halka dolum ölçeği (50 t = 50 000 kg üst sınır)
    const double maxTonnesReference = 50.0;
    final double progress =
        ((kg / 1000.0) / maxTonnesReference).clamp(0.0, 1.0);
    final double ringStroke = isMobileLayout ? 11.0 : 10.0;
    final double innerRingGap =
        toggleBelowRing ? 4.0 : (isMobileLayout ? 8.0 : 16.0);
    final double innerSize = size - (ringStroke * 2 + innerRingGap);
    final double valueSize =
        isMobileLayout ? _kGaugeCenterValueSizeMobile : _kGaugeCenterValueSize;
    final double auxSize =
        isMobileLayout ? _kGaugeCenterAuxSizeMobile : _kGaugeCenterAuxSize;
    final double statusSize = isMobileLayout ? 14.0 : (_kGaugeCenterAuxSize + 1);

    Widget buildCenterTexts() {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (centerStatusOverride != null)
            Text(
              centerStatusOverride!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: statusSize,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black87
                        : Theme.of(context).colorScheme.onSurface,
                  ),
            )
          else ...[
            Text(
              valueText,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: valueSize,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            SizedBox(height: isMobileLayout ? 4 : 2),
            Text(
              translate(unitKey, locale),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily:
                    Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: auxSize,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
          SizedBox(height: isMobileLayout ? 8 : 4),
          Text(
            translate('greenhouse_gas_emissions', locale),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              fontSize: auxSize,
              height: 1.15,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      );
    }

    final bool showToggleInside =
        onToggleChanged != null && !toggleBelowRing;

    Widget buildGaugeRing() {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleChanged == null
                  ? null
                  : () => onToggleChanged!(!useEspData),
              child: SizedBox(
                width: size,
                height: size,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOutCubic,
                  builder: (context, animatedProgress, _) {
                    return CustomPaint(
                      painter: _GradientRingPainter(
                        progress: animatedProgress,
                        strokeWidth: ringStroke,
                        trackColor: Colors.grey.shade300,
                        gradientColors: const [
                          Color(0xFF304411),
                          Color(0xFF48631F),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: Material(
                  color: Colors.white,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleChanged == null
                        ? null
                        : () => onToggleChanged!(!useEspData),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        toggleBelowRing ? 20 : (isMobileLayout ? 12 : 10),
                        toggleBelowRing ? 20 : (isMobileLayout ? 10 : 6),
                        toggleBelowRing ? 20 : (isMobileLayout ? 12 : 10),
                        toggleBelowRing ? 20 : (isMobileLayout ? 8 : 6),
                      ),
                      child: showToggleInside
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  buildCenterTexts(),
                                  SizedBox(height: isMobileLayout ? 8 : 6),
                                  _GaugeModeToggleRow(
                                    useEspData: useEspData,
                                    labelSize: isMobileLayout
                                        ? _kGaugeToggleLabelSizeMobile
                                        : _kGaugeToggleLabelSize,
                                    spacing: isMobileLayout
                                        ? _kGaugeToggleSpacingMobile
                                        : 10,
                                    rowHeight: isMobileLayout
                                        ? _kGaugeToggleRowHeightMobile
                                        : _kGaugeToggleRowHeight,
                                    useLargePill: false,
                                    switchScale: isMobileLayout
                                        ? _kGaugeToggleScaleMobile
                                        : _kGaugeToggleScaleWide,
                                  ),
                                ],
                              ),
                            )
                          : Center(child: buildCenterTexts()),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (toggleBelowRing && onToggleChanged != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildGaugeRing(),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onToggleChanged!(!useEspData),
            child: _GaugeModeToggleRow(
              useEspData: useEspData,
              labelSize: _kGaugeToggleLabelSizeMobile,
              spacing: _kGaugeToggleSpacingMobile,
              rowHeight: _kGaugeToggleRowHeightMobile,
              useLargePill: false,
              switchScale: _kGaugeToggleScaleMobile,
              labelColor: Colors.white,
            ),
          ),
        ],
      );
    }

    return buildGaugeRing();
  }
}

class _GaugeModeToggleRow extends StatelessWidget {
  const _GaugeModeToggleRow({
    required this.useEspData,
    required this.labelSize,
    required this.spacing,
    this.rowHeight = _kGaugeToggleRowHeight,
    this.useLargePill = false,
    this.switchScale = _kGaugeToggleScaleWide,
    this.labelColor,
  });

  final bool useEspData;
  final double labelSize;
  final double spacing;
  final double rowHeight;
  final bool useLargePill;
  final double switchScale;
  final Color? labelColor;

  static const double _kCompactPillWidth = 48;
  static const double _kCompactPillHeight = 24;
  static const double _kCompactThumb = 18;

  @override
  Widget build(BuildContext context) {
    final Color resolvedLabelColor = labelColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.black87
            : Theme.of(context).colorScheme.onSurface);

    Widget toggleVisual;
    if (useLargePill) {
      const pillColor = Color(0xFF48631F);
      final double inset =
          (_kCompactPillHeight - _kCompactThumb) / 2;
      toggleVisual = AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
        width: _kCompactPillWidth,
        height: _kCompactPillHeight,
        padding: EdgeInsets.all(inset),
        decoration: BoxDecoration(
          color: pillColor,
          borderRadius: BorderRadius.circular(_kCompactPillHeight / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment:
              useEspData ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: _kCompactThumb,
            height: _kCompactThumb,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      toggleVisual = Transform.scale(
        scale: switchScale,
        child: IgnorePointer(
          child: Switch(
            value: useEspData,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (_) {},
          ),
        ),
      );
    }

    return SizedBox(
      height: rowHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(right: spacing),
            child: Text(
              'M',
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: labelSize,
                color: resolvedLabelColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          toggleVisual,
          Padding(
            padding: EdgeInsets.only(left: spacing),
            child: Text(
              'E',
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: labelSize,
                color: resolvedLabelColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  _GradientRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.gradientColors,
  });

  final double progress; // 0..1
  final double strokeWidth;
  final Color trackColor;
  final List<Color> gradientColors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    const double startAngle = -3.1415926535 / 2; // top
    final double sweepAngle = 2 * 3.1415926535 * progress;

    // Track
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      0,
      2 * 3.1415926535,
      false,
      trackPaint,
    );

    // Gradient arc
    final SweepGradient gradient = SweepGradient(
      startAngle: 0,
      endAngle: 2 * 3.1415926535,
      colors: gradientColors,
    );
    final Paint progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) {
    if (progress != oldDelegate.progress) return true;
    if (strokeWidth != oldDelegate.strokeWidth) return true;
    if (trackColor != oldDelegate.trackColor) return true;
    if (gradientColors.length != oldDelegate.gradientColors.length) return true;
    for (int i = 0; i < gradientColors.length; i++) {
      if (gradientColors[i] != oldDelegate.gradientColors[i]) return true;
    }
    return false;
  }
}

// _MetricCard kaldırıldı: kullanılmıyordu.

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.label,
    required this.color,
    required this.labelStyle,
    this.onTap,
  });

  final String label;
  final Color color;
  final TextStyle labelStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: labelStyle,
            ),
          ],
        ),
      ),
    );
  }
}
