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
  /// Shelly Plus/Gen2 cihazları için önce /rpc, eski cihazlar için /status endpoint'ini dener
  Future<ShellyData> getStatus() async {
    // Önce /shelly endpoint'ini kontrol et (cihaz bilgileri için)
    // Bu bize cihazın Gen2 olup olmadığını söyler
    bool isGen2 = false;
    try {
      final shellyInfoResponse = await http.get(
        Uri.parse('$baseUrl/shelly'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (shellyInfoResponse.statusCode == 200) {
        final shellyInfo =
            json.decode(shellyInfoResponse.body) as Map<String, dynamic>;
        isGen2 = shellyInfo['gen'] == 2 || shellyInfo['gen'] == '2';
        dev.log(
          '✅ Shelly cihaz bilgisi alındı: Gen${shellyInfo['gen'] ?? '?'}, Model: ${shellyInfo['model'] ?? '?'}',
          name: 'ShellyService',
        );
      }
    } catch (e) {
      dev.log(
        'Shelly /shelly endpoint kontrolü başarısız: $e',
        name: 'ShellyService',
      );
    }

    // Shelly Plus/Gen2 cihazları için önce /rpc endpoint'ini dene
    // Farklı method'ları dene: Switch.GetStatus (id: 0 ile), Shelly.GetStatus
    final rpcMethods = [
      {
        'method': 'Switch.GetStatus',
        'params': {'id': 0}
      },
      {'method': 'Switch.GetStatus', 'params': {}},
      {'method': 'Shelly.GetStatus', 'params': {}},
    ];

    for (final methodConfig in rpcMethods) {
      try {
        final method = methodConfig['method'] as String;
        final params = methodConfig['params'] as Map<String, dynamic>;
        dev.log(
          'Shelly Plus için /rpc endpoint deneniyor: $method (params: $params) - $deviceIp',
          name: 'ShellyService',
        );
        final rpcResponse = await http
            .post(
              Uri.parse('$baseUrl/rpc'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'id': 1,
                'method': method,
                'params': params,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (rpcResponse.statusCode == 200) {
          final responseBody = rpcResponse.body;
          dev.log(
            'Shelly /rpc yanıt alındı ($method): ${responseBody.substring(0, responseBody.length > 200 ? 200 : responseBody.length)}...',
            name: 'ShellyService',
          );
          final data = json.decode(responseBody) as Map<String, dynamic>;
          if (data['result'] != null) {
            dev.log(
              '✅ Shelly /rpc endpoint başarılı ($method - Plus/Gen2): $deviceIp',
              name: 'ShellyService',
            );
            try {
              final shellyData = ShellyData.fromJson(
                data['result'] as Map<String, dynamic>,
                deviceIp,
                deviceId,
              );
              dev.log(
                '✅ Shelly verisi parse edildi: ${shellyData.toString()}',
                name: 'ShellyService',
              );
              return shellyData;
            } catch (parseError) {
              dev.log(
                '❌ Shelly verisi parse hatası: $parseError',
                name: 'ShellyService',
                level: 1000,
              );
              // Parse hatası olsa bile bir sonraki method'u dene
              continue;
            }
          } else if (data['error'] != null) {
            dev.log(
              'Shelly /rpc endpoint hata döndü ($method): ${data['error']}',
              name: 'ShellyService',
            );
            // Bir sonraki method'u dene
            continue;
          } else {
            dev.log(
              'Shelly /rpc endpoint yanıtında result yok: $data',
              name: 'ShellyService',
            );
            continue;
          }
        } else {
          dev.log(
            '❌ Shelly /rpc endpoint ${rpcResponse.statusCode} döndü\n'
            '   Response body: ${rpcResponse.body.substring(0, rpcResponse.body.length > 200 ? 200 : rpcResponse.body.length)}',
            name: 'ShellyService',
            level: 1000,
          );
          continue;
        }
      } catch (rpcError) {
        final method = methodConfig['method'] as String;
        final errorType = rpcError.runtimeType.toString();
        final errorMessage = rpcError.toString();
        dev.log(
          '❌ Shelly /rpc endpoint başarısız ($method):\n'
          '   Tip: $errorType\n'
          '   Mesaj: $errorMessage',
          name: 'ShellyService',
          level: 1000,
        );
        // Bir sonraki method'u dene
        continue;
      }
    }

    dev.log(
      'Tüm /rpc method\'ları başarısız, /status endpoint deneniyor...',
      name: 'ShellyService',
    );

    // /rpc başarısız oldu, klasik /status endpoint'ini dene (eski Shelly cihazları için)
    try {
      dev.log(
        'Shelly klasik /status endpoint deneniyor: $deviceIp',
        name: 'ShellyService',
      );
      final response = await http.get(
        Uri.parse('$baseUrl/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        dev.log(
          '✅ Shelly /status endpoint başarılı (klasik): $deviceIp',
          name: 'ShellyService',
        );
        return ShellyData.fromJson(data, deviceIp, deviceId);
      } else {
        dev.log(
          'Shelly /status endpoint ${response.statusCode} döndü',
          name: 'ShellyService',
        );
        throw Exception('Status code: ${response.statusCode}');
      }
    } catch (statusError) {
      final errorType = statusError.runtimeType.toString();
      final errorMessage = statusError.toString();
      dev.log(
        '❌ Shelly /status endpoint başarısız:\n'
        '   Tip: $errorType\n'
        '   Mesaj: $errorMessage',
        name: 'ShellyService',
        level: 1000,
      );
    }

    // Eğer Gen2 ise, ek RPC method'larını dene
    if (isGen2) {
      final gen2Methods = [
        'Meter.GetStatus',
        'Meter:0.GetStatus',
        'DevicePower:0.GetStatus',
      ];

      for (final method in gen2Methods) {
        try {
          dev.log(
            'Shelly Gen2 ek method deneniyor: $method - $deviceIp',
            name: 'ShellyService',
          );
          final rpcResponse = await http
              .post(
                Uri.parse('$baseUrl/rpc'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'id': 1,
                  'method': method,
                  'params': {},
                }),
              )
              .timeout(const Duration(seconds: 5));

          if (rpcResponse.statusCode == 200) {
            final data = json.decode(rpcResponse.body) as Map<String, dynamic>;
            if (data['result'] != null) {
              dev.log(
                '✅ Shelly Gen2 ek method başarılı ($method): $deviceIp',
                name: 'ShellyService',
              );
              return ShellyData.fromJson(
                data['result'] as Map<String, dynamic>,
                deviceIp,
                deviceId,
              );
            }
          }
        } catch (e) {
          final errorType = e.runtimeType.toString();
          final errorMessage = e.toString();
          dev.log(
            '❌ Shelly Gen2 ek method başarısız ($method):\n'
            '   Tip: $errorType\n'
            '   Mesaj: $errorMessage',
            name: 'ShellyService',
            level: 1000,
          );
          continue;
        }
      }
    }

    // Alternatif GET endpoint'leri dene: /relay/0 (çalışıyor ama sadece relay durumu)
    // /relay/0 çalışıyorsa, /rpc ile Switch.GetStatus'u tekrar dene (id: 0 ile)
    try {
      dev.log(
        'Shelly /relay/0 endpoint kontrol ediliyor: $deviceIp',
        name: 'ShellyService',
      );
      final relayResponse = await http.get(
        Uri.parse('$baseUrl/relay/0'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (relayResponse.statusCode == 200) {
        dev.log(
          '✅ Shelly /relay/0 endpoint erişilebilir, /rpc ile enerji verileri alınacak: $deviceIp',
          name: 'ShellyService',
        );
        // /relay/0 çalışıyorsa, /rpc endpoint'ini id: 0 ile tekrar dene
        try {
          final rpcResponse = await http
              .post(
                Uri.parse('$baseUrl/rpc'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'id': 1,
                  'method': 'Switch.GetStatus',
                  'params': {'id': 0},
                }),
              )
              .timeout(const Duration(seconds: 10));

          if (rpcResponse.statusCode == 200) {
            final responseBody = rpcResponse.body;
            dev.log(
              'Shelly /rpc yanıt alındı (relay/0 sonrası): ${responseBody.substring(0, responseBody.length > 200 ? 200 : responseBody.length)}...',
              name: 'ShellyService',
            );
            final data = json.decode(responseBody) as Map<String, dynamic>;
            if (data['result'] != null) {
              dev.log(
                '✅ Shelly /rpc endpoint başarılı (id: 0 ile): $deviceIp',
                name: 'ShellyService',
              );
              try {
                final shellyData = ShellyData.fromJson(
                  data['result'] as Map<String, dynamic>,
                  deviceIp,
                  deviceId,
                );
                dev.log(
                  '✅ Shelly verisi parse edildi (relay/0 sonrası): ${shellyData.toString()}',
                  name: 'ShellyService',
                );
                return shellyData;
              } catch (parseError) {
                dev.log(
                  '❌ Shelly verisi parse hatası (relay/0 sonrası): $parseError',
                  name: 'ShellyService',
                  level: 1000,
                );
                rethrow;
              }
            } else if (data['error'] != null) {
              dev.log(
                'Shelly /rpc endpoint hata döndü (relay/0 sonrası): ${data['error']}',
                name: 'ShellyService',
              );
            }
          }
        } catch (rpcError) {
          final errorType = rpcError.runtimeType.toString();
          final errorMessage = rpcError.toString();
          dev.log(
            '❌ Shelly /rpc endpoint (id: 0 ile) başarısız:\n'
            '   Tip: $errorType\n'
            '   Mesaj: $errorMessage',
            name: 'ShellyService',
            level: 1000,
          );
        }
      }
    } catch (e) {
      final errorType = e.runtimeType.toString();
      final errorMessage = e.toString();
      dev.log(
        '❌ Shelly /relay/0 endpoint kontrolü başarısız:\n'
        '   Tip: $errorType\n'
        '   Mesaj: $errorMessage',
        name: 'ShellyService',
        level: 1000,
      );
    }

    // Diğer alternatif endpoint'leri dene: /switch:0, /meter:0, /meter/0
    final alternativeEndpoints = ['/switch:0', '/meter:0', '/meter/0'];
    for (final endpoint in alternativeEndpoints) {
      try {
        dev.log(
          'Shelly alternatif endpoint deneniyor: $endpoint - $deviceIp',
          name: 'ShellyService',
        );
        final response = await http.get(
          Uri.parse('$baseUrl$endpoint'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          dev.log(
            '✅ Shelly $endpoint endpoint başarılı: $deviceIp',
            name: 'ShellyService',
          );
          // Bu endpoint'lerden gelen veriyi parse etmeye çalış
          return ShellyData.fromJson(data, deviceIp, deviceId);
        }
      } catch (e) {
        final errorType = e.runtimeType.toString();
        final errorMessage = e.toString();
        dev.log(
          '❌ Shelly $endpoint endpoint başarısız:\n'
          '   Tip: $errorType\n'
          '   Mesaj: $errorMessage',
          name: 'ShellyService',
          level: 1000,
        );
      }
    }

    // Her iki endpoint de başarısız oldu
    final errorMsg = 'Shelly HTTP API hatası: Tüm endpoint\'ler başarısız. '
        'Cihaz erişilebilir mi? IP: $deviceIp\n'
        'Kontrol edin:\n'
        '1. Cihaz aynı WiFi ağında mı?\n'
        '2. IP adresi doğru mu? ($deviceIp)\n'
        '3. Cihaz çalışıyor mu?\n'
        '4. Firewall engelliyor mu?\n'
        '5. Chrome\'da CORS sorunu olabilir - emülatör kullanmayı deneyin';
    dev.log(
      '❌ $errorMsg\n'
      '📋 Denenen endpoint\'ler:\n'
      '   - /rpc (Switch.GetStatus, Shelly.GetStatus)\n'
      '   - /status\n'
      '   - /relay/0\n'
      '   - /switch:0, /meter:0, /meter/0',
      name: 'ShellyService',
      level: 1000,
    );
    throw Exception(errorMsg);
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
  /// Shelly Plus için önce /rpc, sonra /status endpoint'lerini dener
  Future<bool> checkConnection() async {
    // Shelly Plus/Gen2 için önce /rpc endpoint'ini dene (farklı method'larla)
    final rpcMethods = [
      {
        'method': 'Switch.GetStatus',
        'params': {'id': 0}
      },
      {'method': 'Switch.GetStatus', 'params': {}},
      {'method': 'Shelly.GetStatus', 'params': {}},
    ];

    for (final methodConfig in rpcMethods) {
      try {
        final method = methodConfig['method'] as String;
        final params = methodConfig['params'] as Map<String, dynamic>;
        final rpcResponse = await http
            .post(
              Uri.parse('$baseUrl/rpc'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'id': 1,
                'method': method,
                'params': params,
              }),
            )
            .timeout(const Duration(seconds: 5));

        if (rpcResponse.statusCode == 200) {
          final data = json.decode(rpcResponse.body) as Map<String, dynamic>;
          if (data['result'] != null) {
            dev.log(
                '✅ Shelly bağlantı kontrolü başarılı (/rpc - $method): $deviceIp',
                name: 'ShellyService');
            return true;
          }
        }
      } catch (e) {
        final method = methodConfig['method'] as String;
        dev.log(
          'Shelly /rpc bağlantı kontrolü başarısız ($method): $e',
          name: 'ShellyService',
        );
        // Bir sonraki method'u dene
        continue;
      }
    }

    // /rpc başarısız oldu, klasik /status endpoint'ini dene
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        dev.log(
            '✅ Shelly bağlantı kontrolü başarılı (/status - klasik): $deviceIp',
            name: 'ShellyService');
        return true;
      }
    } catch (e) {
      dev.log(
        'Shelly /status bağlantı kontrolü başarısız: $e',
        name: 'ShellyService',
      );
    }

    dev.log(
      '❌ Shelly bağlantı kontrolü başarısız: Tüm endpoint\'ler denendi. IP: $deviceIp',
      name: 'ShellyService',
      level: 1000,
    );
    return false;
  }

  /// Servisi temizle (dispose)
  void dispose() {
    disconnectWebSocket();
    _dataController.close();
  }
}
