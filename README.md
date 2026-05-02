# Carbon Footprint Calculation App

Karbon ayak izi hesaplama ve takip uygulaması - Flutter ile geliştirilmiş işletme odaklı CO₂ emisyon takip sistemi.

## Özellikler

- 🔐 Firebase Authentication ile kullanıcı girişi ve kayıt
- 📊 CO₂ emisyon hesaplama ve görselleştirme
- 📈 Grafikler ve raporlar (fl_chart ile)
- 🌤️ Hava durumu entegrasyonu (Open-Meteo API - tamamen ücretsiz, API key gerektirmez)
- 📱 Fatura tarama (ML Kit ile OCR)
- 🌍 Gerçek zamanlı iklim verileri
- 🎯 Hedef belirleme ve takip
- 🔮 **Gelecek ay beklentisi** — Hedefler ekranında ay sonu CO₂e projeksiyonu, günlük tempo ve küresel günlük ortalamayla karşılaştırma
- 📄 **PDF raporlama** — Raporlar ekranından haftalık veya aylık karbon özeti (ISO uyumlu özet, kategori dağılımı); Unicode/Türkçe karakter desteği (OpenSans TTF)
- 🌐 **PDF rapor dili** — Raporlar bölümünden raporu **Türkçe** veya **English** olarak üretebilirsiniz (uygulama karanlık modda olsa bile dil seçimi geçerlidir)
- 🌐 Çoklu dil desteği (Türkçe/İngilizce)
- 🎨 Modern Material 3 tasarımı
- 🔌 **ESP8266 IoT entegrasyonu** - Gerçek zamanlı sensör verileri
- ⚡ **Shelly Plug S entegrasyonu** - Akıllı priz ile güç tüketimi takibi
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
cd carbon_footprint_calculation_app
```
*(Klasör adı farklıysa depo köküne göre `cd` yapın.)*

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

4. Hava Durumu API Yapılandırması:
   - **Open-Meteo API**: Tamamen ücretsiz ve API key gerektirmez
   - Uygulama otomatik olarak gerçek hava durumu verilerini çeker
   - Şehir adından koordinat bulma, hava durumu, tahmin ve hava kalitesi verileri sağlanır
   - Detaylı bilgi için aşağıdaki "Hava Durumu Entegrasyonu" bölümüne bakın

5. IoT Cihaz Yapılandırması (Opsiyonel):

   **ESP8266 Yapılandırması:**
   - ESP8266 modülünüzün IP adresini `lib/services/api_service.dart` dosyasında güncelleyin:
     ```dart
     static const String espBaseUrl = 'http://192.168.1.100'; // ESP IP adresiniz
     ```
   - ESP8266'nın `/api/consumption` endpoint'ini desteklediğinden emin olun
   - Cihaz ID'sini değiştirmek için `deviceId` değişkenini güncelleyin

   **Shelly Plug S Yapılandırması:**
   - Shelly cihazınızın IP adresini `lib/screens/reports_screen.dart` içindeki `_initializeShelly()` metodunda güncelleyin (`deviceIp:` ve isteğe bağlı `deviceId`).
   - Örnek:
     ```dart
     _apiService.initializeShelly(
       deviceIp: '192.168.x.x', // yerel ağdaki Shelly IP'niz
       deviceId: 'shelly_plug_001',
     );
     ```
   - Shelly cihazı HTTP API ve WebSocket desteği sağlamalıdır (cihaz/sürüme göre değişebilir).
   - `home_screen.dart` içinde de Shelly başlatma çağrısı olabilir; farklı dosyalarda **aynı IP** kullanıldığından emin olun.

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

## Docker ile Çalıştırma (Web)

Uygulamayı Docker ile her ortamda aynı şekilde çalıştırmak için:

1. İmajı build edin:
```bash
docker build -t carbon-footprint-app .
```

2. Container başlatın:
```bash
docker run --rm -p 8080:80 carbon-footprint-app
```

3. Tarayıcıdan açın:
- [http://localhost:8080](http://localhost:8080)

Alternatif olarak Docker Compose:
```bash
docker compose up --build
```

Detaylı kurulum için `KURULUM.md` dosyasına bakın.

**İlgili dokümanlar:** Emisyon faktörleri ve formül ayrıntıları için `KARBON_AYAK_IZI_METODOLOJI.md`; akademik IMRAD taslağı için `MAKALE_IMRAD_TASLAK.md`.

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
- `shared_preferences` - Dil tercihi vb. kalıcı küçük ayarlar (`LanguageProvider`)
- `pdf` - PDF belge oluşturma (karbon raporu şablonu)
- `printing` - PDF önizleme, yazdırma ve paylaşım (mobil/masaüstü/web)

### IoT ve Ağ
- `web_socket_channel` - WebSocket desteği (Shelly Plug S için)
- `connectivity_plus` - Ağ bağlantı durumu kontrolü

## Ekranlar

- **Splash Screen** - Açılış / giriş akışı
- **Login Screen** - Kullanıcı girişi
- **Register Screen** - Yeni kullanıcı/işletme kaydı
- **Home Screen** - Ana sayfa (dashboard, hava durumu, karbon yoğunluğu)
- **Reports Screen** - Raporlar ve grafikler (ESP / manuel / Shelly kaynakları); **haftalık ve aylık PDF** dışa aktarma; **PDF rapor dili** (TR / EN)
- **Goals Screen** - Hedef belirleme, yeşil puan, rozetler ve davranış puanları; **Gelecek Ay Beklentisi** kartı (tahmini ay sonu emisyonu, hedef ve dünya ortalaması ile karşılaştırma)
- **Settings Screen** - Ayarlar (tema, dil, font boyutu)
- **Profile Settings Screen** - Profil ayarları ve işletme bilgileri

## Servisler ve Entegrasyonlar

### API Servisleri
- **ApiService** - ESP8266 ve Shelly Plug S entegrasyonu
- **WeatherService** - Hava durumu ve hava kalitesi (Open-Meteo API - ücretsiz, API key gerektirmez)
- **GlobalCarbonService** - Dünya geneli karbon trend verileri (Our World in Data)
- **ShellyService** - Shelly Plug S HTTP API ve WebSocket desteği

### Veritabanı Servisleri
- **FirebaseRealtimeService** - Firebase Realtime Database işlemleri
- **FirebaseAuthService** - Kullanıcı kimlik doğrulama
- **DatabaseService** - Uygulama içi hafif özet (ör. son okumalar, hedef eşikleri; bellek içi `Map` — kalıcı depolama değildir)
- **PostgresService** - İsteğe bağlı kurumsal/arka uç verisi (HTTP API üzerinden; varsayılan `localhost:3000/api`)

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

#### 2. Yakıt / Doğal Gaz

Uygulama iki durumu ayırır (`fuelIsNaturalGasM3` bayrağı ile):

**Doğal gaz (ölçüm: m³)** — ESP, fatura OCR veya “Gaz (m³)” alanları:
```
CO₂e (kg) = Doğalgaz (m³) × 2.02 kg CO₂e/m³
```

**Sıvı motor yakıtı (ölçüm: litre)** — manuel formdaki “Yakıt (litre)” ve araç tüketimi:
```
CO₂e (kg) = Yakıt (Litre) × 2.31 kg CO₂e/Litre
```

- **2.02 kg/m³**: Doğal gaz yanması için tipik bantla uyumlu örnek sabit (kaynak: envanter / IPCC tipi faktörler; ayrıntı için `KARBON_AYAK_IZI_METODOLOJI.md`).
- **2.31 kg/L**: Benzin–dizel tipi sıvı yakıt için yaygın kullanılan sipariş büyüklüğünde ortalama faktör (IPCC mobil kaynak literatürü).

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

### Grafikte Gösterilen Değerler

Grafikte gösterilen ülke değerleri şu şekilde hesaplanır:

1. **Veri Kaynağı**: Our World in Data'dan yıllık kişi başı CO₂ emisyon verileri (ton CO₂e/yıl)
2. **Dönüştürme**: Yıllık değerler günlük değerlere çevrilir:
   ```
   Günlük Emisyon (kg CO₂e/gün) = (Yıllık Emisyon (ton/yıl) × 1000) / 365
   ```
3. **Son 7 Yıl**: Her ülke için son 7 yılın verileri kullanılarak trend oluşturulur
4. **Grafikte Gösterim**: 
   - Her ülke için son 7 günün değerleri grafikte çizgi olarak gösterilir
   - Grafikteki değerler kişi başı günlük emisyon değerleridir (kg CO₂e/gün)
   - Kullanıcı verileri ile karşılaştırılabilir hale getirilir

#### Örnek Değerler (Kişi Başı Günlük Ortalama)

Grafikte gösterilen değerler, Our World in Data'dan çekilen gerçek verilere dayanır:

- **Türkiye**: ~4.2 kg CO₂e/gün (yıllık ~1.5 ton CO₂e)
- **ABD**: ~15.5 kg CO₂e/gün (yıllık ~5.7 ton CO₂e)
- **Çin**: ~7.4 kg CO₂e/gün (yıllık ~2.7 ton CO₂e)
- **Almanya**: ~8.9 kg CO₂e/gün (yıllık ~3.2 ton CO₂e)
- **Fransa**: ~8.0 kg CO₂e/gün (yıllık ~2.9 ton CO₂e)
- **İngiltere**: ~7.8 kg CO₂e/gün (yıllık ~2.8 ton CO₂e)

**Not**: Grafikte görünen değerler, kullanıcı verileriyle karşılaştırılabilir olması için ölçeklendirilmiş olabilir. Gerçek değerler yukarıdaki aralıklarda olmalıdır.

#### Veri Hesaplama Detayları

```dart
// Örnek: Türkiye verisi çekme
final trend = await globalCarbonService.getCountryDailyTrend('TUR');
// Dönen veri: [4.1, 4.2, 4.3, 4.2, 4.1, 4.0, 4.2] (kg CO₂e/gün)
// Bu değerler son 7 yılın günlük ortalamalarıdır
```

**Veri İşleme Adımları**:
1. Our World in Data API'sinden ülke verileri çekilir
2. `co2_per_capita` (kişi başı yıllık emisyon) değeri alınır
3. Yıllık değer günlük değere çevrilir: `(ton × 1000) / 365 = kg/gün`
4. Son 7 yılın verileri bir liste olarak döndürülür
5. Bu liste grafikte çizgi olarak gösterilir

### Veri Doğruluğu ve Güncellik

- **Our World in Data** verileri, dünya genelinde kabul görmüş ve güvenilir kaynaklardan toplanmaktadır
- Veriler düzenli olarak güncellenmektedir
- Yıllık veriler, en son mevcut yıl için sağlanmaktadır
- Kişi başı değerler, ülke nüfus verileri ile hesaplanmaktadır
- **Veri Formatı**: JSON (açık kaynak, ücretsiz)
- **API Key Gereksinimi**: Yok
- **Güncelleme Sıklığı**: Yıllık (en son yılın verileri kullanılır)

## Hava Durumu Entegrasyonu

### Veri Kaynağı: Open-Meteo API

Uygulama, hava durumu verilerini **Open-Meteo API** kullanarak çekmektedir. Bu API tamamen ücretsizdir ve API key gerektirmez.

#### API Özellikleri

- ✅ **Tamamen Ücretsiz**: API key gerektirmez, kayıt gerektirmez
- ✅ **Sınırsız Çağrı**: Ticari olmayan kullanım için sınırsız API çağrısı
- ✅ **Gerçek Zamanlı Veri**: Güncel hava durumu ve tahmin verileri
- ✅ **Türkiye Desteği**: Türkiye'deki tüm şehirler için veri mevcut
- ✅ **Hava Kalitesi**: AQI (Air Quality Index) verileri dahil

#### Kullanılan API Endpoint'leri

1. **Geocoding API** - Şehir adından koordinat bulma:
   ```
   https://geocoding-api.open-meteo.com/v1/search?name={şehir_adı}&count=1&language=tr
   ```

2. **Weather Forecast API** - Hava durumu ve tahmin:
   ```
   https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m
   ```

3. **Air Quality API** - Hava kalitesi (AQI):
   ```
   https://air-quality-api.open-meteo.com/v1/air-quality?latitude={lat}&longitude={lon}&current=us_aqi,pm10,pm2_5
   ```

#### Nasıl Çalışır?

1. **Şehir Adından Koordinat Bulma**:
   - Kullanıcı şehir adı girer (örn: "Sakarya,TR" veya "Istanbul,TR")
   - Open-Meteo Geocoding API şehir adını koordinatlara (enlem/boylam) çevirir
   - Türkçe dil desteği ile şehir adları doğru şekilde bulunur

2. **Hava Durumu Verilerini Çekme**:
   - Bulunan koordinatlar kullanılarak gerçek zamanlı hava durumu verileri alınır:
     - Sıcaklık (°C)
     - Nem oranı (%)
     - Hava durumu kodu (WMO Weather interpretation codes)
     - Rüzgar hızı (m/s)

3. **Hava Durumu Tahmini**:
   - 5 günlük hava durumu tahmini çekilir
   - Günlük maksimum ve minimum sıcaklık değerleri alınır
   - Ortalama sıcaklık hesaplanır

4. **Hava Kalitesi (AQI)**:
   - US AQI (Air Quality Index) değeri alınır
   - PM10 ve PM2.5 değerleri çekilir
   - AQI değeri metin olarak çevrilir (İyi, Orta, Sağlıksız vb.)

5. **Veri Dönüştürme**:
   - WMO weather code'ları Türkçe açıklamalara çevrilir
   - Hava durumu koşulları Türkçe olarak gösterilir (Açık, Bulutlu, Yağmurlu vb.)
   - Icon kodları OpenWeatherMap formatına uygun olarak eşleştirilir

#### Veri İşleme Süreci

```dart
// Örnek kullanım
final weatherService = WeatherService();

