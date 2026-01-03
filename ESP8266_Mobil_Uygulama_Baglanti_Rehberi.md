# ESP8266 - Mobil Uygulama Bağlantı Rehberi

## 📱 Adım Adım Bağlantı Kurulumu

### ADIM 1: ESP8266 IP Adresini Bulma

1. **ESP8266'yı çalıştırın** (kod yüklü, sensörler bağlı)

2. **Serial Monitor'ü açın** (Arduino IDE'de, 115200 baud)

3. **IP adresini not edin:**
   ```
   WiFi bağlantısı başarılı!
   IP Adresi: 192.168.1.100  ← BU ADRESİ NOT EDİN
   ```

4. **Alternatif: Router'dan kontrol edin**
   - Router yönetim paneline girin (genelde 192.168.1.1 veya 192.168.0.1)
   - Bağlı cihazlar listesinde ESP8266'yı bulun
   - IP adresini not edin

---

### ADIM 2: Flutter Uygulamasında IP Adresini Güncelleme

1. **Projeyi açın:**
   - `lib/services/api_service.dart` dosyasını açın

2. **IP adresini güncelleyin:**
   ```dart
   // ÖNCE (9. satır):
   static const String espBaseUrl = 'http://192.168.1.100'; // ESP IP adresi
   
   // SONRA (Serial Monitor'den aldığınız IP ile değiştirin):
   static const String espBaseUrl = 'http://192.168.1.105'; // ESP IP adresi
   ```

3. **Dosyayı kaydedin** (`Ctrl + S`)

---

### ADIM 3: Aynı WiFi Ağında Olduğunuzdan Emin Olun

**ÖNEMLİ:** Mobil cihazınız ve ESP8266 **aynı WiFi ağında** olmalı!

- ✅ ESP8266: "Ev_WiFi" ağına bağlı
- ✅ Mobil cihaz: "Ev_WiFi" ağına bağlı
- ❌ ESP8266: "Ev_WiFi", Mobil: "Mobil_Veri" → **ÇALIŞMAZ!**

**Test:**
- Mobil cihazınızın tarayıcısını açın
- `http://ESP_IP_ADRESI/api/status` adresine gidin
- JSON yanıt görüyorsanız bağlantı çalışıyor demektir

---

### ADIM 4: Uygulamayı Çalıştırma

1. **Flutter uygulamasını çalıştırın:**
   ```bash
   flutter run
   ```

2. **Veya Android Studio/VS Code'dan:**
   - Run butonuna tıklayın
   - Mobil cihazınızda veya emülatörde uygulama açılacak

---

### ADIM 5: ESP8266 Verilerini Kullanma

Uygulamanızda ESP8266'dan veri çekmek için `ApiService` sınıfını kullanın:

```dart
import 'package:carbon_footprint_calculation_app/services/api_service.dart';

// API servisi oluştur
final apiService = ApiService();

// ESP8266'dan anlık verileri çek
final consumptionData = await apiService.getLiveConsumptionData();

// Verileri kullan
print('Elektrik: ${consumptionData.electricityKwh} kWh');
print('Su: ${consumptionData.waterCubicMeters} m³');
```

---

## 🔧 Uygulamaya ESP8266 Bağlantı Butonu Ekleme

Eğer uygulamanızda ESP8266 bağlantısı için bir buton yoksa, ekleyebilirsiniz:

### Örnek: Home Screen'e Buton Ekleme

```dart
// lib/screens/home_screen.dart dosyasına ekleyin

import 'package:carbon_footprint_calculation_app/services/api_service.dart';

// Buton widget'ı
ElevatedButton(
  onPressed: () async {
    final apiService = ApiService();
    
    // ESP8266 durumunu kontrol et
    final status = await apiService.getEspStatus();
    
    if (status['connected'] == true) {
      // Bağlantı başarılı - verileri çek
      final data = await apiService.getLiveConsumptionData();
      
      // Verileri göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ESP8266 Bağlı!\n'
            'Elektrik: ${data.electricityKwh.toStringAsFixed(2)} kWh\n'
            'Su: ${data.waterCubicMeters.toStringAsFixed(2)} m³',
          ),
        ),
      );
    } else {
      // Bağlantı başarısız
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ESP8266 bağlantısı başarısız!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  },
  child: Text('ESP8266 Verilerini Çek'),
)
```

