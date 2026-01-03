# Karbon Ayak İzi Hesaplama Metodolojisi

## 1. Giriş

Bu doküman, karbon ayak izi hesaplama uygulamasında kullanılan metodoloji, emisyon faktörleri ve veri kaynaklarını açıklamaktadır. Hesaplamalar, uluslararası standartlara uygun olarak CO₂ eşdeğeri (CO₂e) cinsinden yapılmaktadır.

## 2. Hesaplama Formülleri

### 2.1. Toplam Günlük Emisyon Formülü

```
Toplam CO₂e (kg/gün) = Elektrik Emisyonu + Yakıt Emisyonu + Su Emisyonu + Atık Emisyonu
```

### 2.2. Kategori Bazlı Hesaplamalar

#### 2.2.1. Elektrik Tüketimi

**Formül:**
```
CO₂e (kg) = Elektrik Tüketimi (kWh) × 0.233 kg CO₂e/kWh
```

**Emisyon Faktörü:** 0.233 kg CO₂e/kWh

**Kaynak ve Açıklama:**
- Türkiye elektrik üretim karışımı ortalaması
- Bu değer, Türkiye'nin elektrik üretim kaynaklarının (kömür, doğalgaz, hidroelektrik, rüzgar, güneş, nükleer vb.) karışımı dikkate alınarak hesaplanmıştır
- Türkiye İstatistik Kurumu (TÜİK) ve Enerji ve Tabii Kaynaklar Bakanlığı verileri temel alınmıştır
- Değer, ülkenin güncel elektrik üretim karışımına göre güncellenebilir

**Referans Standartlar:**
- IPCC (Intergovernmental Panel on Climate Change) Emisyon Faktörleri
- IEA (International Energy Agency) Türkiye Enerji İstatistikleri

---

#### 2.2.2. Yakıt Tüketimi

**Formül:**
```
CO₂e (kg) = Yakıt Tüketimi (Litre) × 2.31 kg CO₂e/Litre
```

**Emisyon Faktörü:** 2.31 kg CO₂e/Litre

**Kaynak ve Açıklama:**
- Benzin ve dizel yakıt yanma emisyon faktörü
- IPCC standartlarına uygun olarak belirlenmiştir
- Ortalama benzin ve dizel yakıtlar için geçerlidir
- Bu değer, yakıtın yanması sırasında açığa çıkan CO₂ emisyonunu temsil eder

**Referans Standartlar:**
- IPCC 2006 Guidelines for National Greenhouse Gas Inventories
- EPA (Environmental Protection Agency) Mobile Source Emissions

---

#### 2.2.3. Su Tüketimi

**Formül:**
```
CO₂e (kg) = Su Tüketimi (m³) × 0.344 kg CO₂e/m³
```

**Emisyon Faktörü:** 0.344 kg CO₂e/m³

**Kaynak ve Açıklama:**
- Su arıtma, dağıtım ve atık su işleme süreçlerinin toplam emisyonu
- Su tüketiminin karbon ayak izi, aşağıdaki süreçlerden kaynaklanan enerji tüketimini içerir:
  - Suyun arıtılması (filtreleme, klorlama vb.)
  - Suyun pompalanması ve dağıtımı
  - Atık suyun toplanması ve işlenmesi
  - Su arıtma tesislerinin enerji tüketimi

**Referans Standartlar:**
- Water Footprint Network metodolojisi
- EPA Water and Wastewater Treatment Plant Emissions

---

#### 2.2.4. Atık Üretimi

**Formül:**
```
CO₂e (kg) = Atık Miktarı (kg) × 1.9 kg CO₂e/kg
```

**Emisyon Faktörü:** 1.9 kg CO₂e/kg