// 1. Gerçek zamanlı hava durumu
final weather = await weatherService.getWeatherData('Sakarya,TR');
// Dönen veri: {success: true, city: "Sakarya", temperature: 24.5, condition: "Açık", ...}

// 2. 5 günlük tahmin
final forecast = await weatherService.getWeatherForecast('Sakarya,TR');
// Dönen veri: List<Map> - Her gün için sıcaklık, koşul, açıklama

// 3. Hava kalitesi
final aqi = await weatherService.getAirQuality('Sakarya', 'Sakarya', 'Turkey');
// Dönen veri: {success: true, aqi: 78, aqiText: "Orta", pm10: 45, pm2_5: 25}
```

#### Hata Yönetimi

- **Şehir Bulunamazsa**: Placeholder (örnek) veri döndürülür
- **API Hatası**: Placeholder veri kullanılır, uygulama çalışmaya devam eder
- **İnternet Bağlantısı Yok**: Placeholder veri gösterilir
- **Timeout**: 10 saniye timeout süresi, aşılırsa placeholder veri döndürülür

#### Placeholder Veriler

API'den veri çekilemediğinde kullanılan örnek veriler:
- Sıcaklık: 24°C
- Koşul: "Açık"
- Nem: %60
- Rüzgar: 10 m/s
- AQI: 78 (Orta)

#### WMO Weather Codes

Open-Meteo API, WMO (World Meteorological Organization) weather interpretation codes kullanır:
- **0**: Açık gökyüzü
- **1-3**: Az bulutlu / Kısmen bulutlu / Kapalı
- **45-48**: Sisli / Donlu sis
- **51-67**: Çiseleyen yağmur / Yağmur / Donlu yağmur
- **71-77**: Kar / Kar taneleri
- **80-86**: Sağanak yağmur / Kar sağanağı
- **95-99**: Fırtına / Dolu ile fırtına

Bu kodlar otomatik olarak Türkçe açıklamalara çevrilir.

#### Kullanım Örneği

Uygulama içinde hava durumu verileri şu şekilde kullanılır:

```dart
// HomeScreen'de hava durumu yükleme
Future<void> _loadWeatherData() async {
  final weather = await _weatherService.getWeatherData('Sakarya,TR');
  final forecast = await _weatherService.getWeatherForecast('Sakarya,TR');
  final aqi = await _weatherService.getAirQuality('Sakarya', 'Sakarya', 'Turkey');
  
  setState(() {
    _currentWeather = weather;
    _weatherForecast = forecast;
    _airQuality = aqi;
  });
}
```

#### Veri Doğruluğu

- **Open-Meteo API** dünya genelinde kullanılan güvenilir bir hava durumu API'sidir
- Veriler gerçek zamanlı olarak güncellenir
- WMO standartlarına uygun weather code'ları kullanılır
- Türkiye için tüm şehirler desteklenir
- Hava kalitesi verileri US EPA standartlarına göre hesaplanır

## Gerçek Veri Entegrasyonu

### Karbon Emisyon Ortalamaları

Uygulama, ekranda gösterilen **Ulusal Ortalama** ve **Küresel Ortalama** değerlerini gerçek verilerden çekmektedir. Bu veriler **Our World in Data (OWID)** platformundan alınmaktadır.

#### Veri Kaynakları

1. **Küresel Ortalama (Global Average)**:
   - **Kaynak**: Our World in Data - Global Carbon Project
   - **Veri**: Kişi başı günlük CO₂ emisyonu (kg CO₂e/gün)
   - **Ortalama Değer**: ~4.1-4.5 kg/gün (yıllık ~1.5-1.6 ton CO₂e)
   - **Güncelleme**: En son yılın verileri kullanılır
   - **API Endpoint**: `https://raw.githubusercontent.com/owid/co2-data/master/owid-co2-data.json`

