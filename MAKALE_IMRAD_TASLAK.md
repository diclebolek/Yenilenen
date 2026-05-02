# İşletme Odaklı Karbon Ayak İzi İzleme ve Hesaplama Uygulaması: Çok Platformlu Bir Yazılım Mimarisi

**IMRAD yapısında makale taslağı**  
*(Bu metin, bitirme projesi veya dergi gönderisi için düzenlenebilir; yazar adları, kurum ve etik onay bilgileri eklenmelidir.)*

---

## Özet

İklim değişikliğine ilişkin politika ve raporlama çerçevelerinde, sera gazı emisyonlarının **karbon dioksit eşdeğeri (CO₂e)** cinsinden izlenmesi yaygın bir beklenti olarak öne çıkmaktadır. Bu çalışmada, küçük ve orta ölçekli işletme bağlamında tüketim verilerinin toplanması, emisyonların hesaplanması, görselleştirilmesi, **dışa aktarılabilir raporlama** ve **kısa vadeli tahmin (projeksiyon)** sunulması amacıyla geliştirilmiş **çok platformlu (web ve mobil)** bir uygulama mimarisi anlatılmaktadır. Yazılım, **Flutter** çatısı ile tek kod tabanından **Android, iOS ve web** hedeflerine derlenebilmekte; kimlik doğrulama ve gerçek zamanlı veri için **Firebase** bileşenleri, isteğe bağlı kurumsal kayıt için **HTTP üzerinden PostgreSQL API** erişimi ve sensör verisi için **ESP8266** ile **Shelly Plug S** entegrasyonu kullanılmaktadır. Emisyon hesapları, aktivite verisi × emisyon faktörü biçiminde, **GHG Protocol** ve **ISO 14064** ile uyumlu düşünülebilecek bir yaklaşımla yapılandırılmıştır; faktör değerleri literatürdeki bantlarla karşılaştırıldığında, elektrik şebeke faktörünün tekil bir sabitle temsil edildiği ve yıllık güncellemeye açık olduğu belirtilmektedir. Arayüz metinleri **Türkçe ve İngilizce** olacak şekilde yerelleştirilebilmekte; **PDF karbon raporu** üretiminde de dil (**TR/EN**) kullanıcı tarafından seçilebilmektedir. **Ay sonu CO₂e tahmini**, son günlük seriden türetilen tempo ile hesaplanmakta; CO₂ azaltım hedefi ile karşılaştırma ve Our World in Data tabanlı küresel günlük referansla bağlamsal yorum içerebilmektedir. Sonuç bölümünde, sistemin güçlü yönleri ile ölçüm hataları, faktör seçimi ve kapsam sınırları gibi **belirsizlik kaynakları** tartışılmaktadır.

**Anahtar kelimeler:** Karbon ayak izi, CO₂e, GHG Protocol, Flutter, Firebase, IoT, çok platformlu uygulama, işletme emisyonları

---

## 1. Giriş (Introduction)

### 1.1. Konunun bağlamı

Antropojenik sera gazı emisyonlarının azaltılması, hem ulusal envanterler hem de kurumsal sürdürülebilirlik raporları açısından giderek daha fazla önem kazanmaktadır. **GHG Protocol** çerçevesinde, emisyonlar genellikle **Kapsam 1** (doğrudan), **Kapsam 2** (satın alınan enerji ile ilişkili dolaylı) ve **Kapsam 3** (tedarik zinciri vb. diğer dolaylı) olarak sınıflandırılmaktadır. **ISO 14064** serisi ise sera gazı envanterinin ve doğrulamanın nasıl yönetilebileceğine dair rehberlik sunmaktadır. Bu çalışma, söz konusu çerçevelerin tüm gerekliliklerini iddia etmemekle birlikte, hesaplama mantığını bu literatürle **örtüşecek** şekilde kurgulamayı amaçlamaktadır.

### 1.2. Problem ve motivasyon

Küçük işletmelerde (örneğin hizmet sektörü) elektrik, su, ısınma için doğal gaz ve atık gibi girdiler sıklıkla fatura veya sayaçlar üzerinden izlenebilmektedir. Bununla birlikte, verilerin **anlık** toplanması, görselleştirilmesi ve kullanıcıya anlaşılır biçimde sunulması teknik altyapı gerektirmektedir. Literatürde karbon ayak izi veya enerji izleme amaçlı mobil ve web uygulamaları; farklı sektörlerde, farklı veri kaynakları ve farklı emisyon faktörleriyle örneklenebilmektedir. Bu proje, **manuel veri girişi**, **optik karakter tanıma (OCR) ile fatura okuma**, **IoT sensörleri** ve **akıllı priz** üzerinden ölçüm gibi birden fazla veri kanalını tek uygulama içinde birleştirmeyi hedeflemektedir.

