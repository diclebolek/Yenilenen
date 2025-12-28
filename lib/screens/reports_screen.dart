import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:fl_chart/fl_chart.dart';

import '../widgets/consumption_form.dart';
import '../widgets/realtime_esp_data_widget.dart';
import '../widgets/realtime_shelly_data_widget.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../services/api_service.dart';
import '../services/global_carbon_service.dart';
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
  double? _lastCalculatedKgCo2e;
  double? _manualCalculatedKgCo2e; // Manuel hesaplama sonucu
  double? _espCalculatedKgCo2e; // ESP hesaplama sonucu
  bool _useEspData = false; // Gauge'da ESP verisi mi gösterilecek?
  _InputMode _selectedMode = _InputMode.none;
  final FirebaseRealtimeService _firebaseService =
      FirebaseRealtimeService.instance;
  List<double> _dailyEmissions = [0, 0, 0, 0, 0, 0, 0]; // Son 7 gün
  Map<String, double> _categoryDistribution = {
    'electricity': 0.0,
    'gas': 0.0,
    'water': 0.0,
    'waste': 0.0,
  };
  bool _isLoadingTrends = false;
  StreamSubscription<ConsumptionEntry?>? _espDataSubscription;
  final ApiService _apiService = ApiService();
  final String _shellyDeviceId = 'shelly_plug_001';
  final GlobalCarbonService _globalCarbonService = GlobalCarbonService();
  bool _showGlobalTrend = false; // Kişisel mi dünya geneli mi?
  List<double> _globalDailyTrends = [0, 0, 0, 0, 0, 0, 0];
  // Ülke verileri - karşılaştırma için
  Map<String, List<double>> _countryTrends = {};
  // Her ülke için veri kaynağını takip et (true = gerçek veri, false = placeholder)
  Map<String, bool> _countryDataSources = {};
  bool _showCountryComparison = true; // Ülke karşılaştırması gösterilsin mi?

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
    final countryOffsets = {
      'Türkiye': 0.0,
      'ABD': userMax * 0.02, // Kullanıcı max'inin %2'si kadar yukarı
      'Çin': userMax * 0.04, // Kullanıcı max'inin %4'ü kadar yukarı
      'Almanya': userMax * 0.06, // Kullanıcı max'inin %6'sı kadar yukarı
      'Fransa': userMax * 0.08, // Kullanıcı max'inin %8'i kadar yukarı
      'İngiltere': userMax * 0.10, // Kullanıcı max'inin %10'u kadar yukarı
    };

    // Her ülke için bir çizgi oluştur
    int countryIndex = 0;
    _countryTrends.forEach((countryName, countryData) {
      // Ülke verilerini normalize et (kullanıcı verileriyle aynı ölçekte)
      final normalizedCountryData =
          countryData.map((e) => e * scaleFactor).toList();

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

  /// Legend item widget'ı oluştur
  Widget _buildLegendItem(String label, Color color, {bool? isRealData}) {
    final isReal = isRealData ?? true; // Varsayılan olarak gerçek veri
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
        // Veri kaynağı göstergesi
        if (isRealData != null) ...[
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
    _apiService.initializeShelly(
      deviceIp: '192.168.137.232',
      deviceId: _shellyDeviceId,
    );
    try {
      await _apiService.getShellyData(saveToFirebase: true);
    } catch (e) {
      // Hata olsa bile devam et
      debugPrint('Shelly bağlantı hatası: $e');
    }
  }

  @override
  void dispose() {
    _espDataSubscription?.cancel();
    super.dispose();
  }

  /// ESP verilerini real-time dinle ve emisyonu otomatik hesapla
  void _listenToEspData() {
    _espDataSubscription?.cancel(); // Önceki subscription'ı iptal et
    _espDataSubscription =
        _firebaseService.listenToEsp8266Data('esp8266_001').listen((entry) {
      if (entry != null && mounted) {
        // ESP'den gelen verilerle emisyonu hesapla
        final emission = Calculation.calculateDailyEmission(entry);
        setState(() {
          _espCalculatedKgCo2e = emission;
          // Eğer ESP verisi seçiliyse, gauge'ı güncelle
          if (_useEspData) {
            _lastCalculatedKgCo2e = emission;
          }
        });
      }
    });
  }

  /// Son 7 günün verilerini Firebase'den çek ve grafik için hazırla
  /// Hem ESP hem de Shelly verilerini birleştirir
  Future<void> _loadTrendData() async {
    if (!mounted) return; // Widget dispose edilmişse işlemi durdur
    setState(() => _isLoadingTrends = true);
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 7));
      final endDate = now;

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

      if (!mounted) return; // Widget dispose edilmişse işlemi durdur

      // ESP ve Shelly verilerini birleştir
      List<ConsumptionEntry> historyData = [
        ...espHistoryData,
        ...shellyHistoryData
      ];

      // Eğer history'de veri yoksa, latest verilerini de kontrol et
      if (historyData.isEmpty) {
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

          if (espLatestEntry != null && mounted) {
            // ESP latest verisini bugün olarak ekle
            historyData.add(ConsumptionEntry(
              electricityKwh: espLatestEntry.electricityKwh,
              waterCubicMeters: espLatestEntry.waterCubicMeters,
              fuelLiters: espLatestEntry.fuelLiters,
              wasteKg: espLatestEntry.wasteKg,
              createdAt: DateTime.now(), // Bugün olarak işaretle
            ));
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

      final Map<int, ConsumptionEntry> dailyData = {};
      final Map<int, int> dailyDataCount = {}; // Her gün için kaç kayıt var?
      final Map<int, List<String>> dailyDataSources =
          {}; // Her gün için veri kaynakları (ESP/Shelly)

      // Verileri tarihe göre sırala (en eski -> en yeni)
      historyData.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // ESP verilerinin tarihlerini bir Set'e kaydet (hızlı arama için)
      final espTimestamps =
          espHistoryData.map((e) => e.createdAt.millisecondsSinceEpoch).toSet();

      for (var entry in historyData) {
        // Tarih farkını hesapla (mutlak değer)
        final difference = now.difference(entry.createdAt);
        final dayIndex = difference.inDays;

        // Son 7 gün içindeki verileri al (0-6 gün önce)
        if (dayIndex >= 0 && dayIndex < 7) {
          // Veri kaynağını belirle (ESP veya Shelly) - tarih karşılaştırması ile
          final isEsp =
              espTimestamps.contains(entry.createdAt.millisecondsSinceEpoch);
          final source = isEsp ? 'ESP' : 'Shelly';

          if (dailyData.containsKey(dayIndex)) {
            // Aynı günde veri varsa, en son (en güncel) veriyi kullan
            // ÖNEMLİ: Verileri toplamıyoruz, çünkü her kayıt günlük toplamı temsil eder
            final existing = dailyData[dayIndex]!;
            dailyDataCount[dayIndex] = (dailyDataCount[dayIndex] ?? 1) + 1;
            dailyDataSources[dayIndex] = dailyDataSources[dayIndex] ?? [];
            dailyDataSources[dayIndex]!.add(source);

            // En son kaydı kullan (daha yeni tarihli olan)
            if (entry.createdAt.isAfter(existing.createdAt)) {
              debugPrint(
                  '📅 Gün ${dayIndex} için daha yeni veri bulundu, güncelleniyor:');
              debugPrint(
                  '   Eski: E=${existing.electricityKwh.toStringAsFixed(2)} kWh, Y=${existing.fuelLiters.toStringAsFixed(2)} L, S=${existing.waterCubicMeters.toStringAsFixed(2)} m³');
              debugPrint(
                  '   Yeni: E=${entry.electricityKwh.toStringAsFixed(2)} kWh, Y=${entry.fuelLiters.toStringAsFixed(2)} L, S=${entry.waterCubicMeters.toStringAsFixed(2)} m³ (Kaynak: $source)');

              dailyData[dayIndex] = entry; // En son veriyi kullan
            } else {
              debugPrint(
                  '📅 Gün ${dayIndex} için mevcut veri daha güncel, korunuyor');
            }
          } else {
            // İlk veri, direkt ekle
            dailyData[dayIndex] = entry;
            dailyDataCount[dayIndex] = 1;
            dailyDataSources[dayIndex] = [source];
            debugPrint(
                '📅 Gün ${dayIndex} için ilk veri eklendi: E=${entry.electricityKwh.toStringAsFixed(2)} kWh, Y=${entry.fuelLiters.toStringAsFixed(2)} L, S=${entry.waterCubicMeters.toStringAsFixed(2)} m³ (Kaynak: $source)');
          }
        }
      }

      // Özet bilgi
      debugPrint('📊 ========== GÜNLÜK VERİ ÖZETİ ==========');
      dailyDataCount.forEach((day, count) {
        final sources = dailyDataSources[day] ?? [];
        final entry = dailyData[day]!;
        final emission = Calculation.calculateDailyEmission(entry);
        debugPrint('📅 Gün ${day} (${6 - day} gün önce):');
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
        );
        debugPrint(
            '📅 Hiç günlük veri yok, en son veri bugün olarak kullanıldı');
      }

      // Her gün için toplam emisyonu hesapla (günlük trend grafiği için)
      final List<double> emissions = [];
      double totalElectricity = 0;
      double totalGas = 0;
      double totalWater = 0;

      for (int i = 6; i >= 0; i--) {
        // En eski günden en yeni güne (Pazartesi'den Pazar'a)
        if (dailyData.containsKey(i)) {
          final entry = dailyData[i]!;
          final emission = Calculation.calculateDailyEmission(entry);

          // Debug: Detaylı emisyon bilgisi
          final electricityEmission =
              entry.electricityKwh * Calculation.factorElectricityKgPerKwh;
          final fuelEmission =
              entry.fuelLiters * Calculation.factorFuelKgPerLiter;
          final waterEmission =
              entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
          final wasteEmission = entry.wasteKg * Calculation.factorWasteKgPerKg;

          debugPrint('📊 Gün ${6 - i} emisyon detayı:');
          debugPrint(
              '   Elektrik: ${entry.electricityKwh.toStringAsFixed(2)} kWh × 0.233 = ${electricityEmission.toStringAsFixed(2)} kg CO2e');
          debugPrint(
              '   Yakıt: ${entry.fuelLiters.toStringAsFixed(2)} L × 2.31 = ${fuelEmission.toStringAsFixed(2)} kg CO2e');
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
            totalGas += entry.fuelLiters * Calculation.factorFuelKgPerLiter;
            totalWater +=
                entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
          }
        } else {
          emissions.add(0.0);
        }
      }

      // Kategori yüzdelerini hesapla
      final double totalEmission = totalElectricity + totalGas + totalWater;

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
        }

        setState(() {
          _dailyEmissions = emissions;
          _categoryDistribution = {
            'electricity': electricityPercent,
            'gas': gasPercent,
            'water': waterPercent,
            'waste': 0.0,
          };
          // ESP verilerinden hesaplanan bugünün toplam emisyonunu gauge'a aktar
          _lastCalculatedKgCo2e =
              todayTotalEmission > 0 ? todayTotalEmission : null;
          _isLoadingTrends = false;
        });
      } else {
        // Veri olmadığında bile grafiği göstermek için eşit dağılım göster (3 kategori)
        setState(() {
          _dailyEmissions = emissions;
          _categoryDistribution = {
            'electricity': 33.33,
            'gas': 33.33,
            'water': 33.34,
            'waste': 0.0,
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
          _isLoadingTrends = false;
        });
      }
    }
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
      body: Stack(
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
                                          _lastCalculatedKgCo2e =
                                              _espCalculatedKgCo2e;
                                        } else {
                                          _lastCalculatedKgCo2e =
                                              _manualCalculatedKgCo2e;
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: gaugeSize / 3 + 16,
                          ), // Daha az boşluk - widget yukarıda olduğu için
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
                                    color: Colors.black.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: ConsumptionForm(
                                      onCalculated: (valueKgCo2e) {
                                        setState(() {
                                          _manualCalculatedKgCo2e = valueKgCo2e;
                                          // Eğer manuel veri seçiliyse, gauge'ı güncelle
                                          if (!_useEspData) {
                                            _lastCalculatedKgCo2e = valueKgCo2e;
                                          }
                                        });
                                      },
                                      languageProvider: widget.languageProvider,
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
                                    ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
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
                                    ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 20,
                                        spreadRadius: 2,
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.28),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _showGlobalTrend
                                                ? translate(
                                                    'global_trend', locale)
                                                : translate(
                                                    'daily_trends', locale),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(color: Colors.white),
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                _showGlobalTrend
                                                    ? translate(
                                                        'global_trend', locale)
                                                    : translate(
                                                        'personal_trend',
                                                        locale),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                              Switch(
                                                value: _showGlobalTrend,
                                                onChanged: (value) {
                                                  setState(() {
                                                    _showGlobalTrend = value;
                                                  });
                                                },
                                                activeThumbColor: Colors.green,
                                              ),
                                            ],
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
                                          : (_showGlobalTrend
                                                          ? _globalDailyTrends
                                                          : _dailyEmissions)
                                                      .isEmpty ||
                                                  (_showGlobalTrend
                                                          ? _globalDailyTrends
                                                          : _dailyEmissions)
                                                      .every((e) => e == 0)
                                              ? SizedBox(
                                                  height: 200,
                                                  child: Center(
                                                    child: Text(
                                                      translate(
                                                          'no_data_available',
                                                          locale),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: Colors.white
                                                                .withValues(
                                                              alpha: 0.7,
                                                            ),
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              : Builder(
                                                  builder: (context) {
                                                    // Toggle'a göre veri seç
                                                    final currentData =
                                                        _showGlobalTrend
                                                            ? _globalDailyTrends
                                                            : _dailyEmissions;

                                                    // Dünya geneli veriler çok büyük, normalize et
                                                    // Kişisel verilerle karşılaştırılabilir hale getir
                                                    List<double> normalizedData;

                                                    if (_showGlobalTrend) {
                                                      // Dünya geneli verileri normalize et
                                                      // Ortalama kişi başı günlük emisyon: ~4.5 kg
                                                      // Dünya nüfusu: ~8 milyar
                                                      // Toplam: ~36 milyar kg/gün
                                                      // Bu değerleri kişisel verilerle karşılaştırmak için
                                                      // milyar kg cinsinden gösterelim veya normalize edelim
                                                      final maxValue =
                                                          currentData.reduce((a,
                                                                  b) =>
                                                              a > b ? a : b);
                                                      // Eğer çok büyükse (milyar kg), normalize et
                                                      if (maxValue > 1000000) {
                                                        // Milyar kg cinsinden göster
                                                        normalizedData =
                                                            currentData
                                                                .map((e) =>
                                                                    e /
                                                                    1000000000)
                                                                .toList();
                                                      } else {
                                                        normalizedData =
                                                            currentData;
                                                      }
                                                    } else {
                                                      normalizedData =
                                                          currentData;
                                                    }

                                                    // Maksimum değeri hesapla (kullanıcı + ülke verileri)
                                                    final allValues = [
                                                      ...normalizedData,
                                                      if (_showCountryComparison &&
                                                          !_showGlobalTrend)
                                                        ..._countryTrends.values
                                                            .expand((e) => e),
                                                    ];

                                                    // Debug: Değerleri logla
                                                    final userMax =
                                                        normalizedData
                                                                .isNotEmpty
                                                            ? normalizedData
                                                                .reduce((a,
                                                                        b) =>
                                                                    a > b
                                                                        ? a
                                                                        : b)
                                                            : 0.0;
                                                    final userMin = normalizedData
                                                            .isNotEmpty
                                                        ? normalizedData
                                                            .where((e) => e > 0)
                                                            .fold(
                                                                double.infinity,
                                                                (a, b) => a < b
                                                                    ? a
                                                                    : b)
                                                        : 0.0;
                                                    final userAvg =
                                                        normalizedData
                                                                .isNotEmpty
                                                            ? normalizedData
                                                                    .reduce((a,
                                                                            b) =>
                                                                        a + b) /
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
                                                      final countryMax =
                                                          _countryTrends.values
                                                              .expand((e) => e)
                                                              .fold(
                                                                  0.0,
                                                                  (a, b) =>
                                                                      a > b
                                                                          ? a
                                                                          : b);
                                                      debugPrint(
                                                          '📈 Ülke max: $countryMax kg CO2e');
                                                    }

                                                    // Grafik ölçeğini hesapla
                                                    // Kullanıcı verilerinin max değerini kullan, ama çok yüksekse sınırla
                                                    double maxY;
                                                    if (allValues.isEmpty ||
                                                        allValues.every(
                                                            (e) => e == 0)) {
                                                      maxY = 10;
                                                    } else {
                                                      final maxValue = allValues
                                                          .reduce((a, b) =>
                                                              a > b ? a : b);

                                                      // Eğer max değer çok yüksekse (100+ kg), grafik ölçeğini optimize et
                                                      if (maxValue > 100) {
                                                        // Çok yüksek değerler için daha iyi ölçeklendirme
                                                        // Max değerin %15'i kadar padding ekle (daha az padding)
                                                        maxY = (maxValue * 1.15)
                                                            .clamp(
                                                                1.0,
                                                                double
                                                                    .infinity);
                                                        debugPrint(
                                                            '⚠️ Yüksek değer tespit edildi (${maxValue.toStringAsFixed(2)} kg), ölçek optimize edildi: maxY=$maxY');
                                                      } else {
                                                        // Normal değerler için standart padding (%20)
                                                        maxY = (maxValue * 1.2)
                                                            .clamp(
                                                                1.0,
                                                                double
                                                                    .infinity);
                                                      }
                                                    }

                                                    debugPrint(
                                                        '📈 Grafik maxY: $maxY (kullanıcı verileri: ${normalizedData.length} nokta)');

                                                    return SizedBox(
                                                      height: 200,
                                                      child: LineChart(
                                                        LineChartData(
                                                          lineTouchData:
                                                              LineTouchData(
                                                            enabled: true,
                                                            touchTooltipData:
                                                                LineTouchTooltipData(
                                                              getTooltipItems: (List<
                                                                      LineBarSpot>
                                                                  touchedSpots) {
                                                                return touchedSpots.map(
                                                                    (LineBarSpot
                                                                        touchedSpot) {
                                                                  // Her çizgi için tooltip oluştur
                                                                  final lineIndex =
                                                                      touchedSpot
                                                                          .barIndex;
                                                                  String label;
                                                                  Color color;

                                                                  if (lineIndex ==
                                                                      0) {
                                                                    // Kullanıcının kendi verisi
                                                                    label =
                                                                        'Sizin Verileriniz';
                                                                    color = const Color(
                                                                        0xFF304411);
                                                                  } else {
                                                                    // Ülke verileri
                                                                    final countryNames =
                                                                        _countryTrends
                                                                            .keys
                                                                            .toList();
                                                                    if (lineIndex -
                                                                            1 <
                                                                        countryNames
                                                                            .length) {
                                                                      label = countryNames[
                                                                          lineIndex -
                                                                              1];
                                                                      color = _getCountryColor(countryNames[
                                                                          lineIndex -
                                                                              1]);
                                                                    } else {
                                                                      label =
                                                                          'Veri';
                                                                      color = Colors
                                                                          .grey;
                                                                    }
                                                                  }

                                                                  // Tooltip içeriğini kısalt - daha kompakt göster
                                                                  final value =
                                                                      touchedSpot
                                                                          .y
                                                                          .toStringAsFixed(
                                                                              1);
                                                                  return LineTooltipItem(
                                                                    '$label: $value',
                                                                    TextStyle(
                                                                      color:
                                                                          color,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          11,
                                                                    ),
                                                                  );
                                                                }).toList();
                                                              },
                                                              tooltipBgColor: Colors
                                                                  .black
                                                                  .withValues(
                                                                      alpha:
                                                                          0.95),
                                                              tooltipRoundedRadius:
                                                                  8,
                                                              tooltipPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          10,
                                                                      vertical:
                                                                          8),
                                                              tooltipMargin: 8,
                                                            ),
                                                            handleBuiltInTouches:
                                                                true,
                                                          ),
                                                          gridData: FlGridData(
                                                            show: true,
                                                            drawVerticalLine:
                                                                true,
                                                            horizontalInterval:
                                                                maxY / 5,
                                                            verticalInterval: 1,
                                                            getDrawingHorizontalLine:
                                                                (value) {
                                                              return FlLine(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                  alpha: 0.1,
                                                                ),
                                                                strokeWidth: 1,
                                                              );
                                                            },
                                                            getDrawingVerticalLine:
                                                                (value) {
                                                              return FlLine(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                  alpha: 0.1,
                                                                ),
                                                                strokeWidth: 1,
                                                              );
                                                            },
                                                          ),
                                                          titlesData:
                                                              FlTitlesData(
                                                            show: true,
                                                            rightTitles:
                                                                const AxisTitles(
                                                              sideTitles:
                                                                  SideTitles(
                                                                showTitles:
                                                                    false,
                                                              ),
                                                            ),
                                                            topTitles:
                                                                const AxisTitles(
                                                              sideTitles:
                                                                  SideTitles(
                                                                showTitles:
                                                                    false,
                                                              ),
                                                            ),
                                                            bottomTitles:
                                                                AxisTitles(
                                                              sideTitles:
                                                                  SideTitles(
                                                                showTitles:
                                                                    true,
                                                                reservedSize:
                                                                    30,
                                                                interval: 1,
                                                                getTitlesWidget:
                                                                    (
                                                                  double value,
                                                                  TitleMeta
                                                                      meta,
                                                                ) {
                                                                  const style =
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        12,
                                                                  );
                                                                  Widget text;
                                                                  switch (value
                                                                      .toInt()) {
                                                                    case 0:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'mon',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    case 1:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'tue',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    case 2:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'wed',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    case 3:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'thu',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    case 4:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'fri',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    case 5:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'sat',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    case 6:
                                                                      text =
                                                                          Text(
                                                                        translate(
                                                                          'sun',
                                                                          locale,
                                                                        ),
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                    default:
                                                                      text =
                                                                          const Text(
                                                                        '',
                                                                        style:
                                                                            style,
                                                                      );
                                                                      break;
                                                                  }
                                                                  return SideTitleWidget(
                                                                    axisSide: meta
                                                                        .axisSide,
                                                                    space: 8,
                                                                    child: text,
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                            leftTitles:
                                                                AxisTitles(
                                                              sideTitles:
                                                                  SideTitles(
                                                                showTitles:
                                                                    true,
                                                                interval:
                                                                    maxY / 5,
                                                                getTitlesWidget:
                                                                    (
                                                                  double value,
                                                                  TitleMeta
                                                                      meta,
                                                                ) {
                                                                  String label;
                                                                  if (_showGlobalTrend &&
                                                                      maxY >
                                                                          1000) {
                                                                    // Milyar kg cinsinden göster
                                                                    label =
                                                                        '${(value / 1000000000).toStringAsFixed(1)}B';
                                                                  } else {
                                                                    label =
                                                                        '${value.toInt()}';
                                                                  }
                                                                  return Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        right:
                                                                            8),
                                                                    child: Text(
                                                                      label,
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            12,
                                                                        shadows: [
                                                                          Shadow(
                                                                            color:
                                                                                Colors.black,
                                                                            blurRadius:
                                                                                3,
                                                                            offset:
                                                                                Offset(1, 1),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      textAlign:
                                                                          TextAlign
                                                                              .right,
                                                                    ),
                                                                  );
                                                                },
                                                                reservedSize:
                                                                    50,
                                                              ),
                                                            ),
                                                          ),
                                                          borderData:
                                                              FlBorderData(
                                                            show: true,
                                                            border: Border.all(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.2),
                                                            ),
                                                          ),
                                                          minX: 0,
                                                          maxX: 6,
                                                          minY: 0,
                                                          maxY: maxY.toDouble(),
                                                          lineBarsData: [
                                                            // Kullanıcının kendi verileri (ana çizgi)
                                                            LineChartBarData(
                                                              spots:
                                                                  List.generate(
                                                                7,
                                                                (index) =>
                                                                    FlSpot(
                                                                  index
                                                                      .toDouble(),
                                                                  normalizedData
                                                                              .isNotEmpty &&
                                                                          index <
                                                                              normalizedData
                                                                                  .length
                                                                      ? normalizedData[index].clamp(
                                                                          0.0,
                                                                          double
                                                                              .infinity)
                                                                      : 0.0,
                                                                ),
                                                              ),
                                                              isCurved: true,
                                                              gradient:
                                                                  const LinearGradient(
                                                                colors: [
                                                                  Color(
                                                                      0xFF304411),
                                                                  Color(
                                                                      0xFF48631F),
                                                                ],
                                                              ),
                                                              barWidth: 3,
                                                              isStrokeCapRound:
                                                                  true,
                                                              dotData:
                                                                  FlDotData(
                                                                show: true,
                                                                getDotPainter: (
                                                                  spot,
                                                                  percent,
                                                                  barData,
                                                                  index,
                                                                ) {
                                                                  return FlDotCirclePainter(
                                                                    radius: 4,
                                                                    color:
                                                                        const Color(
                                                                      0xFF304411,
                                                                    ),
                                                                    strokeWidth:
                                                                        2,
                                                                    strokeColor:
                                                                        Colors
                                                                            .white,
                                                                  );
                                                                },
                                                              ),
                                                              belowBarData:
                                                                  BarAreaData(
                                                                show: true,
                                                                gradient:
                                                                    LinearGradient(
                                                                  colors: [
                                                                    const Color(
                                                                      0xFF304411,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    ),
                                                                    const Color(
                                                                      0xFF48631F,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.1,
                                                                    ),
                                                                  ],
                                                                  begin: Alignment
                                                                      .topCenter,
                                                                  end: Alignment
                                                                      .bottomCenter,
                                                                ),
                                                              ),
                                                            ),
                                                            // Ülke karşılaştırma çizgileri
                                                            if (_showCountryComparison &&
                                                                !_showGlobalTrend)
                                                              ..._buildCountryLines(
                                                                  normalizedData,
                                                                  maxY.toDouble()),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                      // Legend (açıklama) - ülke çizgileri için
                                      if (_showCountryComparison &&
                                          !_showGlobalTrend &&
                                          _countryTrends.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 12, bottom: 8),
                                          child: Wrap(
                                            spacing: 16,
                                            runSpacing: 8,
                                            alignment: WrapAlignment.center,
                                            children: [
                                              // Kullanıcının kendi verisi
                                              _buildLegendItem(
                                                'Sizin Verileriniz',
                                                const Color(0xFF304411),
                                              ),
                                              // Ülke verileri
                                              ..._countryTrends.keys.map(
                                                (countryName) =>
                                                    _buildLegendItem(
                                                  countryName,
                                                  _getCountryColor(countryName),
                                                  isRealData:
                                                      _countryDataSources[
                                                              countryName] ??
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
                                          padding: const EdgeInsets.only(
                                              top: 4, bottom: 8),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                size: 10,
                                                color: Colors.green
                                                    .withValues(alpha: 0.7),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Gerçek Veri',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                  fontSize: 10,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Icon(
                                                Icons.info_outline,
                                                size: 10,
                                                color: Colors.orange
                                                    .withValues(alpha: 0.7),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Tahmini Veri',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 16),
                                      // Yenile butonu
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () {
                                              if (_showGlobalTrend) {
                                                _loadGlobalTrendData();
                                              } else {
                                                _loadTrendData();
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 18,
                                            ),
                                            label: Text(
                                              translate('refresh', locale),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _showGlobalTrend
                                            ? translate(
                                                'global_trend_description',
                                                locale)
                                            : translate(
                                                'last_7_days_trend', locale),
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
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                                            'category_distribution', locale),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(color: Colors.white),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          // Pasta grafiği
                                          SizedBox(
                                            width: 180,
                                            height: 180,
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
                                                    titleStyle: const TextStyle(
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
                                                    titleStyle: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  // Gaz - Beyaz/Açık Gri
                                                  PieChartSectionData(
                                                    color: Colors.grey.shade300,
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
                                                    titleStyle: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
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
                                            ),
                                          ),
                                        ],
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
    // Convert to tonnes for display; be resilient to null
    final double tonnes = (kgCo2e ?? 0) / 1000.0;
    // Progress baseline to avoid errors; cap between 0 and 1
    const double maxTonnesReference = 50.0; // arbitrary scale for ring fill
    final double progress = (tonnes / maxTonnesReference).clamp(0.0, 1.0);

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
          // Inner content
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
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                        Text(
                          tonnes.toStringAsFixed(1),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          translate('tonnes_co2e', locale),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            translate('greenhouse_gas_emissions', locale),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.black
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onToggleChanged != null) ...[
                    const SizedBox(height: 12),
                    // Switch'i GestureDetector'dan ayır - kendi tıklama alanı olsun
                    GestureDetector(
                      // Switch'in tıklamalarını engelleme
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (onToggleChanged != null && useEspData) {
                                onToggleChanged!(false);
                              }
                            },
                            child: Text(
                              translate('manual', locale),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.black87
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: useEspData,
                            onChanged: onToggleChanged,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              if (onToggleChanged != null && !useEspData) {
                                onToggleChanged!(true);
                              }
                            },
                            child: Text(
                              'ESP',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.black87
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
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