2. **Ulusal Ortalama (Türkiye)**:
   - **Kaynak**: Our World in Data - World Bank verileri
   - **Veri**: Türkiye kişi başı günlük CO₂ emisyonu (kg CO₂e/gün)
   - **Ortalama Değer**: ~6.8 kg/gün (yıllık ~2.5 ton CO₂e)
   - **Güncelleme**: En son yılın verileri kullanılır

#### Nasıl Çalışır?

1. **Uygulama Başlangıcı**:
   - `GlobalCarbonService.getGlobalAveragePerPerson()` fonksiyonu çağrılır
   - Our World in Data API'sinden dünya geneli veriler çekilir
   - En son yılın `co2_per_capita` değeri alınır
   - Yıllık değer günlük değere çevrilir: `(ton/yıl × 1000) / 365 = kg/gün`

2. **Türkiye Ortalaması**:
   - `CarbonDataService.getTurkeyAverage()` fonksiyonu çağrılır
   - Türkiye için güncel ortalama değer döndürülür
   - Veri kaynağı: Our World in Data ve World Bank istatistikleri

3. **Hata Yönetimi**:
   - API'den veri çekilemezse, güvenilir sabit değerler kullanılır:
     - Küresel Ortalama: 4.1 kg/gün
     - Türkiye Ortalaması: 6.8 kg/gün
   - Bu değerler gerçek verilere dayalı referans değerlerdir