---

## 🧪 Test Etme

### 1. Tarayıcıdan Test

Mobil cihazınızın tarayıcısında:
```
http://192.168.1.100/api/status
```

**Beklenen yanıt:**
```json
{
  "uptime": 120,
  "wifi": {
    "ssid": "Ev_WiFi",
    "rssi": -45,
    "ip": "192.168.1.100"
  },
  "sensors": {
    "mq135": "connected",
    "yf_s201": "connected"
  }
}
```

### 2. Tüketim Verilerini Test

```
http://192.168.1.100/api/consumption
```

**Beklenen yanıt:**
```json
{
  "electricity": 0.5,
  "water": 0.25,
  "fuel": 0.0,
  "waste": 0.0,
  "co2_ppm": 400.0,
  "water_flow_liters": 250.0,
  "flow_rate_lpm": 0.0,
  "timestamp": 1234567890
}
```

### 3. Flutter Uygulamasından Test

```dart
final apiService = ApiService();

// Durum kontrolü
final status = await apiService.getEspStatus();
print('Bağlantı: ${status['connected']}');

// Veri çekme
final data = await apiService.getLiveConsumptionData();
print('Elektrik: ${data.electricityKwh} kWh');
print('Su: ${data.waterCubicMeters} m³');
```

---

## ⚠️ Sorun Giderme

### Problem: "ESP modülüne bağlanılamadı"

**Çözümler:**
1. ✅ ESP8266 ve mobil cihaz aynı WiFi ağında mı?
2. ✅ IP adresi doğru mu? (`api_service.dart` dosyasını kontrol edin)
3. ✅ ESP8266 çalışıyor mu? (Serial Monitor'den kontrol edin)
4. ✅ Router firewall ESP8266'ya erişimi engelliyor mu?

### Problem: "Connection timeout"

**Çözümler:**
1. ✅ WiFi sinyal gücünü kontrol edin
2. ✅ ESP8266'ya yakın olun
3. ✅ Timeout süresini artırın (kodda 10 saniye)

### Problem: "404 Not Found"

**Çözümler:**
1. ✅ IP adresi doğru mu?
2. ✅ ESP8266 web server çalışıyor mu?
3. ✅ Endpoint adresi doğru mu? (`/api/consumption`, `/api/status`)

### Problem: Veriler 0 geliyor

**Çözümler:**
1. ✅ Sensörler bağlı mı?
2. ✅ MQ-135 ısınması için 20-30 dakika bekleyin
3. ✅ Su akışı var mı? (YF-S201 test edin)
4. ✅ Serial Monitor'de sensör değerlerini kontrol edin

---

## 📊 Veri Akışı

```
ESP8266 (Sensörler)
    ↓
WiFi (HTTP API)
    ↓
Flutter Uygulaması (ApiService)
    ↓
ConsumptionEntry Model
    ↓
Hesaplama & Gösterim
```

---

## 🔄 Otomatik Veri Çekme

Eğer uygulamanızda otomatik veri çekme istiyorsanız:

```dart
// Timer ile periyodik veri çekme
Timer.periodic(Duration(seconds: 30), (timer) async {
  final apiService = ApiService();
  final data = await apiService.getLiveConsumptionData();
  
  // Verileri güncelle
  setState(() {
    _currentConsumption = data;
  });
});
```

---

## ✅ Kontrol Listesi

- [ ] ESP8266 kod yüklendi
- [ ] Sensörler bağlandı
- [ ] ESP8266 WiFi'ye bağlandı
- [ ] IP adresi not edildi
- [ ] `api_service.dart` dosyasında IP güncellendi
- [ ] Mobil cihaz aynı WiFi ağında
- [ ] Tarayıcıdan API test edildi
- [ ] Flutter uygulaması çalıştırıldı
- [ ] ESP8266 verileri çekildi

---

## 🎉 Başarı!

Artık ESP8266'dan gelen anlık sensör verilerini mobil uygulamanızda kullanabilirsiniz!

**Sonraki Adımlar:**
- Verileri otomatik olarak periyodik çekme
- Verileri veritabanına kaydetme
- Grafiklerde gösterme
- Bildirimler ekleme

**Başarılar! 🚀**

