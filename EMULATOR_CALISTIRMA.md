# Emülatörde Uygulamayı Çalıştırma Rehberi

## 📱 Adım 1: Emülatörü Başlat

### Terminal ile (Hızlı):
```bash
# Mevcut emülatörleri listele
flutter emulators

# Bir emülatör başlat (örnek: Pixel 7)
flutter emulators --launch Pixel_7
```

### Android Studio ile:
1. Android Studio'yu açın
2. Sağ üstteki **Device Manager** ikonuna tıklayın
3. Bir emülatör seçin (örn: Pixel 7)
4. **▶️ Play** butonuna tıklayın

### VS Code ile:
1. VS Code'da **Ctrl+Shift+P** (veya **Cmd+Shift+P**)
2. "Flutter: Launch Emulator" yazın
3. Bir emülatör seçin

---

## 📶 Adım 2: Emülatörü Hotspot'a Bağla

1. **Emülatör açıldıktan sonra:**
   - Emülatörde **Settings** (Ayarlar) uygulamasını açın
   - **Network & Internet** > **WiFi** seçin
   - PC'nizin oluşturduğu **hotspot**'u bulun
   - Hotspot adı genellikle "DESKTOP-XXXXX" veya belirlediğiniz isim
   - Şifreyi girip **Connect** (Bağlan) butonuna tıklayın

2. **IP adresini kontrol edin:**
   - Bağlı WiFi ağının üzerine tıklayın
   - IP adresi görünecek (örn: `192.168.137.150`)
   - IP adresi `192.168.137.x` aralığında olmalı

---

## 🚀 Adım 3: Uygulamayı Çalıştır

### Terminal ile:
```bash
# Emülatör başladıktan sonra
flutter run
```

### VS Code ile:
1. **F5** tuşuna basın VEYA
2. **Run** > **Start Debugging** menüsünden
3. VEYA sağ üstteki **▶️ Run** butonuna tıklayın

### Android Studio ile:
1. **Run** > **Run 'main.dart'** menüsünden
2. VEYA yeşil **▶️ Run** butonuna tıklayın

---

## ✅ Adım 4: Bağlantıyı Kontrol Et

Uygulama açıldıktan sonra:

1. **Home Screen**'e gidin
2. **Shelly cihazı** otomatik olarak bağlanmaya çalışacak
3. Konsol çıktısını kontrol edin:
   - ✅ "Shelly verisi başarıyla alındı!" mesajı görünmeli
   - ❌ Hata varsa, IP adresini kontrol edin

---

## 🔧 Sorun Giderme

### Emülatör WiFi'ye bağlanamıyorsa:
- Emülatör ayarlarından WiFi'yi manuel açın
- Hotspot şifresini doğru girdiğinizden emin olun
- PC'nin hotspot'unun aktif olduğunu kontrol edin

### Uygulama çalışmıyorsa:
```bash
# Bağımlılıkları yükle
flutter pub get

# Temizle ve yeniden derle
flutter clean
flutter pub get
flutter run
```

### Shelly bağlanamıyorsa:
- Shelly cihazının IP adresini kontrol edin (192.168.137.232)
- Emülatör ve Shelly aynı hotspot'a bağlı olmalı
- Windows Firewall'u geçici olarak kapatıp deneyin

---

## 📝 Hızlı Komutlar

```bash
# Emülatörleri listele
flutter emulators

# Emülatör başlat
flutter emulators --launch Pixel_7

# Uygulamayı çalıştır
flutter run

# Bağlı cihazları listele
flutter devices

# Hot reload (kod değişikliğinde)
# Terminal'de 'r' tuşuna basın

# Hot restart (uygulamayı yeniden başlat)
# Terminal'de 'R' tuşuna basın
```

---

## 🎯 Özet

1. ✅ Emülatörü başlat (`flutter emulators --launch Pixel_7`)
2. ✅ Emülatörü hotspot'a bağla (Settings > WiFi)
3. ✅ Uygulamayı çalıştır (`flutter run`)
4. ✅ Shelly bağlantısını kontrol et

**Not:** Emülatör başladıktan sonra WiFi'ye bağlanması 10-30 saniye sürebilir.