#### Veri Doğruluğu

- **Our World in Data** dünya genelinde kabul görmüş ve güvenilir bir veri kaynağıdır
- Veriler Global Carbon Project, World Bank ve diğer resmi kaynaklardan toplanmaktadır
- Yıllık veriler düzenli olarak güncellenmektedir
- Kişi başı değerler, ülke nüfus verileri ile hesaplanmaktadır
- Tüm veriler açık kaynak ve ücretsizdir

#### Ekranda Gösterilen Veriler

| Veri | Durum | Kaynak | Açıklama |
|------|-------|--------|----------|
| **Sıcaklık** | ✅ Gerçek | Open-Meteo API | Gerçek zamanlı hava durumu |
| **Hava Kalitesi (AQI)** | ✅ Gerçek | Open-Meteo Air Quality API | Gerçek zamanlı hava kalitesi |
| **Karbon Yoğunluğu** | ⚠️ Ortalama | Türkiye ortalaması | 420 gCO₂/kWh (Türkiye elektrik üretim karışımı ortalaması) |
| **Ulusal Ortalama** | ✅ Gerçek | Our World in Data | Türkiye kişi başı günlük emisyon ortalaması |
| **Küresel Ortalama** | ✅ Gerçek | Our World in Data | Dünya kişi başı günlük emisyon ortalaması |

