import 'package:flutter/material.dart';

import '../models/consumption_entry.dart';
import '../algorithms/calculation.dart';
import '../services/database_service.dart';
import '../services/firebase_realtime_service.dart';
import '../services/firebase_auth_service.dart';
import '../localization/translations.dart';
import '../providers/language_provider.dart';

enum _WaterInputUnit { cubicMeters, liters }

/// Manuel elektrik satırı — dahili olarak her zaman kWh’a normalize edilir.
enum _ElectricityManualUnit { kWh, wh, mwh }

/// Cihaz gücü girişi — dahili olarak her zaman Watt saklanır.
enum _DevicePowerUnit { watts, kilowatts }

enum _WasteInputUnit { kg, tonnes, grams }

/// Sıvı yakıt (L) veya doğalgaz sayacı (m³).
enum _FuelInputUnit { liquidLiters, naturalGasM3 }

/// Manuel giriş cam panelinde tema bağımsız ön plan / çerçeve (koyu moddaki görünümün light modda korunması için).
const Color _kManualEntryOnGlass = Color(0xFFE8F0E4);
const Color _kManualEntryOutlineOnGlass = Color(0xB3FFFFFF);

/// Kategori çerçeve/yazı vurguları — tema’dan bağımsız sabit renkler.
const Color _kAccentElectric = Color(0xFFFFC107);
const Color _kAccentWater = Color(0xFF42A5F5);
const Color _kAccentWaste = Color(0xFF8D6E63);
const Color _kAccentFuel = Color(0xFFFF9800);

/// Form to enter electricity, fuel, water, and waste data with validation.
/// Stores data in-memory and emits a calculation result via [onCalculated].
class ConsumptionForm extends StatefulWidget {
  const ConsumptionForm({
    super.key,
    required this.onCalculated,
    this.onEntryCalculated,
    this.languageProvider,
  });

  final void Function(double kgCo2e) onCalculated;
  final void Function(double kgCo2e, ConsumptionEntry entry)? onEntryCalculated;
  final LanguageProvider? languageProvider;

  @override
  State<ConsumptionForm> createState() => _ConsumptionFormState();
}

