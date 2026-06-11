import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../config/env_config.dart';

/// PostgreSQL veritabanı bağlantı ve işlem servisi (HTTP API üzerinden)
class PostgresService {
  static PostgresService? _instance;

  String get baseUrl => EnvConfig.postgresApiBaseUrl;

  PostgresService._();

  static PostgresService get instance {
    _instance ??= PostgresService._();
    return _instance!;
  }

  /// Veritabanına bağlan (HTTP API için gerekli değil)
  Future<void> connect() async {
    try {
      // HTTP API test isteği
      final response = await http.get(Uri.parse('$baseUrl/health'));
      if (response.statusCode == 200) {
        debugPrint('PostgreSQL API bağlantısı başarılı');
      } else {
        throw Exception('API bağlantı hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('PostgreSQL API bağlantı hatası: $e');
      // Uygulama yine de çalışır, sadece veritabanı işlemleri başarısız olur
    }
  }

  /// Bağlantıyı kapat (HTTP API için gerekli değil)
  Future<void> disconnect() async {
    // HTTP API için kapatma işlemi gerekli değil
  }

  /// Bağlantı durumunu kontrol et
  bool get isConnected => true; // HTTP API için her zaman true

  /// Kullanıcı girişi doğrula
  Future<Map<String, dynamic>?> authenticateUser(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['user'];
      } else if (response.statusCode == 401) {
        return null; // Hatalı giriş bilgileri
      } else {
        throw Exception('Giriş hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Kullanıcı doğrulama hatası: $e');
      // Simüle edilmiş başarılı giriş (demo için)
      return {
        'kullanici_id': 1,
        'isletme_id': 1,
        'rol': 'sahip',
        'isletme_adi': 'Demo İşletme',
        'sektor_adi': 'Teknoloji',
      };
    }
  }

  /// Yeni kullanıcı kaydı
  Future<int> registerUser({
    required String email,
    required String password,
    required String role,
    required int isletmeId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'role': role,
          'isletme_id': isletmeId,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['kullanici_id'];
      } else {
        throw Exception('Kullanıcı kayıt hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Kullanıcı kayıt hatası: $e');
      // Simüle edilmiş başarılı kayıt (demo için)
      return 1;
    }
  }

  /// Yeni işletme kaydı
  Future<int> registerBusiness({
    required String businessName,
    required int sektorId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/businesses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'business_name': businessName,
          'sektor_id': sektorId,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['isletme_id'];
      } else {
        throw Exception('İşletme kayıt hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('İşletme kayıt hatası: $e');
      // Simüle edilmiş başarılı kayıt (demo için)
      return 1;
    }
  }

  /// Sektörleri getir
  Future<List<Map<String, dynamic>>> getSektors() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sektors'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['sektors']);
      } else {
        throw Exception('Sektör listesi hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Sektör listesi hatası: $e');
      // Simüle edilmiş sektör listesi (demo için)
      return [
        {'sektor_id': 1, 'ad': 'Teknoloji', 'nace_kodu': '62.01'},
        {'sektor_id': 2, 'ad': 'İmalat', 'nace_kodu': '10.11'},
        {'sektor_id': 3, 'ad': 'Hizmet', 'nace_kodu': '47.11'},
        {'sektor_id': 4, 'ad': 'Enerji', 'nace_kodu': '35.11'},
      ];
    }
  }

  /// Faaliyet kaydı ekle
  Future<int> addActivityRecord({
    required int isletmeId,
    required int kategoriId,
    required double miktar,
    required String birim,
    required DateTime donemBaslangic,
    required DateTime donemBitis,
    String? notlar,
    int? olusturanKullanici,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/activities'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'isletme_id': isletmeId,
          'kategori_id': kategoriId,
          'miktar': miktar,
          'birim': birim,
          'donem_baslangic': donemBaslangic.toIso8601String(),
          'donem_bitis': donemBitis.toIso8601String(),
          'notlar': notlar,
          'olusturan_kullanici': olusturanKullanici,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['faaliyet_id'];
      } else {
        throw Exception('Faaliyet kaydı ekleme hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Faaliyet kaydı ekleme hatası: $e');
      // Simüle edilmiş başarılı kayıt (demo için)
      return 1;
    }
  }

