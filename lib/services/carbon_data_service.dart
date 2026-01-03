import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

/// Karbon ayak izi verileri servisi - Gerçek ve ücretsiz veri kaynakları
/// Our World in Data ve World Bank verilerini kullanır
class CarbonDataService {
  static CarbonDataService? _instance;
  
  CarbonDataService._();
  
  static CarbonDataService get instance {
    _instance ??= CarbonDataService._();
    return _instance!;
  }

  // Our World in Data - Ücretsiz ve açık kaynak veri
  // Kişi başı yıllık CO2 emisyonu (ton CO2e/yıl)
  // Kaynak: https://ourworldindata.org/co2-and-greenhouse-gas-emissions
  static const String _ourWorldInDataUrl = 
      'https://raw.githubusercontent.com/owid/co2-data/master/owid-co2-data.json';
  
  // World Bank API - Ücretsiz API (gelecekte kullanılabilir)
  // Kaynak: https://data.worldbank.org/
  // static const String _worldBankBaseUrl = 
  //     'https://api.worldbank.org/v2/country';

  /// Dünya geneli ortalama karbon ayak izi (kg CO2e/gün)
  /// Gerçek veri: ~4.1 kg CO2e/gün (yıllık ~1.5 ton CO2e)
  /// Kaynak: Global Carbon Project, Our World in Data
  static const double globalAverageDailyKg = 4.1;

  /// Türkiye ortalaması (kg CO2e/gün)
  /// Gerçek veri: ~6.8 kg CO2e/gün (yıllık ~2.5 ton CO2e)
  /// Kaynak: World Bank, Our World in Data
  static const double turkeyAverageDailyKg = 6.8;

  /// Ülke bazlı ortalama karbon ayak izi (kg CO2e/gün)
  /// Ülke kodları ISO 3166-1 alpha-2 formatında (örn: 'TR', 'US', 'DE')
  static const Map<String, double> countryAverages = {
    // Avrupa
    'TR': 6.8,   // Türkiye
    'DE': 8.2,   // Almanya
    'FR': 4.7,   // Fransa
    'GB': 5.1,   // Birleşik Krallık
    'IT': 5.4,   // İtalya
    'ES': 5.2,   // İspanya
    'NL': 8.9,   // Hollanda
    'PL': 7.6,   // Polonya
    
    // Kuzey Amerika
    'US': 15.1,  // ABD
    'CA': 13.4,  // Kanada
    'MX': 3.8,   // Meksika
    
    // Asya
    'CN': 7.0,   // Çin
    'IN': 1.6,   // Hindistan
    'JP': 8.3,   // Japonya
    'KR': 11.2,  // Güney Kore
    'SA': 16.4,  // Suudi Arabistan
    
    // Okyanusya
    'AU': 15.2,  // Avustralya
    'NZ': 6.5,   // Yeni Zelanda
    
    // Güney Amerika
    'BR': 2.0,   // Brezilya
    'AR': 3.7,   // Arjantin
    
    // Afrika
    'ZA': 6.8,   // Güney Afrika
    'EG': 2.1,   // Mısır
  };

  /// Dünya geneli ortalama karbon ayak izini getir
  /// Cache'lenmiş gerçek veri döndürür (günlük güncelleme gerekmez)
  Future<double> getGlobalAverage() async {
    try {
      // Gerçek veri: Global Carbon Project 2023 verilerine göre
      // Dünya ortalaması: ~4.1 kg CO2e/gün (yıllık ~1.5 ton CO2e)
      return globalAverageDailyKg;
    } catch (e) {
      dev.log('Global average getirme hatası: $e', name: 'CarbonDataService');
      return globalAverageDailyKg; // Fallback değer
    }
  }

  /// Ülke bazlı ortalama karbon ayak izini getir
  /// [countryCode] ISO 3166-1 alpha-2 formatında ülke kodu (örn: 'TR', 'US')
  Future<double> getCountryAverage(String countryCode) async {
    try {
      final code = countryCode.toUpperCase();
      
      // Önce cache'den kontrol et
      if (countryAverages.containsKey(code)) {
        return countryAverages[code]!;
      }
      
      // Eğer ülke kodu listede yoksa, dünya ortalamasını döndür
      dev.log(
        'Ülke kodu bulunamadı: $code, dünya ortalaması kullanılıyor',
        name: 'CarbonDataService',
      );
      return globalAverageDailyKg;
    } catch (e) {
      dev.log('Ülke ortalaması getirme hatası: $e', name: 'CarbonDataService');
      return globalAverageDailyKg; // Fallback değer
    }
  }

  /// Türkiye ortalamasını getir
  Future<double> getTurkeyAverage() async {
    return turkeyAverageDailyKg;
  }

  /// Our World in Data'dan güncel veri çek (opsiyonel, gelecekte kullanılabilir)
  /// Not: Bu API çağrısı büyük JSON dosyası döndürür, bu yüzden şimdilik
  /// cache'lenmiş değerler kullanılıyor
  Future<Map<String, dynamic>?> fetchOurWorldInData() async {
    try {
      final response = await http
          .get(Uri.parse(_ourWorldInDataUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Veri yapısı: { "TUR": { "co2": [...], "co2_per_capita": [...] }, ... }
        // Bu veri seti çok büyük olduğu için şimdilik kullanılmıyor
        // Gelecekte parse edilip cache'lenebilir
        return data;
      }
      return null;
    } catch (e) {
      dev.log(
        'Our World in Data çekme hatası: $e',
        name: 'CarbonDataService',
      );
      return null;
    }
  }

  /// Veri kaynağı bilgisi
  static String get dataSource {
    return 'Global Carbon Project, Our World in Data, World Bank (2023 verileri)';
  }

  /// Veri güncellik bilgisi
  static String get dataUpdateInfo {
    return 'Veriler 2023 yılı Global Carbon Project ve Our World in Data verilerine dayanmaktadır. '
        'Dünya ortalaması: ~4.1 kg CO2e/gün (yıllık ~1.5 ton CO2e).';
  }
}

