# Firebase Son Adımlar - Detaylı Rehber

Bu rehber, Firebase Authentication ve Realtime Database kurulumunu tamamlamak için gerekli son adımları içerir.

---

## 📋 İçindekiler

1. [Firebase Authentication'ı Etkinleştirme](#1-firebase-authenticationı-etkinleştirme)
2. [Realtime Database Kurallarını Ayarlama](#2-realtime-database-kurallarını-ayarlama)
3. [Uygulamayı Test Etme](#3-uygulamayı-test-etme)

---

## 1. Firebase Authentication'ı Etkinleştirme

### ADIM 1: Firebase Console'a Giriş

1. Tarayıcınızda şu adrese gidin:
   ```
   https://console.firebase.google.com/
   ```

2. Google hesabınızla giriş yapın

3. **"carbon-footprint-app-8111a"** projenizi seçin (veya oluşturduğunuz projeyi)

### ADIM 2: Authentication Sayfasına Gitme

1. Sol menüden **"Authentication"** (Kimlik Doğrulama) seçeneğine tıklayın
   - İkon: 🔐 (kilit) veya "Authentication" yazısı

2. Eğer ilk kez açıyorsanız, **"Get started"** (Başlayın) butonuna tıklayın

### ADIM 3: Sign-in Method'u Etkinleştirme

1. **"Sign-in method"** (Giriş yöntemi) sekmesine tıklayın
   - Sayfanın üst kısmında tab'lar görünecek

2. **"Email/Password"** (E-posta/Şifre) satırını bulun ve üzerine tıklayın
   - Liste halinde sign-in method'lar görünecek:
     - Email/Password
     - Google
     - Facebook
     - vs.

3. **"Enable"** (Etkinleştir) toggle'ını açın
   - Sağ üst köşede bir switch görünecek

4. **"Email link (passwordless sign-in)"** seçeneği:
   - Bu seçeneği **şimdilik kapalı** bırakabilirsiniz
   - Normal e-posta/şifre girişi için gerekli değil

5. **"Save"** (Kaydet) butonuna tıklayın
   - Sayfanın alt kısmında veya sağ üstte olabilir

### ADIM 4: Doğrulama

1. **"Email/Password"** satırında **"Enabled"** (Etkin) yazısını görmelisiniz
2. Yeşil bir işaret veya "Enabled" durumu görünecek

**✅ Authentication başarıyla etkinleştirildi!**

---

## 2. Realtime Database Kurallarını Ayarlama

### ADIM 1: Realtime Database Sayfasına Gitme

1. Sol menüden **"Realtime Database"** seçeneğine tıklayın
   - İkon: ⚡ (şimşek) veya "Realtime Database" yazısı

2. Eğer database oluşturmadıysanız:
   - **"Create Database"** butonuna tıklayın
   - **Location** seçin: `europe-west1` (Türkiye için en yakın)
   - **"Start in test mode"** seçin
   - **"Enable"** butonuna tıklayın

### ADIM 2: Rules Sekmesine Gitme

1. Sayfanın üst kısmında **"Rules"** (Kurallar) sekmesine tıklayın
   - Tab'lar: "Data", "Rules", "Usage", "Backups"

2. Mevcut kuralları göreceksiniz (muhtemelen test mode kuralları)

### ADIM 3: Kuralları Güncelleme

**Seçenek 1: Test Modu (Geliştirme için - Önerilen)**

Aşağıdaki kuralları yapıştırın:

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

**Seçenek 2: Güvenli Mod (Production için)**

Sadece giriş yapmış kullanıcılar okuyup yazabilsin:

```json
{
  "rules": {
    "esp8266_data": {
      "$deviceId": {
        ".read": "auth != null",
        ".write": "auth != null"
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

### ADIM 4: Kuralları Kaydetme

1. Kuralları yazdıktan sonra **"Publish"** (Yayınla) butonuna tıklayın
   - Sağ üst köşede veya sayfanın altında olabilir

2. Onay mesajı görünecek: **"Rules published successfully"**

**✅ Realtime Database kuralları başarıyla ayarlandı!**

---

## 3. Uygulamayı Test Etme

### TEST 1: Web Uygulamasını Test Etme

#### ADIM 1: Web Uygulamasını Açma

1. Tarayıcınızda şu URL'yi açın:
   ```
   https://carbon-footprint-app-8111a.web.app
   ```

2. Veya alternatif URL:
   ```
   https://carbon-footprint-app-8111a.firebaseapp.com
   ```

#### ADIM 2: Kayıt Olma Testi

1. **"Kayıt Ol"** veya **"Register"** butonuna tıklayın

2. Formu doldurun:
   - **İşletme Adı:** Test İşletme
   - **Sektör:** Bir sektör seçin
   - **E-posta:** test@example.com (gerçek bir e-posta kullanın)
   - **Şifre:** 123456 (en az 6 karakter)
   - **Şifre Tekrar:** 123456

3. **"Kayıt Ol"** butonuna tıklayın

4. **Beklenen sonuç:**
   - ✅ "Kayıt başarılı! Giriş yapabilirsiniz." mesajı
   - ✅ Login sayfasına yönlendirme

#### ADIM 3: Giriş Yapma Testi

1. **E-posta** ve **Şifre** alanlarını doldurun

2. **"Giriş Yap"** butonuna tıklayın

3. **Beklenen sonuç:**
   - ✅ Ana sayfaya yönlendirme
   - ✅ Uygulama içeriği görünür

#### ADIM 4: Firebase Console'da Kullanıcıyı Kontrol Etme

1. [Firebase Console](https://console.firebase.google.com/project/carbon-footprint-app-8111a/authentication/users) → **Authentication** → **Users** sekmesine gidin

2. Kaydettiğiniz kullanıcıyı görmelisiniz:
   - E-posta adresi
   - Kayıt tarihi
   - UID (Firebase User ID)

### TEST 2: Mobil Uygulamayı Test Etme

#### ADIM 1: Uygulamayı Çalıştırma

**Android için:**
```bash
flutter run
```

**iOS için:**
```bash
flutter run -d ios
```

**Belirli bir cihaz için:**
```bash
flutter devices  # Mevcut cihazları listele
flutter run -d <device-id>
```

#### ADIM 2: Kayıt ve Giriş Testi

1. Web uygulamasındaki adımları tekrarlayın
2. Mobil uygulamada da aynı şekilde çalışmalı

### TEST 3: ESP8266 Verilerini Firebase'e Kaydetme Testi

#### ADIM 1: ESP8266 Sensörünü Hazırlama

1. ESP8266'nızın çalıştığından emin olun
2. WiFi bağlantısını kontrol edin
3. IP adresini not edin (örn: `192.168.1.100`)

#### ADIM 2: Uygulamada ESP8266 Bağlantısını Test Etme

1. Uygulamada **"ESP8266 Verilerini Çek"** butonuna tıklayın
   - Veya `ApiService` kullanarak manuel test edin

2. **Beklenen sonuç:**
   - ✅ ESP8266'dan veri alınır
   - ✅ Firebase'e otomatik kaydedilir

#### ADIM 3: Firebase Console'da Verileri Kontrol Etme

1. [Firebase Console](https://console.firebase.google.com/project/carbon-footprint-app-8111a/database) → **Realtime Database** → **Data** sekmesine gidin

2. Şu yapıyı görmelisiniz:
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
                 └── ...
   ```

### TEST 4: Real-time Veri Dinleme Testi

#### ADIM 1: Real-time Widget'ı Ekleme

1. `lib/screens/home_screen.dart` dosyasına `RealtimeEspDataWidget` ekleyin:

```dart
import '../widgets/realtime_esp_data_widget.dart';

// Widget tree içinde
RealtimeEspDataWidget()
```

#### ADIM 2: Test Etme

1. Uygulamayı çalıştırın
2. ESP8266'dan veri gönderin
3. **Beklenen sonuç:**
   - ✅ Veriler anlık olarak güncellenir
   - ✅ StreamBuilder otomatik olarak yenilenir

---

## 🔧 Sorun Giderme

### Sorun: "Authentication not enabled" hatası

**Çözüm:**
- Firebase Console'da Authentication'ın etkin olduğundan emin olun
- Email/Password method'unun açık olduğunu kontrol edin

### Sorun: "Permission denied" hatası (Realtime Database)

**Çözüm:**
- Realtime Database Rules'ı kontrol edin
- Test modu için `.read: true, .write: true` olduğundan emin olun

### Sorun: "User not found" hatası

**Çözüm:**
- Önce kayıt olun, sonra giriş yapın
- Firebase Console'da kullanıcının oluşturulduğunu kontrol edin

### Sorun: ESP8266 verileri Firebase'e kaydedilmiyor

**Çözüm:**
1. ESP8266 IP adresini kontrol edin (`ApiService` içinde)
2. WiFi bağlantısını kontrol edin
3. Firebase başlatma kodunu kontrol edin (`main.dart`)
4. Console log'larını kontrol edin

---

## ✅ Kontrol Listesi

### Authentication
- [ ] Firebase Console'da Authentication açıldı
- [ ] Email/Password method etkinleştirildi
- [ ] Test kullanıcısı oluşturuldu
- [ ] Giriş yapma test edildi

### Realtime Database
- [ ] Database oluşturuldu
- [ ] Rules ayarlandı
- [ ] Rules publish edildi
- [ ] ESP8266 verileri kaydedildi
- [ ] Veriler Firebase Console'da görünüyor

### Uygulama
- [ ] Web uygulaması açılıyor
- [ ] Mobil uygulama çalışıyor
- [ ] Kayıt olma çalışıyor
- [ ] Giriş yapma çalışıyor
- [ ] ESP8266 bağlantısı çalışıyor
- [ ] Real-time veri güncellemesi çalışıyor

---

## 📚 Faydalı Linkler

- **Firebase Console:** https://console.firebase.google.com/project/carbon-footprint-app-8111a
- **Authentication:** https://console.firebase.google.com/project/carbon-footprint-app-8111a/authentication
- **Realtime Database:** https://console.firebase.google.com/project/carbon-footprint-app-8111a/database
- **Hosting:** https://console.firebase.google.com/project/carbon-footprint-app-8111a/hosting
- **Web Uygulaması:** https://carbon-footprint-app-8111a.web.app

---

## 🎯 Sonuç

Tüm adımları tamamladıktan sonra:

1. ✅ **Firebase Authentication** çalışıyor
2. ✅ **Firebase Realtime Database** çalışıyor
3. ✅ **Firebase Hosting** çalışıyor
4. ✅ **ESP8266 entegrasyonu** hazır
5. ✅ **Web uygulaması** yayında

Artık uygulamanızı kullanmaya başlayabilirsiniz! 🚀

