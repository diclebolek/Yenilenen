import 'dart:async';
import 'dart:developer' as dev;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// İnternet ve ağ bağlantısı kontrol servisi
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  ConnectivityService();

  /// İnternet bağlantısını kontrol et
  /// Gerçek bir HTTP isteği yaparak internet erişimini test eder
  Future<bool> checkInternetConnection() async {
    try {
      // Google DNS'e istek gönder (hızlı ve güvenilir)
      final response = await http
          .get(
            Uri.parse('https://www.google.com'),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      dev.log(
        'İnternet bağlantı kontrolü başarısız: $e',
        name: 'ConnectivityService',
      );
      return false;
    }
  }

  /// WiFi bağlantısını kontrol et
  /// Sadece WiFi ağına bağlı olup olmadığını kontrol eder (internet gerekmez)
  Future<bool> checkWifiConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.contains(ConnectivityResult.wifi);
    } catch (e) {
      dev.log(
        'WiFi bağlantı kontrolü başarısız: $e',
        name: 'ConnectivityService',
      );
      return false;
    }
  }

  /// Mobil veri bağlantısını kontrol et
  Future<bool> checkMobileDataConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.contains(ConnectivityResult.mobile);
    } catch (e) {
      return false;
    }
  }

  /// Herhangi bir ağ bağlantısı var mı kontrol et
  /// (WiFi veya mobil veri)
  Future<bool> checkAnyConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.isNotEmpty && !result.contains(ConnectivityResult.none);
    } catch (e) {
      return false;
    }
  }

  /// Detaylı bağlantı durumu bilgisi
  Future<Map<String, dynamic>> getConnectionStatus() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      final hasInternet = await checkInternetConnection();
      final hasWifi = connectivityResult.contains(ConnectivityResult.wifi);
      final hasMobile = connectivityResult.contains(ConnectivityResult.mobile);
      final hasAnyConnection = connectivityResult.isNotEmpty &&
          !connectivityResult.contains(ConnectivityResult.none);

      return {
        'hasInternet': hasInternet,
        'hasWifi': hasWifi,
        'hasMobileData': hasMobile,
        'hasAnyConnection': hasAnyConnection,
        'connectionType': connectivityResult.toString(),
        'isConnected': hasAnyConnection,
      };
    } catch (e) {
      dev.log(
        'Bağlantı durumu kontrolü başarısız: $e',
        name: 'ConnectivityService',
      );
      return {
        'hasInternet': false,
        'hasWifi': false,
        'hasMobileData': false,
        'hasAnyConnection': false,
        'connectionType': 'unknown',
        'isConnected': false,
      };
    }
  }

  /// Bağlantı durumu değişikliklerini dinle
  /// Stream döndürür, widget'ta StreamBuilder ile kullanılabilir
  Stream<Map<String, dynamic>> listenToConnectionChanges() {
    return _connectivity.onConnectivityChanged.asyncMap((result) async {
      final hasInternet = await checkInternetConnection();
      final hasWifi = result.contains(ConnectivityResult.wifi);
      final hasMobile = result.contains(ConnectivityResult.mobile);
      final hasAnyConnection =
          result.isNotEmpty && !result.contains(ConnectivityResult.none);

      return {
        'hasInternet': hasInternet,
        'hasWifi': hasWifi,
        'hasMobileData': hasMobile,
        'hasAnyConnection': hasAnyConnection,
        'connectionType': result.toString(),
        'isConnected': hasAnyConnection,
      };
    });
  }

  /// Servisi temizle
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
