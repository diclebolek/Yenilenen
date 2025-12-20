# 📡 İnternet ve Ağ Bağlantısı Kontrol Kılavuzu

Bu kılavuz, uygulamanızın internete bağlı olup olmadığını nasıl kontrol edeceğinizi gösterir.

---

## 🎯 Hızlı Kontrol

### Yöntem 1: Widget Kullanarak (Önerilen)

Uygulamanızda bağlantı durumunu göstermek için hazır widget'ı kullanın:

```dart
import '../widgets/connection_status_widget.dart';

// Widget'ı ekleyin (örn: Home Screen'de)
ConnectionStatusWidget()
```

Bu widget şunları gösterir:
- ✅ **İnternet Bağlantısı**: Gerçek internet erişimi var mı?
- 📶 **WiFi**: WiFi ağına bağlı mı?
- 📱 **Mobil Veri**: Mobil veri bağlantısı var mı?
- 🔄 **Yenile Butonu**: Bağlantıyı tekrar kontrol et

---

## 💻 Kod ile Kontrol

### Temel Kontrol

```dart
import '../services/connectivity_service.dart';

final connectivityService = ConnectivityService();

// İnternet bağlantısını kontrol et
final hasInternet = await connectivityService.checkInternetConnection();
if (hasInternet) {
  print('İnternet bağlantısı var!');
} else {
  print('İnternet bağlantısı yok!');
}
```

### Detaylı Kontrol

```dart
// Tüm bağlantı bilgilerini al
final status = await connectivityService.getConnectionStatus();

print('İnternet: ${status['hasInternet']}');
print('WiFi: ${status['hasWifi']}');
print('Mobil Veri: ${status['hasMobileData']}');
print('Herhangi Bir Bağlantı: ${status['hasAnyConnection']}');
```

### WiFi Kontrolü

```dart
// Sadece WiFi bağlantısını kontrol et
final hasWifi = await connectivityService.checkWifiConnection();
if (hasWifi) {
  print('WiFi bağlı');
} else {
  print('WiFi bağlı değil');
}
```

---

## 🔄 Gerçek Zamanlı Dinleme

Bağlantı durumu değişikliklerini dinlemek için:

```dart
StreamBuilder<Map<String, dynamic>>(
  stream: connectivityService.listenToConnectionChanges(),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final status = snapshot.data!;
      final hasInternet = status['hasInternet'] as bool;
      
      return Text(
        hasInternet ? 'İnternet Bağlı' : 'İnternet Yok',
      );
    }
    return CircularProgressIndicator();
  },
)
```

---

## 🏠 Home Screen'e Ekleme

`home_screen.dart` dosyasına ekleyin:

```dart
import '../widgets/connection_status_widget.dart';

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          // Bağlantı durumu widget'ı
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConnectionStatusWidget(),
          ),
          
          // Diğer widget'lar...
        ],
      ),
    ),
  );
}
```

---

## 📊 Bağlantı Durumları

### ✅ İnternet Bağlı (Yeşil)
- İnternet erişimi var
- Firebase çalışır
- Dış servisler erişilebilir
- Shelly cihazına bağlanabilir (aynı ağdaysa)

### ⚠️ WiFi Bağlı Ama İnternet Yok (Turuncu)
- WiFi ağına bağlı
- İnternet erişimi yok
- Firebase çalışmayabilir
- Shelly cihazına bağlanabilir (yerel ağ)

### ❌ Bağlantı Yok (Kırmızı)
- WiFi veya mobil veri yok
- İnternet erişimi yok
- Firebase çalışmaz
- Shelly cihazına bağlanılamaz

---

## 🔍 Shelly İçin Önemli Notlar

### Shelly Cihazına Bağlanmak İçin:
1. **WiFi Bağlantısı Gerekli**: Shelly cihazına bağlanmak için WiFi'ye bağlı olmalısınız
2. **İnternet Gerekmez**: Shelly cihazı yerel ağda olduğu için internet gerekmez
3. **Aynı Ağ**: Telefon ve Shelly aynı WiFi ağında olmalı

