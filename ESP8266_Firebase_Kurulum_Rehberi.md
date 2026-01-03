# ESP8266 Firebase Realtime Database Kurulum Rehberi

## 📋 Genel Bakış

ESP8266 artık **direkt Firebase Realtime Database'e** veri gönderiyor. Bu sayede mobil uygulamanız Firebase'den **real-time stream** ile anlık verileri alabilir.

## 🔄 Veri Akışı

```
ESP8266 (Sensörler)
    ↓ Her 5 saniyede bir
Firebase Realtime Database (REST API)
    ↓ Real-time Stream
Flutter Mobil Uygulama
    ↓ StreamBuilder ile anlık güncelleme
Kullanıcı Arayüzü
```

## ⚙️ Firebase Güvenlik Kuralları Ayarlama

### Adım 1: Firebase Console'a Giriş

1. [Firebase Console](https://console.firebase.google.com/) adresine gidin
2. Projenizi seçin: **carbon-footprint-app-8111a**
3. Sol menüden **Realtime Database** seçin

### Adım 2: Güvenlik Kurallarını Ayarlayın

**Test Modu (Geliştirme için - Hızlı Başlangıç):**

```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

⚠️ **UYARI:** Test modu herkese okuma/yazma izni verir. Sadece geliştirme için kullanın!

**Production Modu (Güvenli - Önerilen):**

```json
{
  "rules": {
    "esp8266_data": {
      ".read": "auth != null",
      ".write": "auth != null",
      "$deviceId": {
        ".read": true,
        ".write": true
      }
    },
    "esp8266_status": {
      ".read": "auth != null",
      ".write": "auth != null",
      "$deviceId": {
        ".read": true,
        ".write": true
      }
    }
  }
}
```

**Herkes İçin Açık (Sadece ESP8266 verileri için):**

```json
{
  "rules": {
    "esp8266_data": {
      ".read": true,
      ".write": true
    },
    "esp8266_status": {
      ".read": true,
      ".write": true
    },
    "users": {
      ".read": "auth != null",
      ".write": "auth != null"
    }
  }
}
```

### Adım 3: Kuralları Kaydedin

1. Firebase Console'da **Rules** sekmesine gidin
2. Yukarıdaki kurallardan birini seçin ve yapıştırın
3. **Publish** butonuna tıklayın

---

## 🔧 ESP8266 Kod Yapılandırması

### Adım 1: WiFi Ayarları

`esp8266_carbon_sensor.ino` dosyasında WiFi bilgilerinizi girin:

```cpp
const char* ssid = "WIFI_SSID_BURAYA";        // WiFi ağ adınızı girin
const char* password = "WIFI_SIFRE_BURAYA";   // WiFi şifrenizi girin
```

### Adım 2: Firebase Ayarları (Opsiyonel)

Eğer Firebase güvenlik kurallarında authentication kullanıyorsanız:

```cpp
const char* firebaseAuth = "YOUR_FIREBASE_AUTH_TOKEN";  // Firebase Auth token
```

**Not:** Test modunda veya herkese açık kurallarda `firebaseAuth` boş bırakılabilir.

### Adım 3: Cihaz ID'si (Opsiyonel)

Birden fazla ESP8266 cihazınız varsa, her birine farklı ID verin:

```cpp
const char* firebasePath = "/esp8266_data/esp8266_001";  // Cihaz ID'si
```

---

## 📱 Flutter Uygulamasında Kullanım

### Real-time Veri Dinleme

Flutter uygulamanızda zaten `ApiService.listenToFirebaseData()` metodu mevcut. Kullanımı:

```dart
import 'package:carbon_footprint_calculation_app/services/api_service.dart';

final apiService = ApiService();

// StreamBuilder ile anlık veri dinleme
StreamBuilder<ConsumptionEntry?>(
  stream: apiService.listenToFirebaseData(),
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data != null) {
      final data = snapshot.data!;
      return Text('Elektrik: ${data.electricityKwh} kWh');
    }
    return CircularProgressIndicator();
  },
)
```

### Örnek Widget: Anlık Veri Gösterimi

```dart
class RealtimeDataWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();
    
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
          return Text('Veri bekleniyor...');
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

---

## 🧪 Test Etme

### 1. ESP8266 Serial Monitor Kontrolü

Arduino IDE'de Serial Monitor'ü açın (115200 baud). Şu mesajları görmelisiniz:

```
=== ESP8266 Carbon Footprint Sensor ===
WiFi'ye bağlanılıyor: YOUR_WIFI_SSID
WiFi bağlantısı başarılı!
IP Adresi: 192.168.1.100
HTTP Server başlatıldı!
Sensörler ısınması için 20 saniye bekleniyor...
Sistem hazır!
=== Sensör Değerleri ===
CO2 (ppm): 400.00
Elektrik (kWh): 0.20
Su Akışı (L): 0.00
Firebase Durumu: Başarılı
========================
```