### 1.3. Çalışmanın kapsamı ve sınırları

Çalışma, geliştirilen yazılımın **mimarisini**, **kullanılan formülleri ve faktörlerin kaynaklandırılmasını** ve **literatür ve benzer uygulamalarla karşılaştırmalı** olarak tartışmayı kapsamaktadır. Saha ölçümü, istatistiksel hipotez testi veya karbon denetimi düzeyinde doğrulama **bu makalenin kapsamı dışında** bırakılmıştır; elde edilen emisyon rakamlarının “kesin doğruluk” taşıdığı iddia edilmemektedir.

### 1.4. Makalenin organizasyonu

İkinci bölümde materyal ve yöntem (yazılım mimarisi, veri akışı, formüller) açıklanmakta; üçüncü bölümde sistemin işlevsel çıktıları özetlenmekte; dördüncü bölümde literatürle karşılaştırma ve tartışma; beşinci bölümde ise sonuç ve öneriler sunulmaktadır.

---

## 2. Materyal ve Yöntem (Materials and Methods)

### 2.1. Yazılım yığını ve sürümler

Uygulama **Dart** dili ve **Flutter** çatısı ile geliştirilmiştir (`sdk: '>=3.0.0 <4.0.0'`). Arayüz için **Material 3** tasarım ilkeleri kullanılmaktadır. Grafik bileşenleri için **fl_chart** kütüphanesi tercih edilmiştir. **PDF** üretimi ve tarayıcı/istemci yazdırma akışı için **pdf** ve **printing** paketleri kullanılmaktadır (Unicode/Türkçe karakterler için gömülü yazı tipi teması). Durum yönetimi için **provider** paketinden yararlanılmaktadır. Kimlik doğrulama ve bulutta veri için **Firebase Authentication** ile **Firebase Realtime Database** entegrasyonu bulunmaktadır. İsteğe bağlı olarak, yerel veya uzak bir **HTTP API** (`http://localhost:3000/api` varsayılanı) üzerinden **PostgreSQL** ile etkileşim hedeflenmiştir; bağlantı başarısız olsa bile uygulamanın çalışmaya devam edeceği şekilde hata toleransı kodlanmıştır. Ağ işlemleri için **http** paketi; bağlantı durumu için **connectivity_plus** kullanılmaktadır. Görüntüden metin çıkarma amacıyla **Google ML Kit Text Recognition** ve **image_picker** bileşenleri yer almaktadır.

### 2.2. Çok platformlu dağıtım

**Tek kod tabanı** ile **Android**, **iOS**, **web** ve (projede yapılandırılmışsa) masaüstü hedefleri üretilebilmektedir. Web için **Firebase Hosting** yapılandırması (`firebase.json`) ile tek sayfa uygulama yönlendirmesi tanımlanmıştır. Ayrıca, çok aşamalı bir **Docker** görüntüsü ile `flutter build web --release` çıktısının **nginx** üzerinden sunulması mümkündür (`Dockerfile`: Flutter derleme aşaması + `nginx:alpine` çalışma aşaması; `docker-compose.yml` ile örneğin **8080** bağlantı noktası üzerinden erişim). Bu, kurumsal veya demo ortamında web istemcisinin tutarlı biçimde paketlenmesine olanak tanır. Arayüz, ekran genişliğine göre **kompakt** (yaklaşık 1100 piksel altı) ve **geniş** düzen arasında ayrışmaktadır; örneğin ayarlar sekmesi dar ekranlarda alt gezinme yerine yan panel diyalog ile sunulabilmektedir. Bu yaklaşım, mobil tarayıcı ve masaüstü web için uyumlu bir deneyim hedeflemektedir; ancak tüm cihazlarda aynı kullanılabilirliğin sağlandığı **garanti edilmemelidir** (tarayıcı, işletim sistemi ve donanım farklılıklarına bağlı değişkenlik söz konusu olabilir).

### 2.3. Dil yerelleştirmesi (Türkçe / İngilizce)