class _ConsumptionFormState extends State<ConsumptionForm>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _electricityCtrl = TextEditingController();
  final TextEditingController _fuelCtrl = TextEditingController();
  final TextEditingController _waterCtrl = TextEditingController();
  final TextEditingController _wasteCtrl = TextEditingController();

  // Ampul sayısı için yeni controller
  final TextEditingController _bulbCountCtrl = TextEditingController();
  final TextEditingController _bulbWattageCtrl = TextEditingController();
  final TextEditingController _bulbHoursCtrl = TextEditingController();

  late TabController _tabController;

  /// TabBarView yükseklikleri — sekme sırası: elektrik, atık, su, yakıt.
  static const List<double> _kTabViewHeights = [620.0, 480.0, 430.0, 500.0];
  double _tabViewHeight = 620.0;

  // Her kategori için ayrı CO2 değerleri
  double? _electricityCo2;
  double? _fuelCo2;
  double? _waterCo2;
  double? _wasteCo2;
  _WaterInputUnit _waterInputUnit = _WaterInputUnit.cubicMeters;
  _ElectricityManualUnit _electricityManualUnit = _ElectricityManualUnit.kWh;
  _WasteInputUnit _wasteInputUnit = _WasteInputUnit.kg;
  _FuelInputUnit _fuelInputUnit = _FuelInputUnit.liquidLiters;

  // Cihaz seçimi için durum
  final List<_DevicePreset> _devicePresets = const [
    _DevicePreset(
      name: 'Ampul (LED)',
      icon: Icons.lightbulb_outline,
      powerW: 9,
      hoursPerDay: 4,
    ),
    _DevicePreset(
      name: 'Buzdolabı',
      icon: Icons.kitchen,
      powerW: 120,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'PC',
      icon: Icons.computer,
      powerW: 200,
      hoursPerDay: 6,
    ),
    _DevicePreset(
      name: 'Klima (Split)',
      icon: Icons.ac_unit,
      powerW: 1200,
      hoursPerDay: 4,
    ),
    _DevicePreset(
      name: 'Kompresör',
      icon: Icons.tire_repair,
      powerW: 2000,
      hoursPerDay: 3,
    ),
    _DevicePreset(
      name: 'Sunucu',
      icon: Icons.dns,
      powerW: 400,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'Yazıcı',
      icon: Icons.print,
      powerW: 50,
      hoursPerDay: 1,
    ),
    _DevicePreset(
      name: 'Fotokopi',
      icon: Icons.print_disabled,
      powerW: 300,
      hoursPerDay: 1,
    ),
    _DevicePreset(
      name: 'Kettle',
      icon: Icons.coffee_maker,
      powerW: 1800,
      hoursPerDay: 0.5,
    ),
    _DevicePreset(
      name: 'Mikrodalga',
      icon: Icons.microwave,
      powerW: 1200,
      hoursPerDay: 0.3,
    ),
    _DevicePreset(
      name: 'Monitör',
      icon: Icons.monitor,
      powerW: 30,
      hoursPerDay: 6,
    ),
    _DevicePreset(
      name: 'Yönlendirici/Modem',
      icon: Icons.router,
      powerW: 15,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'Switch',
      icon: Icons.device_hub,
      powerW: 25,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'Raf Tipi Sunucu (1U)',
      icon: Icons.storage,
      powerW: 250,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'Güvenlik Kamerası',
      icon: Icons.videocam,
      powerW: 8,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'POS Cihazı',
      icon: Icons.point_of_sale,
      powerW: 10,
      hoursPerDay: 10,
    ),
    _DevicePreset(
      name: 'Otomat (İçecek)',
      icon: Icons.local_drink,
      powerW: 350,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'Asansör (Bekleme)',
      icon: Icons.elevator,
      powerW: 80,
      hoursPerDay: 24,
    ),
    _DevicePreset(
      name: 'Su Sebili',
      icon: Icons.water_damage,
      powerW: 100,
      hoursPerDay: 8,
    ),
  ];
  final List<_SelectedDevice> _selectedDevices = [];
  // inline panel kullanılmıyor

  // Araç seçimi için durum (yakıt)
  final List<_VehiclePreset> _vehiclePresets = const [
    _VehiclePreset(
      name: 'Binek Araç (Benzin)',
      icon: Icons.directions_car,
      litersPer100km: 7.5,
      kmPerDay: 30,
    ),
    _VehiclePreset(
      name: 'Binek Araç (Dizel)',
      icon: Icons.directions_car_filled,
      litersPer100km: 5.5,
      kmPerDay: 30,
    ),
    _VehiclePreset(
      name: 'SUV (Benzin)',
      icon: Icons.sports_motorsports,
      litersPer100km: 9.5,
      kmPerDay: 30,
    ),
    _VehiclePreset(
      name: 'Minibüs',
      icon: Icons.airport_shuttle,
      litersPer100km: 12.0,
      kmPerDay: 40,
    ),
    _VehiclePreset(
      name: 'İş Makinesi',
      icon: Icons.agriculture,
      litersPer100km: 18.0,
      kmPerDay: 20,
    ),
  ];
  final List<_SelectedVehicle> _selectedVehicles = [];
  // inline panel kullanılmıyor

  void _syncTabViewHeight() {
    final h = _kTabViewHeights[_tabController.index];
    if (_tabViewHeight != h) {
      setState(() => _tabViewHeight = h);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_syncTabViewHeight);
  }

  @override
  void dispose() {
    _tabController.removeListener(_syncTabViewHeight);
    _electricityCtrl.dispose();
    _fuelCtrl.dispose();
    _waterCtrl.dispose();
    _wasteCtrl.dispose();
    _bulbCountCtrl.dispose();
    _bulbWattageCtrl.dispose();
    _bulbHoursCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ignore: unused_element
  String? _validateNumeric(String? value) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    if (value == null || value.trim().isEmpty) {
      return translate('required', locale);
    }
    final parsed = double.tryParse(value);
    if (parsed == null) {
      return translate('valid_number_form', locale);
    }
    if (parsed < 0) {
      return translate('positive_number', locale);
    }
    return null;
  }

  // Boş bırakılabilen sayısal alanlar için doğrulama
  String? _validateOptionalNumeric(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // boş serbest
    }
    final parsed = double.tryParse(value);
    if (parsed == null) {
      return translate(
        'valid_number_form',
        widget.languageProvider?.currentLocale ?? const Locale('tr'),
      );
    }
    if (parsed < 0) {
      return translate(
        'positive_number',
        widget.languageProvider?.currentLocale ?? const Locale('tr'),
      );
    }
    return null;
  }

  double _parseOrZero(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    final v = double.tryParse(normalized);
    return (v == null || !v.isFinite) ? 0.0 : v;
  }

  /// Form alanındaki değeri her zaman m³ cinsine çevirir (hesaplama ve kayıt için).
  double _waterCubicMetersFromField() {
    final v = _parseOrZero(_waterCtrl.text);
    return _waterInputUnit == _WaterInputUnit.liters ? v / 1000.0 : v;
  }

  /// Sıfırla vb. nötr çerçeve.
  ButtonStyle get _neutralManualOutlined => OutlinedButton.styleFrom(
        foregroundColor: _kManualEntryOnGlass,
        iconColor: _kManualEntryOnGlass,
        side: const BorderSide(color: _kManualEntryOutlineOnGlass, width: 1),
      );

  ButtonStyle _outlinedAccent(Color accent) => OutlinedButton.styleFrom(
        foregroundColor: accent,
        iconColor: accent,
        side: BorderSide(color: accent, width: 1),
      );

  ButtonStyle _segmentedAccent(Color accent) => ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.all<Color>(accent),
        iconColor: WidgetStateProperty.all<Color>(accent),
        backgroundColor:
            WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.22);
          }
          return accent.withValues(alpha: 0.08);
        }),
        side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final double a =
              states.contains(WidgetState.selected) ? 0.55 : 0.35;
          return BorderSide(color: accent.withValues(alpha: a));
        }),
      );

  ButtonStyle get _manualFilledAccentStyle => FilledButton.styleFrom(
        foregroundColor: _kManualEntryOnGlass,
        iconColor: _kManualEntryOnGlass,
        backgroundColor: const Color(0xFF3D5238),
      );

  void _onWaterUnitChanged(Set<_WaterInputUnit> selected) {
    if (selected.isEmpty) return;
    final newUnit = selected.first;
    if (newUnit == _waterInputUnit) return;
    final v = _parseOrZero(_waterCtrl.text);
    if (v > 0) {
      if (_waterInputUnit == _WaterInputUnit.cubicMeters &&
          newUnit == _WaterInputUnit.liters) {
        final liters = v * 1000.0;
        _waterCtrl.text =
            liters >= 100 ? liters.round().toString() : liters.toStringAsFixed(1);
      } else if (_waterInputUnit == _WaterInputUnit.liters &&
          newUnit == _WaterInputUnit.cubicMeters) {
        final m3 = v / 1000.0;
        _waterCtrl.text = m3.toStringAsFixed(m3 < 1 ? 4 : 3);
      }
    }
    setState(() {
      _waterInputUnit = newUnit;
      _waterCo2 = null;
    });
  }

  /// Manuel elektrik alanı — seçilen birime göre günlük kWh.
  double _manualElectricityKwhFromField() {
    final v = _parseOrZero(_electricityCtrl.text);
    switch (_electricityManualUnit) {
      case _ElectricityManualUnit.kWh:
        return v;
      case _ElectricityManualUnit.wh:
        return v / 1000.0;
      case _ElectricityManualUnit.mwh:
        return v * 1000.0;
    }
  }

  void _onElectricityManualUnitChanged(Set<_ElectricityManualUnit> selected) {
    if (selected.isEmpty) return;
    final newUnit = selected.first;
    if (newUnit == _electricityManualUnit) return;
    final v = _parseOrZero(_electricityCtrl.text);
    if (v > 0) {
      final kwhEquiv = _manualElectricityKwhFromField();
      switch (newUnit) {
        case _ElectricityManualUnit.kWh:
          _electricityCtrl.text = kwhEquiv < 1
              ? kwhEquiv.toStringAsFixed(5)
              : kwhEquiv.toStringAsFixed(kwhEquiv < 10 ? 3 : 2);
          break;
        case _ElectricityManualUnit.wh:
          final wh = kwhEquiv * 1000.0;
          _electricityCtrl.text =
              wh >= 100 ? wh.round().toString() : wh.toStringAsFixed(1);
          break;
        case _ElectricityManualUnit.mwh:
          _electricityCtrl.text =
              (kwhEquiv / 1000.0).toStringAsFixed(kwhEquiv >= 1000 ? 4 : 6);
          break;
      }
    }
    setState(() {
      _electricityManualUnit = newUnit;
      _electricityCo2 = null;
    });
  }

  double _wasteKgFromField() {
    final v = _parseOrZero(_wasteCtrl.text);
    switch (_wasteInputUnit) {
      case _WasteInputUnit.kg:
        return v;
      case _WasteInputUnit.tonnes:
        return v * 1000.0;
      case _WasteInputUnit.grams:
        return v / 1000.0;
    }
  }

  void _onWasteUnitChanged(Set<_WasteInputUnit> selected) {
    if (selected.isEmpty) return;
    final newUnit = selected.first;
    if (newUnit == _wasteInputUnit) return;
    final v = _parseOrZero(_wasteCtrl.text);
    if (v > 0) {
      final kgEquiv = _wasteKgFromField();
      switch (newUnit) {
        case _WasteInputUnit.kg:
          _wasteCtrl.text = kgEquiv.toStringAsFixed(kgEquiv < 1 ? 4 : 3);
          break;
        case _WasteInputUnit.tonnes:
          _wasteCtrl.text =
              (kgEquiv / 1000.0).toStringAsFixed(kgEquiv >= 10000 ? 4 : 6);
          break;
        case _WasteInputUnit.grams:
          final g = kgEquiv * 1000.0;
          _wasteCtrl.text = g >= 100 ? g.round().toString() : g.toStringAsFixed(1);
          break;
      }
    }
    setState(() {
      _wasteInputUnit = newUnit;
      _wasteCo2 = null;
    });
  }

  /// Yakıt CO₂ (manuel satır + araçlar); sıvı L veya gaz m³.
  double _fuelCo2FromManualAndVehicles() {
    final manual = _parseOrZero(_fuelCtrl.text);
    final veh = _calculateVehiclesFuelLiters();
    if (_fuelInputUnit == _FuelInputUnit.naturalGasM3) {
      return manual * Calculation.factorNaturalGasKgPerM3 +
          veh * Calculation.factorFuelKgPerLiter;
    }
    return (manual + veh) * Calculation.factorFuelKgPerLiter;
  }

  void _onFuelUnitChanged(Set<_FuelInputUnit> selected) {
    if (selected.isEmpty) return;
    final nu = selected.first;
    if (nu == _fuelInputUnit) return;
    setState(() {
      _fuelInputUnit = nu;
      _fuelCo2 = null;
    });
  }

  // Ampul hesaplaması için yardımcı fonksiyon
  // ignore: unused_element
  double _calculateBulbElectricity() {
    final count = double.tryParse(_bulbCountCtrl.text) ?? 0;
    final wattage = double.tryParse(_bulbWattageCtrl.text) ?? 0;
    final hours = double.tryParse(_bulbHoursCtrl.text) ?? 0;

    // kWh = (Ampul sayısı × Watt × Saat) / 1000
    return (count * wattage * hours) / 1000;
  }

  // Ampul alanları değiştiğinde UI'yi güncelle
  // ignore: unused_element
  void _onBulbFieldChanged() {
    setState(() {});
  }

  // Cihazların toplam kWh/gün hesaplanması
  double _calculateDevicesElectricity() {
    double total = 0;
    for (final d in _selectedDevices) {
      // kWh = (W × saat/gün × adet) / 1000
      total += (d.powerW * d.hoursPerDay * d.quantity) / 1000.0;
    }
    return total;
  }

  // Cihaz seçim dialogu (eski) - inline panele geçildi (referans korunuyor)
  // ignore: unused_element
  void _openDeviceDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: StatefulBuilder(
            builder: (context, setStateLocal) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Cihaz Seç',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.black),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _devicePresets
                            .map(
                              (p) => _DeviceTile(
                                preset: p,
                                onAddQuantity: (qty) {
                                  final existing = _selectedDevices.firstWhere(
                                    (e) => e.name == p.name,
                                    orElse: () => _SelectedDevice(
                                      name: p.name,
                                      powerW: p.powerW,
                                      hoursPerDay: p.hoursPerDay,
                                    ),
                                  );
                                  if (!_selectedDevices.contains(existing)) {
                                    _selectedDevices.add(
                                      _SelectedDevice(
                                        name: existing.name,
                                        powerW: existing.powerW,
                                        hoursPerDay: existing.hoursPerDay,
                                        quantity: qty,
                                      ),
                                    );
                                  } else {
                                    existing.quantity =
                                        (existing.quantity + qty).clamp(
                                      1,
                                      9999,
                                    );
                                  }
                                  setState(() {});
                                  setStateLocal(() {});
                                  // Cihaz eklendiğinde elektrik hesaplamasını güncelle
                                  _calculateCategory('electricity');
                                  // Toplam hesaplama ve kayıt yap (validation olmadan)
                                  _calculateTotal(skipValidation: true);
                                },
                                onEdit: () async {
                                  await _editDevice(p);
                                  setState(() {});
                                  setStateLocal(() {});
                                  // Cihaz düzenlendiğinde elektrik hesaplamasını güncelle
                                  _calculateCategory('electricity');
                                  // Toplam hesaplama ve kayıt yap (validation olmadan)
                                  _calculateTotal(skipValidation: true);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedDevices.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seçilen Cihazlar',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            ..._selectedDevices.map(
                              (d) => Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${d.name} • ${d.powerW.toStringAsFixed(0)}W • ${d.hoursPerDay.toStringAsFixed(1)} s/g',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.black),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      d.quantity = (d.quantity + 1).clamp(
                                        1,
                                        9999,
                                      );
                                      setState(() {});
                                      setStateLocal(() {});
                                      // Cihaz miktarı değiştiğinde elektrik hesaplamasını güncelle
                                      _calculateCategory('electricity');
                                      // Toplam hesaplama ve kayıt yap (validation olmadan)
                                      _calculateTotal(skipValidation: true);
                                    },
                                    icon: const Icon(
                                      Icons.add_circle,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '${d.quantity}',
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      if (d.quantity > 1) {
                                        d.quantity -= 1;
                                      } else {
                                        _selectedDevices.remove(d);
                                      }
                                      setState(() {});
                                      setStateLocal(() {});
                                      // Cihaz miktarı değiştiğinde elektrik hesaplamasını güncelle
                                      _calculateCategory('electricity');
                                      // Toplam hesaplama ve kayıt yap (validation olmadan)
                                      _calculateTotal(skipValidation: true);
                                    },
                                    icon: const Icon(
                                      Icons.remove_circle,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Toplam (kWh/gün): ${_calculateDevicesElectricity().toStringAsFixed(2)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Tamam',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Araçların toplam yakıt tüketimi (litre/gün)
  double _calculateVehiclesFuelLiters() {
    double total = 0;
    for (final v in _selectedVehicles) {
      // litre/gün = (l/100km) * (km/gün) * adet / 100
      total += (v.litersPer100km * v.kmPerDay * v.quantity) / 100.0;
    }
    return total;
  }

  // Araç seçim dialogu (eski) - inline panele geçildi (referans korunuyor)
  void _openVehicleDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: StatefulBuilder(
            builder: (context, setStateLocal) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Araç Seç',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _vehiclePresets
                            .map(
                              (p) => _VehicleTile(
                                preset: p,
                                onAdd: () {
                                  final existing = _selectedVehicles.firstWhere(
                                    (e) => e.name == p.name,
                                    orElse: () => _SelectedVehicle(
                                      name: p.name,
                                      litersPer100km: p.litersPer100km,
                                      kmPerDay: p.kmPerDay,
                                    ),
                                  );
                                  if (!_selectedVehicles.contains(existing)) {
                                    _selectedVehicles.add(existing);
                                  } else {
                                    existing.quantity += 1;
                                  }
                                  setState(() {});
                                  setStateLocal(() {});
                                },
                                onEdit: () async {
                                  await _editVehicle(p);
                                  setState(() {});
                                  setStateLocal(() {});
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedVehicles.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seçilen Araçlar',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            ..._selectedVehicles.map(
                              (v) => Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${v.name} • ${v.litersPer100km.toStringAsFixed(1)} l/100km • ${v.kmPerDay.toStringAsFixed(1)} km/g',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      v.quantity = (v.quantity + 1).clamp(
                                        1,
                                        9999,
                                      );
                                      setState(() {});
                                      setStateLocal(() {});
                                    },
                                    icon: Icon(
                                      Icons.add_circle,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  Text(
                                    '${v.quantity}',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      if (v.quantity > 1) {
                                        v.quantity -= 1;
                                      } else {
                                        _selectedVehicles.remove(v);
                                      }
                                      setState(() {});
                                      setStateLocal(() {});
                                    },
                                    icon: Icon(
                                      Icons.remove_circle,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Toplam (L/gün): ${_calculateVehiclesFuelLiters().toStringAsFixed(2)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimary,
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                            child: const Text(
                              'Tamam',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editVehicle(_VehiclePreset preset) async {
    final TextEditingController l100Ctrl = TextEditingController(
      text: preset.litersPer100km.toStringAsFixed(1),
    );
    final TextEditingController kmCtrl = TextEditingController(
      text: preset.kmPerDay.toStringAsFixed(1),
    );

    final existing = _selectedVehicles.firstWhere(
      (e) => e.name == preset.name,
      orElse: () => _SelectedVehicle(
        name: preset.name,
        litersPer100km: preset.litersPer100km,
        kmPerDay: preset.kmPerDay,
      ),
    );
    l100Ctrl.text = existing.litersPer100km.toStringAsFixed(1);
    kmCtrl.text = existing.kmPerDay.toStringAsFixed(1);

    await showDialog(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(
            'Düzenle: ${preset.name}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: l100Ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: scheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Litre / 100km',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: scheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Km / Gün',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'İptal',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () {
                final l100 = double.tryParse(l100Ctrl.text);
                final km = double.tryParse(kmCtrl.text);
                if (l100 != null && km != null && l100 >= 0 && km >= 0) {
                  if (_selectedVehicles.contains(existing)) {
                    existing
                      ..litersPer100km = l100
                      ..kmPerDay = km;
                  } else {
                    _selectedVehicles.add(
                      _SelectedVehicle(
                        name: preset.name,
                        litersPer100km: l100,
                        kmPerDay: km,
                      ),
                    );
                  }
                }
                Navigator.of(context).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  Future<_SelectedDevice?> _customizeNewDevice(_DevicePreset preset) async {
    final TextEditingController powerCtrl = TextEditingController(
      text: preset.powerW.toStringAsFixed(0),
    );
    final TextEditingController hoursCtrl = TextEditingController(
      text: preset.hoursPerDay.toStringAsFixed(1),
    );

    _SelectedDevice? result;

    await showDialog(
      context: context,
      builder: (context) {
        var powerUnit = _DevicePowerUnit.watts;
        final scheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: scheme.surface,
              title: Text(
                'Düzenle: ${preset.name}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<_DevicePowerUnit>(
                    segments: const [
                      ButtonSegment(
                        value: _DevicePowerUnit.watts,
                        label: Text('W'),
                      ),
                      ButtonSegment(
                        value: _DevicePowerUnit.kilowatts,
                        label: Text('kW'),
                      ),
                    ],
                    selected: {powerUnit},
                    onSelectionChanged: (Set<_DevicePowerUnit> s) {
                      if (s.isEmpty) return;
                      final nu = s.first;
                      if (nu == powerUnit) return;
                      final t = powerCtrl.text.replaceAll(',', '.').trim();
                      final pv = double.tryParse(t);
                      if (pv != null && pv >= 0) {
                        if (powerUnit == _DevicePowerUnit.watts &&
                            nu == _DevicePowerUnit.kilowatts) {
                          powerCtrl.text = (pv / 1000.0).toStringAsFixed(
                            pv >= 100000 ? 2 : 4,
                          );
                        } else if (powerUnit == _DevicePowerUnit.kilowatts &&
                            nu == _DevicePowerUnit.watts) {
                          powerCtrl.text = (pv * 1000.0).round().toString();
                        }
                      }
                      setLocal(() => powerUnit = nu);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: powerCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: powerUnit == _DevicePowerUnit.kilowatts
                          ? 'Güç (kW)'
                          : 'Güç (W)',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hoursCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Saat / Gün',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'İptal',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    foregroundColor: scheme.onPrimary,
                    backgroundColor: scheme.primary,
                  ),
                  onPressed: () {
                    final pwIn = double.tryParse(
                      powerCtrl.text.replaceAll(',', '.').trim(),
                    );
                    final hr = double.tryParse(
                      hoursCtrl.text.replaceAll(',', '.').trim(),
                    );
                    if (pwIn != null &&
                        hr != null &&
                        pwIn >= 0 &&
                        hr >= 0) {
                      final powerW = powerUnit == _DevicePowerUnit.kilowatts
                          ? pwIn * 1000.0
                          : pwIn;
                      result = _SelectedDevice(
                        name: preset.name,
                        powerW: powerW,
                        hoursPerDay: hr,
                      );
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _editDevice(_DevicePreset preset) async {
    final TextEditingController powerCtrl = TextEditingController(
      text: preset.powerW.toStringAsFixed(0),
    );
    final TextEditingController hoursCtrl = TextEditingController(
      text: preset.hoursPerDay.toStringAsFixed(1),
    );

    // Eğer seçilenler arasında varsa mevcut değerleri yükle
    final existing = _selectedDevices.firstWhere(
      (e) => e.name == preset.name,
      orElse: () => _SelectedDevice(
        name: preset.name,
        powerW: preset.powerW,
        hoursPerDay: preset.hoursPerDay,
      ),
    );
    powerCtrl.text = existing.powerW.toStringAsFixed(0);
    hoursCtrl.text = existing.hoursPerDay.toStringAsFixed(1);

    await showDialog(
      context: context,
      builder: (context) {
        var powerUnit = _DevicePowerUnit.watts;
        final scheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: scheme.surface,
              title: Text(
                'Düzenle: ${preset.name}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<_DevicePowerUnit>(
                    segments: const [
                      ButtonSegment(
                        value: _DevicePowerUnit.watts,
                        label: Text('W'),
                      ),
                      ButtonSegment(
                        value: _DevicePowerUnit.kilowatts,
                        label: Text('kW'),
                      ),
                    ],
                    selected: {powerUnit},
                    onSelectionChanged: (Set<_DevicePowerUnit> s) {
                      if (s.isEmpty) return;
                      final nu = s.first;
                      if (nu == powerUnit) return;
                      final t = powerCtrl.text.replaceAll(',', '.').trim();
                      final pv = double.tryParse(t);
                      if (pv != null && pv >= 0) {
                        if (powerUnit == _DevicePowerUnit.watts &&
                            nu == _DevicePowerUnit.kilowatts) {
                          powerCtrl.text = (pv / 1000.0).toStringAsFixed(
                            pv >= 100000 ? 2 : 4,
                          );
                        } else if (powerUnit == _DevicePowerUnit.kilowatts &&
                            nu == _DevicePowerUnit.watts) {
                          powerCtrl.text = (pv * 1000.0).round().toString();
                        }
                      }
                      setLocal(() => powerUnit = nu);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: powerCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: powerUnit == _DevicePowerUnit.kilowatts
                          ? 'Güç (kW)'
                          : 'Güç (W)',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hoursCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Saat / Gün',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'İptal',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    foregroundColor: scheme.onPrimary,
                    backgroundColor: scheme.primary,
                  ),
                  onPressed: () {
                    final pwIn = double.tryParse(
                      powerCtrl.text.replaceAll(',', '.').trim(),
                    );
                    final hr = double.tryParse(
                      hoursCtrl.text.replaceAll(',', '.').trim(),
                    );
                    if (pwIn != null &&
                        hr != null &&
                        pwIn >= 0 &&
                        hr >= 0) {
                      final powerW = powerUnit == _DevicePowerUnit.kilowatts
                          ? pwIn * 1000.0
                          : pwIn;
                      setState(() {
                        if (_selectedDevices.contains(existing)) {
                          existing
                            ..powerW = powerW
                            ..hoursPerDay = hr;
                        } else {
                          _selectedDevices.add(
                            _SelectedDevice(
                              name: preset.name,
                              powerW: powerW,
                              hoursPerDay: hr,
                            ),
                          );
                        }
                      });
                      _calculateCategory('electricity');
                      _calculateTotal(skipValidation: true);
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Eski _submit fonksiyonu _calculateTotal olarak değiştirildi

  @override
  Widget build(BuildContext context) {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return Card(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      translate('manual_data_entry', locale),
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _calculateTotal,
                    icon: const Icon(Icons.calculate, size: 20),
                    label: const Text('TOPLAM CO₂ HESAPLA'),
                    style: _manualFilledAccentStyle.copyWith(
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 8),

              // Kategori seçim tabları
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: UnderlineTabIndicator(
                    borderSide: BorderSide(
                      width: 3.0,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    insets: const EdgeInsets.symmetric(horizontal: 8.0),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w400,
                  ),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.electrical_services, size: 20),
                      text: translate(
                        'electricity',
                        widget.languageProvider?.currentLocale ??
                            const Locale('tr'),
                      ),
                    ),
                    Tab(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      text: translate(
                        'waste',
                        widget.languageProvider?.currentLocale ??
                            const Locale('tr'),
                      ),
                    ),
                    Tab(
                      icon: const Icon(Icons.water_drop, size: 20),
                      text: translate(
                        'water',
                        widget.languageProvider?.currentLocale ??
                            const Locale('tr'),
                      ),
                    ),
                    Tab(
                      icon: const Icon(Icons.local_gas_station, size: 20),
                      text: translate(
                        'fuel',
                        widget.languageProvider?.currentLocale ??
                            const Locale('tr'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Tab içerikleri (yükseklik sekmeye göre; kısa formlarda gereksiz boşluk olmasın)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: _tabViewHeight,
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      SingleChildScrollView(child: _buildElectricityTab()),
                      SingleChildScrollView(child: _buildWasteTab()),
                      SingleChildScrollView(child: _buildWaterTab()),
                      SingleChildScrollView(child: _buildFuelTab()),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: _neutralManualOutlined,
                  onPressed: _resetForm,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    translate(
                      'reset',
                      widget.languageProvider?.currentLocale ??
                          const Locale('tr'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Elektrik kategorisi - ampul hesaplaması dahil
  Widget _buildElectricityTab() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('electricity_consumption', locale),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<_ElectricityManualUnit>(
          segments: [
            ButtonSegment<_ElectricityManualUnit>(
              value: _ElectricityManualUnit.kWh,
              label: Text(translate('electricity_unit_kwh', locale)),
              icon: const Icon(Icons.bolt, size: 18),
            ),
            ButtonSegment<_ElectricityManualUnit>(
              value: _ElectricityManualUnit.wh,
              label: Text(translate('electricity_unit_wh', locale)),
              icon: const Icon(Icons.flash_on, size: 18),
            ),
            ButtonSegment<_ElectricityManualUnit>(
              value: _ElectricityManualUnit.mwh,
              label: Text(translate('electricity_unit_mwh', locale)),
              icon: const Icon(Icons.power, size: 18),
            ),
          ],
          selected: {_electricityManualUnit},
          onSelectionChanged: _onElectricityManualUnitChanged,
          style: _segmentedAccent(_kAccentElectric),
        ),
        const SizedBox(height: 8),
        Text(
          translate('electricity_tip_manual_units', locale),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _kManualEntryOnGlass.withValues(alpha: 0.88),
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _electricityCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _electricityManualUnit == _ElectricityManualUnit.kWh
                ? translate('electricity_label_kwh', locale)
                : _electricityManualUnit == _ElectricityManualUnit.wh
                    ? translate('electricity_label_wh', locale)
                    : translate('electricity_label_mwh', locale),
            hintText: _electricityManualUnit == _ElectricityManualUnit.kWh
                ? translate('electricity_hint_kwh', locale)
                : _electricityManualUnit == _ElectricityManualUnit.wh
                    ? translate('electricity_hint_wh', locale)
                    : translate('electricity_hint_mwh', locale),
            prefixIcon: const Icon(Icons.electrical_services),
          ),
          validator: _validateOptionalNumeric,
          onChanged: (value) {
            // Değer değiştiğinde hesaplamayı sıfırla
            setState(() => _electricityCo2 = null);
          },
        ),
        const SizedBox(height: 12),

        // Elektrik için hesaplama butonu ve sonuç
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _outlinedAccent(_kAccentElectric),
                onPressed: () => _calculateCategory('electricity'),
                icon: const Icon(Icons.calculate),
                label: const Text('Elektrik CO₂ Hesapla'),
              ),
            ),
            if (_electricityCo2 != null) ...[
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_electricityCo2!.toStringAsFixed(2)} kg CO₂e',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Ampul hesaplaması bölümü kaldırıldı; ampul cihaz kartları listesine eklendi
        // Cihaz seçimi (butonsuz, inline panel - tasarıma uygun saydam zemin)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.devices_other,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cihazlar',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth >= 900;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment:
                        isWide ? WrapAlignment.start : WrapAlignment.center,
                    children: _devicePresets
                        .map(
                          (p) => _DeviceTile(
                            preset: p,
                            onAddQuantity: (qty) {
                              setState(() {
                                _selectedDevices.add(
                                  _SelectedDevice(
                                    name: p.name,
                                    powerW: p.powerW,
                                    hoursPerDay: p.hoursPerDay,
                                    quantity: qty,
                                  ),
                                );
                              });
                              // Cihaz eklendiğinde elektrik hesaplamasını güncelle
                              _calculateCategory('electricity');
                              // Toplam hesaplama ve kayıt yap (validation olmadan)
                              _calculateTotal(skipValidation: true);
                            },
                            onEdit: () async {
                              final customized = await _customizeNewDevice(p);
                              if (customized != null) {
                                setState(
                                  () => _selectedDevices.add(customized),
                                );
                                // Cihaz eklendiğinde elektrik hesaplamasını güncelle
                                _calculateCategory('electricity');
                                // Toplam hesaplama ve kayıt yap (validation olmadan)
                                _calculateTotal(skipValidation: true);
                              }
                            },
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_selectedDevices.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _selectedDevices
                  .map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        label: Text('${d.name} x${d.quantity}'),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _selectedDevices.remove(d));
                          // Cihaz silindiğinde elektrik hesaplamasını güncelle
                          _calculateCategory('electricity');
                          // Toplam hesaplama ve kayıt yap (validation olmadan)
                          _calculateTotal(skipValidation: true);
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 12),
        // inline cihaz paneli kaldırıldı, diyalog kullanılacak
      ],
    );
  }

  // Yakıt kategorisi
  Widget _buildFuelTab() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('fuel_consumption', locale),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<_FuelInputUnit>(
          segments: [
            ButtonSegment<_FuelInputUnit>(
              value: _FuelInputUnit.liquidLiters,
              label: Text(translate('fuel_unit_liquid', locale)),
              icon: const Icon(Icons.local_gas_station, size: 18),
            ),
            ButtonSegment<_FuelInputUnit>(
              value: _FuelInputUnit.naturalGasM3,
              label: Text(translate('fuel_unit_gas', locale)),
              icon: const Icon(Icons.local_fire_department, size: 18),
            ),
          ],
          selected: {_fuelInputUnit},
          onSelectionChanged: _onFuelUnitChanged,
          style: _segmentedAccent(_kAccentFuel),
        ),
        const SizedBox(height: 8),
        Text(
          translate('fuel_tip_units', locale),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _kManualEntryOnGlass.withValues(alpha: 0.88),
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _fuelCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _fuelInputUnit == _FuelInputUnit.liquidLiters
                ? translate('fuel_label_liquid', locale)
                : translate('fuel_label_gas', locale),
            hintText: _fuelInputUnit == _FuelInputUnit.liquidLiters
                ? translate('fuel_hint_liquid', locale)
                : translate('fuel_hint_gas', locale),
            prefixIcon: const Icon(Icons.local_gas_station),
          ),
          validator: _validateOptionalNumeric,
          onChanged: (value) {
            setState(() => _fuelCo2 = null);
          },
        ),
        const SizedBox(height: 12),

        // Yakıt için hesaplama butonu ve sonuç
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _outlinedAccent(_kAccentFuel),
                onPressed: () => _calculateCategory('fuel'),
                icon: const Icon(Icons.calculate),
                label: const Text('Yakıt CO₂ Hesapla'),
              ),
            ),
            if (_fuelCo2 != null) ...[
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_fuelCo2!.toStringAsFixed(2)} kg CO₂e',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Araç ekleme butonu ve seçilen araçlar
        Row(
          children: [
            OutlinedButton.icon(
              style: _outlinedAccent(_kAccentFuel),
              onPressed: _openVehicleDialog,
              icon: const Icon(Icons.add_road),
              label: const Text('Araç ekle'),
            ),
            const SizedBox(width: 8),
            if (_selectedVehicles.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _selectedVehicles
                        .map(
                          (v) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Chip(
                              label: Text('${v.name} x${v.quantity}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setState(() => _selectedVehicles.remove(v));
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // inline araç paneli kaldırıldı, diyalog kullanılacak
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('tip', locale),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _kManualEntryOnGlass,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                translate('fuel_tip', locale),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _kManualEntryOnGlass,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Su kategorisi
  Widget _buildWaterTab() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('water_consumption', locale),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<_WaterInputUnit>(
          segments: [
            ButtonSegment<_WaterInputUnit>(
              value: _WaterInputUnit.cubicMeters,
              label: Text(translate('water_unit_m3', locale)),
              icon: const Icon(Icons.crop_square, size: 18),
            ),
            ButtonSegment<_WaterInputUnit>(
              value: _WaterInputUnit.liters,
              label: Text(translate('water_unit_liters', locale)),
              icon: const Icon(Icons.opacity, size: 18),
            ),
          ],
          selected: {_waterInputUnit},
          onSelectionChanged: _onWaterUnitChanged,
          style: _segmentedAccent(_kAccentWater),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _waterCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _waterInputUnit == _WaterInputUnit.cubicMeters
                ? translate('water_cubic', locale)
                : translate('water_liters_label', locale),
            hintText: _waterInputUnit == _WaterInputUnit.cubicMeters
                ? translate('water_hint_form', locale)
                : translate('water_hint_liters', locale),
            prefixIcon: const Icon(Icons.water_drop),
          ),
          validator: _validateOptionalNumeric,
          onChanged: (value) {
            setState(() => _waterCo2 = null);
          },
        ),
        const SizedBox(height: 12),

        // Su için hesaplama butonu ve sonuç
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _outlinedAccent(_kAccentWater),
                onPressed: () => _calculateCategory('water'),
                icon: const Icon(Icons.calculate),
                label: const Text('Su CO₂ Hesapla'),
              ),
            ),
            if (_waterCo2 != null) ...[
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_waterCo2!.toStringAsFixed(2)} kg CO₂e',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('tip', locale),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _kManualEntryOnGlass,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _waterInputUnit == _WaterInputUnit.cubicMeters
                    ? translate('water_tip', locale)
                    : translate('water_tip_liters', locale),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _kManualEntryOnGlass,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Atık kategorisi
  Widget _buildWasteTab() {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('waste_production', locale),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<_WasteInputUnit>(
          segments: [
            ButtonSegment<_WasteInputUnit>(
              value: _WasteInputUnit.kg,
              label: Text(translate('waste_unit_kg', locale)),
              icon: const Icon(Icons.scale, size: 18),
            ),
            ButtonSegment<_WasteInputUnit>(
              value: _WasteInputUnit.tonnes,
              label: Text(translate('waste_unit_tonnes', locale)),
              icon: const Icon(Icons.inventory_2, size: 18),
            ),
            ButtonSegment<_WasteInputUnit>(
              value: _WasteInputUnit.grams,
              label: Text(translate('waste_unit_g', locale)),
              icon: const Icon(Icons.pie_chart_outline, size: 18),
            ),
          ],
          selected: {_wasteInputUnit},
          onSelectionChanged: _onWasteUnitChanged,
          style: _segmentedAccent(_kAccentWaste),
        ),
        const SizedBox(height: 8),
        Text(
          translate('waste_tip_units', locale),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _kManualEntryOnGlass.withValues(alpha: 0.88),
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _wasteCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _wasteInputUnit == _WasteInputUnit.kg
                ? translate('waste_label_kg', locale)
                : _wasteInputUnit == _WasteInputUnit.tonnes
                    ? translate('waste_label_tonnes', locale)
                    : translate('waste_label_g', locale),
            hintText: _wasteInputUnit == _WasteInputUnit.kg
                ? translate('waste_hint_kg', locale)
                : _wasteInputUnit == _WasteInputUnit.tonnes
                    ? translate('waste_hint_tonnes', locale)
                    : translate('waste_hint_g', locale),
            prefixIcon: const Icon(Icons.delete_outline),
          ),
          validator: _validateOptionalNumeric,
          onChanged: (value) {
            setState(() => _wasteCo2 = null);
          },
        ),
        const SizedBox(height: 12),

        // Atık için hesaplama butonu ve sonuç
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _outlinedAccent(_kAccentWaste),
                onPressed: () => _calculateCategory('waste'),
                icon: const Icon(Icons.calculate),
                label: const Text('Atık CO₂ Hesapla'),
              ),
            ),
            if (_wasteCo2 != null) ...[
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_wasteCo2!.toStringAsFixed(2)} kg CO₂e',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('tip', locale),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _kManualEntryOnGlass,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                translate('waste_tip', locale),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _kManualEntryOnGlass,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Kategori bazlı özet gösterimi
        if (_electricityCo2 != null ||
            _fuelCo2 != null ||
            _waterCo2 != null ||
            _wasteCo2 != null)
          Builder(
            builder: (context) {
              final totalCo2 = ((_electricityCo2 ?? 0) +
                  (_fuelCo2 ?? 0) +
                  (_waterCo2 ?? 0) +
                  (_wasteCo2 ?? 0));
              // Çok yüksek değer kontrolü: 100,000 kg CO₂e'den fazla ise uyarı göster
              final bool isVeryHigh = totalCo2 > 100000;
              final bool hasExtremeValue = (_fuelCo2 ?? 0) > 1000000 ||
                  (_waterCo2 ?? 0) > 1000000 ||
                  (_wasteCo2 ?? 0) > 1000000 ||
                  (_electricityCo2 ?? 0) > 1000000;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isVeryHigh || hasExtremeValue)
                        ? Colors.red.withValues(alpha: 0.5)
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                    width: (isVeryHigh || hasExtremeValue) ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Kategori Bazlı CO₂ Özeti:',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (isVeryHigh || hasExtremeValue) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Değerler çok yüksek! Lütfen kontrol edin.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_electricityCo2 != null)
                      _CategorySummaryRow(
                          label: 'Elektrik',
                          co2: _electricityCo2!,
                          color: Colors.orange,
                          isHigh: _electricityCo2! > 1000000),
                    if (_fuelCo2 != null)
                      _CategorySummaryRow(
                          label: 'Yakıt',
                          co2: _fuelCo2!,
                          color: Colors.red,
                          isHigh: _fuelCo2! > 1000000),
                    if (_waterCo2 != null)
                      _CategorySummaryRow(
                          label: 'Su',
                          co2: _waterCo2!,
                          color: Colors.blue,
                          isHigh: _waterCo2! > 1000000),
                    if (_wasteCo2 != null)
                      _CategorySummaryRow(
                          label: 'Atık',
                          co2: _wasteCo2!,
                          color: Colors.grey,
                          isHigh: _wasteCo2! > 1000000),
                    const SizedBox(height: 8),
                    Divider(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOPLAM:',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Row(
                          children: [
                            if (isVeryHigh || hasExtremeValue)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                              ),
                            Text(
                              '${totalCo2.toStringAsFixed(2)} kg CO₂e',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: (isVeryHigh || hasExtremeValue)
                                        ? Colors.red
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // Her kategori için ayrı hesaplama
  void _calculateCategory(String category) {
    double co2 = 0.0;
    switch (category) {
      case 'electricity':
        // Manuel satır (birime göre kWh) + cihazlardan gelen kWh/gün toplamı
        final electricityKwh = _manualElectricityKwhFromField() +
            _calculateDevicesElectricity();
        co2 = electricityKwh * Calculation.factorElectricityKgPerKwh;
        setState(() => _electricityCo2 = co2);
        break;
      case 'fuel':
        co2 = _fuelCo2FromManualAndVehicles();
        setState(() => _fuelCo2 = co2);
        break;
      case 'water':
        final waterCubicMeters = _waterCubicMetersFromField();
        co2 = waterCubicMeters * Calculation.factorWaterKgPerM3;
        setState(() => _waterCo2 = co2);
        break;
      case 'waste':
        co2 = _wasteKgFromField() * Calculation.factorWasteKgPerKg;
        setState(() => _wasteCo2 = co2);
        break;
    }
  }

  // Toplam hesaplama (son sekmede)
  void _calculateTotal({bool skipValidation = false}) {
    if (!skipValidation && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Önce tüm kategorileri hesapla
    _calculateCategory('electricity');
    _calculateCategory('fuel');
    _calculateCategory('water');
    _calculateCategory('waste');

    // Elektrik tüketimi: Manuel alan (kWh’a normalize) + cihazlar kWh/gün
    double electricityKwh =
        _manualElectricityKwhFromField() + _calculateDevicesElectricity();

    final manualFuel = _parseOrZero(_fuelCtrl.text);
    final vehL = _calculateVehiclesFuelLiters();
    final bool gasFuel = _fuelInputUnit == _FuelInputUnit.naturalGasM3;

    final entry = ConsumptionEntry(
      electricityKwh: electricityKwh,
      fuelLiters: gasFuel ? manualFuel : manualFuel + vehL,
      waterCubicMeters: _waterCubicMetersFromField(),
      wasteKg: _wasteKgFromField(),
      createdAt: DateTime.now(),
      fuelIsNaturalGasM3: gasFuel,
      additiveLiquidFuelLiters: gasFuel ? vehL : 0,
    );
    final result = Calculation.calculateDailyEmission(entry);
    // Update shared readings for goals auto-check
    final db = DatabaseService.instance;
    db.updateReading('Elektrik (kWh)', entry.electricityKwh);
    db.updateReading('Yakıt (litre)', entry.fuelLiters);
    db.updateReading('Su (m³)', entry.waterCubicMeters);
    db.updateReading('Atık (kg)', entry.wasteKg);

    // Manuel verileri Firebase'e kaydet (kullanıcı giriş yapmışsa)
    // Fire-and-forget: await etmeden arka planda kaydet
    final userId = FirebaseAuthService.instance.currentUser?.uid;
    if (userId != null) {
      FirebaseRealtimeService.instance
          .saveManualData(
        userId: userId,
        consumption: entry,
      )
          .catchError((e) {
        // Firebase hatası olsa bile devam et (kullanıcı deneyimini bozma)
        debugPrint('Manuel veri Firebase kayıt hatası: $e');
      });
    }

    widget.onCalculated(result);
    // Eğer onEntryCalculated callback'i varsa, hem toplam emisyonu hem de entry'yi döndür
    widget.onEntryCalculated?.call(result, entry);
  }

  // Form sıfırlama fonksiyonu
  void _resetForm() {
    _electricityCtrl.clear();
    _electricityManualUnit = _ElectricityManualUnit.kWh;
    _fuelCtrl.clear();
    _fuelInputUnit = _FuelInputUnit.liquidLiters;
    _waterCtrl.clear();
    _waterInputUnit = _WaterInputUnit.cubicMeters;
    _wasteCtrl.clear();
    _wasteInputUnit = _WasteInputUnit.kg;
    _bulbCountCtrl.clear();
    _bulbWattageCtrl.clear();
    _bulbHoursCtrl.clear();
    _selectedDevices.clear();
    _selectedVehicles.clear();
    setState(() {
      _electricityCo2 = null;
      _fuelCo2 = null;
      _waterCo2 = null;
      _wasteCo2 = null;
    });
    if (_tabController.index != 0) {
      _tabController.index = 0;
    }
    _syncTabViewHeight();

    final db = DatabaseService.instance;
    db.updateReading('Elektrik (kWh)', 0);
    db.updateReading('Yakıt (litre)', 0);
    db.updateReading('Su (m³)', 0);
    db.updateReading('Atık (kg)', 0);

    final emptyEntry = ConsumptionEntry(
      electricityKwh: 0,
      fuelLiters: 0,
      waterCubicMeters: 0,
      wasteKg: 0,
      createdAt: DateTime.now(),
    );
    widget.onCalculated(0.0);
    widget.onEntryCalculated?.call(0.0, emptyEntry);
  }
}

// Basit cihaz şablonu ve seçili cihaz modeli (yalnızca bu widget içinde kullanılır)
class _DevicePreset {
  const _DevicePreset({
    required this.name,
    required this.icon,
    required this.powerW,
    required this.hoursPerDay,
  });
  final String name;
  final IconData icon;
  final double powerW;
  final double hoursPerDay;
}

class _SelectedDevice {
  _SelectedDevice({
    required this.name,
    required this.powerW,
    required this.hoursPerDay,
    this.quantity = 1,
  });

  final String name;
  double powerW;
  double hoursPerDay;
  int quantity;
}

// Araç seçim modelleri
class _VehiclePreset {
  const _VehiclePreset({
    required this.name,
    required this.icon,
    required this.litersPer100km,
    required this.kmPerDay,
  });
  final String name;
  final IconData icon;
  final double litersPer100km; // l/100km
  final double kmPerDay; // km/gün
}

class _SelectedVehicle {
  _SelectedVehicle({
    required this.name,
    required this.litersPer100km,
    required this.kmPerDay,
  }) : quantity = 1;

  final String name;
  double litersPer100km;
  double kmPerDay;
  int quantity;
}

class _DeviceTile extends StatefulWidget {
  const _DeviceTile({
    required this.preset,
    required this.onAddQuantity,
    required this.onEdit,
  });

  final _DevicePreset preset;
  final void Function(int quantity) onAddQuantity;
  final VoidCallback onEdit;

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  int _quantity = 1;

  void _decrease() {
    setState(() {
      _quantity = (_quantity - 1).clamp(1, 9999);
    });
  }

  void _increase() {
    setState(() {
      _quantity = (_quantity + 1).clamp(1, 9999);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140, // Kart genişliğini azalt
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF304411).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF304411).withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(widget.preset.icon, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.preset.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: widget.onEdit,
                  icon: Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  tooltip: 'Düzenle',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.preset.powerW.toStringAsFixed(0)} W • ${widget.preset.hoursPerDay.toStringAsFixed(1)} s/g',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _QtyButton(icon: Icons.remove, onPressed: _decrease),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '$_quantity',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    _QtyButton(icon: Icons.add, onPressed: _increase),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => widget.onAddQuantity(_quantity),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Text(
                      '+ Ekle',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF304411).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF304411).withValues(alpha: 0.28),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.preset,
    required this.onAdd,
    required this.onEdit,
  });

  final _VehiclePreset preset;
  final VoidCallback onAdd;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return SizedBox(
      width: 170,
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF304411).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF304411).withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(preset.icon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preset.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit,
                      color: scheme.primary,
                      size: 18,
                    ),
                    tooltip: 'Düzenle',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${preset.litersPer100km.toStringAsFixed(1)} l/100km • ${preset.kmPerDay.toStringAsFixed(1)} km/g',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF304411).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF304411).withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    '+ Ekle',
                    style: TextStyle(
                      color: onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Kategori özet satırı widget'ı
class _CategorySummaryRow extends StatelessWidget {
  const _CategorySummaryRow({
    required this.label,
    required this.co2,
    required this.color,
    this.isHigh = false,
  });

  final String label;
  final double co2;
  final Color color;
  final bool isHigh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
          Row(
            children: [
              if (isHigh)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.warning,
                    color: Colors.red,
                    size: 16,
                  ),
                ),
              Text(
                '${co2.toStringAsFixed(2)} kg CO₂e',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isHigh ? Colors.red : color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
