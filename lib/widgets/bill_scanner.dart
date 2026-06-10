import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/consumption_entry.dart';
import '../algorithms/calculation.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';
import 'theme_independent_info_dialog.dart';

/// Fatura tarama kartı widget'ı
class BillScannerCard extends StatefulWidget {
  const BillScannerCard({super.key, this.languageProvider, this.onCalculated});

  final LanguageProvider? languageProvider;
  final void Function(double co2e)? onCalculated;

  @override
  State<BillScannerCard> createState() => _BillScannerCardState();
}

class _BillScannerCardState extends State<BillScannerCard> {
  final ImagePicker _picker = ImagePicker();
  TextRecognizer? _textRecognizer;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initializeTextRecognizer();
  }

  Future<void> _initializeTextRecognizer() async {
    try {
      // ML Kit yalnızca Android/iOS — web'de plugin yok
      if (kIsWeb) {
        dev.log(
          'OCR web platformunda desteklenmiyor (ML Kit yalnızca mobil)',
          name: 'BillScanner',
        );
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        dev.log(
          'OCR Windows masaüstünde devre dışı; manuel giriş kullanılacak',
          name: 'BillScanner',
        );
        return;
      }

      _textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      dev.log('TextRecognizer başarıyla başlatıldı', name: 'BillScanner');
    } catch (e, st) {
      dev.log(
        'TextRecognizer başlatma hatası: $e',
        name: 'BillScanner',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      // Hata durumunda null bırak, OCR kullanılmayacak
    }
  }

  @override
  void dispose() {
    _textRecognizer?.close();
    super.dispose();
  }

  void _showManualCalculationOnReportsDialog() {
    if (!mounted) return;
    final locale =
        widget.languageProvider?.currentLocale ?? const Locale('tr');
    showThemeIndependentInfoDialog(
      context,
      title: translate('bill_scan_manual_redirect_title', locale),
      body: translate('bill_scan_manual_redirect_body', locale),
      okLabel: translate('ok', locale),
    );
  }

  Future<void> _scanBill() async {
    setState(() {
      _isScanning = true;
    });

    try {
      if (kIsWeb) {
        setState(() {
          _isScanning = false;
        });
        if (mounted) {
          _showManualCalculationOnReportsDialog();
        }
        return;
      }

      XFile? image;
      try {
        image = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
      } catch (_) {
        image = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
      }

      if (image == null) {
        setState(() {
          _isScanning = false;
        });
        return;
      }

      if (_textRecognizer == null) {
        setState(() {
          _isScanning = false;
        });
        if (mounted) {
          _showManualCalculationOnReportsDialog();
        }
        return;
      }

      try {
        final inputImage = await _inputImageFromXFile(image);

        final RecognizedText recognizedText =
            await _textRecognizer!.processImage(inputImage);

        final ocrText = _flattenRecognizedText(recognizedText);
        final billData = _parseBillText(ocrText);

        // Eğer hiç veri çıkarılamadıysa kullanıcıya bilgi ver
        if (billData.electricityKwh == 0.0 &&
            billData.fuelLiters == 0.0 &&
            billData.waterCubicMeters == 0.0 &&
            billData.wasteKg == 0.0) {
          if (mounted) {
            final locale =
                widget.languageProvider?.currentLocale ?? const Locale('tr');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(translate('no_data_extracted', locale)),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          setState(() {
            _isScanning = false;
          });
          return;
        }

        // Karbon ayak izi hesapla
        final co2e = Calculation.calculateDailyEmission(billData);
        // Dışarı bildirim
        widget.onCalculated?.call(co2e);

        setState(() {
          _isScanning = false;
        });

        // Başarı mesajı göster
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                translate(
                  'bill_success',
                  locale,
                  params: {'co2e': co2e.toStringAsFixed(2)},
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (ocrError) {
        // OCR hatası durumunda bilgilendir ve çık
        dev.log(
          'OCR hatası: $ocrError',
          name: 'BillScanner',
          level: 1000,
          error: ocrError,
        );
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translate('ocr_failed', locale)),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isScanning = false;
        });
        return;
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
      });

      if (mounted) {
        final locale =
            widget.languageProvider?.currentLocale ?? const Locale('tr');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translate('scan_error', locale, params: {'error': e.toString()}),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// ML Kit için görüntü: decode + (isteğe bağlı) küçültme + BGRA8888 bayt dizisi.
  Future<InputImage> _inputImageFromXFile(XFile image) async {
    final bytes = await image.readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (image.path.isNotEmpty) {
        return InputImage.fromFilePath(image.path);
      }
      throw const FormatException('Görüntü çözümlenemedi');
    }
    const maxEdge = 2200;
    if (decoded.width > maxEdge || decoded.height > maxEdge) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(
          decoded,
          width: maxEdge,
          interpolation: img.Interpolation.linear,
        );
      } else {
        decoded = img.copyResize(
          decoded,
          height: maxEdge,
          interpolation: img.Interpolation.linear,
        );
      }
    }
    final w = decoded.width;
    final h = decoded.height;
    final bgra = Uint8List(w * h * 4);
    var o = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = decoded.getPixel(x, y);
        bgra[o++] = p.b.toInt() & 0xff;
        bgra[o++] = p.g.toInt() & 0xff;
        bgra[o++] = p.r.toInt() & 0xff;
        bgra[o++] = p.a.toInt() & 0xff;
      }
    }
    return InputImage.fromBytes(
      bytes: bgra,
      metadata: InputImageMetadata(
        size: Size(w.toDouble(), h.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: w * 4,
      ),
    );
  }

  String _flattenRecognizedText(RecognizedText rt) {
    final buf = StringBuffer(rt.text);
    for (final block in rt.blocks) {
      buf.writeln();
      buf.writeln(block.text);
      for (final line in block.lines) {
        buf.writeln(line.text);
      }
    }
    return buf.toString();
  }

  /// Fatura metninden tüketim verilerini çıkarır (Türkiye / benzer faturalar).
  ConsumptionEntry _parseBillText(String text) =>
      _BillOcrParser.parseConsumption(text);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide =
              constraints.maxWidth >= 900; // Web/geniş ekran tespiti
          final double w = constraints.maxWidth;
          // Mobilde de konteynırı doldur: genişliğe göre 16:9 yükseklik + üst sınır
          final double cardHeight = isWide
              ? 400
              : (w / (16 / 9)).clamp(240.0, 340.0);
          final Color outlineGreen = Theme.of(context).brightness ==
                  Brightness.dark
              ? const Color(0xFF304411)
              : const Color(0xFF48631F);
          return Container(
            height: cardHeight,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/foto_yükleme.png'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            child: Stack(
              children: [
                // Siyah opacity layer
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                // İçerik
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Sol taraf boş bırakılıyor
                      const Spacer(),
                      // Sağ taraf - text ve buton
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              translate(
                                'bill_scanning_desc',
                                widget.languageProvider?.currentLocale ??
                                    const Locale('tr'),
                              ),
                              textAlign: TextAlign.right,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                            ),
                            const SizedBox(height: 16),
                            // Buton daha sağa alındı
                            OutlinedButton.icon(
                              onPressed: _isScanning ? null : _scanBill,
                              icon: _isScanning
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : (kIsWeb
                                      ? const Icon(
                                          Icons.photo_library,
                                          color: Colors.white,
                                        )
                                      : const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                        )),
                              label: Text(
                                _isScanning
                                    ? translate(
                                        'processing',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      )
                                    : translate(
                                        'scan_bill',
                                        widget.languageProvider
                                                ?.currentLocale ??
                                            const Locale('tr'),
                                      ),
                                style: const TextStyle(color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: outlineGreen.withValues(alpha: 0.95),
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// OCR sonrası fatura metninden sayı çıkarma (Türkçe binlik/ondalık, çoklu desen).
class _BillOcrParser {
  _BillOcrParser._();

  /// "1.234,56" / "1234,5" / "1234.5" → double?
  static double? parseTrNumber(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s'), '').replaceAll('\u00a0', '');
    if (s.isEmpty) return null;
    // Sadece rakam ve ayırıcılar
    s = s.replaceAll(RegExp(r'[^\d\.,]'), '');
    if (s.isEmpty) return null;

    if (s.contains(',') && s.contains('.')) {
      final lc = s.lastIndexOf(',');
      final ld = s.lastIndexOf('.');
      if (lc > ld) {
        // Türkiye: . binlik, , ondalık
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      final parts = s.split(',');
      if (parts.length == 2 && parts[1].length <= 3) {
        s = s.replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (s.contains('.')) {
      final parts = s.split('.');
      if (parts.length > 1 && parts.last.length == 3) {
        s = s.replaceAll('.', '');
      }
    }
    return double.tryParse(s);
  }

  static double _maxInRange(
    Iterable<RegExpMatch> matches,
    int group,
    double maxVal,
  ) {
    double best = 0;
    for (final m in matches) {
      final g = m.group(group);
      if (g == null) continue;
      final v = parseTrNumber(g);
      if (v != null && v > best && v < maxVal) {
        best = v;
      }
    }
    return best;
  }

  /// Türkiye elektrik faturalarında "sözleşme gücü X kW" satırını kWh tüketimi sanmamak için.
  static bool _lineLooksLikeContractPowerKw(String lineLower) {
    return (lineLower.contains('güç') ||
            lineLower.contains('guc') ||
            lineLower.contains('sözleşme') ||
            lineLower.contains('sozlesme') ||
            lineLower.contains('anlaşma') ||
            lineLower.contains('anlasma') ||
            lineLower.contains('demand')) &&
        lineLower.contains('kw') &&
        !lineLower.contains('kwh');
  }

  static ConsumptionEntry parseConsumption(String rawText) {
    var text = rawText
        .replaceAll('m³', 'm3')
        .replaceAll('M³', 'm3')
        .replaceAll(RegExp(r'm\s*³', caseSensitive: false), 'm3')
        .replaceAll('kwh', 'kWh')
        .replaceAll('KWH', 'kWh')
        .replaceAll(RegExp(r'k\s*w\s*h', caseSensitive: false), 'kWh');

    // OCR: bazen "kWe" veya boşluklu birim
    text = text.replaceAll(RegExp(r'k\s*W\s*h', caseSensitive: false), 'kWh');

    // Önce Türkiye’ye özgü sıkı desenler (EDAŞ/EDAŞ tarzı: aktif enerji, toplam tüketim)
    final kwhSpecific = <RegExp>[
      RegExp(
        r'(?:toplam\s*)?(?:elektrik\s*)?tüketim[^\d]{0,120}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:toplam\s*)?(?:elektrik\s*)?tuketim[^\d]{0,120}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
      RegExp(
        r'aktif\s*enerji[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
      RegExp(
        r'aktif\s*enerji\s*tüketimi[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:tüketim|tuketim|endeks|sayac|sayıç|sayic)[^\d]{0,90}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:indüktif|induktif|reaktif|kapasitif)[^\d]{0,60}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:consumption|active\s+energy)[^\d]{0,90}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
        caseSensitive: false,
      ),
    ];

    double electricitySpecific = 0;
    for (final re in kwhSpecific) {
      final v = _maxInRange(re.allMatches(text), 1, 1e7);
      if (v > electricitySpecific) electricitySpecific = v;
    }

    // Genel kWh — satır bazında sözleşme gücü (kW) satırlarını ele
    double electricityLoose = 0;
    final looseKwh = RegExp(
      r'([\d\.\s\u00a0]+(?:,\d+)?)\s*kWh',
      caseSensitive: false,
    );
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final low = line.toLowerCase();
      if (_lineLooksLikeContractPowerKw(low)) continue;
      for (final m in looseKwh.allMatches(line)) {
        final v = parseTrNumber(m.group(1)!);
        if (v != null && v > electricityLoose && v < 1e7) electricityLoose = v;
      }
    }

    final electricity =
        electricitySpecific >= electricityLoose ? electricitySpecific : electricityLoose;

    // Doğalgaz (İGDAŞ / genel): Sm³, STm³, Nm³ yazımları
    final gasPatterns = <RegExp>[
      RegExp(
        r'(?:doğal\s*gaz|dogal\s*gaz|doğalgaz|dogalgaz|natural\s*gas|ıgdaş|igdas|gaz\s*tüketim|gaz\s*tuketim)[^\d]{0,120}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:st\s*m3|stm3|sm3|nm3|m3)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:doğalgaz|dogalgaz)[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:m3|sm3|nm3|st\s*m3)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:^|\n)[^\d]{0,30}gaz[^\d]{0,70}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:m3|sm3|nm3|stm3)',
        caseSensitive: false,
      ),
    ];
    double gas = 0;
    for (final re in gasPatterns) {
      final v = _maxInRange(re.allMatches(text), 1, 1e6);
      if (v > gas) gas = v;
    }

    // Su (İSKİ / genel): abone, soğuk, sayaç
    final waterPatterns = <RegExp>[
      RegExp(
        r'(?:soğuk\s*su|soguk\s*su|içme\s*su|icme\s*su|su\s*tüketim|su\s*tuketim|abone|sayaç|sayac|iski|İSKİ|cold\s*water)[^\d]{0,90}?([\d\.\s\u00a0]+(?:,\d+)?)\s*m3',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:su|water)[^\d]{0,50}?([\d\.\s\u00a0]+(?:,\d+)?)\s*m3',
        caseSensitive: false,
      ),
    ];
    double water = 0;
    for (final re in waterPatterns) {
      final v = _maxInRange(re.allMatches(text), 1, 1e6);
      if (v > water) water = v;
    }

    final wasteRe = RegExp(
      r'(?:atık|atik|waste|çöp|cöp)[^\d]{0,40}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kg',
      caseSensitive: false,
    );
    final waste = _maxInRange(wasteRe.allMatches(text), 1, 1e6);

    return ConsumptionEntry(
      electricityKwh: electricity,
      fuelLiters: gas,
      waterCubicMeters: water,
      wasteKg: waste,
      createdAt: DateTime.now(),
      fuelIsNaturalGasM3: gas > 0,
    );
  }
}