Uygulama metinleri, merkezi bir **çeviri sözlüğü** (`translations.dart`) üzerinden yönetilmektedir. `LanguageProvider` bileşeni, `SharedPreferences` ile seçilen dili kalıcı olarak saklamaktadır. Varsayılan dil **Türkçe** iken, kullanıcı tercihi ile **İngilizce** arayüz seçilebilmektedir. Bu durum, uluslararası okuyucular veya İngilizce raporlama ihtiyacı olan işletmeler için uygun görülebilir; çevirilerin bilimsel terimlerde tam denkliği her zaman sağlanmayabilir, bu nedenle kritik raporlarda uzman gözden geçirilmesi **önerilebilir**.

### 2.4. Sistem mimarisi (yüksek seviye)

**İstemci tarafı** Flutter uygulaması; **kimlik** için Firebase Auth; **gerçek zamanlı tüketim ve cihaz verileri** için Firebase Realtime Database; **harici sensör ve cihazlar** için HTTP (ESP8266 REST), Shelly HTTP/WebSocket ve üçüncü parti **açık veri** (Our World in Data JSON) kaynakları kullanılmaktadır. Uygulama içi hafif durum için `DatabaseService` adlı **bellek içi** bir önbellek kullanılabilmekte; kalıcı işletme verisi ise öncelikle Firebase ve isteğe bağlı PostgreSQL API ile ilişkilendirilmektedir.

Şema benzeri özet (metinsel):

```
[Kullanıcı] → [Flutter istemci]
                 ↓
    ┌────────────┼────────────┐
    ↓            ↓            ↓
[Firebase Auth] [Realtime DB] [HTTP: ESP / Shelly / OWID / Open-Meteo]
    ↓
[İsteğe bağlı: REST API → PostgreSQL]
```

### 2.5. Veri modeli ve emisyon hesaplama formülleri

Temel tüketim kaydı `ConsumptionEntry` modeli ile temsil edilmektedir: elektrik (kWh), su (m³), yakıt (alan adı `fuelLiters` olmakla birlikte **doğal gaz için m³** veya **sıvı yakıt için litre** anlamında kullanılabilmektedir), atık (kg) ve zaman damgası. Yakıt biriminin karışmaması için `fuelIsNaturalGasM3` bayrağı ile ayrım yapılmaktadır.

**Toplam günlük emisyon (kg CO₂e)** aşağıdaki toplama ile ifade edilebilir:

\[
E_{\mathrm{toplam}} = E_{\mathrm{el}} + E_{\mathrm{yakıt}} + E_{\mathrm{su}} + E_{\mathrm{atık}}
\]

Elektrik için:

\[
E_{\mathrm{el}} = Q_{\mathrm{kWh}} \times \mathrm{EF}_{\mathrm{el}}
\]

Doğal gaz (m³) için:

\[
E_{\mathrm{gaz}} = V_{\mathrm{m^3}} \times \mathrm{EF}_{\mathrm{NG}}
\]

Sıvı motor yakıtı (litre) için:

\[
E_{\mathrm{sıvı}} = V_{\mathrm{L}} \times \mathrm{EF}_{\mathrm{mot}}
\]

Su ve atık için sırasıyla:

\[
E_{\mathrm{su}} = V_{\mathrm{su,m^3}} \times \mathrm{EF}_{\mathrm{su}}, \quad
E_{\mathrm{atık}} = m_{\mathrm{atık}} \times \mathrm{EF}_{\mathrm{atık}}
\]

Projede kullanılan **örnek sabitler** (kod tabanından):  
\(\mathrm{EF}_{\mathrm{el}} = 0{,}233\) kg CO₂e/kWh; \(\mathrm{EF}_{\mathrm{NG}} = 2{,}02\) kg CO₂e/m³; \(\mathrm{EF}_{\mathrm{mot}} = 2{,}31\) kg CO₂e/L; \(\mathrm{EF}_{\mathrm{su}} = 0{,}344\) kg CO₂e/m³; \(\mathrm{EF}_{\mathrm{atık}} = 1{,}9\) kg CO₂e/kg.

Bu değerlerin her biri, ulusal envanterler, IPCC kılavuzları veya sektörel ortalamalarla **genellikle uyumlu bantlar** içinde düşünülebilir; özellikle \(\mathrm{EF}_{\mathrm{el}}\) için Türkiye şebeke karışımına ilişkin literatürde daha yüksek aralıklar da raporlanabildiğinden, tek bir sabitin “tek doğru” değer olduğu **söylenmemelidir**. Faktörlerin yıllık güncellenmesi ve kurumsal raporlama gereksinimlerine göre seçilmesi önerilmektedir.

