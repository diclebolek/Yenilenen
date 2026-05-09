# Git: commit ve push (bu proje)

Bu dosya, depoda yapılan değişiklikleri kayıt altına alıp GitHub’a gönderme akışını özetler. Cursor içindeki otomatik işlemlerde de aynı komutlar kullanılır; yalnızca çalışma dizininiz proje kökü olmalıdır.

## Önkoşul

- Bilgisayarda Git yüklü ve `git` PATH’te.
- Depo bir uzak uç noktaya bağlı (ör. `origin` → GitHub).

## Değişiklikleri kaydetmek (commit)

1. Durumu görün:

   ```powershell
   git status
   ```

2. İstediğiniz dosyaları sahneye alın:

   ```powershell
   git add yol/dosya.dart
   ```

   Tüm izlenen değişiklikler için:

   ```powershell
   git add -u
   ```

3. Anlamlı bir mesajla commit oluşturun:

   ```powershell
   git commit -m "Kısa açıklama: ne değişti"
   ```

## Uzak depoya göndermek (push)

Varsayılan dal `main` ise:

```powershell
git push origin main
```

İlk kez dal oluşturuyorsanız veya upstream ayarı gerekiyorsa Git çıktısındaki öneriyi kullanın (ör. `git push -u origin main`).

## Bu projede sık kullanılan doğrulama

Commit öncesi Dart analizi:

```powershell
dart analyze
```

---

*Not: AI asistan oturumlarında yapılan push, yukarıdaki `git add` / `git commit` / `git push` adımlarının aynı şekilde terminalde çalıştırılmasıdır; özel bir “push aracı” yoktur.*
