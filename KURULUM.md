# Uygulamayı Çalıştırma Kılavuzu

## Hızlı Başlangıç

### 1. Bağımlılıkları Yükleyin

```bash
flutter pub get
```

### 2. Flutter Kurulumunu Kontrol Edin

```bash
flutter doctor
```

Bu komut Flutter kurulumunuzu ve eksik bileşenleri kontrol eder.

### 3. Uygulamayı Çalıştırın

#### Web için (En Kolay - Önerilen)
```bash
flutter run -d chrome
```
veya
```bash
flutter run -d web-server
```

#### Android için
```bash
# Android emülatör veya fiziksel cihaz bağlı olmalı
flutter run
```

#### iOS için (Sadece macOS)
```bash
# iOS simülatör veya fiziksel cihaz bağlı olmalı
flutter run
```

## Detaylı Adımlar

### Adım 1: Proje Klasörüne Gidin
```bash
cd c:\Users\test\Desktop\bitirme_C02
```

### Adım 2: Bağımlılıkları Yükleyin
```bash
flutter pub get
```

### Adım 3: Mevcut Cihazları/Emülatörleri Kontrol Edin
```bash
flutter devices
```

Bu komut çalıştırılabilecek cihazları listeler:
- Chrome (web)
- Android Emulator
- iOS Simulator (macOS'ta)
- Fiziksel cihazlar

### Adım 4: Uygulamayı Çalıştırın

**Web için (Önerilen):**
```bash
flutter run -d chrome
```

**Belirli bir cihaz için:**
```bash
flutter run -d <device-id>
```

## Sorun Giderme

### Firebase Hatası Alıyorsanız
Firebase yapılandırması eksik olabilir. `lib/firebase_options.dart` dosyasını kontrol edin.

### Görsel Hatası Alıyorsanız
`assets/images/` klasörüne gerekli görselleri ekleyin (opsiyonel - uygulama çalışır ama bazı görseller görünmeyebilir).

### PostgreSQL Hatası
PostgreSQL bağlantı hatası normaldir - uygulama çalışmaya devam eder, sadece veritabanı işlemleri başarısız olur.

## Hot Reload

Uygulama çalışırken:
- `r` tuşuna basarak hot reload yapabilirsiniz
- `R` tuşuna basarak hot restart yapabilirsiniz
- `q` tuşuna basarak çıkabilirsiniz

## Build (Production)

### Web için
```bash
flutter build web
```
Çıktı: `build/web/` klasöründe

### Android için
```bash
flutter build apk
```
Çıktı: `build/app/outputs/flutter-apk/app-release.apk`

### iOS için (macOS gerekli)
```bash
flutter build ios
```
