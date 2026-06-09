# Güvenlik Dokümantasyonu

Karbon Ayak İzi Hesaplama Uygulaması — mevcut güvenlik önlemleri, yapılandırmalar ve bilinen eksikler.

**Son güncelleme:** Haziran 2026  
**Kapsam:** Flutter mobil/web uygulaması, Firebase, Android derlemesi, Docker (web)

---

## Özet

| Alan | Durum |
|------|--------|
| Kimlik doğrulama | ✅ Firebase Auth (e-posta/şifre) |
| Hassas dosyaların repodan hariç tutulması | ✅ `.gitignore` |
| Release log sızıntısı azaltma | ✅ `debugPrint` kapatıldı |
| Manuel kullanıcı verisi izolasyonu (kod) | ✅ `userId` ile Firebase yolları |
| Firebase Realtime Database kuralları (sunucu) | ⚠️ Repoda yok — konsolda yapılandırılmalı |
| Release imzası (Play Store) | ⚠️ Hâlâ debug key |
| Yerel IoT HTTP (Shelly) | ⚠️ Cleartext + sabit IP |

---

## 1. Kimlik doğrulama ve oturum

### Firebase Authentication

**Dosya:** `lib/services/firebase_auth_service.dart`

| Özellik | Açıklama |
|---------|----------|
| Kayıt | `createUserWithEmailAndPassword` |
| Giriş | `signInWithEmailAndPassword` |
| Çıkış | `signOut()` — Ayarlar ekranından tetiklenir |
| Şifre sıfırlama | `sendPasswordResetEmail` — giriş ekranında e-posta girildikten sonra |
| Şifre değiştirme | Mevcut şifre ile `reauthenticateWithCredential`, ardından `updatePassword` |
| E-posta güncelleme | `verifyBeforeUpdateEmail` |
| E-posta doğrulama | `sendEmailVerification` (servis hazır) |
| Hata mesajları | Firebase hata kodları Türkçe’ye çevrilir (`weak-password`, `wrong-password`, `too-many-requests` vb.) |

### UI doğrulamaları

**Dosyalar:** `lib/screens/login_screen.dart`, `lib/screens/register_screen.dart`, `lib/screens/profile_settings_screen.dart`

- Şifre zorunlu alan
- Minimum **6 karakter** (Firebase varsayılanı ile uyumlu)
- Kayıtta şifre tekrarı eşleşme kontrolü
- Profilde şifre değişimi için mevcut şifre zorunlu

### Oturum akışı

**Dosya:** `lib/main.dart`

- Giriş yapılmadan ana ekranlar gösterilmez (`_isLoggedIn` durumu)
- `_handleLogout()` → Firebase `signOut` + ana sekmeye dönüş
- Firebase oturumu cihazda kalıcıdır (Firebase SDK varsayılanı); uygulama yeniden açıldığında `authStateChanges` ile otomatik senkron **henüz** `main.dart`’ta bağlanmamış — oturum Firebase tarafında devam edebilir

---

## 2. Veri erişimi ve izolasyon (uygulama kodu)

### Manuel veriler — kullanıcıya özel

**Dosya:** `lib/services/firebase_realtime_service.dart`

Firebase Realtime Database yolları oturum açmış kullanıcının `uid` değeri ile oluşturulur:

| Veri | Yol |
|------|-----|
| Manuel tüketim (son) | `/manual_data/{userId}/latest` |
| Manuel geçmiş | `/manual_data/{userId}/history/{YYYY-MM-DD}/...` |
| Yeşil puan | `/green_score/{userId}` |
| Hedefler | `/users/{userId}/goals` |
| Rozetler | `/users/{userId}/badges` |

Raporlar, hedefler ve formlar veri okurken/yazarken `FirebaseAuthService.instance.currentUser?.uid` kullanır.

### IoT / sensör verileri — paylaşımlı

| Veri | Yol | Not |
|------|-----|-----|
| ESP8266 | `/esp8266_data/{deviceId}/...` | Cihaz ID: `esp8266_001` |
| Shelly | Firebase üzerinden cihaz kayıtları | `shelly_plug_001` |
| ESP durum | `/esp8266_status/{deviceId}` | |

Bu yollar **kullanıcıya özel değil**; işletme sensörü varsayımıyla tasarlanmıştır. Güvenlik **Firebase Realtime Database kuralları** ile sınırlandırılmalıdır (aşağıya bakın).

