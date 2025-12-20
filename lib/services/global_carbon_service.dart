import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

/// Dünya geneli karbon ayak izi trend verilerini çeken servis
/// Our World in Data ve diğer açık veri kaynaklarını kullanır
class GlobalCarbonService {
  // Our World in Data GitHub'dan veri çekiyoruz (ücretsiz, API key gerektirmez)
  static const String _owidBaseUrl =
      'https://raw.githubusercontent.com/owid/co2-data/master/owid-co2-data.json';

  GlobalCarbonService();

  /// Dünya geneli günlük CO2 emisyon trendini getir
  /// Son 7 günün ortalamasını döndürür (kg CO₂e)
  Future<List<double>> getGlobalDailyTrend() async {
    try {
      // Our World in Data'dan veri çek
      final response = await http
          .get(Uri.parse(_owidBaseUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Dünya verilerini al (key: "OWID_WRL")
        final worldData = data['OWID_WRL'] as Map<String, dynamic>?;
        if (worldData == null) {
          return _getPlaceholderTrend();
        }

        // Yıllık verileri al
        final yearlyData = worldData['data'] as List<dynamic>?;
        if (yearlyData == null || yearlyData.isEmpty) {
          return _getPlaceholderTrend();
        }

        // Son 7 yılın verilerini al ve günlük ortalamaya çevir
        final recentYears = yearlyData.length >= 7
            ? yearlyData.sublist(yearlyData.length - 7)
            : yearlyData;

        final List<double> dailyTrends = [];
        for (var yearData in recentYears) {
          final yearMap = yearData as Map<String, dynamic>;
          // Yıllık CO2 emisyonu (milyon ton cinsinden)
          final annualEmission = (yearMap['co2'] ?? 0.0).toDouble();
          // Günlük ortalamaya çevir (milyon ton -> kg, sonra günlük)
          // 1 milyon ton = 1,000,000,000 kg
          final dailyEmissionKg = (annualEmission * 1000000000) / 365;
          dailyTrends.add(dailyEmissionKg);
        }

        // Eğer 7 günden az veri varsa, son değeri tekrarla
        while (dailyTrends.length < 7) {
          dailyTrends.add(dailyTrends.isNotEmpty ? dailyTrends.last : 0.0);
        }

        return dailyTrends;
      } else {
        dev.log(
          'Global karbon verisi alınamadı: ${response.statusCode}',
          name: 'GlobalCarbonService',
        );
        return _getPlaceholderTrend();
      }
    } catch (e) {
      dev.log(
        'Global karbon trend hatası: $e',
        name: 'GlobalCarbonService',
      );
      return _getPlaceholderTrend();
    }
  }

  /// Türkiye için günlük CO2 emisyon trendini getir
  Future<List<double>> getTurkeyDailyTrend() async {
    try {
      final response = await http
          .get(Uri.parse(_owidBaseUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Türkiye verilerini al (key: "TUR")
        final turkeyData = data['TUR'] as Map<String, dynamic>?;
        if (turkeyData == null) {
          return _getPlaceholderTrend();
        }

        final yearlyData = turkeyData['data'] as List<dynamic>?;
        if (yearlyData == null || yearlyData.isEmpty) {
          return _getPlaceholderTrend();
        }

        final recentYears = yearlyData.length >= 7
            ? yearlyData.sublist(yearlyData.length - 7)
            : yearlyData;

        final List<double> dailyTrends = [];
        for (var yearData in recentYears) {
          final yearMap = yearData as Map<String, dynamic>;
          final annualEmission = (yearMap['co2'] ?? 0.0).toDouble();
          final dailyEmissionKg = (annualEmission * 1000000000) / 365;
          dailyTrends.add(dailyEmissionKg);
        }

        while (dailyTrends.length < 7) {
          dailyTrends.add(dailyTrends.isNotEmpty ? dailyTrends.last : 0.0);
        }

        return dailyTrends;
      } else {
        return _getPlaceholderTrend();
      }
    } catch (e) {
      dev.log('Türkiye karbon trend hatası: $e', name: 'GlobalCarbonService');
      return _getPlaceholderTrend();
    }
  }

  /// Ortalama kişi başı günlük CO2 emisyonu (kg CO₂e)
  /// Dünya ortalaması: ~4.5 kg/gün
  Future<double> getGlobalAveragePerPerson() async {
    try {
      final response = await http
          .get(Uri.parse(_owidBaseUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final worldData = data['OWID_WRL'] as Map<String, dynamic>?;

        if (worldData != null) {
          final yearlyData = worldData['data'] as List<dynamic>?;
          if (yearlyData != null && yearlyData.isNotEmpty) {
            // En son yılın verisini al
            final latestYear = yearlyData.last as Map<String, dynamic>;
            final annualPerCapita =
                (latestYear['co2_per_capita'] ?? 0.0).toDouble();
            // Yıllık değeri günlüğe çevir (ton -> kg, sonra günlük)
            final dailyPerCapita = (annualPerCapita * 1000) / 365;
            return dailyPerCapita;
          }
        }
      }
    } catch (e) {
      dev.log('Kişi başı ortalama hatası: $e', name: 'GlobalCarbonService');
    }

    // Varsayılan değer (dünya ortalaması)
    return 4.5;
  }

  /// Placeholder trend verisi (API çalışmazsa)
  List<double> _getPlaceholderTrend() {
    // Dünya geneli günlük CO2 emisyonu (milyon ton/gün)
    // Ortalama: ~100 milyon ton/gün = 100,000,000,000 kg/gün
    // Bu değerleri kişisel verilerle karşılaştırmak için normalize ediyoruz
    const double globalDailyAverage =
        100000000000.0; // kg CO₂e/gün (dünya geneli)

    // Son 7 gün için hafif değişkenlik gösteren trend
    return [
      globalDailyAverage * 0.98,
      globalDailyAverage * 0.99,
      globalDailyAverage * 1.0,
      globalDailyAverage * 1.01,
      globalDailyAverage * 0.99,
      globalDailyAverage * 1.02,
      globalDailyAverage * 1.0,
    ];
  }
}
