class ConsumptionEntry {
  final double electricityKwh;
  /// Sıvı yakıt için litre; doğalgaz için m³ ([fuelIsNaturalGasM3] true).
  final double fuelLiters;
  final double waterCubicMeters;
  final double wasteKg;
  final DateTime createdAt;
  /// true: [fuelLiters] doğal gaz m³ (EF kg CO₂e/m³); false: sıvı yakıt litre (EF kg CO₂e/L).
  final bool fuelIsNaturalGasM3;

  const ConsumptionEntry({
    required this.electricityKwh,
    required this.fuelLiters,
    required this.waterCubicMeters,
    required this.wasteKg,
    required this.createdAt,
    this.fuelIsNaturalGasM3 = false,
  });

  @override
  String toString() {
    return 'electricityKwh=$electricityKwh, fuelLiters=$fuelLiters, gasM3=$fuelIsNaturalGasM3, waterM3=$waterCubicMeters, wasteKg=$wasteKg, at=${createdAt.toIso8601String()}';
  }
}

