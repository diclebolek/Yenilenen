# Kurulum ve Calistirma Kilavuzu

Bu dosya proje icin tek kaynak kurulum dokumanidir. Flutter, Firebase, ESP8266 ve emulator adimlarini birlikte icerir.

## 1) Hizli Baslangic

1. Proje klasorune girin.
2. Bagimliliklari yukleyin:

```bash
flutter pub get
```

3. Flutter kurulumunu kontrol edin:

```bash
flutter doctor
```

4. Cihazlari listeleyin:

```bash
flutter devices
```

5. Uygulamayi calistirin:

```bash
flutter run
```

Web icin:

```bash
flutter run -d chrome
```

## 2) Firebase Kurulumu

### 2.1 Firebase Console

1. Firebase'de proje olusturun/acin.
2. Android uygulamasini ekleyin ve `google-services.json` dosyasini indirin.
3. Gerekliyse web uygulamasini ekleyin.
4. Authentication icinde Email/Password girisini etkinlestirin.
5. Realtime Database olusturun.

### 2.2 Gelistirme Rules (gecici)

```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

Not: Bu kurallar sadece gelistirme icindir. Uretimde mutlaka kisitlayin.

### 2.3 Projedeki Firebase dosyalari

- `android/app/google-services.json` dosyasi dogru konumda olmali
- `lib/firebase_options.dart` guncel olmali
- `lib/main.dart` icinde Firebase baslatma kodlari calisiyor olmali

## 3) ESP8266 ve Ag Ayari

`lib/services/api_service.dart` icindeki ESP adresini kendi cihaziniza gore guncelleyin:

```dart
static const String espBaseUrl = 'http://172.20.10.2';
```

Tarayicidan endpoint kontrolu yapin:

- `http://ESP_IP/api/status`
- `http://ESP_IP/api/consumption`

Beklenti: JSON donmeli ve `gas_consumption_m3` gibi alanlar gorunmeli.

## 4) Android Emulator ile Calistirma

### 4.1 Emulator baslatma

```bash
flutter emulators
flutter emulators --launch <emulator_id>
```

Ardindan:

```bash
flutter run
```

### 4.2 Hotspot/Shelly senaryosu (opsiyonel)

Shelly cihazi kullaniyorsaniz emulator ve Shelly ayni agda olmalidir.

- Emulator ayarlarindan WiFi baglantisini kontrol edin
- Gerekirse Windows hotspot'a baglayin
- Shelly IP adresini ilgili ekranda/service'te dogrulayin

## 5) Beklenen Firebase Veri Yolu

Temel yol:

`esp8266_data/esp8266_001/latest`

Sik kullanilan alanlar:

- `gas_consumption_m3`
- `fuel` (uyumluluk icin)
- `water_flow_liters`
- `water`
- `timestamp`
- `created_at`

## 6) Sorun Giderme

### Firebase'e yazilmiyorsa

- `firebase_options.dart` ve `google-services.json` dosyalarini kontrol edin
- Realtime Database rules'inizin gelistirme asamasinda engellemediginden emin olun
- Uygulama loglarinda Firebase write hatasi var mi kontrol edin

### ESP verisi gelmiyorsa

- ESP IP adresi dogru mu kontrol edin
- Telefon/emulator ile ESP ayni agda mi kontrol edin
- `/api/status` ve `/api/consumption` endpointlerini tarayicidan test edin

### Emulator veya derleme sorunlari

```bash
flutter clean
flutter pub get
flutter run
```

## 7) Hot Reload ve Build

Uygulama calisirken:

- `r`: hot reload
- `R`: hot restart
- `q`: cikis

Production build:

```bash
flutter build web
flutter build apk
```