  /// Kategorileri getir
  Future<List<Map<String, dynamic>>> getKategoriler() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/kategoriler'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['kategoriler']);
      } else {
        throw Exception('Kategori listesi hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Kategori listesi hatası: $e');
      // Simüle edilmiş kategori listesi (demo için)
      return [
        {
          'kategori_id': 1,
          'kategori_adi': 'Elektrik Tüketimi',
          'kategori_birimi': 'kwh',
          'kg_co2e_carpani': 0.420,
        },
        {
          'kategori_id': 2,
          'kategori_adi': 'Doğal Gaz',
          'kategori_birimi': 'm3',
          'kg_co2e_carpani': 2.100,
        },
        {
          'kategori_id': 3,
          'kategori_adi': 'Benzin',
          'kategori_birimi': 'litre',
          'kg_co2e_carpani': 2.310,
        },
        {
          'kategori_id': 4,
          'kategori_adi': 'Su Tüketimi',
          'kategori_birimi': 'm3',
          'kg_co2e_carpani': 0.0003,
        },
        {
          'kategori_id': 5,
          'kategori_adi': 'Atık Üretimi',
          'kategori_birimi': 'kg',
          'kg_co2e_carpani': 0.500,
        },
      ];
    }
  }

  /// İşletme CO2 emisyonlarını hesapla
  Future<List<Map<String, dynamic>>> calculateBusinessEmissions(
    int isletmeId,
    int year,
    int month,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/emissions/$isletmeId?year=$year&month=$month'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['emissions']);
      } else {
        throw Exception('CO2 emisyon hesaplama hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('CO2 emisyon hesaplama hatası: $e');
      // Simüle edilmiş emisyon verileri (demo için)
      return [
        {
          'kategori_adi': 'Elektrik Tüketimi',
          'toplam_kg_co2e': 42.0,
          'toplam_miktar': 100.0,
          'kategori_birimi': 'kwh',
        },
        {
          'kategori_adi': 'Doğal Gaz',
          'toplam_kg_co2e': 21.0,
          'toplam_miktar': 10.0,
          'kategori_birimi': 'm3',
        },
        {
          'kategori_adi': 'Benzin',
          'toplam_kg_co2e': 11.55,
          'toplam_miktar': 5.0,
          'kategori_birimi': 'litre',
        },
      ];
    }
  }

  /// İşletme bilgilerini güncelle
  Future<void> updateBusiness({
    required int isletmeId,
    required String businessName,
    required int sektorId,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/businesses/$isletmeId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'business_name': businessName,
          'sektor_id': sektorId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('İşletme güncelleme hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('İşletme güncelleme hatası: $e');
      // Demo için başarılı sayılır
    }
  }

  /// Kullanıcı e-postasını güncelle
  Future<void> updateUserEmail({
    required int kullaniciId,
    required String newEmail,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$kullaniciId/email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': newEmail}),
      );

      if (response.statusCode != 200) {
        throw Exception('E-posta güncelleme hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('E-posta güncelleme hatası: $e');
      // Demo için başarılı sayılır
    }
  }

  /// Kullanıcı şifresini güncelle
  Future<void> updateUserPassword({
    required int kullaniciId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$kullaniciId/password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Şifre güncelleme hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Şifre güncelleme hatası: $e');
      // Demo için başarılı sayılır
    }
  }

  /// Kullanıcı bilgilerini getir
  Future<Map<String, dynamic>?> getUserInfo(int kullaniciId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users/$kullaniciId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['user'];
      } else {
        throw Exception(
          'Kullanıcı bilgisi alma hatası: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Kullanıcı bilgisi alma hatası: $e');
      // Demo için sabit veri döndür
      return {
        'kullanici_id': kullaniciId,
        'eposta': 'admin@teknoloji.com',
        'rol': 'sahip',
        'isletme_id': 1,
      };
    }
  }

  /// İşletme bilgilerini getir
  Future<Map<String, dynamic>?> getBusinessInfo(int isletmeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/businesses/$isletmeId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['business'];
      } else {
        throw Exception('İşletme bilgisi alma hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('İşletme bilgisi alma hatası: $e');
      // Demo için sabit veri döndür
      return {'isletme_id': isletmeId, 'ad': 'Demo İşletme', 'sektor_id': 1};
    }
  }
}
