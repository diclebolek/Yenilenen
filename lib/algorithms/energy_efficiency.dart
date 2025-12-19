import 'dart:math';
import '../models/consumption_entry.dart';

/// Enerji verimliliği algoritmaları sınıfı
/// Dinamik programlama ve greedy algoritmalar ile optimal enerji kullanımı
class EnergyEfficiencyAlgorithm {
  /// Dinamik programlama ile optimal zamanlama hesaplama
  /// Günlük tüketim verilerini analiz ederek en verimli zamanlama önerir
  static List<Map<String, dynamic>> optimizeEnergyUsage(
    List<ConsumptionEntry> consumptionHistory,
    Map<String, double> tariffRates,
  ) {
    final n = consumptionHistory.length;
    if (n == 0) return [];

    // DP tablosu: dp[i][hour] = i. gün saat hour'da minimum maliyet
    final dp = List.generate(n + 1, (_) => List.filled(24, double.infinity));
    final path = List.generate(n + 1, (_) => List.filled(24, -1));

    // Başlangıç durumu
    for (int hour = 0; hour < 24; hour++) {
      dp[0][hour] = 0.0;
    }

    // Dinamik programlama ile optimal çözüm bulma
    for (int i = 1; i <= n; i++) {
      final entry = consumptionHistory[i - 1];
      final totalConsumption =
          entry.electricityKwh + entry.fuelLiters + entry.waterCubicMeters;

      for (int hour = 0; hour < 24; hour++) {
        // Mevcut saatteki maliyet
        final currentCost = totalConsumption * tariffRates['hour_$hour']!;

        // Önceki saatten gelen maliyet (gece tarifesi avantajı)
        final nightCost =
            totalConsumption *
            tariffRates['hour_${(hour - 1 + 24) % 24}']! *
            0.8;

        if (dp[i - 1][hour] + currentCost < dp[i][hour]) {
          dp[i][hour] = dp[i - 1][hour] + currentCost;
          path[i][hour] = hour;
        }

        if (dp[i - 1][(hour - 1 + 24) % 24] + nightCost < dp[i][hour]) {
          dp[i][hour] = dp[i - 1][(hour - 1 + 24) % 24] + nightCost;
          path[i][hour] = (hour - 1 + 24) % 24;
        }
      }
    }

    return _generateOptimalSchedule(dp, path, consumptionHistory, tariffRates);
  }

  /// Greedy algoritma ile anlık tasarruf hesaplama
  /// Mevcut tüketimi ortalama ile karşılaştırarak tasarruf önerileri sunar
  static Map<String, dynamic> calculateImmediateSavings(
    ConsumptionEntry currentConsumption,
    ConsumptionEntry averageConsumption,
  ) {
    final savings = <String, double>{};
    final recommendations = <String>[];

    // Elektrik tasarrufu hesaplama
    final electricityDiff =
        averageConsumption.electricityKwh - currentConsumption.electricityKwh;
    if (electricityDiff > 0) {
      savings['electricity'] = electricityDiff * 0.233; // CO2 faktörü
      recommendations.add(
        'Elektrik tüketiminiz ortalamadan ${electricityDiff.toStringAsFixed(2)} kWh düşük. '
        'Bu durumu koruyarak aylık ${(electricityDiff * 30 * 0.233).toStringAsFixed(2)} kg CO2 tasarrufu sağlayabilirsiniz.',
      );
    } else {
      savings['electricity'] = electricityDiff * 0.233;
      recommendations.add(
        'Elektrik tüketiminiz ortalamadan ${(-electricityDiff).toStringAsFixed(2)} kWh yüksek. '
        'LED ampul kullanımı ve gereksiz cihazları kapatarak tasarruf sağlayabilirsiniz.',
      );
    }

    // Su tasarrufu hesaplama
    final waterDiff =
        averageConsumption.waterCubicMeters -
        currentConsumption.waterCubicMeters;
    if (waterDiff > 0) {
      savings['water'] = waterDiff * 0.344; // CO2 faktörü
      recommendations.add(
        'Su tüketiminiz ortalamadan ${waterDiff.toStringAsFixed(2)} m³ düşük. '
        'Su tasarruflu cihazlar kullanarak bu başarıyı sürdürebilirsiniz.',
      );
    } else {
      savings['water'] = waterDiff * 0.344;
      recommendations.add(
        'Su tüketiminiz ortalamadan ${(-waterDiff).toStringAsFixed(2)} m³ yüksek. '
        'Duş süresini kısaltarak ve su tasarruflu musluklar kullanarak tasarruf sağlayabilirsiniz.',
      );
    }

    // Yakıt tasarrufu hesaplama
    final fuelDiff =
        averageConsumption.fuelLiters - currentConsumption.fuelLiters;
    if (fuelDiff > 0) {
      savings['fuel'] = fuelDiff * 2.31; // CO2 faktörü
      recommendations.add(
        'Yakıt tüketiminiz ortalamadan ${fuelDiff.toStringAsFixed(2)} litre düşük. '
        'Toplu taşıma kullanımını artırarak bu başarıyı sürdürebilirsiniz.',
      );
    } else {
      savings['fuel'] = fuelDiff * 2.31;
      recommendations.add(
        'Yakıt tüketiminiz ortalamadan ${(-fuelDiff).toStringAsFixed(2)} litre yüksek. '
        'Araç paylaşımı ve bisiklet kullanımı ile tasarruf sağlayabilirsiniz.',
      );
    }

    final totalSavings = savings.values.reduce((a, b) => a + b);

    return {
      'totalSavings': totalSavings,
      'breakdown': savings,
      'recommendations': recommendations,
      'efficiencyScore': _calculateEfficiencyScore(totalSavings),
    };
  }

