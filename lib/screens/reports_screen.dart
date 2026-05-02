import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../widgets/consumption_form.dart';
import '../widgets/realtime_esp_data_widget.dart';
import '../widgets/realtime_shelly_data_widget.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../services/api_service.dart';
import '../services/global_carbon_service.dart';
import '../services/firebase_auth_service.dart';
import '../models/consumption_entry.dart';
import '../models/shelly_data.dart';
import '../algorithms/calculation.dart';

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

  double? _lastCalculatedKgCo2e;
  double? _manualCalculatedKgCo2e; // Manuel hesaplama sonucu
  ConsumptionEntry?
      _manualEntry; // Manuel giriş verisi (kategori dağılımı için)
  ConsumptionEntry? _espEntry; // ESP ham verisi (su+gaz için)
  ConsumptionEntry? _shellyEntry; // Shelly ham verisi (elektrik için)
  bool _useEspData = false; // Gauge'da ESP verisi mi gösterilecek?
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
  bool _isLoadingTrends = false;
  StreamSubscription<ConsumptionEntry?>? _espDataSubscription;
  StreamSubscription<ShellyData?>? _shellyDataSubscription;
  final ApiService _apiService = ApiService();
  final String _shellyDeviceId = 'shelly_plug_001';
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
    _loadTrendData();
    _loadGlobalTrendData();
    // Ülke verilerini yükle - öncelikli olarak
    _loadCountryTrends().then((_) {
      debugPrint(
          'Ülke verileri yükleme tamamlandı: ${_countryTrends.length} ülke');
    });
    // ESP verilerini real-time dinle ve otomatik güncelle
    _listenToEspData();
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
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
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

  /// ESP verilerini real-time dinle ve emisyonu otomatik hesapla
  void _listenToEspData() {
    _espDataSubscription?.cancel(); // Önceki subscription'ı iptal et
    _espDataSubscription =
        _firebaseService.listenToEsp8266Data('esp8266_001').listen((entry) {
      if (entry != null && mounted) {
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

  /// Shelly verilerini real-time dinle ve emisyonu otomatik hesapla
  void _listenToShellyData() {
    _shellyDataSubscription?.cancel(); // Önceki subscription'ı iptal et
    _shellyDataSubscription = _apiService
        .listenToFirebaseShellyData(_shellyDeviceId)
        .listen((shellyData) {
      if (shellyData != null && mounted) {
        // Shelly verilerini ConsumptionEntry'ye dönüştür
        final entry = _apiService.shellyDataToConsumptionEntry(shellyData);
        // Shelly ham verisini sakla (elektrik için)
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
          });
        } else {
          debugPrint('📊 Manuel veri bulunamadı');
        }
      }
    } catch (e) {
      debugPrint('Manuel veri yükleme hatası: $e');
    }
  }

  /// ESP ve Shelly verilerini topla ve gauge'ı güncelle
  /// ESP toggle açıkken: Shelly'den sadece elektrik, ESP'den sadece su+gaz
  void _updateCombinedEmission() {
    double totalEmission = 0.0;

    // Shelly'den sadece elektrik emisyonu (Shelly sadece elektrik ölçüyor)
    if (_shellyEntry != null) {
      final electricityEmission =
          _shellyEntry!.electricityKwh * Calculation.factorElectricityKgPerKwh;
      totalEmission += electricityEmission;
      debugPrint(
        '📊 Shelly Elektrik: ${_shellyEntry!.electricityKwh.toStringAsFixed(2)} kWh × ${Calculation.factorElectricityKgPerKwh} = ${electricityEmission.toStringAsFixed(2)} kg CO2e',
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
    }
  }

  /// ESP verilerinden kategori dağılımını güncelle
  void _updateCategoryDistributionFromEsp() {
    double totalElectricity = 0.0;
    double totalGas = 0.0;
    double totalWater = 0.0;
    double totalWaste = 0.0;

    // Shelly'den elektrik
    if (_shellyEntry != null) {
      totalElectricity +=
          _shellyEntry!.electricityKwh * Calculation.factorElectricityKgPerKwh;
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
      ConsumptionEntry? liveEspEntry;

      // Önce ESP'den güncel ölçümü çekip Firebase'e yazmayı dene.
      // Böylece history/latest eski kaldığında (örn. fuel=400) trend ekranı
      // gerçek anlık değere daha hızlı senkronize olur.
      if (_weekOffset == 0) {
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

      // Firebase'den ESP geçmiş verileri çek - timeout ile
      final espHistoryData = await _firebaseService
          .getHistoryData(
        deviceId: 'esp8266_001', // ESP8266 cihaz ID'si
        startDate: startDate,
        endDate: endDate,
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // Timeout durumunda boş liste döndür
          return <ConsumptionEntry>[];
        },
      );

      // Firebase'den Shelly geçmiş verileri çek - timeout ile
      List<ConsumptionEntry> shellyHistoryData = [];
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

        // Shelly verilerini ConsumptionEntry'ye dönüştür
        shellyHistoryData = shellyDataList
            .map((shellyData) =>
                _apiService.shellyDataToConsumptionEntry(shellyData))
            .toList();
      } catch (e) {
        debugPrint('Shelly geçmiş veri hatası: $e');
        // Shelly verisi alınamazsa devam et
      }

      // Firebase'den manuel geçmiş verileri çek - timeout ile
      List<ConsumptionEntry> manualHistoryData = [];
      try {
        // Kullanıcı giriş yapmışsa manuel verileri yükle
        final userId = FirebaseAuthService.instance.currentUser?.uid;
        if (userId != null) {
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
        }
      } catch (e) {
        debugPrint('Manuel geçmiş veri hatası: $e');
        // Manuel verisi alınamazsa devam et
      }

      if (!mounted) return; // Widget dispose edilmişse işlemi durdur

      // ESP, Shelly ve Manuel verilerini birleştir
      List<ConsumptionEntry> historyData = [
        ...espHistoryData,
        ...shellyHistoryData,
        ...manualHistoryData,
      ];

      // ESP'den canlı veri geldiyse mutlaka kaynak listeye ekle (Firebase latest
      // eski/bozuk olsa bile trend hesabı güncel değeri kullanabilsin).
      if (liveEspEntry != null) {
        historyData.add(liveEspEntry);
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
              shellyLatestEntry =
                  _apiService.shellyDataToConsumptionEntry(latestShellyData);
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

      // ESP ve Shelly verilerini birleştir
      final Map<int, ConsumptionEntry> dailyData = {};
      final Map<int, int> dailyDataCount = {};
      final Map<int, List<String>> dailyDataSources = {};

      for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
        final espEntry = espDailyData[dayIndex];
        final shellyEntry = shellyDailyData[dayIndex];
        final manualEntry = manualDailyData[dayIndex];

        // Öncelik: Manuel > ESP+Shelly > ESP > Shelly
        if (manualEntry != null) {
          // Manuel veri varsa onu kullan
          dailyData[dayIndex] = manualEntry;
          dailyDataCount[dayIndex] = 1;
          dailyDataSources[dayIndex] = ['Manuel'];
          debugPrint(
              '📅 Gün $dayIndex: Manuel veri kullanıldı: E=${manualEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${manualEntry.fuelLiters.toStringAsFixed(2)} L, S=${manualEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        } else if (espEntry != null && shellyEntry != null) {
          // ESP + Shelly birleştir
          final combinedEntry = ConsumptionEntry(
            electricityKwh: shellyEntry.electricityKwh, // Shelly'den elektrik
            waterCubicMeters: espEntry.waterCubicMeters, // ESP'den su
            fuelLiters: espEntry.fuelLiters, // ESP'den gaz m³
            wasteKg: (espEntry.wasteKg + shellyEntry.wasteKg) / 2, // Ortalama
            createdAt: shellyEntry.createdAt.isAfter(espEntry.createdAt)
                ? shellyEntry.createdAt
                : espEntry.createdAt, // En güncel tarih
            fuelIsNaturalGasM3: espEntry.fuelIsNaturalGasM3,
          );
          dailyData[dayIndex] = combinedEntry;
          dailyDataCount[dayIndex] = 2;
          dailyDataSources[dayIndex] = ['ESP', 'Shelly'];
          debugPrint('📅 Gün $dayIndex: ESP + Shelly birleştirildi:');
          debugPrint(
              '   ESP: E=${espEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${espEntry.fuelLiters.toStringAsFixed(2)} L, S=${espEntry.waterCubicMeters.toStringAsFixed(2)} m³');
          debugPrint(
              '   Shelly: E=${shellyEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${shellyEntry.fuelLiters.toStringAsFixed(2)} L, S=${shellyEntry.waterCubicMeters.toStringAsFixed(2)} m³');
          debugPrint(
              '   Birleşik: E=${combinedEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${combinedEntry.fuelLiters.toStringAsFixed(2)} L, S=${combinedEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        } else if (espEntry != null) {
          // Sadece ESP verisi
          dailyData[dayIndex] = espEntry;
          dailyDataCount[dayIndex] = 1;
          dailyDataSources[dayIndex] = ['ESP'];
          debugPrint(
              '📅 Gün $dayIndex: Sadece ESP verisi: E=${espEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${espEntry.fuelLiters.toStringAsFixed(2)} L, S=${espEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        } else if (shellyEntry != null) {
          // Sadece Shelly verisi
          dailyData[dayIndex] = shellyEntry;
          dailyDataCount[dayIndex] = 1;
          dailyDataSources[dayIndex] = ['Shelly'];
          debugPrint(
              '📅 Gün $dayIndex: Sadece Shelly verisi: E=${shellyEntry.electricityKwh.toStringAsFixed(2)} kWh, Y=${shellyEntry.fuelLiters.toStringAsFixed(2)} L, S=${shellyEntry.waterCubicMeters.toStringAsFixed(2)} m³');
        }
      }

      // Özet bilgi
      debugPrint('📊 ========== GÜNLÜK VERİ ÖZETİ ==========');
      dailyDataCount.forEach((day, count) {
        final sources = dailyDataSources[day] ?? [];
        final entry = dailyData[day]!;
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

      // Eğer hiç veri yoksa, en son veriyi kullan (bugün için)
      if (dailyData.isEmpty && historyData.isNotEmpty) {
        // En son (en güncel) veriyi kullan, tüm verileri toplama!
        // Veriler zaten tarihe göre sıralı (en eski -> en yeni)
        final latestEntry = historyData.last;
        dailyData[0] = ConsumptionEntry(
          electricityKwh: latestEntry.electricityKwh,
          waterCubicMeters: latestEntry.waterCubicMeters,
          fuelLiters: latestEntry.fuelLiters,
          wasteKg: latestEntry.wasteKg,
          createdAt: DateTime.now(), // Bugün olarak işaretle
          fuelIsNaturalGasM3: latestEntry.fuelIsNaturalGasM3,
        );
        debugPrint(
            '📅 Hiç günlük veri yok, en son veri bugün olarak kullanıldı');
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

      // ESP/Shelly verileri için döngü
      for (int i = 6; i >= 0; i--) {
        // En eski günden en yeni güne (Pazartesi'den Pazar'a)
        if (dailyData.containsKey(i)) {
          final entry = dailyData[i]!;
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

      // Bugünün toplam emisyonunu hesapla (gauge için)
      double todayTotalEmission = 0.0;
      if (dailyData.containsKey(0)) {
        todayTotalEmission = Calculation.calculateDailyEmission(dailyData[0]!);
      }

      if (totalEmission > 0) {
        // Yüzdeleri hesapla
        double electricityPercent = (totalElectricity / totalEmission * 100);
        double gasPercent = (totalGas / totalEmission * 100);
        double waterPercent = (totalWater / totalEmission * 100);
        double wastePercent = (totalWaste / totalEmission * 100);

        // Eğer bir kategori 0 ise, minimum %2 göster (görünürlük için)
        // Diğer kategorilerden orantılı olarak azalt
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
          // Sıfır olan kategorilere minimum %2 ver
          final double remaining = 100 - (minPercent * zeroCount);

          // Sıfır olmayan kategorileri orantılı olarak yeniden hesapla
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
          // Toggle durumuna göre kategori dağılımını seç
          // ESP seçiliyse ESP verilerinden, Manuel seçiliyse Manuel verilerinden
          if (_useEspData) {
            _categoryDistribution = {
              'electricity': electricityPercent,
              'gas': gasPercent,
              'water': waterPercent,
              'waste': wastePercent,
            };
          } else {
            // Manuel veriler için kategori dağılımı
            if (manualTotalEmission > 0) {
              _categoryDistribution = {
                'electricity': manualElectricityPercent,
                'gas': manualGasPercent,
                'water': manualWaterPercent,
                'waste': manualWastePercent,
              };
            } else {
              // Manuel veri yoksa ESP verilerini göster
              _categoryDistribution = {
                'electricity': electricityPercent,
                'gas': gasPercent,
                'water': waterPercent,
                'waste': wastePercent,
              };
            }
          }
          // ESP verilerinden hesaplanan bugünün toplam emisyonunu gauge'a aktar
          _lastCalculatedKgCo2e =
              todayTotalEmission > 0 ? todayTotalEmission : null;
          _isLoadingTrends = false;
        });
      } else {
        // Veri olmadığında bile grafiği göstermek için eşit dağılım göster (4 kategori)
        setState(() {
          _dailyEmissions = emissions;
          _manualDailyEmissions = manualEmissions;
          _categoryDistribution = {
            'electricity': 25.0,
            'gas': 25.0,
            'water': 25.0,
            'waste': 25.0,
          };
          // Veri yoksa bugünün emisyonunu da sıfırla
          _lastCalculatedKgCo2e =
              todayTotalEmission > 0 ? todayTotalEmission : null;
          _isLoadingTrends = false;
        });
      }
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
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
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
        ? List<double>.from(activeDailyData)
        : List<double>.filled(7, 0);
    final todayValue =
        _useEspData ? _lastCalculatedKgCo2e : _manualCalculatedKgCo2e;
    if (todayValue != null && sourceData.length == 7) {
      sourceData[6] = todayValue;
    }

    final weeklyTotal = sourceData.fold<double>(0, (sum, e) => sum + e);
    final weeklyAverage =
        sourceData.isEmpty ? 0.0 : weeklyTotal / sourceData.length;
    final monthlyEstimate = weeklyTotal * 4.0;
    final selectedTotal = monthly ? monthlyEstimate : weeklyTotal;
    final selectedAverage = monthly ? monthlyEstimate / 30.0 : weeklyAverage;

    final categoryRows = [
      _buildCategoryRowForPdf(
        translate('electricity', locale),
        _categoryDistribution['electricity'] ?? 0,
        selectedTotal,
      ),
      _buildCategoryRowForPdf(
        translate('water', locale),
        _categoryDistribution['water'] ?? 0,
        selectedTotal,
      ),
      _buildCategoryRowForPdf(
        translate('gas_label', locale),
        _categoryDistribution['gas'] ?? 0,
        selectedTotal,
      ),
      _buildCategoryRowForPdf(
        translate('waste', locale),
        _categoryDistribution['waste'] ?? 0,
        selectedTotal,
      ),
    ];

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(28),
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
                pw.Bullet(
                  text:
                      '${translate('pdf_total_emission', locale)}: ${selectedTotal.toStringAsFixed(2)} kg CO2e',
                ),
                pw.Bullet(
                  text:
                      '${translate('pdf_average_emission', locale)}: ${selectedAverage.toStringAsFixed(2)} kg CO2e',
                ),
                pw.Bullet(
                  text:
                      '${translate('pdf_methodology_note', locale)}: ${translate('pdf_methodology_value', locale)}',
                ),
                pw.Bullet(
                  text:
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
      name: monthly ? 'carbon-monthly-report.pdf' : 'carbon-weekly-report.pdf',
      onLayout: (format) async => pdf.save(),
    );
  }

  List<String> _buildCategoryRowForPdf(
    String label,
    double percent,
    double totalKg,
  ) {
    final shareKg = totalKg * (percent / 100);
    return [
      label,
      '${percent.toStringAsFixed(1)}%',
      shareKg.toStringAsFixed(2),
    ];
  }

  int _isoWeekNumber(DateTime date) {
    final thursday =
        date.add(Duration(days: 4 - (date.weekday == 7 ? 0 : date.weekday)));
    final firstDayOfYear = DateTime(thursday.year, 1, 1);
    final dayOfYear = thursday.difference(firstDayOfYear).inDays + 1;
    return ((dayOfYear - 1) ~/ 7) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    // MediaQuery'yi build metodunun başında hesapla - ListView içinde değil
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final listViewPadding = EdgeInsets.only(
      top: 8,
      left: 16,
      right: 16,
      bottom: 16 + bottomPadding + 80, // Bottom nav bar için ekstra padding
    );

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
            LayoutBuilder(
              builder: (context, constraints) {
                // Geniş ekranda sabit ölçülerle stabil yerleşim; mobilde orantılı
                final bool isWide = constraints.maxWidth >= 900;
                final double gaugeSize = isWide
                    ? 240.0
                    : (constraints.maxWidth * 0.38).clamp(160.0, 240.0);
                final double headerHeight = isWide
                    ? 180.0 // Daha küçük header - widget'ı yukarı taşımak için
                    : (constraints.maxWidth * 9.0 / 16.0).clamp(120.0, 180.0);
                final ThemeData baseTheme = Theme.of(context);
                return Theme(
                  // Tüm TextTheme renklerini beyaza uygula (başlıklar dahil)
                  data: baseTheme.copyWith(
                    textTheme: baseTheme.textTheme.apply(
                      bodyColor: Colors.white,
                      displayColor: Colors.white,
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    // Varsayılan Text rengi de beyaz
                    style: const TextStyle(color: Colors.white),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? 900 : double.infinity,
                        ),
                        child: ListView(
                          clipBehavior: Clip.none,
                          padding: listViewPadding, // Üst padding azaltıldı
                          children: [
                            // Üst alan: artık arka plan tüm sayfada, burada görsel yer tutucu ve ölçerin konumlandırılması var
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SizedBox(height: headerHeight),
                                // Position gauge higher up - widget'ı yukarı taşımak için
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: -(gaugeSize /
                                      3), // Daha az overlap - widget daha yukarıda
                                  child: Center(
                                    child: _FootprintGauge(
                                      kgCo2e: _lastCalculatedKgCo2e,
                                      size: gaugeSize,
                                      languageProvider: widget.languageProvider,
                                      useEspData: _useEspData,
                                      onToggleChanged: (value) {
                                        setState(() {
                                          _useEspData = value;
                                          // Toggle değiştiğinde gösterilecek veriyi güncelle
                                          if (value) {
                                            // ESP verisi seçildiğinde ESP + Shelly toplamını göster
                                            _updateCombinedEmission();
                                          } else {
                                            // Manuel veri seçildiğinde manuel hesaplamayı göster
                                            // Eğer manuel veri varsa, gauge'ı güncelle
                                            if (_manualCalculatedKgCo2e !=
                                                    null &&
                                                _manualEntry != null) {
                                              _lastCalculatedKgCo2e =
                                                  _manualCalculatedKgCo2e;
                                              // Grafikteki bugünün değerini de güncelle (manuel veriler listesine)
                                              if (_manualDailyEmissions
                                                      .length ==
                                                  7) {
                                                _manualDailyEmissions[6] =
                                                    _manualCalculatedKgCo2e!;
                                                debugPrint(
                                                  '📊 Toggle Manuel: Manuel grafikteki bugünün değeri güncellendi: ${_manualCalculatedKgCo2e!.toStringAsFixed(2)} kg CO2e',
                                                );
                                              }
                                              // Manuel veri seçildiğinde kategori dağılımını güncelle
                                              _updateCategoryDistributionFromEntry(
                                                  _manualEntry!);
                                            }
                                          }
                                        });
                                        // Manuel veri yoksa Firebase'den yükle (setState dışında)
                                        if (!value &&
                                            (_manualCalculatedKgCo2e == null ||
                                                _manualEntry == null)) {
                                          _loadManualDataFromFirebase();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              height: gaugeSize / 3 + 32,
                            ), // Gauge overlap + içerik (toggle) için boşluk
                            // Mode selector buttons
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => setState(
                                      () => _selectedMode = _InputMode.manual,
                                    ),
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
                                    icon: const Icon(Icons.edit_note),
                                    label:
                                        Text(translate('manual_entry', locale)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => setState(
                                      () => _selectedMode =
                                          _selectedMode == _InputMode.raspberry
                                              ? _InputMode.none
                                              : _InputMode.raspberry,
                                    ),
                                    style: ButtonStyle(
                                      minimumSize: const WidgetStatePropertyAll(
                                        Size.fromHeight(48),
                                      ),
                                      foregroundColor:
                                          const WidgetStatePropertyAll(
                                        Colors.white,
                                      ),
                                      backgroundColor:
                                          _selectedMode == _InputMode.raspberry
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
                            const SizedBox(height: 12),
                            // Manual Data Input - cam efekti (blur) + yarı saydam siyah zemin
                            if (_selectedMode == _InputMode.manual)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
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
                            // ESP8266 Anlık Veriler - Raspberry Pi butonuna basıldığında göster
                            if (_selectedMode == _InputMode.raspberry) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: RealtimeEspDataWidget(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Shelly Plug S Anlık Veriler - ESP'nin altında
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.1),
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
                                      padding: const EdgeInsets.all(16),
                                      child: RealtimeShellyDataWidget(
                                        apiService: _apiService,
                                        deviceId: _shellyDeviceId,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Stack(
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
                                          padding: const EdgeInsets.all(16),
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleLarge
                                                                  ?.copyWith(
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                        ),
                                                      ),
                                                      Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              IconButton(
                                                                onPressed: () {
                                                                  if (_showGlobalTrend) {
                                                                    _loadGlobalTrendData();
                                                                  } else {
                                                                    _loadTrendData();
                                                                  }
                                                                },
                                                                icon:
                                                                    const Icon(
                                                                  Icons.refresh,
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
                                                                  vertical: -3,
                                                                ),
                                                                constraints:
                                                                    const BoxConstraints(
                                                                  minWidth: 30,
                                                                  minHeight: 30,
                                                                ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                              ),
                                                              const SizedBox(
                                                                  width: 2),
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
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodySmall
                                                                    ?.copyWith(
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(
                                                                        alpha:
                                                                            0.7,
                                                                      ),
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 2),
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
                                                  const SizedBox(height: 16),
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
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .bodyMedium
                                                                      ?.copyWith(
                                                                        color: Colors
                                                                            .white
                                                                            .withValues(
                                                                          alpha:
                                                                              0.7,
                                                                        ),
                                                                      ),
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
                                                                            (e) =>
                                                                                _toDoubleSafe(e),
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
                                                                          _toDoubleSafe(
                                                                              e))
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
                                                                          _toDoubleSafe(
                                                                              e))
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
                                                                  final minCombined =
                                                                      combined.reduce((a,
                                                                              b) =>
                                                                          a < b
                                                                              ? a
                                                                              : b);
                                                                  final maxCombined =
                                                                      combined.reduce((a,
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
                                                                            ((e - minCombined) /
                                                                                range) *
                                                                            100.0)
                                                                        .toList();
                                                                    personalPlottedSeries = personalSeries
                                                                        .map((e) =>
                                                                            ((e - minCombined) /
                                                                                range) *
                                                                            100.0)
                                                                        .toList();
                                                                    // Çok düşük ama sıfır olmayan kişisel değerleri görünür tut.
                                                                    personalPlottedSeries = personalPlottedSeries
                                                                        .asMap()
                                                                        .entries
                                                                        .map(
                                                                            (entry) {
                                                                      final rawValue =
                                                                          personalSeries[
                                                                              entry.key];
                                                                      final plotted =
                                                                          entry
                                                                              .value;
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
                                                                        .expand(
                                                                            (e) =>
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
                                                                            double
                                                                                .infinity,
                                                                            (a, b) => a < b
                                                                                ? a
                                                                                : b)
                                                                    : 0.0;
                                                                final userAvg = normalizedData
                                                                        .isNotEmpty
                                                                    ? normalizedData.reduce((a,
                                                                                b) =>
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
                                                                  final maxValue =
                                                                      allValues.reduce((a,
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
                                                                    double tempMaxY = maxValue >
                                                                            100
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
                                                                    maxY = ((maxValue +
                                                                                maxOffset) *
                                                                            1.15)
                                                                        .clamp(
                                                                            1.0,
                                                                            double.infinity);
                                                                    debugPrint(
                                                                        '⚠️ Yüksek değer tespit edildi (${maxValue.toStringAsFixed(2)} kg), offset: ${maxOffset.toStringAsFixed(2)}, ölçek optimize edildi: maxY=$maxY');
                                                                  } else {
                                                                    // Normal değerler için standart padding (%20) + offset için ekstra alan
                                                                    maxY = ((maxValue +
                                                                                maxOffset) *
                                                                            1.2)
                                                                        .clamp(
                                                                            1.0,
                                                                            double.infinity);
                                                                    debugPrint(
                                                                        '📊 Normal değer, offset: ${maxOffset.toStringAsFixed(2)}, maxY=$maxY');
                                                                  }
                                                                }

                                                                const double
                                                                    minY = 0.0;
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
                                                                    normalizedData
                                                                        .any((e) =>
                                                                            e >
                                                                            0);
                                                                final hasCountryData =
                                                                    _showCountryComparison &&
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
                                                                            enabled:
                                                                                true,
                                                                            touchTooltipData:
                                                                                LineTouchTooltipData(
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
                                                                                        fontSize: 11,
                                                                                      ),
                                                                                    ),
                                                                                    LineTooltipItem(
                                                                                      '\n${_weekOffset == -1 ? "Tahmini — " : ""}Sizin Veriniz: $personalText',
                                                                                      const TextStyle(
                                                                                        color: Colors.pinkAccent,
                                                                                        fontWeight: FontWeight.bold,
                                                                                        fontSize: 11,
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
                                                                                    label = _weekOffset == -1
                                                                                        ? 'Tahmini (gelecek hafta)'
                                                                                        : 'Sizin Verileriniz';
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
                                                                                      fontSize: 11,
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
                                                                            handleBuiltInTouches:
                                                                                true,
                                                                          ),
                                                                          gridData:
                                                                              FlGridData(
                                                                            show:
                                                                                true,
                                                                            drawVerticalLine:
                                                                                true,
                                                                            horizontalInterval:
                                                                                yInterval,
                                                                            verticalInterval:
                                                                                1,
                                                                            getDrawingHorizontalLine:
                                                                                (value) {
                                                                              return FlLine(
                                                                                color: Colors.white.withValues(
                                                                                  alpha: 0.1,
                                                                                ),
                                                                                strokeWidth: 1,
                                                                              );
                                                                            },
                                                                            getDrawingVerticalLine:
                                                                                (value) {
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
                                                                            show:
                                                                                true,
                                                                            rightTitles:
                                                                                const AxisTitles(
                                                                              sideTitles: SideTitles(
                                                                                showTitles: false,
                                                                              ),
                                                                            ),
                                                                            topTitles:
                                                                                const AxisTitles(
                                                                              sideTitles: SideTitles(
                                                                                showTitles: false,
                                                                              ),
                                                                            ),
                                                                            bottomTitles:
                                                                                AxisTitles(
                                                                              sideTitles: SideTitles(
                                                                                showTitles: true,
                                                                                reservedSize: 30,
                                                                                interval: 1,
                                                                                getTitlesWidget: (
                                                                                  double value,
                                                                                  TitleMeta meta,
                                                                                ) {
                                                                                  const style = TextStyle(
                                                                                    color: Colors.white,
                                                                                    fontWeight: FontWeight.bold,
                                                                                    fontSize: 12,
                                                                                  );
                                                                                  Widget text;
                                                                                  switch (value.toInt()) {
                                                                                    case 0:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'mon',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    case 1:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'tue',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    case 2:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'wed',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    case 3:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'thu',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    case 4:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'fri',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    case 5:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'sat',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    case 6:
                                                                                      text = Text(
                                                                                        translate(
                                                                                          'sun',
                                                                                          locale,
                                                                                        ),
                                                                                        style: style,
                                                                                      );
                                                                                      break;
                                                                                    default:
                                                                                      text = const Text(
                                                                                        '',
                                                                                        style: style,
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
                                                                            leftTitles:
                                                                                AxisTitles(
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
                                                                                      style: const TextStyle(
                                                                                        color: Colors.white,
                                                                                        fontWeight: FontWeight.bold,
                                                                                        fontSize: 12,
                                                                                        shadows: [
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
                                                                            show:
                                                                                true,
                                                                            border:
                                                                                Border.all(
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
                                                                            if (_showGlobalTrend &&
                                                                                normalizedData.isNotEmpty)
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
                                                                            if (hasUserData ||
                                                                                _showGlobalTrend)
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
                                                                                dashArray: _weekOffset == -1
                                                                                    ? const <int>[10, 7]
                                                                                    : null,
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
                                                              _weekOffset += 1;
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
                                                          color: Colors.white70,
                                                        ),
                                                        Text(
                                                          _weekOffset == -1
                                                              ? 'Gelecek hafta (tahmini)'
                                                              : _weekOffset == 0
                                                                  ? 'Bu hafta'
                                                                  : '$_weekOffset. hafta önce',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    color: Colors
                                                                        .white
                                                                        .withValues(
                                                                      alpha:
                                                                          0.85,
                                                                    ),
                                                                  ),
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
                                                          color: Colors.white70,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                  // Legend (açıklama) - ülke çizgileri için
                                                  if (_showCountryComparison &&
                                                      !_showGlobalTrend &&
                                                      _countryTrends.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 12,
                                                              bottom: 8),
                                                      child: Wrap(
                                                        spacing: 16,
                                                        runSpacing: 8,
                                                        alignment: WrapAlignment
                                                            .center,
                                                        children: [
                                                          // Kullanıcının kendi verisi
                                                          if ((_showGlobalTrend
                                                                      ? _globalDailyTrends
                                                                      : (_useEspData
                                                                          ? _dailyEmissions
                                                                          : _manualDailyEmissions))
                                                                  .any((e) =>
                                                                      e > 0) ||
                                                              (_useEspData
                                                                      ? _lastCalculatedKgCo2e
                                                                      : _manualCalculatedKgCo2e) !=
                                                                  null)
                                                            _buildLegendItem(
                                                              _weekOffset == -1
                                                                  ? 'Sizin Verileriniz (tahmini)'
                                                                  : 'Sizin Verileriniz',
                                                              Colors
                                                                  .pinkAccent,
                                                            ),
                                                          // Ülke verileri
                                                          ..._countryTrends.keys
                                                              .map(
                                                            (countryName) =>
                                                                _buildLegendItem(
                                                              countryName,
                                                              _getCountryColor(
                                                                  countryName),
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
                                                      _countryTrends.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
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
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.65),
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 14),
                                                          _legendDashedSwatch(
                                                            Colors.orangeAccent,
                                                            barHeight: 3,
                                                          ),
                                                          const SizedBox(
                                                              width: 5),
                                                          Text(
                                                            translate(
                                                              'estimated_data',
                                                              locale,
                                                            ),
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.65),
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
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
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.white
                                                              .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                        ),
                                                  ),
                                                  // Y ekseni açıklaması
                                                  if (!_showGlobalTrend)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4),
                                                      child: Center(
                                                        child: Text(
                                                          'X ekseni: Son 7 gün (Pzt-Paz)  |  Y ekseni: kg CO2e',
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                  alpha: 0.5,
                                                                ),
                                                                fontSize: 10,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                  if (_showGlobalTrend)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4),
                                                      child: Center(
                                                        child: Text(
                                                          'X ekseni: Son 7 gün (Pzt-Paz)  |  Y ekseni: normalize endeks (%)',
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                  alpha: 0.5,
                                                                ),
                                                                fontSize: 10,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
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
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          translate(
                                              'category_distribution', locale),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(color: Colors.white),
                                        ),
                                        const SizedBox(height: 16),
                                        LayoutBuilder(
                                          builder: (context, chartConstraints) {
                                            final bool compactChart =
                                                chartConstraints.maxWidth < 430;
                                            final double pieSize = compactChart
                                                ? (chartConstraints.maxWidth *
                                                        0.55)
                                                    .clamp(130.0, 180.0)
                                                : 180.0;

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
                                                  sections: [
                                                    // Elektrik - Turuncu
                                                    PieChartSectionData(
                                                      color: Colors.orange,
                                                      value: _categoryDistribution[
                                                              'electricity'] ??
                                                          0.0,
                                                      title: (_categoryDistribution[
                                                                      'electricity'] ??
                                                                  0.0) >
                                                              0
                                                          ? '${(_categoryDistribution['electricity'] ?? 0.0).toStringAsFixed(0)}%'
                                                          : '',
                                                      radius: 50,
                                                      titleStyle:
                                                          const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    // Su - Mavi
                                                    PieChartSectionData(
                                                      color: Colors.blue,
                                                      value:
                                                          _categoryDistribution[
                                                                  'water'] ??
                                                              0.0,
                                                      title: (_categoryDistribution[
                                                                      'water'] ??
                                                                  0.0) >
                                                              0
                                                          ? '${(_categoryDistribution['water'] ?? 0.0).toStringAsFixed(0)}%'
                                                          : '',
                                                      radius: 50,
                                                      titleStyle:
                                                          const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    // Gaz - Beyaz/Açık Gri
                                                    PieChartSectionData(
                                                      color:
                                                          Colors.grey.shade300,
                                                      value:
                                                          _categoryDistribution[
                                                                  'gas'] ??
                                                              0.0,
                                                      title: (_categoryDistribution[
                                                                      'gas'] ??
                                                                  0.0) >
                                                              0
                                                          ? '${(_categoryDistribution['gas'] ?? 0.0).toStringAsFixed(0)}%'
                                                          : '',
                                                      radius: 50,
                                                      titleStyle:
                                                          const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );

                                            final Widget legend = Column(
                                              crossAxisAlignment: compactChart
                                                  ? CrossAxisAlignment.center
                                                  : CrossAxisAlignment.start,
                                              children: [
                                                _LegendDot(
                                                  label: translate(
                                                    'electricity',
                                                    locale,
                                                  ),
                                                  color: Colors.orange,
                                                ),
                                                const SizedBox(height: 8),
                                                _LegendDot(
                                                  label: translate(
                                                      'water', locale),
                                                  color: Colors.blue,
                                                ),
                                                const SizedBox(height: 8),
                                                _LegendDot(
                                                  label: translate(
                                                      'gas_label', locale),
                                                  color: Colors.grey.shade300,
                                                ),
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.7,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          translate(
                                              'pdf_reporting_title', locale),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(color: Colors.white),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          translate(
                                              'pdf_reporting_desc', locale),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white
                                                    .withValues(alpha: 0.78),
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
                                                      icon: const Icon(
                                                          Icons.picture_as_pdf),
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
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FootprintGauge extends StatelessWidget {
  const _FootprintGauge({
    required this.kgCo2e,
    required this.size,
    this.languageProvider,
    this.useEspData = false,
    this.onToggleChanged,
  });

  final double? kgCo2e;
  final double size;
  final LanguageProvider? languageProvider;
  final bool useEspData;
  final ValueChanged<bool>? onToggleChanged;

  @override
  Widget build(BuildContext context) {
    final locale = languageProvider?.currentLocale ?? const Locale('tr');
    // Tüm hesaplamalar kg CO₂e; gösterim: ≥1000 kg → ton; 1–999 kg → kg; 0<…<1 kg → g
    final double kg = (kgCo2e ?? 0).clamp(0.0, double.infinity);
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

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Gradient progress ring - tıklamaları engellemesin
          IgnorePointer(
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _GradientRingPainter(
                  progress: progress,
                  strokeWidth: 10,
                  trackColor: Colors.grey.shade300,
                  gradientColors: const [
                    Color(0xFF304411), // koyu yeşil
                    Color(0xFF48631F), // açık yeşil
                  ],
                ),
              ),
            ),
          ),
          // Inner content — FittedBox: küçük ekranda daire içi taşmayı önler
          Container(
            width: size - 40,
            height: size - 40,
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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: onToggleChanged != null
                            ? () {
                                onToggleChanged!(!useEspData);
                              }
                            : null,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                valueText,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.black
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                translate(unitKey, locale),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.black
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                translate('greenhouse_gas_emissions', locale),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.black
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onToggleChanged != null) ...[
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (size - 56).clamp(110.0, 220.0),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                InkWell(
                                  onTap: () {
                                    if (onToggleChanged != null && useEspData) {
                                      onToggleChanged!(false);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6.0,
                                      vertical: 2.0,
                                    ),
                                    child: Text(
                                      translate('manual', locale),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: 11,
                                            color:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? Colors.black87
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      if (onToggleChanged != null) {
                                        onToggleChanged!(!useEspData);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2.0),
                                      child: Transform.scale(
                                        scale: 0.8,
                                        child: Switch(
                                          value: useEspData,
                                          onChanged: onToggleChanged,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    if (onToggleChanged != null &&
                                        !useEspData) {
                                      onToggleChanged!(true);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6.0,
                                      vertical: 2.0,
                                    ),
                                    child: Text(
                                      'ESP',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: 11,
                                            color:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? Colors.black87
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
  const _LegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
