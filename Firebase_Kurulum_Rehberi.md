# Firebase Realtime Database Kurulum Rehberi

Bu rehber, ESP8266 sensör verilerini Firebase Realtime Database'e real-time senkronize etmek için gerekli adımları içerir.

---

## 📋 İçindekiler

1. [Firebase Projesi Oluşturma](#1-firebase-projesi-oluşturma)
2. [Flutter'a Firebase Ekleme](#2-fluttera-firebase-ekleme)
3. [Firebase Realtime Database Kurulumu](#3-firebase-realtime-database-kurulumu)
4. [Kod Entegrasyonu](#4-kod-entegrasyonu)
5. [Kullanım Örnekleri](#5-kullanım-örnekleri)
6. [Güvenlik Kuralları](#6-güvenlik-kuralları)

---

## 1. Firebase Projesi Oluşturma

### Adım 1: Firebase Console'a Giriş

1. [Firebase Console](https://console.firebase.google.com/) adresine gidin
2. Google hesabınızla giriş yapın
3. **"Add project"** (Proje Ekle) butonuna tıklayın

### Adım 2: Proje Bilgilerini Girin

- **Project name**: `carbon-footprint-app` (veya istediğiniz isim)
- **Google Analytics**: İsteğe bağlı (önerilir)
- **Create project** butonuna tıklayın

### Adım 3: Projeyi Oluşturun

- Firebase projenizi oluşturmayı bekleyin (1-2 dakika)
- **Continue** butonuna tıklayın

---

## 2. Flutter'a Firebase Ekleme

### Adım 1: FlutterFire CLI Kurulumu

Terminal'de çalıştırın:

```bash
dart pub global activate flutterfire_cli
```

### Adım 2: Firebase Projesini Flutter'a Bağla

Proje klasörünüzde çalıştırın:

```bash
flutterfire configure
```

Bu komut:
- Firebase projenizi seçmenizi ister
- Platformları seçmenizi ister (Android, iOS, Web)
- Gerekli konfigürasyon dosyalarını oluşturur

**Not:** Eğer `flutterfire` komutu bulunamazsa:

```bash
# Windows PowerShell
$env:PATH += ";$env:USERPROFILE\.pub-cache\bin"
flutterfire configure

# Linux/Mac
export PATH="$PATH":"$HOME/.pub-cache/bin"
flutterfire configure
```

### Adım 3: Android Yapılandırması

`android/app/build.gradle.kts` dosyasında `minSdkVersion` kontrol edin:

```kotlin
android {
    defaultConfig {
        minSdkVersion 21  // Firebase için minimum 21 gerekli
    }
}
```

### Adım 4: iOS Yapılandırması (Sadece iOS için)

`ios/Runner/Info.plist` dosyasına Firebase eklenir (flutterfire configure otomatik yapar).

---

## 3. Firebase Realtime Database Kurulumu

### Adım 1: Realtime Database Oluştur

1. Firebase Console'da projenize gidin
2. Sol menüden **"Realtime Database"** seçin
3. **"Create Database"** butonuna tıklayın
4. **Location** seçin: `europe-west1` (Türkiye için en yakın)
5. **Start in test mode** seçin (güvenlik kurallarını sonra ayarlayacağız)
6. **Enable** butonuna tıklayın

### Adım 2: Database URL'ini Not Edin

Database oluşturulduktan sonra URL şu formatta olacak:
```
https://your-project-id-default-rtdb.europe-west1.firebasedatabase.app
```

Bu URL'yi not edin (kodda kullanılacak).

---

## 4. Kod Entegrasyonu

### Adım 1: main.dart'ı Güncelle

`lib/main.dart` dosyasını açın ve Firebase'i başlatın:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // flutterfire configure tarafından oluşturulur
import 'services/firebase_realtime_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Firebase Realtime Service'i başlat
  FirebaseRealtimeService.instance.initialize();

  // PostgreSQL bağlantısını başlat
  try {
    await PostgresService.instance.connect();
    print('PostgreSQL bağlantısı başarılı');
  } catch (e) {
    print('PostgreSQL bağlantı hatası: $e');
  }

  runApp(const CarbonFootprintApp());
}
```

### Adım 2: Paketleri Yükle

Terminal'de çalıştırın:

```bash
flutter pub get
```

### Adım 3: ESP8266 Verilerini Otomatik Senkronize Et

`ApiService` artık ESP8266'dan veri çektiğinde otomatik olarak Firebase'e kaydeder.

**Manuel senkronizasyon için:**

```dart
final apiService = ApiService();

// ESP8266'dan veri çek ve Firebase'e kaydet
final data = await apiService.getLiveConsumptionData(saveToFirebase: true);
```

---

## 5. Kullanım Örnekleri

### Örnek 1: Real-time Veri Dinleme (StreamBuilder)

```dart
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'models/consumption_entry.dart';

class RealtimeDataWidget extends StatelessWidget {
  final ApiService apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConsumptionEntry?>(
      stream: apiService.listenToFirebaseData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          return Text('Hata: ${snapshot.error}');
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return Text('Veri yok');
        }

        final data = snapshot.data!;
        return Column(
          children: [
            Text('Elektrik: ${data.electricityKwh.toStringAsFixed(2)} kWh'),
            Text('Su: ${data.waterCubicMeters.toStringAsFixed(2)} m³'),
            Text('Yakıt: ${data.fuelLiters.toStringAsFixed(2)} L'),
            Text('Atık: ${data.wasteKg.toStringAsFixed(2)} kg'),
          ],
        );
      },
    );
  }
}
```

### Örnek 2: ESP8266 Durumunu Dinleme

```dart
StreamBuilder<Map<String, dynamic>?>(
  stream: apiService.listenToFirebaseStatus(),
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data != null) {
      final status = snapshot.data!;
      return Column(
        children: [
          Text('Bağlı: ${status['connected']}'),
          Text('Uptime: ${status['uptime']} saniye'),
          Text('WiFi: ${status['wifi']?['ssid']}'),
        ],
      );
    }
    return Text('Durum bilgisi yok');
  },
)
```

### Örnek 3: Geçmiş Verileri Getirme

```dart
final apiService = ApiService();

// Son 7 günün verilerini getir
final startDate = DateTime.now().subtract(Duration(days: 7));
final endDate = DateTime.now();

final history = await apiService.getFirebaseHistory(
  startDate: startDate,
  endDate: endDate,
);

print('Toplam ${history.length} kayıt bulundu');
```

### Örnek 4: Periyodik Veri Çekme ve Firebase'e Kaydetme

```dart
import 'dart:async';

class Esp8266SyncService {
  final ApiService _apiService = ApiService();
  Timer? _timer;

  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    _timer = Timer.periodic(interval, (timer) async {
      try {
        // ESP8266'dan veri çek ve Firebase'e kaydet
        await _apiService.getLiveConsumptionData(saveToFirebase: true);
        
        // Durum bilgisini de güncelle
        await _apiService.getEspStatus(saveToFirebase: true);
        
        print('Veri senkronize edildi: ${DateTime.now()}');
      } catch (e) {
        print('Senkronizasyon hatası: $e');
      }
    });
  }

  void stopPeriodicSync() {
    _timer?.cancel();
    _timer = null;
  }
}
```

---

## 6. Güvenlik Kuralları

Firebase Console'da **Realtime Database > Rules** sekmesine gidin ve şu kuralları ekleyin:

```json
{
  "rules": {
    "esp8266_data": {
      "$deviceId": {
        ".read": "auth != null",  // Sadece giriş yapmış kullanıcılar okuyabilir
        ".write": "auth != null"  // Sadece giriş yapmış kullanıcılar yazabilir
      }
    },
    "esp8266_status": {
      "$deviceId": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    }
  }
}
```

**Not:** Test modunda tüm kullanıcılar okuyup yazabilir. Production için yukarıdaki kuralları kullanın.

### Alternatif: Public Read, Authenticated Write

Eğer veriler herkese açık olacaksa (sadece yazma korumalı):

```json
{
  "rules": {
    "esp8266_data": {
      "$deviceId": {
        ".read": true,           // Herkes okuyabilir
        ".write": "auth != null" // Sadece giriş yapmış kullanıcılar yazabilir
      }
    }
  }
}
```

---

## 🔧 Sorun Giderme

### Hata: "FirebaseApp not initialized"

**Çözüm:** `main.dart`'ta `Firebase.initializeApp()` çağrıldığından emin olun.

### Hata: "Permission denied"

**Çözüm:** Firebase Console'da Realtime Database Rules'ı kontrol edin.

### Hata: "PlatformException"

**Çözüm:** 
- `flutterfire configure` komutunu tekrar çalıştırın
- `flutter clean` ve `flutter pub get` yapın
- Uygulamayı yeniden başlatın

### Veriler Firebase'e kaydedilmiyor

**Kontrol Listesi:**
- ✅ Firebase.initializeApp() çağrıldı mı?
- ✅ FirebaseRealtimeService.instance.initialize() çağrıldı mı?
- ✅ `saveToFirebase: true` parametresi gönderildi mi?
- ✅ Firebase Console'da database oluşturuldu mu?
- ✅ Internet bağlantısı var mı?

---

## 📊 Firebase Console'da Veri Görüntüleme

1. Firebase Console'a gidin
2. **Realtime Database** sekmesine tıklayın
3. Verileriniz şu yapıda görünecek:

```
esp8266_data/
  └── esp8266_001/
      ├── latest/
      │   ├── electricity: 100.5
      │   ├── water: 50.2
      │   ├── fuel: 0.0
      │   ├── waste: 0.0
      │   └── timestamp: 1234567890
      └── history/
          └── 2025-01-15/
              └── 1234567890/
                  └── ...
```

---

## 🎯 Sonraki Adımlar

1. **Firebase Authentication** ekleyin (kullanıcı girişi için)
2. **Firebase Cloud Messaging** ekleyin (bildirimler için)
3. **Firebase Analytics** ekleyin (kullanım istatistikleri için)
4. **Firebase Storage** ekleyin (dosya saklama için)

---

## 📚 Kaynaklar

- [Firebase Realtime Database Dokümantasyonu](https://firebase.google.com/docs/database)
- [FlutterFire Dokümantasyonu](https://firebase.flutter.dev/)
- [Firebase Console](https://console.firebase.google.com/)

---

**Not:** Bu rehber, ESP8266 verilerini Firebase Realtime Database'e senkronize etmek için hazırlanmıştır. PostgreSQL backend'iniz ayrıca çalışmaya devam edecektir.

