import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

/// Hava durumu ve iklim verileri servisi
/// Placeholder/mock veri kullanıyor (API key gerektirmez)
class WeatherService {
  // API key yoksa placeholder veri döndürülür
  static const String _apiKey = 'YOUR_API_KEY_HERE';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  // Hava kalitesi için placeholder veri kullanılıyor
  static const String _aqiApiKey = 'YOUR_AQI_API_KEY_HERE';
  static const String _aqiBaseUrl = 'https://api.airvisual.com/v2';

  WeatherService();

  /// Şehir için hava durumu verilerini çek
  /// [cityName] şehir adı (örn: "Istanbul,TR")
  Future<Map<String, dynamic>> getWeatherData(String cityName) async {
    try {
      // Eğer API key yoksa placeholder döndür
      if (_apiKey == 'YOUR_API_KEY_HERE') {
        dev.log(
          'OpenWeatherMap API key bulunamadı, placeholder veri döndürülüyor',
          name: 'WeatherService',
        );
        return _getPlaceholderWeather(cityName);
      }

      final response = await http
          .get(
            Uri.parse(
              '$_baseUrl/weather?q=$cityName&appid=$_apiKey&units=metric&lang=tr',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'city': data['name'] ?? cityName,
          'temperature': (data['main']?['temp'] ?? 0.0).toDouble(),
          'condition': _getWeatherCondition(data['weather']?[0]?['main']),
          'description': data['weather']?[0]?['description'] ?? '',
          'humidity': data['main']?['humidity'] ?? 0,
          'windSpeed': (data['wind']?['speed'] ?? 0.0).toDouble(),
          'icon': data['weather']?[0]?['icon'] ?? '',
        };
      } else {
        dev.log(
          'Hava durumu API hatası: ${response.statusCode}',
          name: 'WeatherService',
        );
        return _getPlaceholderWeather(cityName);
      }
    } catch (e) {
      dev.log('Hava durumu çekme hatası: $e', name: 'WeatherService');
      return _getPlaceholderWeather(cityName);
    }
  }

  /// 5 günlük hava durumu tahmini
  Future<List<Map<String, dynamic>>> getWeatherForecast(String cityName) async {
    try {
      if (_apiKey == 'YOUR_API_KEY_HERE') {
        return _getPlaceholderForecast();
      }

      final response = await http
          .get(
            Uri.parse(
              '$_baseUrl/forecast?q=$cityName&appid=$_apiKey&units=metric&lang=tr',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> list = data['list'] ?? [];

        // İlk 3 günü al (bugün, yarın, 2 gün sonra)
        return list.take(3).map((item) {
          return {
            'date': DateTime.fromMillisecondsSinceEpoch(
              (item['dt'] ?? 0) * 1000,
            ),
            'temperature': (item['main']?['temp'] ?? 0.0).toDouble(),
            'condition': _getWeatherCondition(item['weather']?[0]?['main']),
            'description': item['weather']?[0]?['description'] ?? '',
            'icon': item['weather']?[0]?['icon'] ?? '',
          };
        }).toList();
      } else {
        return _getPlaceholderForecast();
      }
    } catch (e) {
      dev.log('Hava durumu tahmini hatası: $e', name: 'WeatherService');
      return _getPlaceholderForecast();
    }
  }

  /// Hava kalitesi (AQI) verilerini çek
  Future<Map<String, dynamic>> getAirQuality(
    String city,
    String state,
    String country,
  ) async {
    try {
      if (_aqiApiKey == 'YOUR_AQI_API_KEY_HERE') {
        dev.log(
          'AirVisual API key bulunamadı, placeholder veri döndürülüyor',
          name: 'WeatherService',
        );
        return _getPlaceholderAQI();
      }

      // Önce şehir koordinatlarını al
      final cityResponse = await http
          .get(
            Uri.parse(
              '$_aqiBaseUrl/city?city=$city&state=$state&country=$country&key=$_aqiApiKey',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (cityResponse.statusCode == 200) {
        final data = json.decode(cityResponse.body);
        final aqi = data['data']?['current']?['pollution']?['aqius'] ?? 0;
        final aqiText = _getAQIText(aqi);

        return {'success': true, 'aqi': aqi, 'aqiText': aqiText, 'city': city};
      } else {
        return _getPlaceholderAQI();
      }
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

  /// Hava durumu koşulunu Türkçe'ye çevir
  String _getWeatherCondition(String? condition) {
    if (condition == null) return 'Bilinmiyor';

    const Map<String, String> conditions = {
      'Clear': 'Açık',
      'Clouds': 'Bulutlu',
      'Rain': 'Yağmurlu',
      'Drizzle': 'Çiseleyen Yağmur',
      'Thunderstorm': 'Fırtına',
      'Snow': 'Karlı',
      'Mist': 'Sisli',
      'Fog': 'Sisli',
      'Haze': 'Puslu',
    };

    return conditions[condition] ?? condition;
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
