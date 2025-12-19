# Carbon Footprint Calculation App

Karbon ayak izi hesaplama ve takip uygulaması - Flutter ile geliştirilmiş işletme odaklı CO₂ emisyon takip sistemi.

## Özellikler

- 🔐 Firebase Authentication ile kullanıcı girişi ve kayıt
- 📊 CO₂ emisyon hesaplama ve görselleştirme
- 📈 Grafikler ve raporlar (fl_chart ile)
- 🌤️ Hava durumu entegrasyonu
- 📱 Fatura tarama (ML Kit ile OCR)
- 🌍 Gerçek zamanlı iklim verileri
- 🎯 Hedef belirleme ve takip
- 🌐 Çoklu dil desteği (Türkçe/İngilizce)
- 🎨 Modern Material 3 tasarımı

## Gereksinimler

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Firebase projesi (Firebase Console'dan oluşturulmalı)
- PostgreSQL veritabanı (opsiyonel - HTTP API üzerinden)

## Kurulum

1. Projeyi klonlayın:
```bash
git clone <repository-url>
cd bitirme_C02
```

2. Bağımlılıkları yükleyin:
```bash
flutter pub get
```

3. Firebase yapılandırması:
   - Firebase Console'dan yeni bir proje oluşturun
   - `lib/firebase_options.dart` dosyasındaki Firebase config bilgilerini güncelleyin
   - Android/iOS için gerekli config dosyalarını ekleyin

4. Assets (Görseller):
   Aşağıdaki görselleri `assets/images/` klasörüne eklemeniz gerekmektedir:
   - `herosectionafis.jpg` - Ana sayfa hero görseli 1
   - `herosectionafis2.jpg` - Ana sayfa hero görseli 2
   - `herosectionafis3.jpg` - Ana sayfa hero görseli 3
   - `olive-drab_small.webp` - Ağaç bağışı banner görseli
   - `bckgrnd2.jpeg` - Login/Register arkaplan görseli
   - `foto_yükleme.png` - Fatura tarama placeholder görseli
   - `tema-vakfi-logosu_1.png` - TEMA Vakfı logosu
   - `greenpeacelogo.png` - Greenpeace logosu
   - `akut.png` - AKUT logosu
   - `çevko.jpg` - ÇEVKO logosu

5. Uygulamayı çalıştırın:
```bash
flutter run
```

## Proje Yapısı

```
lib/
├── algorithms/          # CO₂ hesaplama algoritmaları
├── localization/       # Çeviri dosyaları
├── models/             # Veri modelleri
├── providers/          # State management (Provider)
├── screens/            # Ekranlar (UI)
├── services/           # Servisler (Firebase, API, Database)
├── themes/             # Tema yapılandırması
└── widgets/            # Yeniden kullanılabilir widget'lar
```

## Kullanılan Paketler

- `firebase_core` - Firebase temel yapılandırma
- `firebase_auth` - Kullanıcı kimlik doğrulama
- `firebase_database` - Realtime Database
- `provider` - State management
- `fl_chart` - Grafik ve çizelgeler
- `http` - HTTP istekleri
- `image_picker` - Görsel seçme
- `google_mlkit_text_recognition` - OCR (fatura tarama)
- `url_launcher` - URL açma
- `shared_preferences` - Yerel veri saklama
- `web3dart` - Blockchain entegrasyonu

## Ekranlar

- **Login Screen** - Kullanıcı girişi
- **Register Screen** - Yeni kullanıcı/işletme kaydı
- **Home Screen** - Ana sayfa (dashboard)
- **Reports Screen** - Raporlar ve grafikler
- **Goals Screen** - Hedef belirleme ve takip
- **Settings Screen** - Ayarlar (tema, dil, font boyutu)

## Notlar

- PostgreSQL bağlantısı opsiyoneldir (HTTP API üzerinden)
- Hava durumu API'leri için API key'ler `weather_service.dart` içinde yapılandırılmalıdır
- Firebase Realtime Database kullanılmaktadır
- Uygulama web, Android ve iOS platformlarını destekler
- **Windows desktop build devre dışı bırakılmıştır** (CMake gerektirir)

## Lisans

Bu proje eğitim amaçlı geliştirilmiştir.
