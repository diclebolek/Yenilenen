import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dil yönetimi için provider - çevrimdışı çalışır
class LanguageProvider extends ChangeNotifier {
  static const String _languageKey = 'selected_language';
  Locale _currentLocale = const Locale('tr', 'TR'); // Varsayılan Türkçe
  bool _isInitialized = false;

  Locale get currentLocale => _currentLocale;

  bool get isEnglish => _currentLocale.languageCode == 'en';
  bool get isTurkish => _currentLocale.languageCode == 'tr';
  bool get isInitialized => _isInitialized;

  /// Provider'ı başlat - kaydedilen dili yükle
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguage = prefs.getString(_languageKey);

      if (savedLanguage != null) {
        _currentLocale = Locale(savedLanguage);
      }
    } catch (e) {
      // Hata durumunda varsayılan dil kullan
      _currentLocale = const Locale('tr', 'TR');
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Dil tercihini kaydet
  Future<void> _saveLanguagePreference(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
    } catch (e) {
      // Kaydetme hatası - sessizce devam et
    }
  }

  /// Dil değiştir
  void changeLanguage(Locale locale) {
    if (_currentLocale != locale) {
      _currentLocale = locale;
      _saveLanguagePreference(locale.languageCode);
      notifyListeners();
    }
  }

  /// İngilizce'ye geç
  void switchToEnglish() {
    changeLanguage(const Locale('en', 'US'));
  }

  /// Türkçe'ye geç
  void switchToTurkish() {
    changeLanguage(const Locale('tr', 'TR'));
  }

  /// Dil değiştir (toggle)
  void toggleLanguage() {
    if (isTurkish) {
      switchToEnglish();
    } else {
      switchToTurkish();
    }
  }
}