### Opsiyonel PostgreSQL API

**Dosya:** `lib/services/postgres_service.dart`

- Varsayılan: `http://localhost:3000/api`
- Ana giriş **Firebase Auth** üzerinden; PostgreSQL API geliştirme/opsiyonel arka uç içindir
- Production’da gerçek sunucu URL’si ve TLS gerekir

---

## 3. Hassas bilgilerin korunması (kaynak kodu)

### `.gitignore`

**Dosya:** `.gitignore`

Repoya **commit edilmemesi** gereken dosyalar:

```
**/google-services.json
**/GoogleService-Info.plist
**/firebase_options.dart
.env
.env.local
*.db / *.sqlite / *.sqlite3
/build/
```

Firebase yapılandırması her geliştirici/CI ortamında yerelde `flutterfire configure` veya manuel kopya ile sağlanır.

### Docker web derlemesi

**Dosyalar:** `Dockerfile`, `docker-compose.yml`

- `firebase_options.dart` gitignore’da olduğu için **temiz klon + Docker build** öncesinde dosyanın build ortamına eklenmesi gerekir
- Docker yalnızca **web** sürümünü nginx ile sunar; Android APK üretmez

---

## 4. Android derlemesi

### ProGuard

**Dosyalar:** `android/app/build.gradle.kts`, `android/app/proguard-rules.pro`

- Release build tipinde ProGuard dosyaları referanslanır
- `proguard-rules.pro`: ML Kit opsiyonel dil modelleri için `-dontwarn` kuralları
- **`minifyEnabled` / `shrinkResources` açık değil** — kod küçültme/obfuscation tam etkin değil

### İmzalama

**Dosya:** `android/app/build.gradle.kts`

```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")  // TODO: production keystore
}
```

Release APK şu an **debug imzası** ile üretilir. Play Store veya resmi dağıtım için **kendi keystore** tanımlanmalıdır.

### AndroidManifest izinleri ve ağ

**Dosya:** `android/app/src/main/AndroidManifest.xml`

| Ayar | Değer | Güvenlik notu |
|------|--------|----------------|
| `INTERNET` | Var | Firebase, API, hava durumu |
| `CAMERA` | Var | Fatura OCR (ML Kit) |
| `POST_NOTIFICATIONS` | Var | Yerel bildirimler |
| `usesCleartextTraffic` | **`true`** | Yerel Shelly HTTP için; dış ağda MITM riski artar |

Shelly Plug S yerel ağda **HTTP** kullandığı için cleartext açıktır. İdeal çözüm: yalnızca yerel IP aralıkları için `network_security_config`.

### Sabit Shelly IP (kod içi)

**Dosyalar:** `lib/screens/reports_screen.dart`, `lib/screens/home_screen.dart`

- Örnek: `192.168.137.57` kaynak kodda sabit
- Ayarlardan yapılandırılmıyor; farklı ağda IP sızıntısı ve yanlış hedef riski

---

## 5. Loglama ve bilgi sızıntısı

### Release’te `debugPrint` kapatma

**Dosya:** `lib/main.dart`

```dart
if (kReleaseMode) {
  debugPrint = (String? message, {int? wrapWidth}) {};
}
```

- **Debug / profile** derlemelerde loglar normal çalışır
- **Release APK/IPA**’da `debugPrint` çıktıları logcat’e düşmez (IP, tüketim, Shelly debug mesajları vb.)

### Raporlar ekranı — ek log susturma

**Dosya:** `lib/screens/reports_screen.dart`

- `_ReportsScreenState` içinde yerel `debugPrint` override ile ekran içi gürültü azaltılır (geliştirme sırasında)

### Hâlâ aktif olabilecek loglar

**Dosyalar:** `lib/services/*.dart` (ör. `shelly_service.dart`, `firebase_auth_service.dart`)

- `dart:developer` **`dev.log(...)`** release modda da yazabilir
- Tam susturma için ileride merkezi bir `AppLogger` ve `kReleaseMode` kontrolü eklenebilir

---

## 6. Üçüncü taraf API’ler

| Servis | API anahtarı | Not |
|--------|--------------|-----|
| Firebase | Proje config (gitignore) | Auth + Realtime DB |
| Open-Meteo (hava) | Gerekmez | Açık, ücretsiz |
| Our World in Data | Gerekmez | Açık JSON |
| Shelly (yerel) | Yok | Yerel HTTP/WebSocket |
| ESP8266 | Yok | Firebase / yerel ağ |

