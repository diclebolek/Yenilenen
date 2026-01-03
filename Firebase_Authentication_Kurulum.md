# Firebase Authentication Kurulum Rehberi

Bu rehber, Firebase Authentication'ı Flutter uygulamanıza nasıl ekleyeceğinizi gösterir.

---

## 📋 İçindekiler

1. [Firebase Console'da Authentication'ı Etkinleştirme](#1-firebase-consoleda-authenticationı-etkinleştirme)
2. [Flutter'a firebase_auth Paketini Ekleme](#2-fluttera-firebase_auth-paketini-ekleme)
3. [Login Ekranını Güncelleme](#3-login-ekranını-güncelleme)
4. [Register Ekranını Güncelleme](#4-register-ekranını-güncelleme)
5. [Kullanım Örnekleri](#5-kullanım-örnekleri)

---

## 1. Firebase Console'da Authentication'ı Etkinleştirme

### Adım 1: Authentication'ı Açın

1. [Firebase Console](https://console.firebase.google.com/) → Projenizi seçin
2. Sol menüden **"Authentication"** seçin
3. **"Get started"** butonuna tıklayın

### Adım 2: Sign-in Method'u Etkinleştirin

1. **"Sign-in method"** sekmesine tıklayın
2. **"Email/Password"** seçeneğini tıklayın
3. **"Enable"** toggle'ını açın
4. **"Email link (passwordless sign-in)"** seçeneğini isterseniz açabilirsiniz (opsiyonel)
5. **"Save"** butonuna tıklayın

**Not:** Diğer sign-in method'ları (Google, Facebook, vs.) da ekleyebilirsiniz, ancak şu an için Email/Password yeterli.

---

## 2. Flutter'a firebase_auth Paketini Ekleme

`pubspec.yaml` dosyasına `firebase_auth` paketi zaten eklendi. Paketleri yükleyin:

```bash
flutter pub get
```

---

## 3. Login Ekranını Güncelleme

`lib/screens/login_screen.dart` dosyasını Firebase Authentication kullanacak şekilde güncelleyin.

### Seçenek 1: Sadece Firebase Authentication (Önerilen)

```dart
import '../services/firebase_auth_service.dart';

Future<void> _handleLogin() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isLoading = true;
  });

  try {
    // Firebase Authentication ile giriş
    await FirebaseAuthService.instance.signInWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    // Başarılı giriş
    widget.onLoginSuccess();
  } on FirebaseAuthException catch (e) {
    final errorMessage = FirebaseAuthService.instance.getAuthErrorMessage(e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Giriş sırasında hata oluştu: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
```

### Seçenek 2: Hibrit Yaklaşım (Firebase + PostgreSQL)

Önce Firebase Authentication ile giriş yap, başarısız olursa PostgreSQL'e düş:

```dart
try {
  // Önce Firebase Authentication ile dene
  try {
    await FirebaseAuthService.instance.signInWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    widget.onLoginSuccess();
  } catch (firebaseError) {
    // Firebase başarısız olursa PostgreSQL'e düş
    final userData = await PostgresService.instance.authenticateUser(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (userData != null) {
      widget.onLoginSuccess();
    } else {
      // Her iki yöntem de başarısız
      throw Exception('Giriş bilgileri hatalı');
    }
  }
} catch (e) {
  // Hata göster
}
```

---

## 4. Register Ekranını Güncelleme

`lib/screens/register_screen.dart` dosyasını Firebase Authentication kullanacak şekilde güncelleyin.

### Firebase Authentication ile Kayıt

```dart
import '../services/firebase_auth_service.dart';

Future<void> _handleRegister() async {
  if (!_formKey.currentState!.validate()) return;

  if (_selectedSektorId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lütfen bir sektör seçin'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    // 1. Firebase Authentication ile kullanıcı oluştur
    final userCredential = await FirebaseAuthService.instance.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    // 2. İsteğe bağlı: PostgreSQL'e de kaydet (işletme bilgileri için)
    try {
      final isletmeId = await PostgresService.instance.registerBusiness(
        businessName: _businessNameController.text.trim(),
        sektorId: _selectedSektorId!,
      );

      // Firebase UID'yi PostgreSQL'de saklayabilirsiniz
      // await PostgresService.instance.linkFirebaseUser(
      //   firebaseUid: userCredential.user!.uid,
      //   isletmeId: isletmeId,
      // );
    } catch (e) {
      // PostgreSQL hatası olsa bile Firebase kaydı başarılı
      print('PostgreSQL kayıt hatası: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kayıt başarılı! Giriş yapabilirsiniz.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.of(context).pop();
    }
  } on FirebaseAuthException catch (e) {
    final errorMessage = FirebaseAuthService.instance.getAuthErrorMessage(e);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kayıt sırasında hata oluştu: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
```

---

## 5. Kullanım Örnekleri

### Mevcut Kullanıcıyı Kontrol Etme

```dart
final authService = FirebaseAuthService.instance;
final currentUser = authService.currentUser;

if (currentUser != null) {
  print('Kullanıcı giriş yapmış: ${currentUser.email}');
} else {
  print('Kullanıcı giriş yapmamış');
}
```

### Kullanıcı Durumunu Dinleme

```dart
StreamBuilder<User?>(
  stream: FirebaseAuthService.instance.authStateChanges,
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data != null) {
      // Kullanıcı giriş yapmış
      return HomeScreen();
    } else {
      // Kullanıcı giriş yapmamış
      return LoginScreen();
    }
  },
)
```

### Şifre Sıfırlama

```dart
try {
  await FirebaseAuthService.instance.sendPasswordResetEmail(email);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Şifre sıfırlama e-postası gönderildi'),
      backgroundColor: Colors.green,
    ),
  );
} on FirebaseAuthException catch (e) {
  final errorMessage = FirebaseAuthService.instance.getAuthErrorMessage(e);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(errorMessage),
      backgroundColor: Colors.red,
    ),
  );
}
```

### Çıkış Yapma

```dart
await FirebaseAuthService.instance.signOut();
Navigator.of(context).pushReplacement(
  MaterialPageRoute(builder: (context) => LoginScreen()),
);
```

---

## 🔐 Güvenlik Notları

1. **Şifre Gereksinimleri:** Firebase Authentication minimum 6 karakter şifre ister. Daha güçlü şifre politikaları için Firebase Console'da ayarlayabilirsiniz.

2. **E-posta Doğrulama:** Kullanıcı kaydından sonra e-posta doğrulama gönderebilirsiniz:
   ```dart
   await FirebaseAuthService.instance.sendEmailVerification();
   ```

3. **Session Yönetimi:** Firebase Authentication otomatik olarak session yönetir. Kullanıcı çıkış yapana kadar giriş kalır.

---

## ✅ Kontrol Listesi

- [ ] Firebase Console'da Authentication etkinleştirildi
- [ ] Email/Password sign-in method etkinleştirildi
- [ ] `firebase_auth` paketi eklendi ve yüklendi
- [ ] `FirebaseAuthService` oluşturuldu
- [ ] Login ekranı güncellendi
- [ ] Register ekranı güncellendi
- [ ] Hata mesajları Türkçe'ye çevrildi
- [ ] Test edildi

---

## 🆘 Sorun Giderme

### "Email already in use" hatası

**Çözüm:** Bu e-posta adresi zaten kayıtlı. Giriş yapmayı deneyin veya farklı bir e-posta kullanın.

### "Weak password" hatası

**Çözüm:** Şifre en az 6 karakter olmalıdır. Daha güçlü bir şifre kullanın.

### "User not found" hatası

**Çözüm:** Bu e-posta adresine kayıtlı kullanıcı yok. Önce kayıt olun.

---

## 📚 Kaynaklar

- [Firebase Authentication Dokümantasyonu](https://firebase.google.com/docs/auth)
- [FlutterFire Auth Dokümantasyonu](https://firebase.flutter.dev/docs/auth/overview)