**Kaynak ve Açıklama:**
- Atık toplama, taşıma ve bertaraf süreçlerinin ortalama emisyonu
- Bu değer, aşağıdaki süreçlerden kaynaklanan emisyonları içerir:
  - Atığın toplanması (koleksiyon araçlarının yakıt tüketimi)
  - Atığın taşınması (nakliye emisyonları)
  - Atığın bertaraf edilmesi (depolama, yakma, geri dönüşüm süreçleri)
  - Atık depolama alanlarından kaynaklanan metan (CH₄) emisyonları (CO₂e'ye dönüştürülmüş)

**Referans Standartlar:**
- IPCC Waste Management Guidelines
- EPA Municipal Solid Waste Landfill Emissions

---

## 3. Referans Değerler

### 3.1. Kişi Başı Günlük Ortalama Emisyonlar

| Ülke/Bölge | Ortalama (kg CO₂e/gün) | Yıllık (ton CO₂e/yıl) | Kaynak |
|------------|------------------------|----------------------|--------|
| Dünya Ortalaması | ~4.1 | ~1.5 | Global Carbon Project, Our World in Data |
| Türkiye | ~6.8 | ~2.5 | World Bank, Our World in Data |
| ABD | ~15.5 | ~5.7 | EPA, Our World in Data |
| Avrupa Birliği | ~8-9 | ~3.0-3.3 | Eurostat, Our World in Data |
| Çin | ~7.5 | ~2.7 | Global Carbon Project |
| Almanya | ~9.2 | ~3.4 | Eurostat |
| Fransa | ~7.8 | ~2.9 | Eurostat |
| İngiltere | ~8.5 | ~3.1 | UK Government Statistics |

### 3.2. Çevresel Etki Skoru

Uygulama, kullanıcıların günlük emisyon değerlerini Türkiye ortalaması (~15 kg CO₂e/gün) ile karşılaştırarak bir çevresel etki skoru (0-100) hesaplar:

- **100 puan**: Ortalamanın %50'si veya daha az (≤7.5 kg/gün) - Çok İyi
- **80 puan**: Ortalamanın %75'i (≤11.25 kg/gün) - İyi
- **60 puan**: Ortalama seviye (≤15 kg/gün) - Orta
- **40 puan**: Ortalamanın %125'i (≤18.75 kg/gün) - Kötü
- **20 puan**: Ortalamanın %125'inden fazla (>18.75 kg/gün) - Çok Kötü

---

## 4. Veri Kaynakları

### 4.1. Emisyon Faktörleri

- **IPCC (Intergovernmental Panel on Climate Change)**: Uluslararası iklim değişikliği paneli standartları
- **Türkiye İstatistik Kurumu (TÜİK)**: Ulusal enerji ve çevre istatistikleri
- **Enerji ve Tabii Kaynaklar Bakanlığı**: Elektrik üretim karışımı verileri
- **EPA (Environmental Protection Agency)**: Çevre koruma ajansı emisyon faktörleri
- **IEA (International Energy Agency)**: Uluslararası enerji ajansı istatistikleri

### 4.2. Ülke Karşılaştırma Verileri

- **Our World in Data (OWID)**: Açık kaynak karbon emisyon verileri
  - URL: `https://raw.githubusercontent.com/owid/co2-data/master/owid-co2-data.json`
  - Veri formatı: JSON
  - Güncelleme: Düzenli olarak güncellenmektedir
  - Lisans: Açık kaynak (Creative Commons)

- **World Bank**: Dünya Bankası karbon emisyon verileri
- **Global Carbon Project**: Küresel karbon projesi verileri

---

## 5. Hesaplama Doğruluğu ve Sınırlamalar

### 5.1. Doğruluk

- Emisyon faktörleri, uluslararası standartlara uygun olarak belirlenmiştir
- Elektrik emisyon faktörü, Türkiye'nin güncel elektrik üretim karışımına göre güncellenebilir
- Hesaplamalar, kullanıcıların günlük tüketim verilerine dayanmaktadır
- Gerçek zamanlı IoT sensör verileri (ESP8266, Shelly Plug S) ile desteklenmektedir

### 5.2. Sınırlamalar

- Emisyon faktörleri, ortalama değerler temel alınarak hesaplanmıştır
- Bölgesel farklılıklar (örneğin, farklı şehirlerdeki elektrik üretim karışımları) dikkate alınmamıştır
- Yakıt türü (benzin/dizel/LPG) ayrımı yapılmamıştır (ortalama değer kullanılmıştır)
- Atık türü ayrımı (organik/plastik/kağıt vb.) yapılmamıştır
- Dolaylı emisyonlar (örneğin, ürün üretim süreçlerinden kaynaklanan emisyonlar) dahil edilmemiştir

### 5.3. Gelecek İyileştirmeler

- Bölgesel elektrik üretim karışımı verilerinin entegrasyonu
- Yakıt türü bazlı ayrıntılı hesaplamalar
- Atık türü bazlı ayrıntılı hesaplamalar
- Dolaylı emisyonların dahil edilmesi
- Hayat döngüsü analizi (LCA) entegrasyonu

---

## 6. Referanslar

1. IPCC (2006). *2006 IPCC Guidelines for National Greenhouse Gas Inventories*. Intergovernmental Panel on Climate Change.

2. Our World in Data (2024). *CO₂ and Greenhouse Gas Emissions*. https://ourworldindata.org/co2-and-greenhouse-gas-emissions

3. EPA (2024). *Greenhouse Gas Emissions Factors*. U.S. Environmental Protection Agency.

4. TÜİK (2024). *Enerji İstatistikleri*. Türkiye İstatistik Kurumu.

5. IEA (2024). *Turkey Energy Statistics*. International Energy Agency.

6. Global Carbon Project (2024). *Global Carbon Budget*. https://www.globalcarbonproject.org/

7. World Bank (2024). *World Development Indicators: CO₂ Emissions*. https://data.worldbank.org/

---

## 7. Sonuç

Bu metodoloji, kullanıcıların günlük karbon ayak izlerini hesaplamak için uluslararası standartlara uygun emisyon faktörleri kullanmaktadır. Hesaplamalar, şeffaf ve doğrulanabilir veri kaynaklarına dayanmaktadır. Metodoloji, yeni veriler ve standartlar çıktıkça güncellenebilir ve iyileştirilebilir.

---

**Doküman Versiyonu:** 1.0  
**Son Güncelleme:** 2024  
**Hazırlayan:** Karbon Ayak İzi Hesaplama Uygulaması Geliştirme Ekibi

