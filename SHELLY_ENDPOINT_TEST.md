# Shelly Plug S Endpoint Test Rehberi

## ⚠️ ÖNEMLİ: Chrome'da CORS Sorunu

Flutter web uygulaması Chrome'da çalışırken, Shelly cihazına yapılan HTTP istekleri **CORS (Cross-Origin Resource Sharing)** politikası tarafından engellenebilir. Bu durumda şu hatayı görürsünüz:

```
Access to fetch at 'http://192.168.137.57/...' from origin 'http://localhost:49746' 
has been blocked by CORS policy: No 'Access-Control-Allow-Origin' header is present 
on the requested resource.
```

### ✅ Çözüm Seçenekleri:

#### 1. Chrome'u CORS'u Devre Dışı Bırakarak Çalıştırma (Geliştirme İçin)

```powershell
flutter run -d chrome --web-browser-flag="--disable-web-security" --web-browser-flag="--user-data-dir=C:/temp/chrome_dev"
```

**Not:** Bu yöntem sadece geliştirme için kullanılmalıdır. Production'da güvenlik riski oluşturur.

#### 2. Emülatör Kullanma (ÖNERİLEN)

Android emülatörü kullanmak en güvenilir çözümdür:

1. Android Studio'da emülatörü başlatın
2. Emülatörü hotspot'a bağlayın
3. Flutter uygulamasını emülatörde çalıştırın:
   ```powershell
   flutter run
   ```

#### 3. Gerçek Cihaz Kullanma

Android/iOS fiziksel cihaz kullanmak da CORS sorununu çözer:
```powershell
flutter run
```

---

## 🔍 IP Adresi: 192.168.137.57

### Test Adımları

Tarayıcınızda aşağıdaki adresleri sırayla deneyin:

#### 1. `/rpc` (POST - Tarayıcıda test edilemez, uygulama içinde test edilir)
```
http://192.168.137.57/rpc
```
**Not:** Bu endpoint POST isteği gerektirir, tarayıcıda GET yaparsanız hata alırsınız.

#### 2. `/status` (GET)
```
http://192.168.137.57/status
```
**Beklenen:** JSON yanıt veya "Not Found"

#### 3. `/shelly` (GET)
```
http://192.168.137.57/shelly
```
**Beklenen:** Cihaz bilgileri (JSON)

#### 4. `/meter/0` (GET)
```
http://192.168.137.57/meter/0
```
**Beklenen:** Enerji ölçüm verileri (JSON)

#### 5. `/relay/0` (GET)
```
http://192.168.137.57/relay/0
```
**Beklenen:** Relay durumu (JSON)

#### 6. `/settings` (GET)
```
http://192.168.137.57/settings
```
**Beklenen:** Cihaz ayarları (JSON)

#### 7. Ana sayfa (GET)
```
http://192.168.137.57/
```
**Beklenen:** HTML sayfası veya JSON

---

## 🔧 Alternatif Test Yöntemleri

### PowerShell ile Test (Windows)

```powershell
# /status endpoint testi
Invoke-WebRequest -Uri "http://192.168.137.57/status" -Method GET

# /shelly endpoint testi
Invoke-WebRequest -Uri "http://192.168.137.57/shelly" -Method GET

# /meter/0 endpoint testi
Invoke-WebRequest -Uri "http://192.168.137.57/meter/0" -Method GET
```

### curl ile Test (Linux/Mac/Windows)

```bash
# /status endpoint testi
curl http://192.168.137.57/status

# /shelly endpoint testi
curl http://192.168.137.57/shelly

# /meter/0 endpoint testi
curl http://192.168.137.57/meter/0

# /rpc endpoint testi (POST)
curl -X POST http://192.168.137.57/rpc \
  -H "Content-Type: application/json" \
  -d '{"id":1,"method":"Shelly.GetStatus","params":{}}'
```

---

## 📋 Sorun Giderme

### "Not Found" Hatası Alıyorsanız:

1. **IP Adresini Doğrulayın:**
   - Shelly uygulamasından cihazın IP adresini kontrol edin
   - Router admin panelinden bağlı cihazları kontrol edin

2. **Ağ Bağlantısını Kontrol Edin:**
   - Cihaz ve bilgisayar aynı WiFi ağında mı?
   - Ping testi yapın: `ping 192.168.137.57`

3. **Cihaz Modelini Kontrol Edin:**
   - Shelly Plug S mi? (Farklı modeller farklı endpoint'ler kullanabilir)
   - Cihazın firmware versiyonu güncel mi?

4. **Firewall/Antivirus:**
   - Geçici olarak kapatıp deneyin
   - Windows Defender Firewall'dan izin verin

5. **Port Kontrolü:**
   - Shelly cihazları genellikle port 80 kullanır
   - Farklı bir port kullanıyor olabilir: `http://192.168.137.57:8080/status`

---

## ✅ Başarılı Yanıt Örnekleri

### `/status` Endpoint Yanıtı (Klasik Shelly):
```json
{
  "wifi_sta": {
    "connected": true,
    "ssid": "WiFi_Adi",
    "ip": "192.168.137.57",
    "rssi": -45
  },
  "cloud": {
    "enabled": false,
    "connected": false
  },
  "mqtt": {
    "connected": false
  },
  "time": "12:34",
  "unixtime": 1234567890,
  "serial": 12345,
  "has_update": false,
  "mac": "AA:BB:CC:DD:EE:FF",
  "relays": [
    {
      "ison": false,
      "has_timer": false,
      "timer_started": 0,
      "timer_duration": 0,
      "timer_remaining": 0,
      "overpower": false,
      "is_valid": true,
      "source": "http"
    }
  ],
  "meters": [
    {
      "power": 0.0,
      "overpower": 0.0,
      "is_valid": true,
      "timestamp": 1234567890,
      "counters": [0.0, 0.0, 0.0],
      "total": 0
    }
  ],
  "temperature": 25.5,
  "overtemperature": false,
  "tmp": {
    "tC": 25.5,
    "tF": 77.9
  },
  "update": {
    "status": "idle",
    "has_update": false,
    "new_version": "20221109-130540/v1.12.1-gad0d283",
    "old_version": "20221109-130540/v1.12.1-gad0d283"
  }
}
```

### `/rpc` Endpoint Yanıtı (Shelly Plus/Gen2):
```json
{
  "id": 1,
  "result": {
    "wifi": {
      "sta_ip": "192.168.137.57",
      "status": "got ip",
      "ssid": "WiFi_Adi",
      "rssi": -45
    },
    "cloud": {
      "enabled": false,
      "connected": false
    },
    "switch:0": {
      "id": 0,
      "source": "http",
      "output": false,
      "temperature": {
        "tC": 25.5,
        "tF": 77.9
      },
      "apower": 0.0,
      "voltage": 230.0,
      "current": 0.0,
      "aenergy": {
        "total": 0.0,
        "by_minute": [0.0, 0.0, 0.0],
        "minute_ts": 1234567890
      }
    }
  }
}
```

---

## 🎯 Hangi Endpoint Çalışıyorsa

Hangi endpoint çalışıyorsa, o endpoint'i kullanacak şekilde kodu güncelleyebiliriz. Lütfen hangi endpoint'in çalıştığını bildirin!

