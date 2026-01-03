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
  /// Hem klasik Shelly formatını hem de Gen2 (Plus) formatını destekler
  factory ShellyData.fromJson(
      Map<String, dynamic> json, String deviceIp, String deviceId) {
    // Gen2 (Plus) formatını kontrol et
    // 1. Önce direkt Gen2 formatını kontrol et (Switch.GetStatus yanıtı)
    if (json.containsKey('output') && json.containsKey('apower')) {
      // Relay durumu
      final isOn = json['output'] == true;
      
      // Güç tüketimi (apower = anlık güç, Watt)
      final powerWatt = (json['apower'] ?? 0.0).toDouble();
      
      // Voltaj
      final voltage = (json['voltage'] ?? 0.0).toDouble();
      
      // Akım
      final current = (json['current'] ?? 0.0).toDouble();
      
      // Enerji tüketimi (aenergy.total = toplam enerji, Wh cinsinden)
      final aenergy = json['aenergy'] as Map<String, dynamic>?;
      final energyKwh = aenergy != null && aenergy['total'] != null
          ? (aenergy['total'] as num).toDouble() / 1000.0 // Wh'den kWh'ye çevir
          : 0.0;
      
      // Sıcaklık (temperature.tC)
      final tempData = json['temperature'] as Map<String, dynamic>?;
      final temperature = tempData != null && tempData['tC'] != null
          ? (tempData['tC'] as num).toDouble()
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
    
    // 2. switch:0 objesi içinde Gen2 formatını kontrol et
    if (json.containsKey('switch:0')) {
      final switchData = json['switch:0'] as Map<String, dynamic>;
      
      // Relay durumu
      final isOn = switchData['output'] == true;
      
      // Güç tüketimi (apower = anlık güç, Watt)
      final powerWatt = (switchData['apower'] ?? 0.0).toDouble();
      
      // Voltaj
      final voltage = (switchData['voltage'] ?? 0.0).toDouble();
      
      // Akım
      final current = (switchData['current'] ?? 0.0).toDouble();
      
      // Enerji tüketimi (aenergy.total = toplam enerji, Wh cinsinden)
      final aenergy = switchData['aenergy'] as Map<String, dynamic>?;
      final energyKwh = aenergy != null && aenergy['total'] != null
          ? (aenergy['total'] as num).toDouble() / 1000.0 // Wh'den kWh'ye çevir
          : 0.0;
      
      // Sıcaklık (temperature.tC)
      final tempData = switchData['temperature'] as Map<String, dynamic>?;
      final temperature = tempData != null && tempData['tC'] != null
          ? (tempData['tC'] as num).toDouble()
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
    
    // 3. /relay/0 endpoint formatı (sadece relay durumu, enerji verileri yok)
    if (json.containsKey('ison') && !json.containsKey('apower') && !json.containsKey('power')) {
      // Bu sadece relay durumu, enerji verileri yok
      // Varsayılan değerlerle döndür (enerji verileri için /rpc kullanılmalı)
      // Not: debugPrint kullanılamaz çünkü bu bir model sınıfı, loglama servis katmanında yapılmalı
      return ShellyData(
        powerWatt: 0.0,
        energyKwh: 0.0,
        voltage: 0.0,
        current: 0.0,
        isOn: json['ison'] == true,
        temperature: null,
        deviceIp: deviceIp,
        deviceId: deviceId,
        timestamp: DateTime.now(),
      );
    }
    
    // Klasik Shelly formatı (relays ve meters)
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
