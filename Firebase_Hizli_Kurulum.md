# Firebase Hızlı Kurulum Rehberi - ESP8266 için

## 🎯 Yapmanız Gerekenler (5 Dakika)

### ADIM 1: Firebase Console'a Giriş

1. Tarayıcınızda şu adrese gidin: https://console.firebase.google.com/
2. Projenizi seçin: **carbon-footprint-app-8111a**

### ADIM 2: Realtime Database Oluşturma

1. Sol menüden **⚡ Realtime Database** seçeneğine tıklayın
2. Eğer database yoksa:
   - **"Create Database"** butonuna tıklayın
   - **Location** seçin: `europe-west1` (Türkiye için en yakın)
   - **"Start in test mode"** seçeneğini işaretleyin
   - **"Enable"** butonuna tıklayın
3. Database URL'ini not edin (zaten kodda var):
   ```
   https://carbon-footprint-app-8111a-default-rtdb.firebaseio.com
   ```

### ADIM 3: Güvenlik Kurallarını Ayarlama

1. Realtime Database sayfasında üstteki **"Rules"** sekmesine tıklayın
2. Aşağıdaki kuralları kopyalayıp yapıştırın:

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
    ".read": true,
    ".write": true
  }
}
```

3. **"Publish"** (Yayınla) butonuna tıklayın
4. "Rules published successfully" mesajını görmelisiniz

### ADIM 4: Test Etme

1. ESP8266'ınızı çalıştırın
2. Firebase Console'da **"Data"** sekmesine gidin
3. Şu yapıyı görmelisiniz:

```
esp8266_data/
  └── esp8266_001/
      └── latest/
          ├── electricity: 0.5
          ├── water: 0.25
          ├── fuel: 0.0
          ├── waste: 0.0
          ├── co2_ppm: 400.0
          ├── timestamp: 1234567890
          └── created_at: ""
```

✅ **Başarılı!** ESP8266 artık Firebase'e veri gönderebilir.

---

## ⚠️ Önemli Notlar

### Güvenlik Uyarısı

Yukarıdaki kurallar **test modu** kurallarıdır. Herkes okuyup yazabilir. 

**Production (canlı) ortam için:**
- Authentication ekleyin
- Daha sıkı güvenlik kuralları kullanın
- Sadece giriş yapmış kullanıcılar erişebilsin

### Sorun Giderme

**Problem: "Permission denied" hatası**
- ✅ Rules sekmesinde kuralların doğru olduğundan emin olun
- ✅ "Publish" butonuna tıkladığınızdan emin olun
- ✅ Database'in test modunda olduğundan emin olun

**Problem: Veriler görünmüyor**
- ✅ ESP8266'ın WiFi'ye bağlı olduğundan emin olun
- ✅ Serial Monitor'de "Firebase Durumu: Başarılı" mesajını kontrol edin
- ✅ Firebase Console'da doğru projeyi seçtiğinizden emin olun

---

## 📱 Sonraki Adımlar

1. ✅ ESP8266'ı çalıştırın
2. ✅ Firebase Console'da verilerin geldiğini kontrol edin
3. ✅ Flutter uygulamanızı çalıştırın
4. ✅ Home screen'de anlık verileri görün

**Hepsi bu kadar! 🎉**

