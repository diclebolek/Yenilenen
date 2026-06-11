import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;

import '../config/env_config.dart';
import '../algorithms/calculation.dart';
import '../localization/translations.dart';
import '../models/consumption_entry.dart';
import '../models/shelly_data.dart';
import 'api_service.dart';
import 'firebase_realtime_service.dart';
import 'notification_service.dart';

/// Raporlar gauge'ı ile ana sayfa tablosu arasında paylaşılan canlı emisyon durumu.
/// Sekmeler arası geçişte widget yeniden oluşsa bile değer bellekte kalır.
class LiveEmissionService extends ChangeNotifier {
  LiveEmissionService._();
  static final LiveEmissionService instance = LiveEmissionService._();

  ConsumptionEntry? _espEntry;
  ConsumptionEntry? _shellyEntry;
  double _shellySessionKwhConsumed = 0;
  double? _shellyPrevMeterKwh;
  DateTime? _shellyConsumptionDayStart;

  /// Raporlar yuvarlak gauge'ında gösterilen günlük kg CO₂e (E veya M modu).
  double? _gaugeDailyKgCo2e;
  bool _gaugeUseEspMode = true;

  ConsumptionEntry? get espEntry => _espEntry;
  ConsumptionEntry? get shellyEntry => _shellyEntry;
  double get shellySessionKwhConsumed => _shellySessionKwhConsumed;
  double? get gaugeDailyKgCo2e => _gaugeDailyKgCo2e;
  bool get gaugeUseEspMode => _gaugeUseEspMode;

  void setEspEntry(ConsumptionEntry? entry) {
    _espEntry = entry;
    _syncDailySensorSummaryCache();
    syncEspGaugeFromLiveSensors();
  }

  void ingestShellyReading(ShellyData data, ConsumptionEntry entry) {
    _registerShellyMeterDelta(data);
    _shellyEntry = entry;
    _syncDailySensorSummaryCache();
    syncEspGaugeFromLiveSensors();
  }

  void _syncDailySensorSummaryCache() {
    final kg = combinedLiveKgCo2e();
    if (kg <= 1e-9) return;
    NotificationService.instance
        .cacheAndScheduleDailySensorSummary(
      kgCo2e: kg,
      sensorMode: true,
    )
        .catchError((_) {});
  }

  void resetShellyBaseline() {
    _shellySessionKwhConsumed = 0;
    _shellyPrevMeterKwh = null;
    final n = DateTime.now();
    _shellyConsumptionDayStart = DateTime(n.year, n.month, n.day);
  }

  void _registerShellyMeterDelta(ShellyData d) {
    final meter = d.energyKwh;
    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    if (_shellyConsumptionDayStart == null ||
        _shellyConsumptionDayStart != dayStart) {
      _shellySessionKwhConsumed = 0;
      _shellyPrevMeterKwh = null;
      _shellyConsumptionDayStart = dayStart;
    }
    if (_shellyPrevMeterKwh == null) {
      _shellyPrevMeterKwh = meter;
      return;
    }
    final delta = meter - _shellyPrevMeterKwh!;
    if (delta < -1e-9) {
      _shellyPrevMeterKwh = meter;
      return;
    }
    _shellySessionKwhConsumed += delta;
    _shellyPrevMeterKwh = meter;
  }

  double combinedLiveKgCo2e() {
    var total = 0.0;

    if (_shellyEntry != null) {
      total += _shellySessionKwhConsumed *
          Calculation.factorElectricityKgPerKwh;
    }

    if (_espEntry != null) {
      total += _espEntry!.waterCubicMeters * Calculation.factorWaterKgPerM3;
      total += Calculation.fuelEmissionKgCo2e(_espEntry!);
    }

    return total > 0 ? total : 0.0;
  }

  /// Ana sayfa tablosu / raporlar gauge — önce canlı ESP+Shelly, sonra yayımlanan gauge.
  double? effectiveDailyKgCo2e({bool preferEspLive = true}) {
    const eps = 1e-9;
    if (preferEspLive && _gaugeUseEspMode) {
      final live = combinedLiveKgCo2e();
      if (live > eps) return live;
    }
    if (_gaugeDailyKgCo2e != null && _gaugeDailyKgCo2e! > eps) {
      return _gaugeDailyKgCo2e;
    }
    if (preferEspLive && _gaugeUseEspMode) {
      return null;
    }
    return _gaugeDailyKgCo2e;
  }