### Firebase İçin:
- **İnternet Gerekli**: Firebase'e veri kaydetmek için internet bağlantısı şarttır
- **WiFi Yeterli Değil**: Sadece WiFi'ye bağlı olmak yeterli değil, internet erişimi olmalı

---

## 🛠️ Örnek Kullanım Senaryoları

### Senaryo 1: İnternet Kontrolü Sonrası İşlem

```dart
Future<void> checkAndProceed() async {
  final connectivityService = ConnectivityService();
  final hasInternet = await connectivityService.checkInternetConnection();
  
  if (hasInternet) {
    // Firebase'e veri kaydet
    await saveToFirebase();
  } else {
    // Kullanıcıya uyarı göster
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('İnternet Bağlantısı Yok'),
        content: Text('Firebase\'e veri kaydedilemiyor. Lütfen internet bağlantınızı kontrol edin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
```

### Senaryo 2: Shelly İçin Bağlantı Kontrolü

```dart
Future<void> connectToShelly() async {
  final connectivityService = ConnectivityService();
  final status = await connectivityService.getConnectionStatus();
  
  if (status['hasWifi'] == true) {
    // WiFi bağlı, Shelly'ye bağlanabilir
    await apiService.initializeShelly(
      deviceIp: '192.168.1.100',
      deviceId: 'shelly_plug_001',
    );
  } else {
    // WiFi yok, uyarı göster
    showSnackBar('WiFi bağlantısı gerekli!');
  }
}
```

---

## ⚠️ Önemli Notlar

1. **İnternet vs WiFi**: 
   - WiFi bağlı olmak = İnternet bağlı olmak demek değildir
   - WiFi'ye bağlı olabilirsiniz ama internet erişimi olmayabilir

2. **Shelly İçin**:
   - Shelly cihazına bağlanmak için sadece WiFi gerekir
   - İnternet gerekmez (yerel ağ)

3. **Firebase İçin**:
   - Firebase'e veri kaydetmek için internet gerekir
   - WiFi yeterli değil, internet erişimi olmalı

4. **Mobil Veri**:
   - Mobil veri ile de internet erişimi olabilir
   - Ancak Shelly'ye bağlanmak için WiFi gerekir

---

## 🆘 Sorun Giderme

### Problem: "İnternet bağlantısı yok" ama WiFi bağlı
**Çözüm:**
- Router'ınızın internet bağlantısını kontrol edin
- DNS ayarlarını kontrol edin
- Farklı bir web sitesine erişmeyi deneyin

### Problem: "WiFi bağlı değil" ama WiFi açık
**Çözüm:**
- WiFi'yi kapatıp açın
- Farklı bir WiFi ağına bağlanmayı deneyin
- Uygulamayı yeniden başlatın

### Problem: Widget görünmüyor
**Çözüm:**
- Widget'ı doğru import ettiğinizden emin olun
- `ConnectionStatusWidget()` widget'ını eklediğinizden emin olun
- Uygulamayı yeniden başlatın

---

## 📱 Android İzinleri

Android için `AndroidManifest.xml` dosyasına şu izinleri ekleyin (zaten ekli olabilir):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

---

## ✅ Kontrol Listesi

Bağlantı kontrolü için:
- [ ] `connectivity_plus` paketi yüklü
- [ ] `ConnectionStatusWidget` import edildi
- [ ] Widget ekranda görünüyor
- [ ] İnternet bağlantısı test edildi
- [ ] WiFi bağlantısı test edildi

---

## 🎉 Hazırsınız!

Artık uygulamanızın internete bağlı olup olmadığını kolayca kontrol edebilirsiniz!

**Not**: Shelly cihazına bağlanmak için internet gerekmez, sadece WiFi bağlantısı yeterlidir. Ancak Firebase'e veri kaydetmek için internet gerekir.
