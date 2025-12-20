import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/shelly_data.dart';

/// Shelly Plug S cihazı ile iletişim servisi
/// HTTP API ve WebSocket desteği sağlar
class ShellyService {
  /// Shelly cihazının IP adresi (örn: '192.168.1.100')
  final String deviceIp;

  /// Cihaz ID'si (opsiyonel, IP kullanılabilir)
  final String deviceId;

  /// HTTP API base URL
  String get baseUrl => 'http://$deviceIp';

  /// WebSocket URL
  String get wsUrl => 'ws://$deviceIp/rpc';

  /// WebSocket kanalı
  WebSocketChannel? _wsChannel;

  /// WebSocket stream controller
  final StreamController<ShellyData> _dataController =
      StreamController<ShellyData>.broadcast();

  /// WebSocket bağlantı durumu
  bool _isConnected = false;

  ShellyService({
    required this.deviceIp,
    String? deviceId,
  }) : deviceId = deviceId ?? deviceIp;

  /// Shelly cihazının durumunu HTTP API üzerinden al
  /// GET /status endpoint'ini kullanır
  Future<ShellyData> getStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ShellyData.fromJson(data, deviceIp, deviceId);
      } else {
        throw Exception(
          'Shelly cihazından veri alınamadı: ${response.statusCode}',
        );
      }
    } catch (e, st) {
      dev.log(
        'Shelly HTTP API hatası: $e',
        name: 'ShellyService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Cihazı aç/kapat
  /// turn: 'on' veya 'off'
  Future<bool> setRelayState({required String turn}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/relay/0?turn=$turn'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final relays = data['relays'] as List?;
        if (relays != null && relays.isNotEmpty) {
          return (relays[0] as Map<String, dynamic>)['ison'] == true;
        }
        return false;
      } else {
        throw Exception(
          'Shelly cihazı kontrol edilemedi: ${response.statusCode}',
        );
      }
    } catch (e, st) {
      dev.log(
        'Shelly relay kontrol hatası: $e',
        name: 'ShellyService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// WebSocket bağlantısını başlat
  /// Gerçek zamanlı veri akışı için kullanılır
  Future<void> connectWebSocket() async {
    if (_isConnected && _wsChannel != null) {
      dev.log('WebSocket zaten bağlı', name: 'ShellyService');
      return;
    }

    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      // WebSocket mesajlarını dinle
      _wsChannel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message) as Map<String, dynamic>;

            // Shelly WebSocket yanıt formatına göre parse et
            // NotifyStatus mesajlarını yakala
            if (data['method'] == 'NotifyStatus') {
              final params = data['params'] as Map<String, dynamic>?;
              if (params != null) {
                final shellyData =
                    ShellyData.fromJson(params, deviceIp, deviceId);
                _dataController.add(shellyData);
              }
            }
            // Status mesajlarını da yakala
            else if (data['result'] != null) {
              final result = data['result'] as Map<String, dynamic>;
              final shellyData =
                  ShellyData.fromJson(result, deviceIp, deviceId);
              _dataController.add(shellyData);
            }
          } catch (e) {
            dev.log(
              'WebSocket mesaj parse hatası: $e',
              name: 'ShellyService',
            );
          }
        },
        onError: (error) {
          dev.log(
            'WebSocket hata: $error',
            name: 'ShellyService',
            level: 1000,
          );
          _isConnected = false;
        },
        onDone: () {
          dev.log('WebSocket bağlantısı kapandı', name: 'ShellyService');
          _isConnected = false;
        },
      );

      // Status bildirimlerini aktif et
      _wsChannel!.sink.add(json.encode({
        'id': 1,
        'method': 'Shelly.GetStatus',
        'params': {},
      }));

      // NotifyStatus bildirimlerini aktif et
      _wsChannel!.sink.add(json.encode({
        'id': 2,
        'method': 'NotifyStatus',
        'params': {'enable': true},
      }));

      dev.log(
        'Shelly WebSocket bağlantısı kuruldu: $wsUrl',
        name: 'ShellyService',
      );
    } catch (e, st) {
      dev.log(
        'WebSocket bağlantı hatası: $e',
        name: 'ShellyService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      _isConnected = false;
      rethrow;
    }
  }

  /// WebSocket bağlantısını kapat
  Future<void> disconnectWebSocket() async {
    if (_wsChannel != null) {
      await _wsChannel!.sink.close();
      _wsChannel = null;
      _isConnected = false;
      dev.log('Shelly WebSocket bağlantısı kapatıldı', name: 'ShellyService');
    }
  }

  /// WebSocket üzerinden gerçek zamanlı veri stream'i
  /// StreamBuilder ile kullanılabilir
  Stream<ShellyData> get realtimeData {
    return _dataController.stream;
  }

  /// WebSocket bağlantı durumu
  bool get isConnected => _isConnected;

  /// Cihazın erişilebilir olup olmadığını kontrol et
  Future<bool> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      dev.log(
        'Shelly bağlantı kontrolü başarısız: $e',
        name: 'ShellyService',
        level: 1000,
      );
      return false;
    }
  }

  /// Servisi temizle (dispose)
  void dispose() {
    disconnectWebSocket();
    _dataController.close();
  }
}
