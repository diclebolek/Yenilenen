# Carbon Footprint Calculation App

Karbon ayak izi hesaplama ve takip uygulaması - Flutter ile geliştirilmiş işletme odaklı CO₂ emisyon takip sistemi.

## Özellikler

- 🔐 Firebase Authentication ile kullanıcı girişi ve kayıt
- 📊 CO₂ emisyon hesaplama ve görselleştirme
- 📈 Grafikler ve raporlar (fl_chart ile)
- 🌤️ Hava durumu entegrasyonu (OpenWeatherMap API)
- 📱 Fatura tarama (ML Kit ile OCR)
- 🌍 Gerçek zamanlı iklim verileri
- 🎯 Hedef belirleme ve takip
- 🌐 Çoklu dil desteği (Türkçe/İngilizce)
- 🎨 Modern Material 3 tasarımı
- 🔌 **ESP8266 IoT entegrasyonu** - Gerçek zamanlı sensör verileri
- ⚡ **Shelly Plug S entegrasyonu** - Akıllı priz ile güç tüketimi takibi
- 🔗 **Blockchain entegrasyonu** - Web3 ve Ethereum desteği
- 📡 **WebSocket desteği** - Gerçek zamanlı veri akışı
- 🌐 **Global karbon verileri** - Our World in Data entegrasyonu