### 2.6. IoT ve gerçek zamanlı veri

**ESP8266** modülü, HTTP üzerinden `/api/consumption` uç noktasından JSON okunacak şekilde tasarlanmıştır; gaz tüketimi `gas_consumption_m3` veya `fuel` alanlarından, su ise litre veya m³ alanlarından türetilebilmektedir. Veriler isteğe bağlı olarak Firebase’e yazılmaktadır. **Shelly Plug S** ile elektrik tüketimi (kWh) izlenebilmekte; rapor ekranında ESP ile Shelly verilerinin birleştirilmesi gibi senaryolar kodda ele alınmaktadır.

### 2.7. Küresel karşılaştırma verileri

`GlobalCarbonService`, Our World in Data’nın açık **JSON** veri kümesinden ülke ve dünya düzeyinde eğilimleri çekmeye çalışmaktadır. Ağ hatalarında yer tutucu (placeholder) dizilere dönülebilmektedir. Bu bölüm, bilimsel ölçüm değil, **bağlamsal karşılaştırma** amacı taşımaktadır.

### 2.8. Ek özellikler (kısa)

- **Fatura tarama (OCR):** ML Kit ile metin çıkarımı ve düzenli ifadelerle kWh, m³ vb. alanların parse edilmesi.  
- **Hava durumu:** `WeatherService` ile üçüncü parti API (ör. Open-Meteo) kullanımı projede tanımlanmıştır.  
- **Hedefler (Goals):** Firebase üzerinden hedef takibi; bazı hedef türlerinde aylık tüketim veya emisyon farkına dayalı ilerleme güncellemesi. Son sürümde sabit hedefler yerine, son üç ay eğilimine bağlı **dinamik hedef** üretimi ve hedefin gerisinde kalındığında saat bazlı tüketim yoğunluğuna göre **otomatik öneri** metinleri (ör. belirli saatlerde %X azaltım) eklenmiştir.  
- **PDF raporlama (Raporlar ekranı):** Kullanıcı, **haftalık** veya **aylık** karbon özetini ISO 14064 düşüncesine uygun **sade bir metin özetine** göre PDF olarak dışa aktarabilmektedir. Rapor; dönem etiketi, üretim zamanı, toplam ve ortalama kg CO₂e, kısa metodoloji ve kapsam notları, kategori dağılım tablosu ve sorumluluk reddi metnini içermektedir. Rapor dili, uygulama dilinden bağımsız olarak **Türkçe** veya **İngilizce** seçilebilmekte; böylece karanlık tema veya genel arayüz dili ile çakışma azaltılmaya çalışılmıştır. Aylık PDF için haftalık toplamlardan türetilmiş bir ölçekleme kullanıldığı (ör. haftalık toplam × 4) kodda tercih edilmiştir; bu, “kesin aylık envanter” yerine **hızlı özet** niteliğindedir.  
- **Tahminleme / projeksiyon (Hedefler ekranı):** **Ay sonu CO₂e projeksiyonu**, ay başından bugüne kadar **manuel + ESP8266 + Shelly** verilerinin birleştirildiği günlük toplamlar üzerinden, **son 7 gün** için tahmini günlük ortalamaya dayalı olarak hesaplanmaktadır (projeksiyon ≈ günlük ortalama × ayın gün sayısı). Sonuç, kullanıcının **CO₂ azaltım hedefi** (kg, ay sonu) ile karşılaştırılarak “hedefte / hedef üzerinde” durumu metin ve gösterge ile sunulmaktadır. Ek olarak, Our World in Data eğiliminden türetilen **küresel günlük referans** ile kullanıcı temposu kıyaslanabilmekte; mümkün olduğunda **son 7 gün ile önceki 7 gün** karşılaştırması (ESP ağırlıklı veya birleşik seri) ile haftadan haftaya değişim yüzdesi açıklanabilmektedir. Hedef temposunun üzerinde kalındığında, bekleme tüketimi azaltımına yönelik **sayısal ipucu** (kg CO₂e cinsinden düşük güvenilirlikli tahmin) üretilebilmektedir.  
- **Enerji verimliliği algoritmaları:** `EnergyEfficiencyAlgorithm` ve tarife benzeri saat katsayıları ile gelişmiş analiz yolları kodda bulunmaktadır; kullanıcı arayüzünde ne ölçüde görünür olduğu sürüme bağlı olabilir.

---

## 3. Bulgular (Results)

