import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../models/consumption_entry.dart';
import 'blockchain_service.dart';
import 'firebase_realtime_service.dart';

/// API servisi - ESP modülü, blockchain ve Firebase entegrasyonu
class ApiService {
  static const String espBaseUrl = 'http://192.168.1.100'; // ESP IP adresi
  static const String deviceId =
      'esp8266_001'; // Cihaz ID'si (değiştirilebilir)

  final BlockchainService _blockchainService = BlockchainService();
  final FirebaseRealtimeService _firebaseService =
      FirebaseRealtimeService.instance;

  ApiService();

  /// ESP modülünden canlı tüketim verilerini çek ve Firebase'e kaydet
  Future<ConsumptionEntry> getLiveConsumptionData({
    bool saveToFirebase = true,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$espBaseUrl/api/consumption'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final consumption = ConsumptionEntry(
          electricityKwh: (data['electricity'] ?? 0.0).toDouble(),
          waterCubicMeters: (data['water'] ?? 0.0).toDouble(),
          fuelLiters: (data['fuel'] ?? data['co2_ppm'] ?? 0.0)
              .toDouble(), // Gaz (CO2 ppm) değeri
          wasteKg: (data['waste'] ?? 0.0).toDouble(),
          createdAt: DateTime.now(),
        );

        // Firebase'e kaydet (opsiyonel)
        if (saveToFirebase) {
          try {
            await _firebaseService.saveEsp8266Data(
              deviceId: deviceId,
              consumption: consumption,
              additionalData: {
                'co2_ppm': data['co2_ppm'] ?? 0.0,
                'water_flow_liters': data['water_flow_liters'] ?? 0.0,
                'flow_rate_lpm': data['flow_rate_lpm'] ?? 0.0,
              },
            );
          } catch (e) {
            dev.log(
              'Firebase kayıt hatası (devam ediliyor): $e',
              name: 'ApiService',
            );
            // Firebase hatası olsa bile veriyi döndür
          }
        }

        return consumption;
      } else {
        throw Exception(
          'ESP modülünden veri alınamadı: ${response.statusCode}',
        );
      }
    } catch (e, st) {
      dev.log(
        'ESP bağlantı hatası: $e',
        name: 'ApiService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      // Hata durumunda varsayılan değerler döndür
      return ConsumptionEntry(
        electricityKwh: 0.0,
        waterCubicMeters: 0.0,
        fuelLiters: 0.0,
        wasteKg: 0.0,
        createdAt: DateTime.now(),
      );
    }
  }

  /// ESP modülü durumunu kontrol et ve Firebase'e kaydet
  Future<Map<String, dynamic>> getEspStatus({
    bool saveToFirebase = true,
  }) async {
    try {
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

  /// Veriyi blockchain'e kaydet ve doğrula
  Future<Map<String, dynamic>> storeAndVerifyData({
    required ConsumptionEntry consumption,
    required String userId,
  }) async {
    try {
      // Blockchain'e kaydet
      final transactionHash = await _blockchainService.storeConsumptionData(
        electricity: consumption.electricityKwh,
        water: consumption.waterCubicMeters,
        fuel: consumption.fuelLiters,
        waste: consumption.wasteKg,
        timestamp: consumption.createdAt.millisecondsSinceEpoch,
        userId: userId,
      );

      // Doğruluğunu kontrol et
      final isVerified = await _blockchainService.verifyData(transactionHash);

      return {
        'success': true,
        'transactionHash': transactionHash,
        'verified': isVerified,
        'timestamp': consumption.createdAt.toIso8601String(),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString(), 'verified': false};
    }
  }

  /// Blockchain durumunu kontrol et
  Future<Map<String, dynamic>> getBlockchainStatus() async {
    return await _blockchainService.getBlockchainStatus();
  }

  /// Karbon ayak izi verilerini blockchain'e kaydet
  Future<String> storeCarbonFootprint({
    required double dailyEmission,
    required double monthlyEmission,
    required double yearlyEmission,
    required String userId,
  }) async {
    return await _blockchainService.storeCarbonFootprint(
      dailyEmission: dailyEmission,
      monthlyEmission: monthlyEmission,
      yearlyEmission: yearlyEmission,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      userId: userId,
    );
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
}
