import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

/// Hava durumu ve iklim verileri servisi
/// Open-Meteo API kullanıyor (tamamen ücretsiz, API key gerektirmez)
class WeatherService {
  // Open-Meteo API - tamamen ücretsiz, API key gerektirmiyor
  static const String _weatherBaseUrl = 'https://api.open-meteo.com/v1';
  static const String _geocodingBaseUrl = 'https://geocoding-api.open-meteo.com/v1';
  static const String _airQualityBaseUrl = 'https://air-quality-api.open-meteo.com/v1';

  WeatherService();

  /// Şehir için hava durumu verilerini çek
  /// [cityName] şehir adı (örn: "Istanbul,TR" veya "Sakarya,TR")
  Future<Map<String, dynamic>> getWeatherData(String cityName) async {
    try {
      // Önce şehir adından koordinatları al
      final coordinates = await _getCityCoordinates(cityName);
      if (coordinates == null) {
        dev.log(
          'Şehir koordinatları bulunamadı: $cityName',
          name: 'WeatherService',
        );
        return _getPlaceholderWeather(cityName);
      }

      final lat = coordinates['latitude'];
      final lon = coordinates['longitude'];
      final city = coordinates['name'] ?? cityName.split(',')[0];

      // Open-Meteo hava durumu API'sini çağır
      final response = await http
          .get(
            Uri.parse(
              '$_weatherBaseUrl/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&timezone=auto',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];

        if (current != null) {
          final weatherCode = current['weather_code'] ?? 0;
          return {
            'success': true,
            'city': city,
            'temperature': (current['temperature_2m'] ?? 0.0).toDouble(),
            'condition': _getWeatherConditionFromCode(weatherCode),
            'description': _getWeatherDescriptionFromCode(weatherCode),
            'humidity': current['relative_humidity_2m'] ?? 0,
            'windSpeed': (current['wind_speed_10m'] ?? 0.0).toDouble(),
            'icon': _getWeatherIconFromCode(weatherCode),
          };
        }
      }

      dev.log(
        'Hava durumu API hatası: ${response.statusCode}',
        name: 'WeatherService',
      );
      return _getPlaceholderWeather(cityName);
    } catch (e) {
      dev.log('Hava durumu çekme hatası: $e', name: 'WeatherService');
      return _getPlaceholderWeather(cityName);
    }
  }