Bu bölüm deneysel istatistik yerine, geliştirilen sistemin **işlevsel özellikleri** açısından özetlenmektedir.

### 3.1. Uygulama modülleri

- **Kimlik ve oturum:** Giriş ve kayıt ekranları; Firebase Authentication ile e-posta tabanlı akış.  
- **Ana sayfa:** İklim/hava ve bilgilendirici bileşenler; işletme veya kampanya odaklı içerikler.  
- **Raporlar:** Günlük emisyon göstergesi, manuel / ESP veri seçimi, grafikler, IoT kartları (ESP anlık veriler, Shelly), küresel/kişisel trend karşılaştırması; **haftalık/aylık PDF dışa aktarımı** (dil seçimi TR/EN), ISO uyumlu özet metinleri ve kategori tablosu.  
- **Hedefler:** Kullanıcı hedeflerinin listelenmesi ve kısmen otomatik güncellenmesi; **ay sonu CO₂e tahmini**, hedefe göre izleme çizgisi, küresel günlük referansla karşılaştırma ve haftalık değişim açıklamaları.  
- **Ayarlar:** Tema, dil, yazı boyutu, profil ayarları.

### 3.2. Çok dillilik ve arayüz

Türkçe ve İngilizce dil seçimi, uygulama genelinde `translate(anahtar, locale)` deseni ile uygulanmaktadır. Bu yapı, yeni dillerin eklenmesine de imkân tanımaktadır.

### 3.3. Hesaplama çıktısı

Tüketim girdileri ve seçilen emisyon faktörleri ile **kg CO₂e** cinsinden toplam ve kategori dağılımları üretilebilmektedir. Gösterim birimi, değerin büyüklüğüne göre gram, kilogram veya ton CO₂e olarak ölçeklenebilmektedir (kullanıcı arayüzü mantığı).

Son güncellemelerle birlikte çıktılar yalnızca anlık/günlük raporlamayla sınırlı kalmamış; (i) haftalık ve aylık **PDF** dışa aktarımı (bağımsız dil seçimi), (ii) hedef modülünde **son 7 gün temposuna** dayalı ay sonu projeksiyonu ve hedef ile uyum göstergesi, (iii) Our World in Data tabanlı **küresel günlük** referansla kullanıcı temposunun kıyası ve (iv) mümkün olduğunda **son 7 gün / önceki 7 gün** haftalık değişim metni gibi öngörü ve raporlama bileşenleri kullanıcıya sunulmuştur.

---

## 4. Tartışma (Discussion)

### 4.1. Literatür ve benzer çalışmalarla karşılaştırma

Karbon ayak izi hesaplama uygulamaları literatürde; **ev kullanıcıları**, **şehir ölçeği**, **endüstriyel tesisler** veya **belirli sektörler** için ayrı ayrı raporlanabilmektedir. Bu proje, **işletme / kuaför veya benzeri hizmet ortamı** bağlamında **manuel + IoT + OCR** kombinasyonunu tek istemcide toplamayı hedeflemektedir. Literatürdeki birçok çalışmada olduğu gibi, emisyon faktörlerinin **tekil sabit** olarak kullanılması, bölgesel şebeke farklılıklarını veya tedarikçi bazlı faktörleri tam yansıtmayabilir. Bu nedenle sonuçlar, **yönetsel karar** için tam bir envanter yerine **gösterge** niteliğinde değerlendirilebilir.

### 4.2. GHG Protocol ve ISO 14064 ile ilişki

Hesaplama mantığı, “aktivite × faktör” ilkesi ile GHG Protocol’ün düşünce yapısı ile **uyumludur** denilebilir; ancak Kapsam 3’ün tamamı, ürün düzeyi LCA veya tedarik zinciri detayı bu uygulamada **sınırlı veya dışlanmış** olabilir. ISO 14064 uyumluluğu için resmi doğrulama süreçleri ayrıca yürütülmelidir.

### 4.3. Veri tabanı ve altyapı seçimleri

Firebase Realtime Database, düşük gecikmeli senkronizasyon için uygundur; ölçek, güvenlik kuralları ve maliyet projeye göre değerlendirilmelidir. PostgreSQL tarafı, HTTP API ile soyutlandığından, mobil istemcinin doğrudan SQL protokolü kullanması gerekmemektedir. Bu, güvenlik açısından olumlu görülebilir; öte yandan API katmanının sürdürülmesi gereklidir.

### 4.4. Güçlü yönler

