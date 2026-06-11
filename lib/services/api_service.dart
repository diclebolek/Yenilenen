import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../models/consumption_entry.dart';
import '../models/shelly_data.dart';
import '../config/env_config.dart';
import 'firebase_realtime_service.dart';
import 'shelly_service.dart';

/// API servisi - ESP modülü, Shelly ve Firebase entegrasyonu
class ApiService {
  static String get espBaseUrl => EnvConfig.espBaseUrl;

  static String get deviceId => EnvConfig.espDeviceId;

  final FirebaseRealtimeService _firebaseService =
      FirebaseRealtimeService.instance;

  // Shelly Plug S servisi (opsiyonel, IP adresi ile başlatılabilir)
  ShellyService? _shellyService;

  ApiService();

  /// ESP'den `/api/consumption` okur. Başarılıysa kayıt, ağ/HTTP hatasında [null].
  /// Firebase'e yazmayı dener; yazılamasa bile ESP'den gelen [ConsumptionEntry] döner.
  Future<ConsumptionEntry?> fetchEspConsumptionOrNull({
    bool saveToFirebase = true,
  }) async {
    try {
      // Web'de CORS preflight tetiklememek icin GET'e ozel header eklemiyoruz.
      final response = await http
          .get(Uri.parse('$espBaseUrl/api/consumption'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        dev.log(
          'ESP /api/consumption HTTP ${response.statusCode}',
          name: 'ApiService',
        );
        return null;
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        return null;
      }
      final data = Map<String, dynamic>.from(decoded);

      // Su verisi: ESP'den water_flow_liters geliyorsa onu kullan, yoksa water kullan
      // water_flow_liters litre cinsinden, m³'e çevir (1 litre = 0.001 m³)
      final waterLiters =
          (data['water_flow_liters'] ?? data['water'] ?? 0.0).toDouble();
      final waterCubicMeters = waterLiters * 0.001;

      final gasConsumptionM3 =
          (data['gas_consumption_m3'] ?? data['fuel'] ?? 0.0).toDouble();

      final consumption = ConsumptionEntry(
        electricityKwh: (data['electricity'] ?? 0.0).toDouble(),
        waterCubicMeters: waterCubicMeters,
        fuelLiters: gasConsumptionM3, // Doğalgaz m³
        wasteKg: (data['waste'] ?? 0.0).toDouble(),
        createdAt: DateTime.now(),
        fuelIsNaturalGasM3: true,
      );

      if (saveToFirebase) {
        try {
          await _firebaseService.saveEsp8266Data(
            deviceId: deviceId,
            consumption: consumption,
            additionalData: {
              'gas_consumption_m3': gasConsumptionM3,
              'water_flow_liters': data['water_flow_liters'] ?? 0.0,
              'flow_rate_lpm': data['flow_rate_lpm'] ?? 0.0,
            },
          );
        } catch (e) {
          dev.log(
            'Firebase kayıt hatası (devam ediliyor): $e',
            name: 'ApiService',
          );
        }
      }

      return consumption;
    } catch (e, st) {
      dev.log(
        'ESP bağlantı hatası: $e',
        name: 'ApiService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// ESP modülünden canlı tüketim verilerini çek ve Firebase'e kaydet
  Future<ConsumptionEntry> getLiveConsumptionData({
    bool saveToFirebase = true,
  }) async {
    final ok = await fetchEspConsumptionOrNull(saveToFirebase: saveToFirebase);
    if (ok != null) {
      return ok;
    }
    return ConsumptionEntry(
      electricityKwh: 0.0,
      waterCubicMeters: 0.0,
      fuelLiters: 0.0,
      wasteKg: 0.0,
      createdAt: DateTime.now(),
    );
  }

  /// ESP modülü durumunu kontrol et ve Firebase'e kaydet
  Future<Map<String, dynamic>> getEspStatus({
    bool saveToFirebase = true,
  }) async {
    try {
      // Web CORS uyumlulugu icin gereksiz header kullanmiyoruz.
      final response = await http
          .get(Uri.parse('$espBaseUrl/api/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = {
          'connected': true,
          'uptime': data['uptime'],
          'sensors': data['sensors'],
          'wifi': data['wifi'],
        };

        // Firebase'e kaydet (opsiyonel)
        if (saveToFirebase) {
          try {
            await _firebaseService.saveEsp8266Status(
              deviceId: deviceId,
              status: status,
            );
          } catch (e) {
            dev.log(
              'Firebase durum kayıt hatası (devam ediliyor): $e',
              name: 'ApiService',
            );
          }
        }

        return status;
      }
    } catch (e, st) {
      dev.log(
        'ESP durum kontrolü hatası: $e',
        name: 'ApiService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
    }

    return {'connected': false, 'error': 'ESP modülüne bağlanılamadı'};
  }

  // Placeholder: implement real weather call in a future version.
  Future<Map<String, dynamic>> getWeatherAdjustment(String city) async {
    return {'status': 'coming_soon', 'city': city};
  }

  /// Firebase'den real-time veri dinle
  /// Stream döndürür, widget'ta StreamBuilder ile kullanılabilir
  Stream<ConsumptionEntry?> listenToFirebaseData() {
    return _firebaseService.listenToEsp8266Data(deviceId);
  }

  /// Firebase'den real-time durum dinle
  Stream<Map<String, dynamic>?> listenToFirebaseStatus() {
    return _firebaseService.listenToEsp8266Status(deviceId);
  }

  /// Firebase'den geçmiş verileri getir
  Future<List<ConsumptionEntry>> getFirebaseHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return await _firebaseService.getHistoryData(
      deviceId: deviceId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  // ========== SHELLY PLUG S ENTEGRASYONU ==========

  /// Shelly Plug S servisini başlat
  /// deviceIp: Shelly cihazının IP adresi (örn: '192.168.1.100')
  /// deviceId: Cihaz ID'si (opsiyonel, IP kullanılabilir)
  void initializeShelly({
    required String deviceIp,
    String? deviceId,
  }) {
    _shellyService = ShellyService(
      deviceIp: deviceIp,
      deviceId: deviceId,
    );
    dev.log(
      'Shelly servisi başlatıldı: $deviceIp',
      name: 'ApiService',
    );
  }

  /// Shelly Plug S'den güç tüketimi verilerini al
  /// HTTP API üzerinden anlık veri çeker
  Future<ShellyData> getShellyData({
    bool saveToFirebase = true,
  }) async {
    if (_shellyService == null) {
      throw Exception(
        'Shelly servisi başlatılmamış. initializeShelly() çağrılmalı.',
      );
    }

    try {
      final shellyData = await _shellyService!.getStatus();

      // Firebase'e kaydet (opsiyonel)
      if (saveToFirebase) {
        try {
          await _firebaseService.saveShellyData(
            deviceId: shellyData.deviceId,
            shellyData: shellyData,
          );
        } catch (e) {
          dev.log(
            'Firebase Shelly kayıt hatası (devam ediliyor): $e',
            name: 'ApiService',
          );
          // Firebase hatası olsa bile veriyi döndür
        }
      }

      return shellyData;
    } catch (e, st) {
      dev.log(
        'Shelly veri alma hatası: $e',
        name: 'ApiService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Shelly Plug S'yi aç/kapat
  /// turn: 'on' veya 'off'
  Future<bool> setShellyRelayState({required String turn}) async {
    if (_shellyService == null) {
      throw Exception(
        'Shelly servisi başlatılmamış. initializeShelly() çağrılmalı.',
      );
    }

    try {
      return await _shellyService!.setRelayState(turn: turn);
    } catch (e, st) {
      dev.log(
        'Shelly relay kontrol hatası: $e',
        name: 'ApiService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Shelly WebSocket bağlantısını başlat
  /// Gerçek zamanlı veri akışı için
  Future<void> connectShellyWebSocket() async {
    if (_shellyService == null) {
      throw Exception(
        'Shelly servisi başlatılmamış. initializeShelly() çağrılmalı.',
      );
    }

    try {
      await _shellyService!.connectWebSocket();
    } catch (e, st) {
      dev.log(
        'Shelly WebSocket bağlantı hatası: $e',
        name: 'ApiService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Shelly WebSocket bağlantısını kapat
  Future<void> disconnectShellyWebSocket() async {
    if (_shellyService != null) {
      await _shellyService!.disconnectWebSocket();
    }
  }

  /// Shelly WebSocket üzerinden gerçek zamanlı veri stream'i
  /// StreamBuilder ile kullanılabilir
  Stream<ShellyData>? getShellyRealtimeData() {
    if (_shellyService == null) {
      return null;
    }
    return _shellyService!.realtimeData;
  }

  /// Shelly bağlantı durumunu kontrol et
  Future<bool> checkShellyConnection() async {
    if (_shellyService == null) {
      return false;
    }
    return await _shellyService!.checkConnection();
  }

  /// Firebase'den Shelly real-time veri dinle
  /// Stream döndürür, widget'ta StreamBuilder ile kullanılabilir
  Stream<ShellyData?> listenToFirebaseShellyData(String deviceId) {
    return _firebaseService.listenToShellyData(deviceId);
  }

  /// Firebase'den Shelly geçmiş verileri getir
  Future<List<ShellyData>> getFirebaseShellyHistory({
    required String deviceId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return await _firebaseService.getShellyHistory(
      deviceId: deviceId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Shelly verilerini ConsumptionEntry'ye dönüştür
  /// [ShellyData.energyKwh] cihazın **kümülatif** kWh sayacıdır (günlük tüketim değil).
  /// Günlük emisyon için rapor ekranında ardışık örnek farkı kullanılır.
  ConsumptionEntry shellyDataToConsumptionEntry(ShellyData shellyData) {
    return ConsumptionEntry(
      electricityKwh: shellyData.energyKwh,
      waterCubicMeters: 0.0, // Shelly'de su verisi yok
      fuelLiters: 0.0, // Shelly'de yakıt verisi yok
      wasteKg: 0.0, // Shelly'de atık verisi yok
      createdAt: shellyData.timestamp,
    );
  }

  /// Kümülatif Shelly kayıtlarını ardışık farkla tüketim girişlerine çevirir.
  /// Uzun veri boşluklarında veya sayaç sıçramalarında tüm kümülatif fark günlük
  /// tüketim sanılmasın diye aralık ve delta üst sınırı uygulanır.
  List<ConsumptionEntry> shellyDataListToDeltaConsumptionEntries(
    List<ShellyData> raw, {
    Duration maxReadingGap = const Duration(hours: 36),
    double maxDeltaKwhPerReading = 80.0,
  }) {
    if (raw.isEmpty) return [];
    final sorted = List<ShellyData>.from(raw)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final out = <ConsumptionEntry>[];
    double? prevMeter;
    DateTime? prevTimestamp;
    for (final sd in sorted) {
      var deltaKwh = 0.0;
      if (prevMeter != null && prevTimestamp != null) {
        final gap = sd.timestamp.difference(prevTimestamp);
        if (gap <= maxReadingGap) {
          final d = sd.energyKwh - prevMeter;
          if (d >= 0 && d <= maxDeltaKwhPerReading) {
            deltaKwh = d;
          }
        }
      }
      prevMeter = sd.energyKwh;
      prevTimestamp = sd.timestamp;
      out.add(
        ConsumptionEntry(
          electricityKwh: deltaKwh,
          waterCubicMeters: 0,
          fuelLiters: 0,
          wasteKg: 0,
          createdAt: sd.timestamp,
          fuelIsNaturalGasM3: true,
        ),
      );
    }
    return out;
  }
}