  /// 5 günlük hava durumu tahmini
  Future<List<Map<String, dynamic>>> getWeatherForecast(String cityName) async {
    try {
      // Önce şehir adından koordinatları al
      final coordinates = await _getCityCoordinates(cityName);
      if (coordinates == null) {
        return _getPlaceholderForecast();
      }

      final lat = coordinates['latitude'];
      final lon = coordinates['longitude'];

      // Open-Meteo tahmin API'sini çağır (günlük veriler)
      final response = await http
          .get(
            Uri.parse(
              '$_weatherBaseUrl/forecast?latitude=$lat&longitude=$lon&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final daily = data['daily'];

        if (daily != null) {
          final List<dynamic> timeList = daily['time'] ?? [];
          final List<dynamic> weatherCodeList = daily['weather_code'] ?? [];
          final List<dynamic> tempMaxList = daily['temperature_2m_max'] ?? [];
          final List<dynamic> tempMinList = daily['temperature_2m_min'] ?? [];

          // İlk 3 günü al (bugün, yarın, 2 gün sonra)
          return List.generate(
            timeList.length > 3 ? 3 : timeList.length,
            (index) {
              final dateStr = timeList[index] as String;
              final date = DateTime.parse(dateStr);
              final weatherCode = weatherCodeList[index] ?? 0;
              final tempMax = tempMaxList[index] ?? 0.0;
              final tempMin = tempMinList[index] ?? 0.0;
              final avgTemp = ((tempMax + tempMin) / 2).toDouble();

              return {
                'date': date,
                'temperature': avgTemp,
                'condition': _getWeatherConditionFromCode(weatherCode),
                'description': _getWeatherDescriptionFromCode(weatherCode),
                'icon': _getWeatherIconFromCode(weatherCode),
              };
            },
          );
        }
      }

      return _getPlaceholderForecast();
    } catch (e) {
      dev.log('Hava durumu tahmini hatası: $e', name: 'WeatherService');
      return _getPlaceholderForecast();
    }
  }

  /// Hava kalitesi (AQI) verilerini çek
  /// Open-Meteo Air Quality API kullanıyor (ücretsiz)
  Future<Map<String, dynamic>> getAirQuality(
    String city,
    String state,
    String country,
  ) async {
    try {
      // Şehir adını birleştir
      final cityName = '$city,$country';
      final coordinates = await _getCityCoordinates(cityName);
      if (coordinates == null) {
        return _getPlaceholderAQI();
      }

      final lat = coordinates['latitude'];
      final lon = coordinates['longitude'];

      // Open-Meteo Air Quality API'sini çağır
      final response = await http
          .get(
            Uri.parse(
              '$_airQualityBaseUrl/air-quality?latitude=$lat&longitude=$lon&current=us_aqi,pm10,pm2_5',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];

        if (current != null) {
          final aqi = current['us_aqi'] ?? 0;
          final aqiText = _getAQIText(aqi);

          return {
            'success': true,
            'aqi': aqi,
            'aqiText': aqiText,
            'city': city,
            'pm10': current['pm10'] ?? 0,
            'pm2_5': current['pm2_5'] ?? 0,
          };
        }
      }

      return _getPlaceholderAQI();
    } catch (e) {
      dev.log('AQI çekme hatası: $e', name: 'WeatherService');
      return _getPlaceholderAQI();
    }
  }

  /// Elektrik karbon yoğunluğu (Türkiye için yaklaşık değer)
  /// Gerçek API için: https://www.electricitymaps.com/ veya benzeri servisler kullanılabilir
  Future<double> getCarbonIntensity(String country) async {
    // Türkiye için ortalama değer (gCO2/kWh)
    // Gerçek veri için Electricity Maps API kullanılabilir
    const Map<String, double> countryAverages = {
      'TR': 420.0, // Türkiye ortalaması
      'US': 400.0,
      'DE': 350.0,
      'FR': 50.0, // Nükleer enerji nedeniyle düşük
    };

    return countryAverages[country] ?? 400.0;
  }

  /// Şehir adından koordinatları al (Open-Meteo Geocoding API)
  Future<Map<String, dynamic>?> _getCityCoordinates(String cityName) async {
    try {
      // Şehir adını temizle (örn: "Istanbul,TR" -> "Istanbul")
      final cleanCityName = cityName.split(',')[0].trim();

      final response = await http
          .get(
            Uri.parse(
              '$_geocodingBaseUrl/search?name=$cleanCityName&count=1&language=tr&format=json',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final result = results[0];
          return {
            'latitude': result['latitude'] ?? 0.0,
            'longitude': result['longitude'] ?? 0.0,
            'name': result['name'] ?? cleanCityName,
          };
        }
      }

      return null;
    } catch (e) {
      dev.log('Koordinat bulma hatası: $e', name: 'WeatherService');
      return null;
    }
  }

  /// Open-Meteo weather code'undan hava durumu koşulunu al
  /// WMO Weather interpretation codes (WW) kullanılıyor
  String _getWeatherConditionFromCode(int code) {
    // WMO Weather interpretation codes
    if (code == 0) return 'Açık';
    if (code <= 3) return 'Az Bulutlu';
    if (code <= 48) return 'Bulutlu';
    if (code <= 57) return 'Yağmurlu';
    if (code <= 67) return 'Yağmurlu';
    if (code <= 77) return 'Karlı';
    if (code <= 82) return 'Yağmurlu';
    if (code <= 86) return 'Karlı';
    if (code <= 99) return 'Fırtına';
    return 'Bilinmiyor';
  }

  /// Open-Meteo weather code'undan açıklama al
  String _getWeatherDescriptionFromCode(int code) {
    // WMO Weather interpretation codes açıklamaları
    const Map<int, String> descriptions = {
      0: 'Açık gökyüzü',
      1: 'Çoğunlukla açık',
      2: 'Kısmen bulutlu',
      3: 'Kapalı',
      45: 'Sisli',
      48: 'Donlu sis',
      51: 'Hafif çiseleyen yağmur',
      53: 'Orta çiseleyen yağmur',
      55: 'Yoğun çiseleyen yağmur',
      56: 'Hafif donlu çiseleyen yağmur',
      57: 'Yoğun donlu çiseleyen yağmur',
      61: 'Hafif yağmur',
      63: 'Orta yağmur',
      65: 'Yoğun yağmur',
      66: 'Hafif donlu yağmur',
      67: 'Yoğun donlu yağmur',
      71: 'Hafif kar',
      73: 'Orta kar',
      75: 'Yoğun kar',
      77: 'Kar taneleri',
      80: 'Hafif sağanak yağmur',
      81: 'Orta sağanak yağmur',
      82: 'Yoğun sağanak yağmur',
      85: 'Hafif kar sağanağı',
      86: 'Yoğun kar sağanağı',
      95: 'Fırtına',
      96: 'Dolu ile fırtına',
      99: 'Şiddetli dolu ile fırtına',
    };

    return descriptions[code] ?? 'Bilinmiyor';
  }

  /// Open-Meteo weather code'undan icon kodu al
  String _getWeatherIconFromCode(int code) {
    // Basit icon mapping (OpenWeatherMap icon formatına benzer)
    if (code == 0) return '01d'; // Açık
    if (code <= 3) return '02d'; // Az bulutlu
    if (code <= 48) return '03d'; // Bulutlu
    if (code <= 57) return '09d'; // Yağmurlu
    if (code <= 67) return '10d'; // Yağmurlu
    if (code <= 77) return '13d'; // Karlı
    if (code <= 82) return '09d'; // Sağanak
    if (code <= 86) return '13d'; // Kar sağanağı
    if (code <= 99) return '11d'; // Fırtına
    return '01d';
  }

  /// AQI değerini metne çevir
  String _getAQIText(int aqi) {
    if (aqi <= 50) return 'İyi';
    if (aqi <= 100) return 'Orta';
    if (aqi <= 150) return 'Hassas Gruplar İçin Sağlıksız';
    if (aqi <= 200) return 'Sağlıksız';
    if (aqi <= 300) return 'Çok Sağlıksız';
    return 'Tehlikeli';
  }

  /// Placeholder hava durumu verisi
  Map<String, dynamic> _getPlaceholderWeather(String cityName) {
    return {
      'success': false,
      'city': cityName.split(',')[0],
      'temperature': 24.0,
      'condition': 'Açık',
      'description': 'Mock hava durumu verisi',
      'humidity': 60,
      'windSpeed': 10.0,
      'icon': '01d',
    };
  }

  /// Placeholder hava durumu tahmini
  List<Map<String, dynamic>> _getPlaceholderForecast() {
    return [
      {
        'date': DateTime.now(),
        'temperature': 24.0,
        'condition': 'Açık',
        'description': 'Placeholder',
        'icon': '01d',
      },
      {
        'date': DateTime.now().add(const Duration(days: 1)),
        'temperature': 18.0,
        'condition': 'Bulutlu',
        'description': 'Placeholder',
        'icon': '02d',
      },
      {
        'date': DateTime.now().add(const Duration(days: 2)),
        'temperature': 22.0,
        'condition': 'Karışık',
        'description': 'Placeholder',
        'icon': '03d',
      },
    ];
  }

  /// Placeholder AQI verisi
  Map<String, dynamic> _getPlaceholderAQI() {
    return {'success': false, 'aqi': 78, 'aqiText': 'Orta', 'city': 'İstanbul'};
  }
}