  /// Peak shaving algoritması - pik saatlerde tüketimi azaltma
  static Map<String, dynamic> calculatePeakShaving(
    List<ConsumptionEntry> hourlyData,
    List<double> peakHours,
  ) {
    if (hourlyData.length != 24) return {'error': '24 saatlik veri gerekli'};

    final peakConsumption = <int, double>{};
    final offPeakConsumption = <int, double>{};

    for (int hour = 0; hour < 24; hour++) {
      final consumption = hourlyData[hour].electricityKwh;

      if (peakHours.contains(hour.toDouble())) {
        peakConsumption[hour] = consumption;
      } else {
        offPeakConsumption[hour] = consumption;
      }
    }

    final peakTotal = peakConsumption.values.reduce((a, b) => a + b);
    final offPeakTotal = offPeakConsumption.values.reduce((a, b) => a + b);

    // Pik saatlerdeki tüketimi %20 azaltma önerisi
    final suggestedReduction = peakTotal * 0.2;
    final potentialSavings = suggestedReduction * 0.233; // CO2 tasarrufu

    return {
      'peakConsumption': peakTotal,
      'offPeakConsumption': offPeakTotal,
      'suggestedReduction': suggestedReduction,
      'potentialSavings': potentialSavings,
      'recommendations': [
        'Pik saatlerde (${peakHours.map((h) => '${h.toInt()}:00').join(', ')}) tüketimi azaltın',
        'Büyük elektrikli cihazları gece saatlerinde kullanın',
        'Klima ve ısıtıcıları pik saatler dışında çalıştırın',
      ],
    };
  }

  /// Verimlilik skoru hesaplama (0-100 arası)
  static int _calculateEfficiencyScore(double totalSavings) {
    if (totalSavings >= 0) {
      return min(100, (totalSavings * 10).round());
    } else {
      return max(0, (100 + totalSavings * 5).round());
    }
  }

  /// Optimal zamanlama çizelgesi oluşturma
  static List<Map<String, dynamic>> _generateOptimalSchedule(
    List<List<double>> dp,
    List<List<int>> path,
    List<ConsumptionEntry> consumptionHistory,
    Map<String, double> tariffRates,
  ) {
    final schedule = <Map<String, dynamic>>[];

    // En optimal sonucu bul
    double minCost = double.infinity;
    int bestHour = 0;

    for (int hour = 0; hour < 24; hour++) {
      if (dp[consumptionHistory.length][hour] < minCost) {
        minCost = dp[consumptionHistory.length][hour];
        bestHour = hour;
      }
    }

    // Geriye doğru takip ederek optimal çizelge oluştur
    int currentHour = bestHour;
    for (int i = consumptionHistory.length; i > 0; i--) {
      final entry = consumptionHistory[i - 1];

      schedule.insert(0, {
        'day': i,
        'optimalHour': currentHour,
        'consumption':
            entry.electricityKwh + entry.fuelLiters + entry.waterCubicMeters,
        'cost': dp[i][currentHour] - dp[i - 1][path[i][currentHour]],
        'tariff': tariffRates['hour_$currentHour'],
        'recommendation': _getHourlyRecommendation(currentHour),
      });

      currentHour = path[i][currentHour];
    }

    return schedule;
  }

  /// Saatlik öneriler
  static String _getHourlyRecommendation(int hour) {
    if (hour >= 22 || hour <= 6) {
      return 'Gece tarifesi - Büyük elektrikli cihazları bu saatlerde kullanın';
    } else if (hour >= 17 && hour <= 21) {
      return 'Pik saatler - Tüketimi mümkün olduğunca azaltın';
    } else if (hour >= 7 && hour <= 11) {
      return 'Sabah saatleri - Orta düzeyde tüketim uygun';
    } else {
      return 'Öğle saatleri - Normal tüketim seviyesi';
    }
  }
}