---

## 7. Firebase Realtime Database kuralları (ÖNEMLİ — konsol)

Repoda **`database.rules.json` dosyası yoktur**. Sunucu tarafı güvenlik için Firebase Console → Realtime Database → **Rules** bölümünde aşağıdakine benzer kurallar uygulanmalıdır:

```json
{
  "rules": {
    "manual_data": {
      "$uid": {
        ".read": "auth != null && auth.uid == $uid",
        ".write": "auth != null && auth.uid == $uid"
      }
    },
    "users": {
      "$uid": {
        ".read": "auth != null && auth.uid == $uid",
        ".write": "auth != null && auth.uid == $uid"
      }
    },
    "green_score": {
      "$uid": {
        ".read": "auth != null && auth.uid == $uid",
        ".write": "auth != null && auth.uid == $uid"
      }
    },
    "esp8266_data": {
      ".read": "auth != null",
      ".write": false
    },
    "esp8266_status": {
      ".read": "auth != null",
      ".write": false
    }
  }
}
```

> **Not:** Kurallar konsolda yapılandırılmadan Auth olsa bile veritabanı okuma/yazma açık kalabilir. Bu, production için **en kritik** eksik adımdır.

---

## 8. Bilinen riskler ve önerilen iyileştirmeler

| Öncelik | Konu | Öneri |
|---------|------|--------|
| 🔴 Yüksek | Firebase DB kuralları | Yukarıdaki kuralları Console’a uygula; repoya `database.rules.json` ekle |
| 🔴 Yüksek | Release imzası | Production keystore, debug imzasını kaldır |
| 🟠 Orta | Cleartext HTTP | `network_security_config` ile yalnızca yerel Shelly IP’lerine izin |
| 🟠 Orta | Shelly IP | Ayarlar ekranından `SharedPreferences` ile kaydet |
| 🟠 Orta | `dev.log` | Release’te merkezi logger ile kapat |
| 🟡 Düşük | Şifre politikası | Min. 8 karakter, karmaşıklık (Firebase + UI) |
| 🟡 Düşük | Firebase App Check | Sahte istemci isteklerini sınırla |
| 🟡 Düşük | `minifyEnabled` + R8 | Release APK reverse-engineering zorluğu |
| 🟡 Düşük | Docker nginx | Güvenlik header’ları (`X-Frame-Options`, `CSP` vb.) |

---

## 9. Güvenlikle ilgili dosya indeksi

| Dosya | Rol |
|-------|-----|
| `lib/main.dart` | Release `debugPrint` kapatma, logout, Firebase init |
| `lib/services/firebase_auth_service.dart` | Auth işlemleri |
| `lib/services/firebase_realtime_service.dart` | DB yolları, `userId` kapsamı |
| `lib/screens/login_screen.dart` | Giriş, şifre sıfırlama |
| `lib/screens/register_screen.dart` | Kayıt validasyonu |
| `lib/screens/profile_settings_screen.dart` | Şifre/e-posta güncelleme |
| `.gitignore` | Hassas config hariç tutma |
| `android/app/build.gradle.kts` | ProGuard referansı, imzalama |
| `android/app/proguard-rules.pro` | ML Kit ProGuard kuralları |
| `android/app/src/main/AndroidManifest.xml` | İzinler, cleartext |
| `Dockerfile` / `docker-compose.yml` | Web container (config dışarıda) |

---

## 10. Hızlı kontrol listesi (deployment öncesi)

- [ ] Firebase Realtime Database kuralları test edildi (Simulator veya Rules Playground)
- [ ] `google-services.json` / `firebase_options.dart` yalnızca güvenli ortamda, repoda yok
- [ ] Release APK **production keystore** ile imzalandı
- [ ] Release build’de logcat’te IP/tüketim `debugPrint` çıkmıyor
- [ ] Shelly yalnızca güvenilir yerel ağda erişilebilir
- [ ] `.env` veya gizli anahtar repoya eklenmedi
- [ ] (Web Docker) `firebase_options.dart` build pipeline’da inject ediliyor

---

## Referanslar

- [Firebase Auth — Flutter](https://firebase.google.com/docs/auth/flutter/start)
- [Firebase Realtime Database — Security Rules](https://firebase.google.com/docs/database/security)
- [Android Network Security Configuration](https://developer.android.com/privacy-and-security/security-config)
