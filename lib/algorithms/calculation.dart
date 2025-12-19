import '../models/consumption_entry.dart';
import 'energy_efficiency.dart';

/// Gelişmiş karbon ayak izi hesaplama algoritmaları
/// Enerji verimliliği algoritmaları ile entegre çalışır
class Calculation {
  static const double factorElectricityKgPerKwh = 0.233; // kg CO2e per kWh
  static const double factorFuelKgPerLiter = 2.31; // kg CO2e per liter
  static const double factorWaterKgPerM3 = 0.344; // kg CO2e per m3
  static const double factorWasteKgPerKg = 1.9; // kg CO2e per kg

  // Tarife oranları (Türkiye için örnek değerler)
  static const Map<String, double> tariffRates = {
    'hour_0': 0.25,
    'hour_1': 0.25,
    'hour_2': 0.25,
    'hour_3': 0.25,
    'hour_4': 0.25,
    'hour_5': 0.25,
    'hour_6': 0.25,
    'hour_7': 0.35,
    'hour_8': 0.35,
    'hour_9': 0.35,
    'hour_10': 0.35,
    'hour_11': 0.35,
    'hour_12': 0.35,
    'hour_13': 0.35,
    'hour_14': 0.35,
    'hour_15': 0.35,
    'hour_16': 0.35,
    'hour_17': 0.50,
    'hour_18': 0.50,
    'hour_19': 0.50,
    'hour_20': 0.50,
    'hour_21': 0.50,
    'hour_22': 0.25,
    'hour_23': 0.25,
  };

  /// Günlük emisyon hesaplama (temel)
  static double calculateDailyEmission(ConsumptionEntry entry) {
    final electricity = entry.electricityKwh * factorElectricityKgPerKwh;
    final fuel = entry.fuelLiters * factorFuelKgPerLiter;
    final water = entry.waterCubicMeters * factorWaterKgPerM3;
    final waste = entry.wasteKg * factorWasteKgPerKg;
    return electricity + fuel + water + waste;
  }

  /// Gelişmiş emisyon hesaplama (enerji verimliliği ile)
  static Map<String, dynamic> calculateAdvancedEmission(
    ConsumptionEntry entry,
    List<ConsumptionEntry> historicalData,
  ) {
    final basicEmission = calculateDailyEmission(entry);

    // Enerji verimliliği analizi
    if (historicalData.isNotEmpty) {
      final averageConsumption = _calculateAverageConsumption(historicalData);
      final savings = EnergyEfficiencyAlgorithm.calculateImmediateSavings(
        entry,
        averageConsumption,
      );

      // Optimal zamanlama analizi
      final optimalSchedule = EnergyEfficiencyAlgorithm.optimizeEnergyUsage(
        historicalData,
        tariffRates,
      );

      // Peak shaving analizi
      final peakHours = [17.0, 18.0, 19.0, 20.0, 21.0]; // Pik saatler
      final peakShaving = EnergyEfficiencyAlgorithm.calculatePeakShaving(
        historicalData.take(24).toList(),
        peakHours,
      );

      return {
        'basicEmission': basicEmission,
        'optimizedEmission': basicEmission - (savings['totalSavings'] ?? 0),
        'potentialSavings': savings['totalSavings'] ?? 0,
        'efficiencyScore': savings['efficiencyScore'] ?? 0,
        'recommendations': savings['recommendations'] ?? [],
        'optimalSchedule': optimalSchedule,
        'peakShaving': peakShaving,
        'carbonFootprint': {
          'daily': basicEmission,
          'weekly': basicEmission * 7,
          'monthly': basicEmission * 30,
          'yearly': basicEmission * 365,
        },
      };
    }

    return {
      'basicEmission': basicEmission,
      'carbonFootprint': {
        'daily': basicEmission,
        'weekly': basicEmission * 7,
        'monthly': basicEmission * 30,
        'yearly': basicEmission * 365,
      },
    };
  }

  /// Ortalama tüketim hesaplama
  static ConsumptionEntry _calculateAverageConsumption(
    List<ConsumptionEntry> data,
  ) {
    if (data.isEmpty) {
      return ConsumptionEntry(
        electricityKwh: 0,
        waterCubicMeters: 0,
        fuelLiters: 0,
        wasteKg: 0,
        createdAt: DateTime.now(),
      );
    }

    final totalElectricity = data.fold(
      0.0,
      (sum, entry) => sum + entry.electricityKwh,
    );
    final totalWater = data.fold(
      0.0,
      (sum, entry) => sum + entry.waterCubicMeters,
    );
    final totalFuel = data.fold(0.0, (sum, entry) => sum + entry.fuelLiters);
    final totalWaste = data.fold(0.0, (sum, entry) => sum + entry.wasteKg);

    return ConsumptionEntry(
      electricityKwh: totalElectricity / data.length,
      waterCubicMeters: totalWater / data.length,
      fuelLiters: totalFuel / data.length,
      wasteKg: totalWaste / data.length,
      createdAt: DateTime.now(),
    );
  }

  /// Karbon ayak izi kategorilerine göre analiz
  static Map<String, dynamic> analyzeEmissionByCategory(
    ConsumptionEntry entry,
  ) {
    final electricityEmission =
        entry.electricityKwh * factorElectricityKgPerKwh;
    final fuelEmission = entry.fuelLiters * factorFuelKgPerLiter;
    final waterEmission = entry.waterCubicMeters * factorWaterKgPerM3;
    final wasteEmission = entry.wasteKg * factorWasteKgPerKg;

    final totalEmission =
        electricityEmission + fuelEmission + waterEmission + wasteEmission;

    return {
      'electricity': {
        'emission': electricityEmission,
        'percentage': totalEmission > 0
            ? (electricityEmission / totalEmission) * 100
            : 0,
        'category': 'Enerji Tüketimi',
        'recommendation': 'LED ampul kullanın, gereksiz cihazları kapatın',
      },
      'fuel': {
        'emission': fuelEmission,
        'percentage': totalEmission > 0
            ? (fuelEmission / totalEmission) * 100
            : 0,
        'category': 'Ulaşım',
        'recommendation': 'Toplu taşıma kullanın, bisiklet tercih edin',
      },
      'water': {
        'emission': waterEmission,
        'percentage': totalEmission > 0
            ? (waterEmission / totalEmission) * 100
            : 0,
        'category': 'Su Tüketimi',
        'recommendation': 'Su tasarruflu cihazlar kullanın',
      },
      'waste': {
        'emission': wasteEmission,
        'percentage': totalEmission > 0
            ? (wasteEmission / totalEmission) * 100
            : 0,
        'category': 'Atık Yönetimi',
        'recommendation': 'Geri dönüşüm yapın, kompost kullanın',
      },
      'total': totalEmission,
    };
  }

  /// Çevresel etki skoru hesaplama (0-100)
  static int calculateEnvironmentalScore(double dailyEmission) {
    // Türkiye ortalaması: ~15 kg CO2/gün
    const double averageEmission = 15.0;

    if (dailyEmission <= averageEmission * 0.5) {
      return 100; // Çok iyi
    } else if (dailyEmission <= averageEmission * 0.75) {
      return 80; // İyi
    } else if (dailyEmission <= averageEmission) {
      return 60; // Orta
    } else if (dailyEmission <= averageEmission * 1.25) {
      return 40; // Kötü
    } else {
      return 20; // Çok kötü
    }
  }
}