- Tek kod tabanı ile **web ve mobil** dağıtım; isteğe bağlı **Docker** ile web ön yüzünün statik barındırılması.  
- **İki dil** desteği ve genişletilebilir çeviri yapısı; PDF raporunda **ayrı dil seçimi**.  
- **ESP8266** ve **Shelly** ile ölçüm kanalı çeşitliliği.  
- **OWID** gibi açık veri ile küresel bağlam sunma çabası; hedef ekranında tahmin ve karşılaştırma ile birleştirilmesi.  
- **PDF raporlama** ve **ay sonu projeksiyonu** ile yönetişim odaklı çıktılar.

### 4.5. Sınırlılıklar ve belirsizlikler

- Emisyon faktörleri sabit ve **zaman içinde güncellenmeyebilir**.  
- Elektrik faktörü, literatürdeki ülke ortalaması ile **tam örtüşmeyebilir**.  
- OCR ile fatura okuma, görüntü kalitesine bağlı **hata** riski taşır.  
- IoT ölçümleri sensör kalibrasyonu ve ağ kesintilerinden etkilenebilir.  
- “Kişi başı” veya “işletme başı” karşılaştırmalarında sınır koşullarının net tanımı her zaman yapılmamış olabilir.

Bu sınırlılıklar, sonuçların **kesin** olduğu şeklinde yorumlanmaması gerektiğini düşündürmektedir.

---

## 5. Sonuç ve Öneriler (Conclusion)

Bu çalışmada, karbon ayak izinin izlenmesi için **Flutter** tabanlı, **Firebase** ve isteğe bağlı **PostgreSQL API** ile desteklenen, **Türkçe/İngilizce** arayüze sahip ve **web ile mobil** istemcilerde çalışabilen bir mimari anlatılmıştır. Emisyonlar, CO₂e cinsinden, aktivite verilerinin emisyon faktörleri ile çarpımına dayalı olarak hesaplanmaktadır; doğal gaz ve sıvı yakıt birimleri ayrıştırılmaya çalışılmıştır. Uygulama, **haftalık/aylık PDF raporu** ve **Hedefler** bölümünde **ay sonu projeksiyonu** ile raporlama ve öngörü kapasitesini genişletmiştir. Literatürdeki benzer sistemlerle karşılaştırıldığında, IoT ve OCR entegrasyonunun bir arada sunulması ile birlikte **dışa aktarılabilir rapor** ve **kısa vadeli tahmin** bileşenleri uygulamanın ayırt edici yönleri arasında sayılabilir.

Gelecek çalışmalar için şunlar **önerilebilir**: (i) elektrik faktörünün yıllık resmi verilerle güncellenmesi, (ii) kullanıcı testleri ile arayüz ve anlaşılabilirlik değerlendirmesi, (iii) ölçüm doğruluğu için kalibrasyon prosedürlerinin dokümante edilmesi, (iv) kurumsal raporlama için **CSV/Excel** veya denetim izi (audit trail) düzeyinde dışa aktarım, projeksiyon için **belirsizlik aralığı** ve senaryo analizi, (v) Kapsam 3 kapsamının genişletilmesi için tedarikçi verisi entegrasyonu.

---

## Teşekkür

*(Varsa proje danışmanı, işletme ortakları ve açık kaynak kütüphane geliştiricilerine teşekkür eklenebilir.)*

---

## Kaynakça (örnek format)

1. Greenhouse Gas Protocol. *Corporate Accounting and Reporting Standard*. WRI & WBCSD.  
2. ISO 14064-1. *Greenhouse gases — Part 1: Specification with guidance at the organization level for quantification and reporting of greenhouse gas emissions and removals*.  
3. IPCC. *2006 IPCC Guidelines for National Greenhouse Gas Inventories*.  
4. Our World in Data. *CO₂ and Greenhouse Gas Emissions* (açık veri kümesi).  
5. Flutter Team. *Flutter documentation*. https://docs.flutter.dev/  
6. Firebase. *Realtime Database documentation*.  

*(Atıflar, kullanılan rapor ve veri setlerinin kesin sürümlerine göre genişletilmelidir.)*

---

**Not:** Bu dosya, Word’e aktarım için Markdown olarak hazırlanmıştır. `dicle_bolek_makale_taslagı.docx` içeriği bu ortamda doğrudan okunamadığından, bölüm başlıkları ve tablolar kendi taslağınızla birleştirilmek üzere burada sıfırdan düzenlenmiştir.
