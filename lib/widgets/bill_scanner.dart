import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:developer' as dev;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/consumption_entry.dart';
import '../algorithms/calculation.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';

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
      // Windows'ta OCR desteklenmiyor, diğer platformlarda dene
      if (!kIsWeb && Platform.isWindows) {
        dev.log(
          'OCR Windows\'ta desteklenmiyor, manuel giriş kullanılacak',
          name: 'BillScanner',
        );
        return;
      }

      _textRecognizer = TextRecognizer();
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

  Future<void> _openManualEntry() async {
    // Windows için manuel veri girişi dialog'u
    final result = await showDialog<ConsumptionEntry>(
      context: context,
      builder: (context) =>
          _ManualEntryDialog(languageProvider: widget.languageProvider),
    );

    if (result != null) {
      // Karbon ayak izi hesapla
      final co2e = Calculation.calculateDailyEmission(result);
      // Dışarı bildirim
      widget.onCalculated?.call(co2e);

      // Başarı mesajı göster
      if (mounted) {
        final locale =
            widget.languageProvider?.currentLocale ?? const Locale('tr');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translate(
                'data_success',
                locale,
                params: {'co2e': co2e.toStringAsFixed(2)},
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _scanBill() async {
    setState(() {
      _isScanning = true;
    });

    try {
      XFile? image;

      // Platform kontrolü - web'de sadece galeri kullan
      if (kIsWeb) {
        // Web'de sadece galeri seçimi
        image = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
        );
      } else {
        // Mobil'de kamera veya galeri seçimi
        try {
          image = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 80,
          );
        } catch (e) {
          // Kamera hatası durumunda galeri kullan
          image = await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 80,
          );
        }
      }

      if (image == null) {
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // OCR ile metin çıkar
      if (_textRecognizer == null) {
        // OCR başlatılamadıysa kullanıcıya bilgi ver ve çık
        if (mounted) {
          final locale =
              widget.languageProvider?.currentLocale ?? const Locale('tr');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translate('windows_not_supported', locale)),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isScanning = false;
        });
        await _openManualEntry();
        return;
      }

      try {
        InputImage inputImage;
        if (kIsWeb) {
          // Web için bytes kullan
          final bytes = await image.readAsBytes();
          inputImage = InputImage.fromBytes(
            bytes: bytes,
            metadata: InputImageMetadata(
              size: const Size(800, 600), // Varsayılan boyut
              rotation: InputImageRotation.rotation0deg,
              format: InputImageFormat.bgra8888,
              bytesPerRow: 4 * 800,
            ),
          );
        } else {
          // Mobil için file path kullan
          inputImage = InputImage.fromFilePath(image.path);
        }

        final RecognizedText recognizedText =
            await _textRecognizer!.processImage(inputImage);

        // Akıllı parsing ile fatura verilerini çıkar
        final billData = _parseBillText(recognizedText.text);

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

  /// Fatura metninden tüketim verilerini çıkarır
  ConsumptionEntry _parseBillText(String text) {
    // Elektrik kWh bul
    final electricityRegex = RegExp(
      r'(\d+[,.]?\d*)\s*kWh',
      caseSensitive: false,
    );
    final electricityMatch = electricityRegex.firstMatch(text);
    final electricity = electricityMatch != null
        ? double.parse(electricityMatch.group(1)!.replaceAll(',', '.'))
        : 0.0;

    // Gaz m³ bul (doğal gaz) - daha spesifik regex
    final gasRegex = RegExp(
      r'(?:gaz|gas|doğal gaz|natural gas)[\s\S]*?(\d+[,.]?\d*)\s*m³',
      caseSensitive: false,
    );
    final gasMatch = gasRegex.firstMatch(text);
    final gas = gasMatch != null
        ? double.parse(gasMatch.group(1)!.replaceAll(',', '.'))
        : 0.0;

    // Su m³ bul - daha spesifik regex
    final waterRegex = RegExp(
      r'(?:su|water|içme suyu)[\s\S]*?(\d+[,.]?\d*)\s*m³',
      caseSensitive: false,
    );
    final waterMatch = waterRegex.firstMatch(text);
    final water = waterMatch != null
        ? double.parse(waterMatch.group(1)!.replaceAll(',', '.'))
        : 0.0;

    // Atık kg bul
    final wasteRegex = RegExp(
      r'(?:atık|waste|çöp)[\s\S]*?(\d+[,.]?\d*)\s*kg',
      caseSensitive: false,
    );
    final wasteMatch = wasteRegex.firstMatch(text);
    final waste = wasteMatch != null
        ? double.parse(wasteMatch.group(1)!.replaceAll(',', '.'))
        : 0.0;

    return ConsumptionEntry(
      electricityKwh: electricity,
      fuelLiters: gas, // Gazı yakıt olarak say
      waterCubicMeters: water,
      wasteKg: waste,
      createdAt: DateTime.now(),
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
          // Web'de görseli daha büyük göstermek için yüksekliği artır
          final double cardHeight = isWide ? 400 : 230;
          return Container(
            height: cardHeight,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/foto_yükleme.png'),
                fit: isWide
                    ? BoxFit.cover
                    : BoxFit.contain, // Web'de cover, mobilde contain
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
                            ElevatedButton.icon(
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
                                  : const Icon(
                                      kIsWeb
                                          ? Icons.photo_library
                                          : Icons.camera_alt,
                                    ),
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
                              ),
                              style: ElevatedButton.styleFrom(
                                // Buton rengi: AppBar ile aynı yeşil (tema parlaklığına göre)
                                backgroundColor: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF304411)
                                    : const Color(0xFF48631F),
                                foregroundColor: Colors.white,
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

/// Windows için manuel veri girişi dialog'u
class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog({this.languageProvider});

  final LanguageProvider? languageProvider;

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _electricityController = TextEditingController();
  final _gasController = TextEditingController();
  final _waterController = TextEditingController();
  final _wasteController = TextEditingController();

  @override
  void dispose() {
    _electricityController.dispose();
    _gasController.dispose();
    _waterController.dispose();
    _wasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return AlertDialog(
      title: Text(translate('manual_entry_title', locale)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _electricityController,
              decoration: InputDecoration(
                labelText: translate('electricity_label', locale),
                hintText: translate('electricity_hint', locale),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return translate('required_field', locale);
                }
                if (double.tryParse(value) == null) {
                  return translate('valid_number', locale);
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _gasController,
              decoration: InputDecoration(
                labelText: translate('gas_label', locale),
                hintText: translate('gas_hint', locale),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return translate('required_field', locale);
                }
                if (double.tryParse(value) == null) {
                  return translate('valid_number', locale);
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _waterController,
              decoration: InputDecoration(
                labelText: translate('water_label', locale),
                hintText: translate('water_hint', locale),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return translate('required_field', locale);
                }
                if (double.tryParse(value) == null) {
                  return translate('valid_number', locale);
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _wasteController,
              decoration: InputDecoration(
                labelText: translate('waste_label', locale),
                hintText: translate('waste_hint', locale),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return translate('required_field', locale);
                }
                if (double.tryParse(value) == null) {
                  return translate('valid_number', locale);
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('cancel', locale)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final entry = ConsumptionEntry(
                electricityKwh: double.parse(_electricityController.text),
                fuelLiters: double.parse(_gasController.text),
                waterCubicMeters: double.parse(_waterController.text),
                wasteKg: double.parse(_wasteController.text),
                createdAt: DateTime.now(),
              );
              Navigator.of(context).pop(entry);
            }
          },
          child: Text(translate('calculate', locale)),
        ),
      ],
    );
  }
}
