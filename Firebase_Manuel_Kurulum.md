# Firebase Manuel Kurulum Rehberi

Firebase CLI kullanmadan manuel olarak Firebase'i Flutter projenize eklemek için bu rehberi takip edin.

---

## 📋 Adımlar

### 1. Firebase Console'dan Config Bilgilerini Alın

1. [Firebase Console](https://console.firebase.google.com/) adresine gidin
2. Projenizi seçin: **carbon-footprint-app**
3. Sol menüden **⚙️ Project Settings** (Proje Ayarları) tıklayın
4. Aşağı kaydırın ve **"Your apps"** (Uygulamalarınız) bölümüne gidin

### 2. Web Uygulaması Ekleme (Web için)

1. **"Add app"** butonuna tıklayın
2. **Web** (</>) ikonunu seçin
3. App nickname: `carbon-footprint-web` (veya istediğiniz isim)
4. **Register app** butonuna tıklayın
5. Config bilgilerini kopyalayın:

```javascript
const firebaseConfig = {
  apiKey: "AIza...",
  authDomain: "carbon-footprint-app-8111a.firebaseapp.com",
  databaseURL: "https://carbon-footprint-app-8111a-default-rtdb.europe-west1.firebasedatabase.app",
  projectId: "carbon-footprint-app-8111a",
  storageBucket: "carbon-footprint-app-8111a.appspot.com",
  messagingSenderId: "40318061378",
  appId: "1:40318061378:web:..."
};
```

### 3. Android Uygulaması Ekleme (Android için)

1. **"Add app"** butonuna tıklayın
2. **Android** ikonunu seçin
3. Android package name: `com.example.carbon_footprint_calculation_app` (veya `android/app/build.gradle.kts` dosyasındaki `applicationId`)
4. **Register app** butonuna tıklayın
5. `google-services.json` dosyasını indirin
6. `google-services.json` dosyasını `android/app/` klasörüne kopyalayın
7. Config bilgilerini not edin

### 4. iOS Uygulaması Ekleme (iOS için - Opsiyonel)

1. **"Add app"** butonuna tıklayın
2. **iOS** ikonunu seçin
3. iOS bundle ID: `com.example.carbonFootprintCalculationApp` (veya `ios/Runner.xcodeproj` dosyasındaki bundle ID)
4. **Register app** butonuna tıklayın
5. `GoogleService-Info.plist` dosyasını indirin
6. `GoogleService-Info.plist` dosyasını `ios/Runner/` klasörüne kopyalayın
7. Config bilgilerini not edin

### 5. Realtime Database URL'ini Not Edin

1. Firebase Console'da sol menüden **Realtime Database** seçin
2. Database URL'ini kopyalayın (eğer oluşturmadıysanız önce oluşturun):
   ```
   https://carbon-footprint-app-8111a-default-rtdb.europe-west1.firebasedatabase.app
   ```

### 6. firebase_options.dart Dosyasını Güncelleyin

`lib/firebase_options.dart` dosyasını açın ve Firebase Console'dan aldığınız bilgilerle doldurun:

```dart
static const FirebaseOptions web = FirebaseOptions(
  apiKey: 'AIza...', // Web app config'den
  appId: '1:40318061378:web:...', // Web app config'den
  messagingSenderId: '40318061378', // Project number
  projectId: 'carbon-footprint-app-8111a',
  authDomain: 'carbon-footprint-app-8111a.firebaseapp.com',
  databaseURL: 'https://carbon-footprint-app-8111a-default-rtdb.europe-west1.firebasedatabase.app',
  storageBucket: 'carbon-footprint-app-8111a.appspot.com',
);

static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIza...', // Android app config'den
  appId: '1:40318061378:android:...', // Android app config'den
  messagingSenderId: '40318061378',
  projectId: 'carbon-footprint-app-8111a',
  storageBucket: 'carbon-footprint-app-8111a.appspot.com',
);
```

### 7. Android build.gradle.kts Dosyasını Güncelleyin

`android/build.gradle.kts` dosyasına Google Services plugin'ini ekleyin:

```kotlin
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.0")
    }
}
```

`android/app/build.gradle.kts` dosyasının en altına ekleyin:

```kotlin
plugins {
    // ... diğer plugin'ler
    id("com.google.gms.google-services")
}
```

### 8. main.dart Dosyasını Güncelleyin

`lib/main.dart` dosyasını açın ve Firebase import'larını ekleyin:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/firebase_realtime_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Firebase Realtime Service'i başlat
  FirebaseRealtimeService.instance.initialize();

  // ... diğer kodlar
}
```

### 9. Paketleri Yükleyin

```bash
flutter pub get
```

### 10. Test Edin

```bash
flutter run
```

---

## ✅ Kontrol Listesi

- [ ] Firebase Console'da Web app eklendi
- [ ] Firebase Console'da Android app eklendi (Android için)
- [ ] Firebase Console'da iOS app eklendi (iOS için)
- [ ] `google-services.json` dosyası `android/app/` klasörüne kopyalandı (Android için)
- [ ] `GoogleService-Info.plist` dosyası `ios/Runner/` klasörüne kopyalandı (iOS için)
- [ ] `lib/firebase_options.dart` dosyası güncellendi
- [ ] `android/build.gradle.kts` dosyası güncellendi (Android için)
- [ ] `android/app/build.gradle.kts` dosyası güncellendi (Android için)
- [ ] `lib/main.dart` dosyası güncellendi
- [ ] `flutter pub get` çalıştırıldı
- [ ] Realtime Database oluşturuldu

---

## 🔧 Sorun Giderme

### Hata: "FirebaseApp not initialized"

**Çözüm:** `main.dart`'ta `Firebase.initializeApp()` çağrıldığından emin olun.

### Hata: "google-services.json not found" (Android)

**Çözüm:** `google-services.json` dosyasının `android/app/` klasöründe olduğundan emin olun.

### Hata: "API key is invalid"

**Çözüm:** Firebase Console'dan doğru config bilgilerini kopyaladığınızdan emin olun.

---

## 📚 Kaynaklar

- [Firebase Console](https://console.firebase.google.com/)
- [Firebase Realtime Database Dokümantasyonu](https://firebase.google.com/docs/database)

