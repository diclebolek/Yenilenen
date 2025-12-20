/// Shelly Plug S cihazından gelen verileri temsil eden model
class ShellyData {
  /// Güç tüketimi (Watt)
  final double powerWatt;

  /// Toplam enerji tüketimi (kWh)
  final double energyKwh;

  /// Voltaj (V)
  final double voltage;

  /// Akım (A)
  final double current;

  /// Cihaz durumu (açık/kapalı)
  final bool isOn;

  /// Sıcaklık (°C)
  final double? temperature;

  /// Cihaz IP adresi
  final String deviceIp;

  /// Cihaz ID'si
  final String deviceId;

  /// Veri alınma zamanı
  final DateTime timestamp;

  const ShellyData({
    required this.powerWatt,
    required this.energyKwh,
    required this.voltage,
    required this.current,
    required this.isOn,
    this.temperature,
    required this.deviceIp,
    required this.deviceId,
    required this.timestamp,
  });

  /// JSON'dan ShellyData oluştur
  factory ShellyData.fromJson(
      Map<String, dynamic> json, String deviceIp, String deviceId) {
    // Shelly API yanıt yapısına göre parse et
    final relays = json['relays'] as List?;
    final meters = json['meters'] as List?;

    // Relay durumu (ilk relay'i kontrol et)
    final isOn = relays != null && relays.isNotEmpty
        ? (relays[0] as Map<String, dynamic>)['ison'] == true
        : false;

    // Güç tüketimi (ilk meter'dan)
    final meter = meters != null && meters.isNotEmpty
        ? meters[0] as Map<String, dynamic>
        : <String, dynamic>{};

    final powerWatt = (meter['power'] ?? 0.0).toDouble();
    final energyKwh =
        (meter['total'] ?? 0.0).toDouble() / 1000.0; // Wh'den kWh'ye çevir
    final voltage = (meter['voltage'] ?? 0.0).toDouble();
    final current = (meter['current'] ?? 0.0).toDouble();

    // Sıcaklık (eğer varsa)
    final temperature = json['temperature'] != null
        ? (json['temperature'] as num).toDouble()
        : null;

    return ShellyData(
      powerWatt: powerWatt,
      energyKwh: energyKwh,
      voltage: voltage,
      current: current,
      isOn: isOn,
      temperature: temperature,
      deviceIp: deviceIp,
      deviceId: deviceId,
      timestamp: DateTime.now(),
    );
  }

  /// Map'e dönüştür (Firebase için)
  Map<String, dynamic> toMap() {
    return {
      'power_watt': powerWatt,
      'energy_kwh': energyKwh,
      'voltage': voltage,
      'current': current,
      'is_on': isOn,
      'temperature': temperature,
      'device_ip': deviceIp,
      'device_id': deviceId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'created_at': timestamp.toIso8601String(),
    };
  }

  /// Map'ten ShellyData oluştur (Firebase'den okuma için)
  factory ShellyData.fromMap(Map<String, dynamic> map) {
    return ShellyData(
      powerWatt: (map['power_watt'] ?? 0.0).toDouble(),
      energyKwh: (map['energy_kwh'] ?? 0.0).toDouble(),
      voltage: (map['voltage'] ?? 0.0).toDouble(),
      current: (map['current'] ?? 0.0).toDouble(),
      isOn: map['is_on'] == true,
      temperature: map['temperature'] != null
          ? (map['temperature'] as num).toDouble()
          : null,
      deviceIp: map['device_ip'] ?? '',
      deviceId: map['device_id'] ?? '',
      timestamp: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.fromMillisecondsSinceEpoch(
              map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            ),
    );
  }

  @override
  String toString() {
    return 'ShellyData(power: ${powerWatt}W, energy: ${energyKwh}kWh, voltage: ${voltage}V, current: ${current}A, isOn: $isOn)';
  }
}