## Gereksinimler

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Firebase projesi (Firebase Console'dan oluşturulmalı)
- PostgreSQL veritabanı (opsiyonel - HTTP API üzerinden)
- ESP8266 modülü (opsiyonel - IoT sensör verileri için)
- Shelly Plug S cihazı (opsiyonel - akıllı priz için)

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
   - Firebase Realtime Database'i etkinleştirin
   - Authentication'ı etkinleştirin (Email/Password)

4. API Key Yapılandırması (Opsiyonel):
   - **Hava Durumu API**: `lib/services/weather_service.dart` dosyasında:
     - `_apiKey` değişkenine OpenWeatherMap API key'inizi ekleyin
     - `_aqiApiKey` değişkenine AirVisual API key'inizi ekleyin (hava kalitesi için)
   - API key'ler olmadan da uygulama çalışır (placeholder veri kullanır)

5. IoT Cihaz Yapılandırması (Opsiyonel):

   **ESP8266 Yapılandırması:**
   - ESP8266 modülünüzün IP adresini `lib/services/api_service.dart` dosyasında güncelleyin:
     ```dart
     static const String espBaseUrl = 'http://192.168.1.100'; // ESP IP adresiniz
     ```
   - ESP8266'nın `/api/consumption` endpoint'ini desteklediğinden emin olun
   - Cihaz ID'sini değiştirmek için `deviceId` değişkenini güncelleyin

   **Shelly Plug S Yapılandırması:**
   - Shelly cihazınızın IP adresini `lib/screens/reports_screen.dart` dosyasında güncelleyin:
     ```dart
     _apiService.initializeShelly(
       deviceIp: '10.55.13.119', // Shelly IP adresiniz
       deviceId: 'shelly_plug_001',
     );
     ```
   - Shelly cihazı HTTP API ve WebSocket desteği sağlamalıdır

6. Assets (Görseller):
   Aşağıdaki görselleri `assets/images/` klasörüne eklemeniz gerekmektedir:
   - `herosectionafis.png` - Ana sayfa hero görseli 1
   - `herosectionafis2.png` - Ana sayfa hero görseli 2
   - `herosectionafis3.png` - Ana sayfa hero görseli 3
   - `olive-drab_small.webp` - Ağaç bağışı banner görseli
   - `bckgrnd2.jpeg` - Login/Register arkaplan görseli
   - `foto_yükleme.png` - Fatura tarama placeholder görseli
   - `tema-vakfi-logosu_1.png` - TEMA Vakfı logosu
   - `greenpeacelogo.png` - Greenpeace logosu
   - `akut.png` - AKUT logosu
   - `çevko.jpg` - ÇEVKO logosu

7. Uygulamayı çalıştırın:
```bash
flutter run
```

Detaylı kurulum için `KURULUM.md` dosyasına bakın.

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

### Temel Paketler
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

### IoT ve Blockchain
- `web3dart` - Blockchain entegrasyonu (Ethereum)
- `web_socket_channel` - WebSocket desteği (Shelly Plug S için)
- `connectivity_plus` - Ağ bağlantı durumu kontrolü

## Ekranlar

- **Login Screen** - Kullanıcı girişi
- **Register Screen** - Yeni kullanıcı/işletme kaydı
- **Home Screen** - Ana sayfa (dashboard, hava durumu, karbon yoğunluğu)
- **Reports Screen** - Raporlar ve grafikler (ESP/Manuel veri toggle)
- **Goals Screen** - Hedef belirleme ve takip
- **Settings Screen** - Ayarlar (tema, dil, font boyutu)
- **Profile Settings Screen** - Profil ayarları ve işletme bilgileri

## Servisler ve Entegrasyonlar

### API Servisleri
- **ApiService** - ESP8266 ve Shelly Plug S entegrasyonu
- **WeatherService** - Hava durumu ve hava kalitesi (OpenWeatherMap, AirVisual)
- **GlobalCarbonService** - Dünya geneli karbon trend verileri (Our World in Data)
- **ShellyService** - Shelly Plug S HTTP API ve WebSocket desteği

### Veritabanı Servisleri
- **FirebaseRealtimeService** - Firebase Realtime Database işlemleri
- **FirebaseAuthService** - Kullanıcı kimlik doğrulama
- **DatabaseService** - Yerel veri saklama (SharedPreferences)
- **PostgresService** - PostgreSQL bağlantısı (opsiyonel, HTTP API üzerinden)

### Blockchain
- **BlockchainService** - Ethereum blockchain entegrasyonu (Web3)

### Hesaplama Algoritmaları
- **Calculation** - CO₂ emisyon hesaplama algoritmaları
- **EnergyEfficiency** - Enerji verimliliği hesaplamaları

## Karbon Ayak İzi Hesaplama Metodolojisi

### Hesaplama Formülleri

Uygulama, kullanıcıların günlük tüketim verilerini CO₂ eşdeğeri (CO₂e) cinsinden hesaplar. Hesaplama, uluslararası standartlara uygun emisyon faktörleri kullanılarak yapılmaktadır:

#### 1. Elektrik Tüketimi
```
CO₂e (kg) = Elektrik Tüketimi (kWh) × 0.233 kg CO₂e/kWh
```
- **Emisyon Faktörü**: 0.233 kg CO₂e/kWh
- **Kaynak**: Türkiye elektrik üretim karışımı ortalaması
- **Not**: Bu değer, Türkiye'nin elektrik üretim kaynakları (kömür, doğalgaz, hidroelektrik, rüzgar, güneş vb.) dikkate alınarak hesaplanmıştır.

#### 2. Yakıt Tüketimi
```
CO₂e (kg) = Yakıt Tüketimi (Litre) × 2.31 kg CO₂e/Litre
```
- **Emisyon Faktörü**: 2.31 kg CO₂e/Litre
- **Kaynak**: Benzin/dizel yakıt yanma emisyon faktörü (IPCC standartları)
- **Not**: Bu değer, ortalama benzin ve dizel yakıtlar için geçerlidir.

#### 3. Su Tüketimi
```
CO₂e (kg) = Su Tüketimi (m³) × 0.344 kg CO₂e/m³
```
- **Emisyon Faktörü**: 0.344 kg CO₂e/m³
- **Kaynak**: Su arıtma, dağıtım ve atık su işleme süreçlerinin toplam emisyonu
- **Not**: Su tüketiminin karbon ayak izi, suyun arıtılması, pompalanması ve atık suyun işlenmesi süreçlerinden kaynaklanan enerji tüketimini içerir.

#### 4. Atık Üretimi
```
CO₂e (kg) = Atık Miktarı (kg) × 1.9 kg CO₂e/kg
```
- **Emisyon Faktörü**: 1.9 kg CO₂e/kg
- **Kaynak**: Atık toplama, taşıma ve bertaraf süreçlerinin ortalama emisyonu
- **Not**: Bu değer, atığın toplanması, taşınması ve bertaraf edilmesi süreçlerinden kaynaklanan emisyonları içerir.

### Toplam Günlük Emisyon
```
Toplam CO₂e (kg/gün) = Elektrik Emisyonu + Yakıt Emisyonu + Su Emisyonu + Atık Emisyonu
```

### Normal Değerler (Referans)
- **Dünya Ortalaması**: ~4.1 kg CO₂e/gün (kişi başı)
- **Türkiye Ortalaması**: ~6.8 kg CO₂e/gün (kişi başı)
- **ABD Ortalaması**: ~15.5 kg CO₂e/gün (kişi başı)
- **Avrupa Ortalaması**: ~8-9 kg CO₂e/gün (kişi başı)

### Veri Kaynakları ve Doğruluk
- Emisyon faktörleri, IPCC (Intergovernmental Panel on Climate Change) standartları ve ulusal enerji istatistikleri temel alınarak belirlenmiştir.
- Elektrik emisyon faktörü, Türkiye'nin güncel elektrik üretim karışımına göre güncellenebilir.
- Hesaplamalar, kullanıcıların günlük tüketim verilerine dayanmaktadır ve gerçek zamanlı IoT sensör verileri ile desteklenebilir.

## Ülke Verileri ve Grafik Karşılaştırması

### Veri Kaynağı: Our World in Data (OWID)

Uygulama, grafiklerde gösterilen ülke karşılaştırma verilerini **Our World in Data (OWID)** platformundan çekmektedir. Bu platform, dünya genelinde karbon emisyon verilerini açık kaynak olarak sağlamaktadır.

#### Veri Çekme Yöntemi
- **API Endpoint**: `https://raw.githubusercontent.com/owid/co2-data/master/owid-co2-data.json`
- **Veri Formatı**: JSON
- **Güncelleme**: Veriler düzenli olarak güncellenmektedir
- **API Key Gereksinimi**: Yok (açık kaynak veri)

#### Desteklenen Ülkeler
Uygulama şu ülkelerin verilerini grafikte gösterir:
- **Türkiye** (TUR) - ISO 3166-1 alpha-3 kodu
- **ABD** (USA)
- **Çin** (CHN)
- **Almanya** (DEU)
- **Fransa** (FRA)
- **İngiltere** (GBR)

#### Veri İşleme Süreci

1. **Veri Çekme**: 
   - Her ülke için ISO 3166-1 alpha-3 formatında ülke kodu kullanılarak veri çekilir
   - Yıllık CO₂ emisyon verileri (ton CO₂e/yıl) alınır

2. **Dönüştürme**:
   - Yıllık veriler, kişi başı günlük değerlere dönüştürülür:
   ```
   Günlük Emisyon (kg CO₂e/gün) = (Yıllık Emisyon (ton/yıl) × 1000) / 365
   ```
   - Son 7 yılın verileri kullanılarak trend oluşturulur

3. **Normalizasyon**:
   - Ülke verileri kişi başı değerler olarak hesaplanır (`co2_per_capita`)
   - Kullanıcı verileri ile karşılaştırılabilir hale getirilir
   - Grafikte görünürlük için ölçeklendirme uygulanır (kullanıcı verileri çok yüksekse)

4. **Hata Yönetimi**:
   - API'den veri çekilemezse veya veri geçersizse, placeholder (tahmini) veriler kullanılır
   - Placeholder veriler, ülkelere göre ortalama kişi başı günlük emisyon değerlerine dayanır:
     - Türkiye: 4.2 kg/gün
     - ABD: 15.5 kg/gün
     - Çin: 7.4 kg/gün
     - Almanya: 8.9 kg/gün
     - Fransa: 8.0 kg/gün
     - İngiltere: 7.8 kg/gün

#### Grafik Gösterimi

- **Kullanıcı Verileri**: Koyu yeşil çizgi ile gösterilir (gerçek zamanlı veya manuel giriş)
- **Ülke Verileri**: Farklı renklerle gösterilir:
  - Türkiye: Mavi
  - ABD: Kırmızı
  - Çin: Turuncu
  - Almanya: Sarı
  - Fransa: Mor
  - İngiltere: Teal (turkuaz)

- **Veri Kaynağı Göstergesi**:
  - ✅ Yeşil işaret: Gerçek veri (API'den başarıyla yüklendi)
  - ⚠️ Turuncu işaret: Tahmini veri (placeholder, API'den yüklenemedi)

#### Ölçeklendirme ve Görünürlük

Kullanıcı verileri ile ülke verileri arasında büyük fark olduğunda (örneğin kullanıcı verileri 900+ kg/gün, ülke verileri 4-15 kg/gün), ülke verileri grafikte görünür olması için ölçeklendirilir:
- Ülke verileri, kullanıcı max değerinin %15'ine ölçeklendirilir
- Her ülke çizgisi, görünürlük için farklı yükseklik offset'i ile ayrılır
- Bu sayede tüm ülke çizgileri grafikte ayırt edilebilir şekilde görüntülenir

### Veri Doğruluğu ve Güncellik

- **Our World in Data** verileri, dünya genelinde kabul görmüş ve güvenilir kaynaklardan toplanmaktadır
- Veriler düzenli olarak güncellenmektedir
- Yıllık veriler, en son mevcut yıl için sağlanmaktadır
- Kişi başı değerler, ülke nüfus verileri ile hesaplanmaktadır

## Önemli Notlar

### Yapılandırma
- **PostgreSQL bağlantısı opsiyoneldir** (HTTP API üzerinden)
- **Hava durumu API'leri opsiyoneldir** - API key olmadan placeholder veri kullanılır
- **ESP8266 ve Shelly Plug S opsiyoneldir** - Manuel veri girişi ile de çalışır
- **Firebase Realtime Database** kullanılmaktadır (gerçek zamanlı veri senkronizasyonu için)

### Platform Desteği
- ✅ Web (Chrome, Firefox, Safari)
- ✅ Android (API 21+)
- ✅ iOS (iOS 12+)
- ❌ Windows desktop (CMake gerektirir, devre dışı)

### Güvenlik
- Firebase Authentication ile kullanıcı verileri korunur
- API key'ler kod içinde saklanmamalıdır (production için environment variables kullanın)
- ESP8266 ve Shelly cihazları yerel ağda olmalıdır (güvenlik için)

### Geliştirme
- Hot reload desteklenir (`r` tuşu)
- Hot restart için `R` tuşu
- Debug modda detaylı loglar görüntülenir
- `flutter doctor` komutu ile kurulum kontrolü yapılabilir

### Veri Akışı
1. **Manuel Giriş**: Kullanıcı form ile veri girer → Hesaplama → Firebase'e kayıt
2. **ESP8266**: Sensör verileri → HTTP API → Firebase → Uygulama
3. **Shelly Plug S**: Güç tüketimi → HTTP API/WebSocket → Firebase → Uygulama
4. **Firebase Realtime**: Tüm veriler gerçek zamanlı olarak senkronize edilir

## Sorun Giderme

### Firebase Bağlantı Hatası
- `lib/firebase_options.dart` dosyasının doğru yapılandırıldığından emin olun
- Firebase Console'da Realtime Database'in etkin olduğunu kontrol edin
- Authentication yöntemlerinin (Email/Password) etkin olduğunu kontrol edin

### ESP8266 Bağlantı Hatası
- ESP8266'nın aynı ağda olduğundan emin olun
- IP adresinin doğru olduğunu kontrol edin (`lib/services/api_service.dart`)
- ESP8266'nın `/api/consumption` endpoint'ini desteklediğinden emin olun
- Firewall ayarlarını kontrol edin

### Shelly Plug S Bağlantı Hatası
- Shelly cihazının IP adresinin doğru olduğunu kontrol edin
- Cihazın HTTP API ve WebSocket desteğinin etkin olduğundan emin olun
- Ağ bağlantısını kontrol edin

### Görsel Hataları
- `assets/images/` klasörüne gerekli görselleri ekleyin
- `pubspec.yaml` dosyasında assets yapılandırmasının doğru olduğunu kontrol edin
- `flutter pub get` komutunu çalıştırın

### Build Hataları
- `flutter clean` komutunu çalıştırın
- `flutter pub get` komutunu tekrar çalıştırın
- `flutter doctor` ile eksik bileşenleri kontrol edin

### API Key Hataları
- API key'ler olmadan da uygulama çalışır (placeholder veri kullanır)
- Gerçek veri için API key'leri `lib/services/weather_service.dart` içinde yapılandırın

## Katkıda Bulunma

Bu proje eğitim amaçlı geliştirilmiştir. Katkılarınızı bekliyoruz!

## Lisans

Bu proje eğitim amaçlı geliştirilmiştir.