  /// Canlı sensör okumasını yuvarlak gauge ile paylaş (E modu).
  void syncEspGaugeFromLiveSensors() {
    if (!_gaugeUseEspMode) return;
    final live = combinedLiveKgCo2e();
    if (live <= 1e-9) return;
    publishGaugeDailyKg(live, useEspMode: true);
  }

  void publishGaugeDailyKg(double? kg, {required bool useEspMode}) {
    final normalized = (kg != null && kg > 1e-9) ? kg : null;
    final changed = _gaugeDailyKgCo2e != normalized ||
        _gaugeUseEspMode != useEspMode;
    if (!changed) return;
    _gaugeDailyKgCo2e = normalized;
    _gaugeUseEspMode = useEspMode;
    notifyListeners();
    if (useEspMode) {
      NotificationService.instance
          .cacheAndScheduleDailySensorSummary(
        kgCo2e: normalized,
        sensorMode: true,
      )
          .catchError((_) {});
    }
  }

  Future<void> bootstrapFromFirebase({
    required FirebaseRealtimeService firebase,
    required ApiService api,
    required String shellyDeviceId,
  }) async {
    try {
      final esp = await firebase.getLatestData(EnvConfig.espDeviceId);
      if (esp != null) {
        setEspEntry(esp);
      }
    } catch (_) {}

    resetShellyBaseline();
    _shellyEntry = null;

    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    try {
      final hist = await api.getFirebaseShellyHistory(
        deviceId: shellyDeviceId,
        startDate: now.subtract(const Duration(days: 4)),
        endDate: now,
      );
      if (hist.isEmpty) {
        syncEspGaugeFromLiveSensors();
        return;
      }

      hist.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _shellyEntry = api.shellyDataToConsumptionEntry(hist.last);

      final todayReadings = hist
          .where((r) =>
              r.timestamp.year == dayStart.year &&
              r.timestamp.month == dayStart.month &&
              r.timestamp.day == dayStart.day)
          .toList();

      if (todayReadings.length >= 2) {
        for (final reading in todayReadings) {
          ingestShellyReading(
            reading,
            api.shellyDataToConsumptionEntry(reading),
          );
        }
        return;
      }

      final todayKwh = api
          .shellyDataListToDeltaConsumptionEntries(hist)
          .where((e) =>
              e.createdAt.year == dayStart.year &&
              e.createdAt.month == dayStart.month &&
              e.createdAt.day == dayStart.day)
          .fold<double>(0.0, (sum, e) => sum + e.electricityKwh);

      if (todayKwh > 1e-9) {
        _shellySessionKwhConsumed = todayKwh;
        _shellyPrevMeterKwh = hist.last.energyKwh;
        _shellyConsumptionDayStart = dayStart;
      }
      syncEspGaugeFromLiveSensors();
    } catch (_) {
      syncEspGaugeFromLiveSensors();
    }
    await refreshDailyNotificationSchedule();
  }

  Future<void> refreshDailyNotificationSchedule() async {
    if (!_gaugeUseEspMode) return;
    final kg = combinedLiveKgCo2e();
    await NotificationService.instance.cacheAndScheduleDailySensorSummary(
      kgCo2e: kg > 1e-9 ? kg : null,
      sensorMode: true,
    );
  }
}

/// Raporlar [_FootprintGauge] ile birebir aynı sayı + birim biçimi.
String formatGaugeKgCo2eDisplay(double kg, Locale locale) {
  final clamped = kg.clamp(0.0, double.infinity);
  final String valueText;
  final String unitKey;

  if (clamped >= 1000) {
    final t = clamped / 1000.0;
    valueText = t >= 100
        ? t.toStringAsFixed(0)
        : t >= 10
            ? t.toStringAsFixed(1)
            : t.toStringAsFixed(2);
    unitKey = 'tonnes_co2e';
  } else if (clamped == 0) {
    valueText = '0.0';
    unitKey = 'kg_co2e';
  } else if (clamped < 1) {
    final g = clamped * 1000.0;
    valueText = g >= 100
        ? g.toStringAsFixed(0)
        : g >= 10
            ? g.toStringAsFixed(1)
            : g >= 1
                ? g.toStringAsFixed(2)
                : g.toStringAsFixed(3);
    unitKey = 'g_co2e';
  } else {
    valueText = clamped >= 100
        ? clamped.toStringAsFixed(0)
        : clamped >= 10
            ? clamped.toStringAsFixed(1)
            : clamped.toStringAsFixed(2);
    unitKey = 'kg_co2e';
  }

  return '$valueText ${translate(unitKey, locale)}';
}
