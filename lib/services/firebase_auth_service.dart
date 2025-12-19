import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as dev;

/// Firebase Authentication servisi - Kullanıcı girişi ve kayıt işlemleri
class FirebaseAuthService {
  static FirebaseAuthService? _instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  FirebaseAuthService._();

  static FirebaseAuthService get instance {
    _instance ??= FirebaseAuthService._();
    return _instance!;
  }

  /// Mevcut kullanıcıyı getir
  User? get currentUser => _auth.currentUser;

  /// Kullanıcı durumunu dinle (Stream)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// E-posta ve şifre ile kayıt ol
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      dev.log(
        'Kullanıcı kaydı başarılı: ${userCredential.user?.email}',
        name: 'FirebaseAuthService',
      );

      return userCredential;
    } on FirebaseAuthException catch (e) {
      dev.log(
        'Firebase kayıt hatası: ${e.code} - ${e.message}',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    } catch (e) {
      dev.log('Kayıt hatası: $e', name: 'FirebaseAuthService', level: 1000);
      rethrow;
    }
  }

  /// E-posta ve şifre ile giriş yap
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      dev.log(
        'Kullanıcı girişi başarılı: ${userCredential.user?.email}',
        name: 'FirebaseAuthService',
      );

      return userCredential;
    } on FirebaseAuthException catch (e) {
      dev.log(
        'Firebase giriş hatası: ${e.code} - ${e.message}',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    } catch (e) {
      dev.log('Giriş hatası: $e', name: 'FirebaseAuthService', level: 1000);
      rethrow;
    }
  }

  /// Çıkış yap
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      dev.log('Kullanıcı çıkışı başarılı', name: 'FirebaseAuthService');
    } catch (e) {
      dev.log('Çıkış hatası: $e', name: 'FirebaseAuthService', level: 1000);
      rethrow;
    }
  }

  /// Şifre sıfırlama e-postası gönder
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      dev.log(
        'Şifre sıfırlama e-postası gönderildi: $email',
        name: 'FirebaseAuthService',
      );
    } on FirebaseAuthException catch (e) {
      dev.log(
        'Şifre sıfırlama hatası: ${e.code} - ${e.message}',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    } catch (e) {
      dev.log(
        'Şifre sıfırlama hatası: $e',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    }
  }

  /// E-posta doğrulama gönder
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        dev.log(
          'E-posta doğrulama gönderildi: ${user.email}',
          name: 'FirebaseAuthService',
        );
      }
    } catch (e) {
      dev.log(
        'E-posta doğrulama hatası: $e',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Şifre güncelle
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Mevcut şifreyi doğrula
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Yeni şifreyi güncelle
      await user.updatePassword(newPassword);

      dev.log('Şifre güncellendi', name: 'FirebaseAuthService');
    } on FirebaseAuthException catch (e) {
      dev.log(
        'Şifre güncelleme hatası: ${e.code} - ${e.message}',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    } catch (e) {
      dev.log(
        'Şifre güncelleme hatası: $e',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    }
  }

  /// E-posta güncelle
  Future<void> updateEmail(String newEmail) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      await user.verifyBeforeUpdateEmail(
        newEmail,
      ); // Yeni e-posta için doğrulama gönder

      dev.log('E-posta güncellendi: $newEmail', name: 'FirebaseAuthService');
    } on FirebaseAuthException catch (e) {
      dev.log(
        'E-posta güncelleme hatası: ${e.code} - ${e.message}',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    } catch (e) {
      dev.log(
        'E-posta güncelleme hatası: $e',
        name: 'FirebaseAuthService',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Firebase Auth hata mesajlarını Türkçe'ye çevir
  String getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Şifre çok zayıf. En az 6 karakter olmalıdır.';
      case 'email-already-in-use':
        return 'Bu e-posta adresi zaten kullanılıyor.';
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'user-not-found':
        return 'Bu e-posta adresine kayıtlı kullanıcı bulunamadı.';
      case 'wrong-password':
        return 'Hatalı şifre.';
      case 'user-disabled':
        return 'Bu kullanıcı hesabı devre dışı bırakılmış.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin.';
      case 'operation-not-allowed':
        return 'Bu işlem şu anda izin verilmiyor.';
      case 'requires-recent-login':
        return 'Bu işlem için tekrar giriş yapmanız gerekiyor.';
      default:
        return 'Bir hata oluştu: ${e.message ?? e.code}';
    }
  }
}
