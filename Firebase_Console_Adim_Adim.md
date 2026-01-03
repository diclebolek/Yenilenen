# Firebase Console - Adım Adım Rehber

## 📱 Web Uygulaması Ekleme ve Config Bilgilerini Alma

### ADIM 1: Firebase Console'a Giriş

1. Tarayıcınızda [Firebase Console](https://console.firebase.google.com/) adresine gidin
2. Google hesabınızla giriş yapın
3. **carbon-footprint-app** projenizi seçin (veya oluşturduğunuz projeyi)

---

### ADIM 2: Project Settings'e Gitme

1. Sol üst köşede proje adının yanındaki **⚙️ (dişli çark) ikonuna** tıklayın
2. Açılan menüden **"Project settings"** (Proje ayarları) seçeneğine tıklayın

**Alternatif yol:**
- Sol menüden **⚙️ Project Settings** seçeneğine tıklayın

---

### ADIM 3: Web Uygulaması Ekleme

1. **Project Settings** sayfasında aşağı kaydırın
2. **"Your apps"** (Uygulamalarınız) bölümünü bulun
3. Eğer hiç uygulama yoksa, **"</>" (Web) ikonuna** tıklayın
4. Eğer zaten uygulamalar varsa, **"Add app"** butonuna tıklayın ve **"</>" (Web) ikonunu** seçin

**Not:** Web ikonu şu şekilde görünür: `</>` veya `</> Web`

---

### ADIM 4: Web Uygulaması Kaydetme

1. **App nickname** (Uygulama takma adı) girin: `carbon-footprint-web` (veya istediğiniz isim)
2. **"Also set up Firebase Hosting"** seçeneğini şimdilik işaretlemeyin (opsiyonel)
3. **"Register app"** butonuna tıklayın

---

### ADIM 5: Config Bilgilerini Kopyalama

Config bilgileri iki formatta gösterilir:

#### Format 1: JavaScript (CDN)
```javascript
const firebaseConfig = {r
  apiKey: "AIzaSyC...",  // ← Bu değeri kopyalayın
  authDomain: "carbon-footprint-app-8111a.firebaseapp.com",
  databaseURL: "https://carbon-footprint-app-8111a-default-rtdb.firebaseio.com",
  projectId: "carbon-footprint-app-8111a",
  storageBucket: "carbon-footprint-app-8111a.appspot.com",
  messagingSenderId: "40318061378",
  appId: "1:40318061378:web:abc123..."  // ← Bu değeri kopyalayın
};
```

#### Format 2: npm
```javascript
import { initializeApp } from 'firebase/app';

const firebaseConfig = {
  apiKey: "AIzaSyC...",
  // ... diğer değerler
};
```

**Hangi değerleri kopyalayacaksınız:**
- ✅ `apiKey` → `YOUR_WEB_API_KEY` yerine
- ✅ `appId` → `YOUR_WEB_APP_ID` yerine
- ✅ `messagingSenderId` → `YOUR_MESSAGING_SENDER_ID` yerine (zaten biliyoruz: 40318061378)

---

### ADIM 6: Config Bilgilerini Görme (Eğer Uygulama Zaten Varsa)

Eğer Web uygulaması zaten eklenmişse:

1. **Project Settings** sayfasında **"Your apps"** bölümüne gidin
2. Web uygulamanızın altında **"</>" (Web) ikonu** görünecek
3. Web uygulamanızın yanındaki **⚙️ (dişli çark) ikonuna** tıklayın
4. Veya Web uygulamanızın üzerine tıklayın
5. **"SDK setup and configuration"** bölümünde config bilgilerini göreceksiniz
6. **"Config"** sekmesine tıklayın

---

## 📱 Android Uygulaması Ekleme

### ADIM 1: Android Uygulaması Ekleme

1. **Project Settings** sayfasında **"Your apps"** bölümüne gidin
2. **"Add app"** butonuna tıklayın
3. **🤖 Android ikonuna** tıklayın

### ADIM 2: Android Package Name Bulma

Android package name'i bulmak için:

1. Projenizde `android/app/build.gradle.kts` dosyasını açın
2. `applicationId` değerini bulun:

```kotlin
android {
    defaultConfig {
        applicationId "com.example.carbon_footprint_calculation_app"  // ← Bu değer
    }
}
```

**Veya:**
- `android/app/src/main/AndroidManifest.xml` dosyasında `package` değerini kontrol edin

### ADIM 3: Android Uygulaması Kaydetme

1. **Android package name** girin: `com.example.carbon_footprint_calculation_app` (veya build.gradle.kts'deki değer)
2. **App nickname** (opsiyonel): `carbon-footprint-android`
3. **"Register app"** butonuna tıklayın

### ADIM 4: google-services.json Dosyasını İndirme

1. **"Download google-services.json"** butonuna tıklayın
2. İndirilen `google-services.json` dosyasını kopyalayın
3. Projenizde `android/app/` klasörüne yapıştırın

**Önemli:** Dosya yolu şöyle olmalı:
```
android/app/google-services.json
```

### ADIM 5: Android Config Bilgilerini Kopyalama

1. Android uygulamanızın yanındaki **⚙️ (dişli çark) ikonuna** tıklayın
2. **"SDK setup and configuration"** bölümünde config bilgilerini göreceksiniz
3. Şu değerleri kopyalayın:
   - `apiKey`
   - `appId` (format: `1:40318061378:android:...`)

---

## 🔧 build.gradle.kts Dosyalarını Güncelleme (Android için)

### android/build.gradle.kts

Dosyanın başına ekleyin:

```kotlin
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.0")
    }
}
```

### android/app/build.gradle.kts

Dosyanın en altına ekleyin:

```kotlin
plugins {
    // ... mevcut plugin'ler
    id("com.google.gms.google-services")
}
```

---

## ✅ Kontrol Listesi

### Web için:
- [ ] Firebase Console'da Web uygulaması eklendi
- [ ] `apiKey` değeri kopyalandı
- [ ] `appId` değeri kopyalandı
- [ ] `firebase_options.dart` dosyası güncellendi

### Android için:
- [ ] Firebase Console'da Android uygulaması eklendi
- [ ] `google-services.json` dosyası `android/app/` klasörüne kopyalandı
- [ ] `apiKey` değeri kopyalandı
- [ ] `appId` değeri kopyalandı
- [ ] `android/build.gradle.kts` dosyası güncellendi
- [ ] `android/app/build.gradle.kts` dosyası güncellendi
- [ ] `firebase_options.dart` dosyası güncellendi

---

## 🆘 Sorun Giderme

### "Add app" butonu görünmüyor

**Çözüm:** 
- Sayfayı yenileyin (F5)
- Farklı bir tarayıcı deneyin
- Firebase Console'un tam ekran olduğundan emin olun

### Config bilgileri görünmüyor

**Çözüm:**
- Web uygulamanızın yanındaki **⚙️ (dişli çark) ikonuna** tıklayın
- **"SDK setup and configuration"** bölümüne gidin
- **"Config"** sekmesine tıklayın

### Android package name bulunamıyor

**Çözüm:**
- `android/app/build.gradle.kts` dosyasını açın
- `applicationId` değerini arayın
- Eğer yoksa, `android/app/src/main/AndroidManifest.xml` dosyasındaki `package` değerini kullanın

---

## 📸 Görsel Yardım

Firebase Console'da şu sırayla ilerleyin:

1. **Sol üst köşe** → ⚙️ (dişli çark) → **Project settings**
2. **Aşağı kaydır** → **"Your apps"** bölümü
3. **"Add app"** butonu → **</> Web** veya **🤖 Android**
4. Bilgileri doldur → **"Register app"**
5. Config bilgilerini kopyala

---

**Not:** Eğer hala bulamıyorsanız, ekran görüntüsü paylaşabilirsiniz veya hangi adımda takıldığınızı belirtebilirsiniz.