### 2. Firebase Console'dan Kontrol

1. Firebase Console > Realtime Database
2. `esp8266_data` > `esp8266_001` > `latest` yoluna gidin
3. Verilerin anlık olarak güncellendiğini görmelisiniz

### 3. Flutter Uygulamasından Test

```dart
// Test kodu
final apiService = ApiService();

// Stream'i dinle
apiService.listenToFirebaseData().listen((data) {
  if (data != null) {
    print('Yeni veri geldi!');
    print('Elektrik: ${data.electricityKwh} kWh');
    print('Su: ${data.waterCubicMeters} m³');
  }
});
```

---

## ⚠️ Sorun Giderme

### Problem: "Firebase gönderim hatası: -1"

**Çözümler:**
1. ✅ WiFi bağlantısını kontrol edin
2. ✅ Firebase güvenlik kurallarını kontrol edin (test modunda olmalı)
3. ✅ Firebase Host adresini kontrol edin
4. ✅ Serial Monitor'de hata mesajlarını kontrol edin

### Problem: "WiFi bağlantısı yok"

**Çözümler:**
1. ✅ SSID ve şifreyi kontrol edin
2. ✅ WiFi sinyal gücünü kontrol edin
3. ✅ Router ayarlarını kontrol edin

### Problem: Veriler Firebase'e gitmiyor

**Çözümler:**
1. ✅ Serial Monitor'de "Firebase Durumu: Başarılı" mesajını kontrol edin
2. ✅ Firebase Console'da verilerin gelip gelmediğini kontrol edin
3. ✅ Firebase güvenlik kurallarını kontrol edin
4. ✅ ESP8266'nın internet bağlantısını kontrol edin

### Problem: Flutter uygulaması veri almıyor

**Çözümler:**
1. ✅ Firebase'in başlatıldığından emin olun (`main.dart`)
2. ✅ `listenToFirebaseData()` stream'inin çalıştığından emin olun
3. ✅ Firebase Console'da verilerin geldiğini kontrol edin
4. ✅ Device ID'sinin doğru olduğundan emin olun (`esp8266_001`)

---

## 📊 Veri Yapısı

### Firebase'de Veri Yapısı

```
esp8266_data/
  └── esp8266_001/
      ├── latest/
      │   ├── electricity: 0.5
      │   ├── water: 0.25
      │   ├── fuel: 0.0
      │   ├── waste: 0.0
      │   ├── co2_ppm: 400.0
      │   ├── water_flow_liters: 250.0
      │   ├── flow_rate_lpm: 0.0
      │   ├── timestamp: 1234567890
      │   └── created_at: ""
      └── history/
          └── 2024-01-01/
              └── 1234567890/
                  └── (latest ile aynı yapı)

esp8266_status/
  └── esp8266_001/
      ├── connected: true
      ├── uptime: 120
      ├── wifi/
      │   ├── ssid: "Ev_WiFi"
      │   ├── rssi: -45
      │   └── ip: "192.168.1.100"
      ├── sensors/
      │   ├── mq135: "connected"
      │   └── yf_s201: "connected"
      └── last_update: 1234567890
```

---

## 🎯 Özellikler

✅ **Anlık Veri Akışı:** Her 5 saniyede bir Firebase'e veri gönderilir  
✅ **Real-time Stream:** Flutter uygulaması anlık güncellemeleri alır  
✅ **Geçmiş Veri:** Tarih bazlı geçmiş veriler saklanır  
✅ **Durum Takibi:** ESP8266 durumu Firebase'de takip edilir  
✅ **Geriye Dönük Uyumluluk:** HTTP API endpoint'leri hala çalışıyor  

---

## 🚀 Sonraki Adımlar

1. ✅ Firebase güvenlik kurallarını production için ayarlayın
2. ✅ Birden fazla ESP8266 cihazı için farklı device ID'leri kullanın
3. ✅ Flutter uygulamasında real-time widget'lar ekleyin
4. ✅ Veri görselleştirme (grafikler) ekleyin
5. ✅ Bildirimler ekleyin (eşik değerler aşıldığında)

---

## ✅ Kontrol Listesi

- [ ] Firebase Realtime Database oluşturuldu
- [ ] Firebase güvenlik kuralları ayarlandı
- [ ] ESP8266 WiFi ayarları yapıldı
- [ ] ESP8266 kodu yüklendi
- [ ] Serial Monitor'de "Firebase Durumu: Başarılı" görünüyor
- [ ] Firebase Console'da veriler görünüyor
- [ ] Flutter uygulaması Firebase'den veri alıyor
- [ ] Real-time widget'lar çalışıyor

---

**Başarılar! 🎉**

