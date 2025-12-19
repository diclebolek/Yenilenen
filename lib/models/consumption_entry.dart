class ConsumptionEntry {
  final double electricityKwh;
  final double fuelLiters;
  final double waterCubicMeters;
  final double wasteKg;
  final DateTime createdAt;

  const ConsumptionEntry({
    required this.electricityKwh,
    required this.fuelLiters,
    required this.waterCubicMeters,
    required this.wasteKg,
    required this.createdAt,
  });

  @override
  String toString() {
    return 'electricityKwh=$electricityKwh, fuelLiters=$fuelLiters, waterM3=$waterCubicMeters, wasteKg=$wasteKg, at=${createdAt.toIso8601String()}';
  }
}

