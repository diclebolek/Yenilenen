import 'package:flutter_test/flutter_test.dart';
import 'package:carbon_footprint_calculation_app/widgets/bill_scanner.dart';
import 'package:carbon_footprint_calculation_app/algorithms/calculation.dart';

void main() {
  test('parses combined utility bill sample', () {
    const sample = '''
FATURA BİLGİLERİ VE TÜKETİM ÖZETİ
ENERJİ A.Ş.
Tüketim Detayları:
Müşteri Adı: Halil Yıldız
Fatura Tarihi: 09.06.2026
Aktif Enerji Tüketimi
150,50 kWh
Toplam Doğalgaz Kullanımı:
25,30 m³
Su Tüketim Miktarı:
8,70 m³
Evsel Atık Miktarı:
12,00 kg
''';

    final result = BillOcrParser.parseConsumption(sample);
    final entry = result.entry;

    expect(entry.electricityKwh, closeTo(150.5, 0.01));
    expect(entry.fuelLiters, closeTo(25.3, 0.01));
    expect(entry.waterCubicMeters, closeTo(8.7, 0.01));
    expect(entry.wasteKg, closeTo(12.0, 0.01));
    expect(entry.fuelIsNaturalGasM3, isTrue);

    final total = Calculation.calculateDailyEmission(entry);
    expect(total, closeTo(111.97, 0.5));
  });

  test('parses electricity-only bill', () {
    const sample = 'Aktif Enerji Tüketimi 80,00 kWh';
    final entry = BillOcrParser.parseConsumption(sample).entry;
    expect(entry.electricityKwh, closeTo(80.0, 0.01));
    expect(entry.fuelLiters, 0);
    expect(entry.waterCubicMeters, 0);
    expect(entry.wasteKg, 0);
  });

  test('converts water liters to cubic meters', () {
    const sample = 'Su Tüketim Miktarı: 870 L';
    final result = BillOcrParser.parseConsumption(sample);
    expect(result.entry.waterCubicMeters, closeTo(0.87, 0.001));
    expect(result.conversionNotes, isNotEmpty);
    expect(result.conversionNotes.length, 1);
  });

  test('OCR column layout: gas label does not steal electricity kWh', () {
    const sample = '''
Toplam Doğalgaz Kullanımı:
150,50 kWh
25,30 m3
''';
    final result = BillOcrParser.parseConsumption(sample);
    expect(result.entry.fuelLiters, closeTo(25.3, 0.01));
    expect(
      result.conversionNotes.where((n) => n.contains('kWh →')),
      isEmpty,
    );
  });

  test('stacked OCR table: labels column then amounts column', () {
    const sample = '''
Aktif Enerji Tüketimi
Toplam Doğalgaz Kullanımı:
Su Tüketim Miktarı:
Evsel Atık Miktarı:
150,50 kWh
25,30 m3
8,70 m3
12,00 kg
''';
    final entry = BillOcrParser.parseConsumption(sample).entry;
    expect(entry.electricityKwh, closeTo(150.5, 0.01));
    expect(entry.fuelLiters, closeTo(25.3, 0.01));
    expect(entry.waterCubicMeters, closeTo(8.7, 0.01));
    expect(entry.wasteKg, closeTo(12.0, 0.01));
  });

  test('conversion notes are unique', () {
    const sample = '''
Toplam Doğalgaz Kullanımı:
150,50 kWh
25,30 m3
''';
    final notes = BillOcrParser.parseConsumption(sample).conversionNotes;
    expect(notes.length, notes.toSet().length);
  });

  test('parses OCR-corrupted electricity kWh label and unit', () {
    const sample = 'Akt1f Enerj1 Tüket1m1 150,5O kVVh';
    final entry = BillOcrParser.parseConsumption(sample).entry;
    expect(entry.electricityKwh, closeTo(150.5, 0.01));
  });

  test('parses OCR-corrupted natural gas with rn3 unit', () {
    const sample = 'D0gal gaz kullanimi 25,30 rn3';
    final entry = BillOcrParser.parseConsumption(sample).entry;
    expect(entry.fuelLiters, closeTo(25.3, 0.01));
    expect(entry.fuelIsNaturalGasM3, isTrue);
  });

  test('parses OCR-corrupted stacked table layout', () {
    const sample = '''
Akt1f Enerj1
D0galgaz Kullanimi
Su Tuketim Miktari
Evse1 At1k Miktari
150,5O kVVh
25,3O rn3
8,7O m O3
12,OO kg
''';
    final entry = BillOcrParser.parseConsumption(sample).entry;
    expect(entry.electricityKwh, closeTo(150.5, 0.01));
    expect(entry.fuelLiters, closeTo(25.3, 0.01));
    expect(entry.waterCubicMeters, closeTo(8.7, 0.01));
    expect(entry.wasteKg, closeTo(12.0, 0.01));
  });

  test('parseTrNumber fixes common OCR digit confusions', () {
    expect(BillOcrParser.parseTrNumber('15O,5O'), closeTo(150.5, 0.01));
    expect(BillOcrParser.parseTrNumber('l2,OO'), closeTo(12.0, 0.01));
    expect(BillOcrParser.parseTrNumber('8.7O'), closeTo(8.7, 0.01));
  });
}
