import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:fl_chart/fl_chart.dart';

import '../widgets/consumption_form.dart';
import '../widgets/realtime_esp_data_widget.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import '../services/firebase_realtime_service.dart';
import '../models/consumption_entry.dart';
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

  @override
  void initState() {
    super.initState();
    _loadTrendData();
    // ESP verilerini real-time dinle ve otomatik güncelle
    _listenToEspData();
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
          _lastCalculatedKgCo2e = emission;
        });
      }
    });
  }

  /// Son 7 günün verilerini Firebase'den çek ve grafik için hazırla
  Future<void> _loadTrendData() async {
    if (!mounted) return; // Widget dispose edilmişse işlemi durdur
    setState(() => _isLoadingTrends = true);
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 7));
      final endDate = now;

      // Firebase'den geçmiş verileri çek - timeout ile
      final historyData = await _firebaseService
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

      if (!mounted) return; // Widget dispose edilmişse işlemi durdur

      // Eğer history'de veri yoksa, latest verisini de kontrol et
      if (historyData.isEmpty) {
        try {
          // Latest verisini al
          final latestEntry =
              await _firebaseService.getLatestData('esp8266_001');

          if (latestEntry != null && mounted) {
            // Latest verisini bugün olarak ekle
            historyData.add(ConsumptionEntry(
              electricityKwh: latestEntry.electricityKwh,
              waterCubicMeters: latestEntry.waterCubicMeters,
              fuelLiters: latestEntry.fuelLiters,
              wasteKg: latestEntry.wasteKg,
              createdAt: DateTime.now(), // Bugün olarak işaretle
            ));
          } else {
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

      // Günlere göre grupla ve toplam emisyonu hesapla
      final Map<int, List<ConsumptionEntry>> dailyData = {};
      for (var entry in historyData) {
        // Tarih farkını hesapla (mutlak değer)
        final difference = now.difference(entry.createdAt);
        final dayIndex = difference.inDays;

        // Son 7 gün içindeki verileri al (0-6 gün önce)
        if (dayIndex >= 0 && dayIndex < 7) {
          dailyData.putIfAbsent(dayIndex, () => []).add(entry);
        }
      }

      // Eğer hiç veri yoksa, latest verisini kullan (bugün için)
      if (dailyData.isEmpty && historyData.isNotEmpty) {
        // En son veriyi bugün olarak ekle
        final latestEntry = historyData.last;
        dailyData.putIfAbsent(0, () => []).add(latestEntry);
      }

      // Her gün için toplam emisyonu hesapla (günlük trend grafiği için)
      final List<double> emissions = [];
      double totalElectricity = 0;
      double totalGas = 0;
      double totalWater = 0;

      for (int i = 6; i >= 0; i--) {
        // En eski günden en yeni güne (Pazartesi'den Pazar'a)
        if (dailyData.containsKey(i)) {
          double dayEmission = 0;
          for (var entry in dailyData[i]!) {
            final emission = Calculation.calculateDailyEmission(entry);
            dayEmission += emission;

            // Kategori dağılımı için sadece bugünün (i == 0) verilerini topla
            if (i == 0) {
              totalElectricity +=
                  entry.electricityKwh * Calculation.factorElectricityKgPerKwh;
              totalGas += entry.fuelLiters * Calculation.factorFuelKgPerLiter;
              totalWater +=
                  entry.waterCubicMeters * Calculation.factorWaterKgPerM3;
            }
          }
          emissions.add(dayEmission);
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
        for (var entry in dailyData[0]!) {
          todayTotalEmission += Calculation.calculateDailyEmission(entry);
        }
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
                                        setState(
                                          () => _lastCalculatedKgCo2e =
                                              valueKgCo2e,
                                        );
                                      },
                                      languageProvider: widget.languageProvider,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // ESP8266 Anlık Veriler - Raspberry Pi butonuna basıldığında göster
                          if (_selectedMode == _InputMode.raspberry)
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
                                        translate('daily_trends', locale),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: Colors.white),
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
                                          : _dailyEmissions.isEmpty ||
                                                  _dailyEmissions
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
                                              : SizedBox(
                                                  height: 200,
                                                  child: LineChart(
                                                    LineChartData(
                                                      gridData: FlGridData(
                                                        show: true,
                                                        drawVerticalLine: true,
                                                        horizontalInterval: 1,
                                                        verticalInterval: 1,
                                                        getDrawingHorizontalLine:
                                                            (value) {
                                                          return FlLine(
                                                            color: Colors.white
                                                                .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                            strokeWidth: 1,
                                                          );
                                                        },
                                                        getDrawingVerticalLine:
                                                            (value) {
                                                          return FlLine(
                                                            color: Colors.white
                                                                .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                            strokeWidth: 1,
                                                          );
                                                        },
                                                      ),
                                                      titlesData: FlTitlesData(
                                                        show: true,
                                                        rightTitles:
                                                            const AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                            showTitles: false,
                                                          ),
                                                        ),
                                                        topTitles:
                                                            const AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                            showTitles: false,
                                                          ),
                                                        ),
                                                        bottomTitles:
                                                            AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                            showTitles: true,
                                                            reservedSize: 30,
                                                            interval: 1,
                                                            getTitlesWidget: (
                                                              double value,
                                                              TitleMeta meta,
                                                            ) {
                                                              const style =
                                                                  TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 12,
                                                              );
                                                              Widget text;
                                                              switch (value
                                                                  .toInt()) {
                                                                case 0:
                                                                  text = Text(
                                                                    translate(
                                                                      'mon',
                                                                      locale,
                                                                    ),
                                                                    style:
                                                                        style,
                                                                  );
                                                                  break;
                                                                case 1:
                                                                  text = Text(
                                                                    translate(
                                                                      'tue',
                                                                      locale,
                                                                    ),
                                                                    style:
                                                                        style,
                                                                  );
                                                                  break;
                                                                case 2:
                                                                  text = Text(
                                                                    translate(
                                                                      'wed',
                                                                      locale,
                                                                    ),
                                                                    style:
                                                                        style,
                                                                  );
                                                                  break;
                                                                case 3:
                                                                  text = Text(
                                                                    translate(
                                                                      'thu',
                                                                      locale,
                                                                    ),
                                                                    style:
                                                                        style,
                                                                  );
                                                                  break;
                                                                case 4:
                                                                  text = Text(
                                                                    translate(
                                                                      'fri',
                                                                      locale,
                                                                    ),
                                                                    style:
                                                                        style,
                                                                  );
                                                                  break;
                                                                case 5:
                                                                  text = Text(
                                                                    translate(
                                                                      'sat',
                                                                      locale,
                                                                    ),
                                                                    style:
                                                                        style,
                                                                  );
                                                                  break;
                                                                case 6:
                                                                  text = Text(
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
                                                        leftTitles: AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                            showTitles: true,
                                                            interval:
                                                                20, // Her 20 birimde bir sayı göster
                                                            getTitlesWidget: (
                                                              double value,
                                                              TitleMeta meta,
                                                            ) {
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        right:
                                                                            8),
                                                                child: Text(
                                                                  '${value.toInt()}',
                                                                  style:
                                                                      const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        16,
                                                                    shadows: [
                                                                      Shadow(
                                                                        color: Colors
                                                                            .black,
                                                                        blurRadius:
                                                                            3,
                                                                        offset: Offset(
                                                                            1,
                                                                            1),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  textAlign:
                                                                      TextAlign
                                                                          .right,
                                                                ),
                                                              );
                                                            },
                                                            reservedSize: 50,
                                                          ),
                                                        ),
                                                      ),
                                                      borderData: FlBorderData(
                                                        show: true,
                                                        border: Border.all(
                                                          color: Colors.white
                                                              .withValues(
                                                                  alpha: 0.2),
                                                        ),
                                                      ),
                                                      minX: 0,
                                                      maxX: 6,
                                                      minY: 0,
                                                      maxY: _dailyEmissions
                                                                  .isEmpty ||
                                                              _dailyEmissions
                                                                  .every((e) =>
                                                                      e == 0)
                                                          ? 10
                                                          : (_dailyEmissions
                                                                      .reduce(
                                                                    (a, b) =>
                                                                        a > b
                                                                            ? a
                                                                            : b,
                                                                  ) *
                                                                  1.2)
                                                              .clamp(
                                                                  1.0, 100.0),
                                                      lineBarsData: [
                                                        LineChartBarData(
                                                          spots: List.generate(
                                                            7,
                                                            (index) => FlSpot(
                                                              index.toDouble(),
                                                              _dailyEmissions
                                                                          .isNotEmpty &&
                                                                      index <
                                                                          _dailyEmissions
                                                                              .length
                                                                  ? _dailyEmissions[
                                                                          index]
                                                                      .clamp(
                                                                          0.0,
                                                                          100.0)
                                                                  : 0.0,
                                                            ),
                                                          ),
                                                          isCurved: true,
                                                          gradient:
                                                              const LinearGradient(
                                                            colors: [
                                                              Color(0xFF304411),
                                                              Color(0xFF48631F),
                                                            ],
                                                          ),
                                                          barWidth: 3,
                                                          isStrokeCapRound:
                                                              true,
                                                          dotData: FlDotData(
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
                                                                strokeWidth: 2,
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
                                                                  alpha: 0.3,
                                                                ),
                                                                const Color(
                                                                  0xFF48631F,
                                                                ).withValues(
                                                                  alpha: 0.1,
                                                                ),
                                                              ],
                                                              begin: Alignment
                                                                  .topCenter,
                                                              end: Alignment
                                                                  .bottomCenter,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                      const SizedBox(height: 16),
                                      // Yenile butonu
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            onPressed: _loadTrendData,
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
                                        translate('last_7_days_trend', locale),
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
  });

  final double? kgCo2e;
  final double size;
  final LanguageProvider? languageProvider;

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
        children: [
          // Gradient progress ring
          SizedBox(
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  tonnes.toStringAsFixed(1),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  translate('tonnes_co2e', locale),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  translate('greenhouse_gas_emissions', locale),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                ),
              ],
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
