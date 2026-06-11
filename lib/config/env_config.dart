import 'dart:io' show File;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Ortam degiskenleri: asset [assets/config/env.example] + istege bagli kok `.env`.
///
/// Firebase anahtarlari yerel `.env` veya [_firebaseDefaults] ile gelir (web icin asset yeterli degilse .env gerekir).
class EnvConfig {
  EnvConfig._();

  static bool _loaded = false;

  static const _deviceDefaults = <String, String>{
    'ESP_BASE_URL': 'http://172.20.10.2',
    'ESP_DEVICE_ID': 'esp8266_001',
    'SHELLY_DEVICE_IP': '192.168.137.43',
    'SHELLY_DEVICE_ID': 'shelly_plug_001',
    'POSTGRES_API_BASE_URL': 'http://localhost:3000/api',
  };

  /// Firebase — client tarafinda kullanilir; yerel `.env` ile override edilebilir.
  static const _firebaseDefaults = <String, String>{
    'FIREBASE_PROJECT_ID': 'carbon-footprint-app-8111a',
    'FIREBASE_DATABASE_URL':
        'https://carbon-footprint-app-8111a-default-rtdb.firebaseio.com',
    'FIREBASE_MESSAGING_SENDER_ID': '40318061378',
    'FIREBASE_AUTH_DOMAIN': 'carbon-footprint-app-8111a.firebaseapp.com',
    'FIREBASE_STORAGE_BUCKET':
        'carbon-footprint-app-8111a.firebasestorage.app',
    'FIREBASE_API_KEY_WEB': 'AIzaSyDFDbPLPdGcEAIRMT5K8YcMbFI3VmRJtpc',
    'FIREBASE_APP_ID_WEB': '1:40318061378:web:8641d5cc5e0d87c0d4d6db',
    'FIREBASE_MEASUREMENT_ID': 'G-F5FF23KSNH',
    'FIREBASE_API_KEY_ANDROID': 'AIzaSyCCLiAwHue3WotS1eMGKvNHRDPr5V8wI44',
    'FIREBASE_APP_ID_ANDROID': '1:40318061378:android:a26d0d7f89f8d0bad4d6db',
    'FIREBASE_API_KEY_IOS': 'AIzaSyDDfwAGs_SmFb09SpJ8Tejioe9mYY_S8W4',
    'FIREBASE_APP_ID_IOS': '1:40318061378:ios:51f776051f19dd34d4d6db',
    'FIREBASE_IOS_BUNDLE_ID': 'com.example.carbonFootprintCalculationApp',
  };

  static Future<void> load() async {
    if (_loaded) return;
    try {
      await dotenv.load(fileName: 'assets/config/env.example');
    } catch (_) {
      // Asset yoksa asagidaki varsayilanlar kullanilir.
    }
    if (!kIsWeb) {
      try {
        final localEnv = File('.env');
        if (await localEnv.exists()) {
          dotenv.testLoad(
            fileInput: await localEnv.readAsString(),
            mergeWith: dotenv.env,
          );
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  static String _env(String key) {
    final fromFile = dotenv.env[key]?.trim();
    if (fromFile != null && fromFile.isNotEmpty) {
      return fromFile;
    }
    return _deviceDefaults[key] ?? _firebaseDefaults[key] ?? '';
  }

  static String get espBaseUrl => _env('ESP_BASE_URL');

  static String get espDeviceId => _env('ESP_DEVICE_ID');

  static String get shellyDeviceIp => _env('SHELLY_DEVICE_IP');

  static String get shellyDeviceId => _env('SHELLY_DEVICE_ID');

  static String get postgresApiBaseUrl => _env('POSTGRES_API_BASE_URL');

  static FirebaseOptions get firebaseOptions {
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: _env('FIREBASE_API_KEY_WEB'),
        appId: _env('FIREBASE_APP_ID_WEB'),
        messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _env('FIREBASE_PROJECT_ID'),
        authDomain: _env('FIREBASE_AUTH_DOMAIN'),
        storageBucket: _env('FIREBASE_STORAGE_BUCKET'),
        measurementId: _env('FIREBASE_MEASUREMENT_ID'),
        databaseURL: _env('FIREBASE_DATABASE_URL'),
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: _env('FIREBASE_API_KEY_ANDROID'),
          appId: _env('FIREBASE_APP_ID_ANDROID'),
          messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
          projectId: _env('FIREBASE_PROJECT_ID'),
          storageBucket: _env('FIREBASE_STORAGE_BUCKET'),
          databaseURL: _env('FIREBASE_DATABASE_URL'),
        );
      case TargetPlatform.iOS:
        return FirebaseOptions(
          apiKey: _env('FIREBASE_API_KEY_IOS'),
          appId: _env('FIREBASE_APP_ID_IOS'),
          messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
          projectId: _env('FIREBASE_PROJECT_ID'),
          storageBucket: _env('FIREBASE_STORAGE_BUCKET'),
          iosBundleId: _env('FIREBASE_IOS_BUNDLE_ID'),
          databaseURL: _env('FIREBASE_DATABASE_URL'),
        );
      default:
        return FirebaseOptions(
          apiKey: _env('FIREBASE_API_KEY_WEB'),
          appId: _env('FIREBASE_APP_ID_WEB'),
          messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
          projectId: _env('FIREBASE_PROJECT_ID'),
          authDomain: _env('FIREBASE_AUTH_DOMAIN'),
          storageBucket: _env('FIREBASE_STORAGE_BUCKET'),
          databaseURL: _env('FIREBASE_DATABASE_URL'),
        );
    }
  }
}