**Not**: Karbon yoğunluğu gerçek zamanlı değildir, ancak Türkiye'nin elektrik üretim karışımına dayalı gerçek bir ortalama değerdir. Gerçek zamanlı karbon yoğunluğu için ücretli API'ler (ör. Electricity Maps) gereklidir.

## Önemli Notlar

### Yapılandırma
- **PostgreSQL bağlantısı opsiyoneldir** (HTTP API üzerinden)
- **Hava durumu API'si tamamen ücretsizdir** - Open-Meteo API kullanılır, API key gerektirmez
- **ESP8266 ve Shelly Plug S opsiyoneldir** - Manuel veri girişi ile de çalışır
- **Firebase Realtime Database** kullanılmaktadır (gerçek zamanlı veri senkronizasyonu için)

### Platform Desteği
- ✅ Web (Chrome, Firefox, Safari vb.)
- ✅ Android
- ✅ iOS
- ⚠️ Windows / macOS masaüstü: Flutter bu hedefleri üretebilir; bu depoda öncelik mobil ve web üzerindedir, masaüstü için ek test gerekir.

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

### Hava Durumu API Hataları
- Open-Meteo API tamamen ücretsizdir ve API key gerektirmez
- İnternet bağlantısı olmadan placeholder veri kullanılır
- Şehir adı bulunamazsa placeholder veri döndürülür

## Katkıda Bulunma

Bu proje eğitim amaçlı geliştirilmiştir. Katkılarınızı bekliyoruz!

## Lisans

Bu proje eğitim amaçlı geliştirilmiştir.
