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
import '../themes/app_theme.dart';
import 'theme_independent_info_dialog.dart';

/// OCR sonrası fatura ayrıştırma sonucu (birim dönüşüm notları ile).
class BillOcrParseResult {
  const BillOcrParseResult({
    required this.entry,
    this.conversionNotes = const [],
  });

  final ConsumptionEntry entry;
  final List<String> conversionNotes;
}

/// Fatura tarama kartı widget'ı
class BillScannerCard extends StatefulWidget {
  const BillScannerCard({super.key, this.languageProvider});

  final LanguageProvider? languageProvider;

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

      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
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
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
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
        final RecognizedText recognizedText = await _processBillImage(image);

        final ocrText = _flattenRecognizedText(recognizedText);
        final parseResult = _parseBillText(ocrText);
        final billData = parseResult.entry;

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

        setState(() {
          _isScanning = false;
        });

        // Anlık sonuç penceresi (kaydedilmez)
        if (mounted) {
          _showBillScanResultDialog(
            context,
            entry: billData,
            conversionNotes: parseResult.conversionNotes,
            locale:
                widget.languageProvider?.currentLocale ?? const Locale('tr'),
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

  /// ML Kit OCR — önce dosya yolu, gerekirse JPEG bitmap (Android bgra8888 bytes desteklemez).
  Future<RecognizedText> _processBillImage(XFile image) async {
    final path = image.path;
    if (_isLocalFilePath(path)) {
      try {
        final fromFile = InputImage.fromFilePath(path);
        return await _textRecognizer!.processImage(fromFile);
      } catch (e, st) {
        dev.log(
          'fromFilePath OCR denemesi başarısız, bitmap yedeklenecek: $e',
          name: 'BillScanner',
          error: e,
          stackTrace: st,
        );
      }
    }

    try {
      final fromBitmap = await _inputImageFromDecodedBitmap(image);
      return await _textRecognizer!.processImage(fromBitmap);
    } catch (bitmapError, st) {
      dev.log(
        'Bitmap OCR denemesi başarısız: $bitmapError',
        name: 'BillScanner',
        level: 1000,
        error: bitmapError,
        stackTrace: st,
      );
      if (_isLocalFilePath(path)) {
        return await _textRecognizer!.processImage(
          InputImage.fromFilePath(path),
        );
      }
      rethrow;
    }
  }

  bool _isLocalFilePath(String path) {
    if (path.isEmpty) return false;
    final lower = path.toLowerCase();
    if (lower.startsWith('content://') || lower.startsWith('http')) {
      return false;
    }
    return true;
  }

  img.Image _resizeIfNeeded(img.Image decoded) {
    const maxEdge = 2200;
    if (decoded.width <= maxEdge && decoded.height <= maxEdge) {
      return decoded;
    }
    if (decoded.width >= decoded.height) {
      return img.copyResize(
        decoded,
        width: maxEdge,
        interpolation: img.Interpolation.linear,
      );
    }
    return img.copyResize(
      decoded,
      height: maxEdge,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Decode + JPEG; ML Kit Android/iOS [InputImage.fromBitmap] ile uyumlu.
  Future<InputImage> _inputImageFromDecodedBitmap(XFile image) async {
    final bytes = await image.readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Görüntü çözümlenemedi');
    }
    decoded = _resizeIfNeeded(decoded);
    final jpgBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
    return InputImage.fromBitmap(
      bitmap: jpgBytes,
      width: decoded.width,
      height: decoded.height,
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
  BillOcrParseResult _parseBillText(String text) =>
      BillOcrParser.parseConsumption(text);

  void _showBillScanResultDialog(
    BuildContext context, {
    required ConsumptionEntry entry,
    required List<String> conversionNotes,
    required Locale locale,
  }) {
    final analysis = Calculation.analyzeEmissionByCategory(entry);
    final totalCo2e = (analysis['total'] as num).toDouble();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            fontFamily: 'PlayfairDisplay',
            colorScheme: const ColorScheme.light(
              primary: AppTheme.infoDialogForeground,
              onPrimary: Colors.white,
              surface: AppTheme.infoDialogBackground,
              onSurface: AppTheme.infoDialogForeground,
            ),
          ),
          child: AlertDialog(
            backgroundColor: AppTheme.infoDialogBackground,
            surfaceTintColor: Colors.transparent,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            title: Text(
              translate('bill_scan_result_title', locale),
              style: const TextStyle(
                color: AppTheme.infoDialogForeground,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    translate('bill_scan_result_note', locale),
                    style: TextStyle(
                      color: AppTheme.infoDialogForeground.withValues(
                        alpha: 0.85,
                      ),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (entry.electricityKwh > 0)
                    _BillResultRow(
                      label: translate('electricity_label', locale),
                      amount: '${entry.electricityKwh.toStringAsFixed(2)} kWh',
                      co2e: (analysis['electricity']['emission'] as num)
                          .toDouble(),
                      locale: locale,
                    ),
                  if (entry.fuelLiters > 0 && entry.fuelIsNaturalGasM3)
                    _BillResultRow(
                      label: translate('gas_label', locale),
                      amount: '${entry.fuelLiters.toStringAsFixed(2)} m³',
                      co2e: (analysis['fuel']['emission'] as num).toDouble(),
                      locale: locale,
                    ),
                  if (entry.waterCubicMeters > 0)
                    _BillResultRow(
                      label: translate('water_label', locale),
                      amount: '${entry.waterCubicMeters.toStringAsFixed(2)} m³',
                      co2e: (analysis['water']['emission'] as num).toDouble(),
                      locale: locale,
                    ),
                  if (entry.wasteKg > 0)
                    _BillResultRow(
                      label: translate('waste_label', locale),
                      amount: '${entry.wasteKg.toStringAsFixed(2)} kg',
                      co2e: (analysis['waste']['emission'] as num).toDouble(),
                      locale: locale,
                    ),
                  if (conversionNotes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final note in conversionNotes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          translate(
                            'bill_scan_conversion_note',
                            locale,
                            params: {'note': note},
                          ),
                          style: TextStyle(
                            color: AppTheme.infoDialogForeground.withValues(
                              alpha: 0.8,
                            ),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Divider(
                    color: AppTheme.infoDialogForeground.withValues(
                      alpha: 0.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        translate('bill_scan_total_co2e', locale),
                        style: const TextStyle(
                          color: AppTheme.infoDialogForeground,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        translate(
                          'bill_scan_row_co2e',
                          locale,
                          params: {
                            'co2e': totalCo2e.toStringAsFixed(2),
                          },
                        ),
                        style: const TextStyle(
                          color: AppTheme.infoDialogForeground,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.infoDialogForeground,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  translate('ok', locale),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
          final double cardHeight =
              isWide ? 400 : (w / (16 / 9)).clamp(240.0, 340.0);
          final Color outlineGreen =
              Theme.of(context).brightness == Brightness.dark
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

class _BillResultRow extends StatelessWidget {
  const _BillResultRow({
    required this.label,
    required this.amount,
    required this.co2e,
    required this.locale,
  });

  final String label;
  final String amount;
  final double co2e;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.infoDialogForeground,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  amount,
                  style: TextStyle(
                    color: AppTheme.infoDialogForeground.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            translate(
              'bill_scan_row_co2e',
              locale,
              params: {'co2e': co2e.toStringAsFixed(2)},
            ),
            style: const TextStyle(
              color: AppTheme.infoDialogForeground,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// OCR sonrası fatura metninden sayı çıkarma (Türkçe binlik/ondalık, çoklu desen).
class BillOcrParser {
  BillOcrParser._();

  /// Doğalgaz kWh → m³ (Türkiye faturalarında ~10,55 kWh/Sm³).
  static const double _kwhPerGasM3 = 10.55;

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

  static String _unitFromMatch(String matchedText,
      {required String defaultUnit}) {
    final unitM = RegExp(
      r'(kwh|mwh|wh|m3|sm3|nm3|stm3|st\s*m3|kg|lt|l)\b',
      caseSensitive: false,
    ).allMatches(matchedText);
    if (unitM.isEmpty) return defaultUnit;
    return unitM.last.group(1)!.toLowerCase().replaceAll(' ', '');
  }

  static String _normalizeOcrText(String rawText) {
    var text = rawText
        .replaceAll('m³', 'm3')
        .replaceAll('M³', 'm3')
        .replaceAll(RegExp(r'm\s*³', caseSensitive: false), 'm3')
        .replaceAll('kwh', 'kWh')
        .replaceAll('KWH', 'kWh')
        .replaceAll(RegExp(r'k\s*w\s*h', caseSensitive: false), 'kWh');
    text = text.replaceAll(RegExp(r'k\s*W\s*h', caseSensitive: false), 'kWh');
    text = text.replaceAll(RegExp(r'm\s+3\b', caseSensitive: false), 'm3');
    return text;
  }

  /// OCR tablo satırı: tüketim etiketi (elektrik / gaz / su / atık).
  static String? _consumptionLabelCategory(String line) {
    final low = line.toLowerCase();
    if (RegExp(r'aktif\s*enerji|elektrik', caseSensitive: false).hasMatch(low)) {
      return 'electricity';
    }
    if (RegExp(
      r'doğalgaz|dogalgaz|doğal\s*gaz|dogal\s*gaz|natural\s*gas',
      caseSensitive: false,
    ).hasMatch(low)) {
      return 'gas';
    }
    if (RegExp(
      r'su\s*tüketim|su\s*tuketim|soğuk\s*su|soguk\s*su|cold\s*water',
      caseSensitive: false,
    ).hasMatch(low)) {
      return 'water';
    }
    if (RegExp(
      r'evsel\s*atık|evsel\s*atik|atık\s*miktar|atik\s*miktar',
      caseSensitive: false,
    ).hasMatch(low)) {
      return 'waste';
    }
    return null;
  }

  static ({double value, String unit})? _parseLineAmount(String line) {
    for (final m in _amountWithUnitRe.allMatches(line)) {
      final v = parseTrNumber(m.group(1)!);
      if (v == null || v <= 0) continue;
      final unit = m.group(2)!.toLowerCase().replaceAll(' ', '');
      return (value: v, unit: unit);
    }
    return null;
  }

  static double _normalizeCategoryValue(
    String category,
    double value,
    String unit, {
    List<String>? conversionNotes,
  }) {
    switch (category) {
      case 'electricity':
        return _normalizeElectricityKwh(
          value,
          unit,
          conversionNotes: conversionNotes,
        );
      case 'gas':
        return _normalizeGasM3(
          value,
          unit,
          conversionNotes: unit.contains('kwh') ? conversionNotes : null,
        );
      case 'water':
        return _normalizeWaterM3(
          value,
          unit,
          conversionNotes: (unit == 'l' || unit == 'lt') ? conversionNotes : null,
        );
      case 'waste':
        return value;
      default:
        return value;
    }
  }

  /// OCR iki sütun: önce tüm etiketler, sonra tüm miktarlar (sırayla eşleştir).
  static Map<String, double> _extractStackedLabelAmountTable(
    List<String> lines, {
    List<String>? conversionNotes,
  }) {
    final categories = <String>[];
    final inlineValues = <String, double>{};
    final amountOnlyLines = <({double value, String unit})>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final category = _consumptionLabelCategory(trimmed);
      final amountOnLine = _parseLineAmount(trimmed);

      if (category != null) {
        categories.add(category);
        if (amountOnLine != null) {
          inlineValues[category] = _normalizeCategoryValue(
            category,
            amountOnLine.value,
            amountOnLine.unit,
            conversionNotes: conversionNotes,
          );
        }
      } else if (amountOnLine != null) {
        amountOnlyLines.add(amountOnLine);
      }
    }

    final result = Map<String, double>.from(inlineValues);

    if (categories.isEmpty || amountOnlyLines.isEmpty) return result;

    if (categories.length == amountOnlyLines.length) {
      for (int i = 0; i < categories.length; i++) {
        final cat = categories[i];
        if (result.containsKey(cat)) continue;
        final p = amountOnlyLines[i];
        result[cat] = _normalizeCategoryValue(
          cat,
          p.value,
          p.unit,
          conversionNotes: conversionNotes,
        );
      }
      return result;
    }

    final labelOnlyCats = <String>[];
    for (final cat in categories) {
      if (!result.containsKey(cat)) labelOnlyCats.add(cat);
    }
    if (labelOnlyCats.length == amountOnlyLines.length) {
      for (int i = 0; i < labelOnlyCats.length; i++) {
        final cat = labelOnlyCats[i];
        final p = amountOnlyLines[i];
        result[cat] = _normalizeCategoryValue(
          cat,
          p.value,
          p.unit,
          conversionNotes: conversionNotes,
        );
      }
    }

    return result;
  }

  static void _addUniqueConversionNote(List<String>? notes, String note) {
    if (notes == null || notes.contains(note)) return;
    notes.add(note);
  }

  static bool _chunkLooksLikeElectricityAmount(String chunk) {
    final low = chunk.toLowerCase();
    return low.contains('aktif enerji') ||
        low.contains('elektrik') ||
        (RegExp(r'\bkwh\b', caseSensitive: false).hasMatch(low) &&
            !low.contains('doğalgaz') &&
            !low.contains('dogalgaz'));
  }

  static double _normalizeElectricityKwh(
    double value,
    String unitRaw, {
    List<String>? conversionNotes,
  }) {
    final u = unitRaw.toLowerCase().replaceAll(' ', '');
    if (u.contains('mwh')) {
      _addUniqueConversionNote(
        conversionNotes,
        '${value.toStringAsFixed(2)} MWh → ${(value * 1000).toStringAsFixed(2)} kWh',
      );
      return value * 1000;
    }
    if (u == 'wh' || u.endsWith('wh') && !u.contains('kwh')) {
      _addUniqueConversionNote(
        conversionNotes,
        '${value.toStringAsFixed(0)} Wh → ${(value / 1000).toStringAsFixed(4)} kWh',
      );
      return value / 1000;
    }
    return value;
  }

  static double _normalizeGasM3(
    double value,
    String unitRaw, {
    List<String>? conversionNotes,
  }) {
    final u = unitRaw.toLowerCase().replaceAll(' ', '');
    if (u.contains('kwh')) {
      final m3 = value / _kwhPerGasM3;
      _addUniqueConversionNote(
        conversionNotes,
        '${value.toStringAsFixed(2)} kWh → ${m3.toStringAsFixed(2)} m³',
      );
      return m3;
    }
    return value;
  }

  static double _normalizeWaterM3(
    double value,
    String unitRaw, {
    List<String>? conversionNotes,
  }) {
    final u = unitRaw.toLowerCase().replaceAll(' ', '');
    if (u == 'l' || u == 'lt' || u.endsWith('lt') || u.contains('litre')) {
      final m3 = value / 1000;
      _addUniqueConversionNote(
        conversionNotes,
        '${value.toStringAsFixed(1)} L → ${m3.toStringAsFixed(3)} m³',
      );
      return m3;
    }
    return value;
  }

  /// Sayı + birim deseni (satır veya blok içinde).
  static final RegExp _amountWithUnitRe = RegExp(
    r'([\d\.\s\u00a0]+(?:,\d+)?)\s*(kwh|mwh|wh|m3|sm3|nm3|stm3|st\s*m3|kg|lt|l)\b',
    caseSensitive: false,
  );

  static double? _firstAmountWithUnit(
    String text, {
    List<String>? allowedUnits,
    List<String>? conversionNotes,
    double Function(double value, String unit)? normalize,
  }) {
    for (final m in _amountWithUnitRe.allMatches(text)) {
      final numRaw = m.group(1);
      final unitRaw = m.group(2);
      if (numRaw == null || unitRaw == null) continue;
      final unit = unitRaw.toLowerCase().replaceAll(' ', '');
      if (allowedUnits != null && !allowedUnits.any((a) => unit.contains(a))) {
        continue;
      }
      final v = parseTrNumber(numRaw);
      if (v == null || v <= 0) continue;
      if (normalize != null) {
        return normalize(v, unit);
      }
      return v;
    }
    return null;
  }

  /// Önce tercih edilen birimleri dener (ör. gaz için önce m³, sonra kWh).
  static double? _firstAmountWithUnitPriority(
    String text, {
    required List<String> preferredUnits,
    List<String> fallbackUnits = const [],
    List<String>? conversionNotes,
    double Function(double value, String unit)? normalize,
  }) {
    for (final units in [preferredUnits, fallbackUnits]) {
      if (units.isEmpty) continue;
      final v = _firstAmountWithUnit(
        text,
        allowedUnits: units,
        conversionNotes: conversionNotes,
        normalize: normalize,
      );
      if (v != null) return v;
    }
    return null;
  }

  /// Tablo satırları: etiket aynı veya sonraki satırda miktar olabilir.
  static double _extractByLabelLines(
    List<String> lines,
    List<RegExp> labelPatterns,
    List<String> allowedUnitHints, {
    required double Function(double value, String unit) normalize,
    List<String>? conversionNotes,
    double maxVal = 1e7,
    List<String> preferredUnitHints = const [],
    List<String> fallbackUnitHints = const [],
    bool skipElectricityAmountLines = false,
  }) {
    double best = 0;
    final usePriority = preferredUnitHints.isNotEmpty;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final low = line.toLowerCase();
      final matched =
          labelPatterns.any((p) => p.hasMatch(low) || p.hasMatch(line));
      if (!matched) continue;

      for (int f = 0; f <= 10 && i + f < lines.length; f++) {
        final chunk = lines[i + f];
        if (f > 0 && _consumptionLabelCategory(chunk) != null) {
          continue;
        }
        if (skipElectricityAmountLines && _chunkLooksLikeElectricityAmount(chunk)) {
          continue;
        }
        final double? v = usePriority
            ? _firstAmountWithUnitPriority(
                chunk,
                preferredUnits: preferredUnitHints,
                fallbackUnits: fallbackUnitHints,
                conversionNotes: conversionNotes,
                normalize: normalize,
              )
            : _firstAmountWithUnit(
                chunk,
                allowedUnits: allowedUnitHints,
                conversionNotes: conversionNotes,
                normalize: normalize,
              );
        if (v != null && v > best && v < maxVal) best = v;

        // Sadece sayı (birim sonraki satırda veya OCR birimi kaçırdı)
        final bare = RegExp(r'^([\d\.\s\u00a0]+(?:,\d+)?)\s*$');
        final bm = bare.firstMatch(chunk.trim());
        if (bm != null) {
          final bareVal = parseTrNumber(bm.group(1)!);
          if (bareVal != null && bareVal > 0 && bareVal < maxVal) {
            double candidate = bareVal;
            if (allowedUnitHints.contains('lt') &&
                bareVal >= 50 &&
                !chunk.toLowerCase().contains('m3')) {
              candidate = normalize(bareVal, 'l');
            }
            if (candidate > best) best = candidate;
          }
        }
      }
    }
    return best;
  }

  static List<String> _uniqueNotes(List<String> notes) {
    final unique = <String>[];
    for (final note in notes) {
      if (!unique.contains(note)) unique.add(note);
    }
    return unique;
  }

  static BillOcrParseResult parseConsumption(String rawText) {
    final conversionNotes = <String>[];
    final text = _normalizeOcrText(rawText);
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).toList();

    final stackedTable = _extractStackedLabelAmountTable(
      lines,
      conversionNotes: conversionNotes,
    );

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
      RegExp(
        r'aktif\s*enerji\s*tüketimi[^\d]{0,120}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:kwh|mwh|wh)',
        caseSensitive: false,
      ),
    ];

    double electricitySpecific = 0;
    for (final re in kwhSpecific) {
      final v = _maxInRange(re.allMatches(text), 1, 1e7);
      if (v > electricitySpecific) electricitySpecific = v;
    }

    // MWh / Wh içeren elektrik satırları
    final elecUnitRe = RegExp(
      r'(?:aktif\s*enerji|elektrik|tüketim|tuketim|energy)[^\d]{0,120}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(mwh|kwh|wh)\b',
      caseSensitive: false,
    );
    for (final m in elecUnitRe.allMatches(text)) {
      final n = parseTrNumber(m.group(1)!);
      final unit = m.group(2) ?? 'kwh';
      if (n != null && n > 0) {
        final kwh = _normalizeElectricityKwh(
          n,
          unit,
          conversionNotes: conversionNotes,
        );
        if (kwh > electricitySpecific && kwh < 1e7) electricitySpecific = kwh;
      }
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

    final electricity = electricitySpecific >= electricityLoose
        ? electricitySpecific
        : electricityLoose;

    // Doğalgaz (İGDAŞ / genel): Sm³, STm³, Nm³ yazımları
    final gasPatterns = <RegExp>[
      RegExp(
        r'(?:toplam\s*)?doğalgaz\s*kullanımı[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:st\s*m3|stm3|sm3|nm3|m3)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:toplam\s*)?dogalgaz\s*kullanimi[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:st\s*m3|stm3|sm3|nm3|m3)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:doğal\s*gaz|dogal\s*gaz|doğalgaz|dogalgaz|natural\s*gas|ıgdaş|igdas|gaz\s*tüketim|gaz\s*tuketim)[^\d]{0,120}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:st\s*m3|stm3|sm3|nm3|m3)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:doğalgaz|dogalgaz)[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:m3|sm3|nm3|st\s*m3)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:^|\n)[^\d]{0,30}gaz[^\d]{0,70}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(?:m3|sm3|nm3|stm3)\b',
        caseSensitive: false,
      ),
    ];
    double gas = 0;
    for (final re in gasPatterns) {
      for (final m in re.allMatches(text)) {
        final n = parseTrNumber(m.group(1)!);
        if (n == null || n <= 0) continue;
        final matchText = m.group(0) ?? '';
        if (_chunkLooksLikeElectricityAmount(matchText)) continue;
        final unit = _unitFromMatch(matchText, defaultUnit: 'm3');
        final m3 = _normalizeGasM3(n, unit);
        if (m3 > gas && m3 < 1e6) gas = m3;
      }
    }

    // Su (İSKİ / genel): abone, soğuk, sayaç
    final waterPatterns = <RegExp>[
      RegExp(
        r'su\s*tüketim\s*miktarı[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(m3|lt|l)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'su\s*tuketim\s*miktari[^\d]{0,100}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(m3|lt|l)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:soğuk\s*su|soguk\s*su|içme\s*su|icme\s*su|su\s*tüketim|su\s*tuketim|abone|sayaç|sayac|iski|İSKİ|cold\s*water)[^\d]{0,90}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(m3|lt|l)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:su|water)[^\d]{0,50}?([\d\.\s\u00a0]+(?:,\d+)?)\s*(m3|lt|l)\b',
        caseSensitive: false,
      ),
    ];
    double water = 0;
    for (final re in waterPatterns) {
      for (final m in re.allMatches(text)) {
        final n = parseTrNumber(m.group(1)!);
        if (n == null || n <= 0) continue;
        final unit = _unitFromMatch(m.group(0) ?? '', defaultUnit: 'm3');
        final m3 = _normalizeWaterM3(
          n,
          unit,
          conversionNotes:
              (unit == 'l' || unit == 'lt') ? conversionNotes : null,
        );
        if (m3 > water && m3 < 1e6) water = m3;
      }
    }

    final wastePatterns = <RegExp>[
      RegExp(
        r'evsel\s*atık\s*miktarı[^\d]{0,80}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kg',
        caseSensitive: false,
      ),
      RegExp(
        r'evsel\s*atik\s*miktari[^\d]{0,80}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kg',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:atık|atik|waste|çöp|cöp)[^\d]{0,40}?([\d\.\s\u00a0]+(?:,\d+)?)\s*kg',
        caseSensitive: false,
      ),
    ];
    double waste = 0;
    for (final re in wastePatterns) {
      final v = _maxInRange(re.allMatches(text), 1, 1e6);
      if (v > waste) waste = v;
    }

    // Satır bazlı tablo (OCR sütunları ayırdığında)
    final electricityFromLines = _extractByLabelLines(
      lines,
      [
        RegExp(r'aktif\s*enerji', caseSensitive: false),
        RegExp(r'elektrik\s*tüketim', caseSensitive: false),
        RegExp(r'elektrik\s*tuketim', caseSensitive: false),
        RegExp(r'active\s+energy', caseSensitive: false),
      ],
      ['kwh', 'mwh', 'wh'],
      normalize: (v, u) =>
          _normalizeElectricityKwh(v, u, conversionNotes: conversionNotes),
      conversionNotes: conversionNotes,
    );

    final gasFromLines = _extractByLabelLines(
      lines,
      [
        RegExp(r'doğalgaz', caseSensitive: false),
        RegExp(r'dogalgaz', caseSensitive: false),
        RegExp(r'doğal\s*gaz', caseSensitive: false),
        RegExp(r'dogal\s*gaz', caseSensitive: false),
        RegExp(r'natural\s*gas', caseSensitive: false),
      ],
      ['m3', 'sm3', 'nm3', 'stm3', 'kwh'],
      normalize: (v, u) => _normalizeGasM3(
        v,
        u,
        conversionNotes: u.contains('kwh') ? conversionNotes : null,
      ),
      conversionNotes: conversionNotes,
      maxVal: 1e6,
      preferredUnitHints: ['m3', 'sm3', 'nm3', 'stm3'],
      fallbackUnitHints: ['kwh'],
      skipElectricityAmountLines: true,
    );

    final waterFromLines = _extractByLabelLines(
      lines,
      [
        RegExp(r'su\s*tüketim', caseSensitive: false),
        RegExp(r'su\s*tuketim', caseSensitive: false),
        RegExp(r'soğuk\s*su', caseSensitive: false),
        RegExp(r'soguk\s*su', caseSensitive: false),
        RegExp(r'cold\s*water', caseSensitive: false),
      ],
      ['m3', 'lt', 'l'],
      normalize: (v, u) => _normalizeWaterM3(
        v,
        u,
        conversionNotes: (u == 'l' || u == 'lt') ? conversionNotes : null,
      ),
      conversionNotes: conversionNotes,
      maxVal: 1e6,
    );

    final wasteFromLines = _extractByLabelLines(
      lines,
      [
        RegExp(r'evsel\s*atık', caseSensitive: false),
        RegExp(r'evsel\s*atik', caseSensitive: false),
        RegExp(r'atık', caseSensitive: false),
        RegExp(r'atik', caseSensitive: false),
        RegExp(r'waste', caseSensitive: false),
      ],
      ['kg'],
      normalize: (v, _) => v,
      maxVal: 1e6,
    );

    double pickCategoryValue(
      double regexValue,
      double lineValue,
      double stackedValue,
    ) {
      if (stackedValue > 0) return stackedValue;
      return regexValue >= lineValue ? regexValue : lineValue;
    }

    final finalElectricity = pickCategoryValue(
      electricity,
      electricityFromLines,
      stackedTable['electricity'] ?? 0,
    );
    final finalGas = pickCategoryValue(
      gas,
      gasFromLines,
      stackedTable['gas'] ?? 0,
    );
    final finalWater = pickCategoryValue(
      water,
      waterFromLines,
      stackedTable['water'] ?? 0,
    );
    final finalWaste = pickCategoryValue(
      waste,
      wasteFromLines,
      stackedTable['waste'] ?? 0,
    );

    return BillOcrParseResult(
      entry: ConsumptionEntry(
        electricityKwh: finalElectricity,
        fuelLiters: finalGas,
        waterCubicMeters: finalWater,
        wasteKg: finalWaste,
        createdAt: DateTime.now(),
        fuelIsNaturalGasM3: finalGas > 0,
      ),
      conversionNotes: _uniqueNotes(conversionNotes),
    );
  }
}
