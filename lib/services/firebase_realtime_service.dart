import 'dart:developer' as dev;
import 'package:firebase_database/firebase_database.dart';
import '../models/consumption_entry.dart';
import '../models/shelly_data.dart';

/// Firebase Realtime Database servisi - ESP8266 verilerini real-time senkronize eder
class FirebaseRealtimeService {
  static FirebaseRealtimeService? _instance;
  late DatabaseReference _databaseRef;

  FirebaseRealtimeService._();

  static FirebaseRealtimeService get instance {
    _instance ??= FirebaseRealtimeService._();
    return _instance!;
  }

  /// Firebase'i başlat (main.dart'ta Firebase.initializeApp() çağrıldıktan sonra)
  void initialize() {
    _databaseRef = FirebaseDatabase.instance.ref();
    dev.log(
      'Firebase Realtime Database başlatıldı',
      name: 'FirebaseRealtimeService',
    );
  }

  /// ESP8266 verilerini Firebase'e kaydet
  /// Path: /esp8266_data/{deviceId}/latest
  Future<void> saveEsp8266Data({
    required String deviceId,
    required ConsumptionEntry consumption,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final data = {
        'electricity': consumption.electricityKwh,
        'water': consumption.waterCubicMeters,
        'fuel': consumption.fuelLiters,
        'waste': consumption.wasteKg,
        'co2_ppm': additionalData?['co2_ppm'] ?? 0.0,
        'water_flow_liters': additionalData?['water_flow_liters'] ?? 0.0,
        'flow_rate_lpm': additionalData?['flow_rate_lpm'] ?? 0.0,
        'timestamp': timestamp,
        'created_at': consumption.createdAt.toIso8601String(),
      };

      // Latest veriyi kaydet
      await _databaseRef
          .child('esp8266_data')
          .child(deviceId)
          .child('latest')
          .set(data);

      // Geçmiş verileri de kaydet (tarih bazlı)
      final dateKey = DateTime.now().toIso8601String().split(
            'T',
          )[0]; // YYYY-MM-DD
      await _databaseRef
          .child('esp8266_data')
          .child(deviceId)
          .child('history')
          .child(dateKey)
          .child(timestamp.toString())
          .set(data);

      dev.log(
        'ESP8266 verisi Firebase\'e kaydedildi: $deviceId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Manuel verileri Firebase'e kaydet
  /// Path: /manual_data/{userId}/latest ve /manual_data/{userId}/history
  Future<void> saveManualData({
    required String userId,
    required ConsumptionEntry consumption,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final data = {
        'electricity': consumption.electricityKwh,
        'water': consumption.waterCubicMeters,
        'fuel': consumption.fuelLiters,
        'waste': consumption.wasteKg,
        'timestamp': timestamp,
        'created_at': consumption.createdAt.toIso8601String(),
        'source': 'manual', // Manuel giriş olduğunu belirt
      };

      // Latest veriyi kaydet
      await _databaseRef
          .child('manual_data')
          .child(userId)
          .child('latest')
          .set(data);

      // Geçmiş verileri de kaydet (tarih bazlı)
      final dateKey =
          DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
      await _databaseRef
          .child('manual_data')
          .child(userId)
          .child('history')
          .child(dateKey)
          .child(timestamp.toString())
          .set(data);

      dev.log(
        'Manuel veri Firebase\'e kaydedildi: $userId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase manuel veri kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      // Hata olsa bile devam et (kullanıcı deneyimini bozma)
    }
  }

  /// Manuel verileri getir (geçmiş veriler)
  /// Path: /manual_data/{userId}/history
  Future<List<ConsumptionEntry>> getManualHistoryData({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startKey = startDate.toIso8601String().split('T')[0];
      final endKey = endDate.toIso8601String().split('T')[0];

      final snapshot = await _databaseRef
          .child('manual_data')
          .child(userId)
          .child('history')
          .get();

      if (snapshot.value == null) {
        return [];
      }

      final historyData = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      final List<ConsumptionEntry> entries = [];

      historyData.forEach((dateKey, timestamps) {
        if (dateKey.compareTo(startKey) >= 0 &&
            dateKey.compareTo(endKey) <= 0) {
          final timestampMap = Map<String, dynamic>.from(
            timestamps as Map<Object?, Object?>,
          );

          timestampMap.forEach((timestamp, data) {
            final entryData = Map<String, dynamic>.from(
              data as Map<Object?, Object?>,
            );

            // Tarih oluştur
            DateTime createdAt;
            if (entryData['created_at'] != null &&
                entryData['created_at'].toString().isNotEmpty &&
                entryData['created_at'] != '') {
              try {
                createdAt = DateTime.parse(entryData['created_at']);
              } catch (e) {
                final timestampValue = entryData['timestamp'] ?? timestamp;
                createdAt = timestampValue is int
                    ? DateTime.fromMillisecondsSinceEpoch(timestampValue)
                    : DateTime.tryParse(dateKey) ?? DateTime.now();
              }
            } else {
              final timestampValue = entryData['timestamp'] ?? timestamp;
              if (timestampValue is int) {
                createdAt = DateTime.fromMillisecondsSinceEpoch(timestampValue);
              } else {
                createdAt = DateTime.tryParse(dateKey) ?? DateTime.now();
              }
            }

            entries.add(
              ConsumptionEntry(
                electricityKwh: (entryData['electricity'] ?? 0.0).toDouble(),
                waterCubicMeters: (entryData['water'] ?? 0.0).toDouble(),
                fuelLiters: (entryData['fuel'] ?? 0.0).toDouble(),
                wasteKg: (entryData['waste'] ?? 0.0).toDouble(),
                createdAt: createdAt,
              ),
            );
          });
        }
      });

      // Tarihe göre sırala
      entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      return entries;
    } catch (e, st) {
      dev.log(
        'Firebase manuel geçmiş veri hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Manuel verilerin en son kaydını getir
  /// Path: /manual_data/{userId}/latest
  Future<ConsumptionEntry?> getLatestManualData(String userId) async {
    try {
      final snapshot = await _databaseRef
          .child('manual_data')
          .child(userId)
          .child('latest')
          .get();

      if (snapshot.value == null) {
        return null;
      }

      final data = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      // Tarih oluştur
      DateTime createdAt;
      if (data['created_at'] != null &&
          data['created_at'].toString().isNotEmpty &&
          data['created_at'] != '') {
        try {
          createdAt = DateTime.parse(data['created_at']);
        } catch (e) {
          final timestamp =
              data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
          createdAt = DateTime.fromMillisecondsSinceEpoch(
            timestamp is int
                ? timestamp
                : int.tryParse(timestamp.toString()) ??
                    DateTime.now().millisecondsSinceEpoch,
          );
        }
      } else {
        final timestamp =
            data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
        createdAt = DateTime.fromMillisecondsSinceEpoch(
          timestamp is int
              ? timestamp
              : int.tryParse(timestamp.toString()) ??
                  DateTime.now().millisecondsSinceEpoch,
        );
      }

      return ConsumptionEntry(
        electricityKwh: (data['electricity'] ?? 0.0).toDouble(),
        waterCubicMeters: (data['water'] ?? 0.0).toDouble(),
        fuelLiters: (data['fuel'] ?? 0.0).toDouble(),
        wasteKg: (data['waste'] ?? 0.0).toDouble(),
        createdAt: createdAt,
      );
    } catch (e, st) {
      dev.log(
        'Firebase manuel latest veri hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Real-time dinleme - ESP8266 verilerini anlık olarak dinle
  /// Stream döndürür, widget'ta StreamBuilder ile kullanılabilir
  Stream<ConsumptionEntry?> listenToEsp8266Data(String deviceId) {
    try {
      return _databaseRef
          .child('esp8266_data')
          .child(deviceId)
          .child('latest')
          .onValue
          .map((event) {
        if (event.snapshot.value == null) {
          return null;
        }

        final data = Map<String, dynamic>.from(
          event.snapshot.value as Map<Object?, Object?>,
        );

        // created_at parse et veya timestamp kullan
        DateTime createdAt;
        if (data['created_at'] != null &&
            data['created_at'].toString().isNotEmpty &&
            data['created_at'] != '') {
          try {
            createdAt = DateTime.parse(data['created_at']);
          } catch (e) {
            // Parse hatası varsa timestamp kullan
            final timestamp =
                data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
            createdAt = DateTime.fromMillisecondsSinceEpoch(
              timestamp is int
                  ? timestamp
                  : int.tryParse(timestamp.toString()) ??
                      DateTime.now().millisecondsSinceEpoch,
            );
          }
        } else {
          // created_at yoksa timestamp kullan
          final timestamp =
              data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
          createdAt = DateTime.fromMillisecondsSinceEpoch(
            timestamp is int
                ? timestamp
                : int.tryParse(timestamp.toString()) ??
                    DateTime.now().millisecondsSinceEpoch,
          );
        }

        // Su verisi: water_flow_liters varsa onu kullan (litre -> m³), yoksa water kullan
        // Eğer water zaten m³ ise direkt kullan, değilse litre olarak kabul et
        // Not: Firebase'de water_flow_liters litre cinsinden, water ise m³ cinsinden kaydedilmiş olabilir
        final waterCubicMeters = data['water_flow_liters'] != null &&
                (data['water_flow_liters'] as num).toDouble() > 0
            ? (data['water_flow_liters'] as num).toDouble() *
                0.001 // Litre'yi m³'e çevir
            : (data['water'] ?? 0.0).toDouble(); // Zaten m³ ise direkt kullan

        return ConsumptionEntry(
          electricityKwh: (data['electricity'] ?? 0.0).toDouble(),
          waterCubicMeters: waterCubicMeters,
          fuelLiters: (data['fuel'] ?? data['co2_ppm'] ?? 0.0)
              .toDouble(), // Gaz (CO2 ppm) değeri
          wasteKg: (data['waste'] ?? 0.0).toDouble(),
          createdAt: createdAt,
        );
      });
    } catch (e, st) {
      dev.log(
        'Firebase dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value(null);
    }
  }

  /// ESP8266 durum bilgisini kaydet
  Future<void> saveEsp8266Status({
    required String deviceId,
    required Map<String, dynamic> status,
  }) async {
    try {
      await _databaseRef.child('esp8266_status').child(deviceId).set({
        ...status,
        'last_update': DateTime.now().toIso8601String(),
      });

      dev.log(
        'ESP8266 durumu Firebase\'e kaydedildi: $deviceId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase durum kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// ESP8266 durumunu real-time dinle
  Stream<Map<String, dynamic>?> listenToEsp8266Status(String deviceId) {
    try {
      return _databaseRef.child('esp8266_status').child(deviceId).onValue.map((
        event,
      ) {
        if (event.snapshot.value == null) {
          return null;
        }

        return Map<String, dynamic>.from(
          event.snapshot.value as Map<Object?, Object?>,
        );
      });
    } catch (e, st) {
      dev.log(
        'Firebase durum dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value(null);
    }
  }

  /// Belirli bir tarih aralığındaki geçmiş verileri getir
  Future<List<ConsumptionEntry>> getHistoryData({
    required String deviceId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startKey = startDate.toIso8601String().split('T')[0];
      final endKey = endDate.toIso8601String().split('T')[0];

      final snapshot = await _databaseRef
          .child('esp8266_data')
          .child(deviceId)
          .child('history')
          .get();

      if (snapshot.value == null) {
        return [];
      }

      final historyData = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      final List<ConsumptionEntry> entries = [];

      historyData.forEach((dateKey, timestamps) {
        if (dateKey.compareTo(startKey) >= 0 &&
            dateKey.compareTo(endKey) <= 0) {
          final timestampMap = Map<String, dynamic>.from(
            timestamps as Map<Object?, Object?>,
          );

          timestampMap.forEach((timestamp, data) {
            final entryData = Map<String, dynamic>.from(
              data as Map<Object?, Object?>,
            );

            // Su verisi: water_flow_liters varsa onu kullan (litre -> m³), yoksa water kullan
            final waterCubicMeters = entryData['water_flow_liters'] != null &&
                    (entryData['water_flow_liters'] as num).toDouble() > 0
                ? (entryData['water_flow_liters'] as num).toDouble() *
                    0.001 // Litre'yi m³'e çevir
                : (entryData['water'] ?? 0.0)
                    .toDouble(); // Zaten m³ ise direkt kullan

            // Tarih oluştur: created_at varsa ve boş değilse parse et, yoksa timestamp kullan
            DateTime createdAt;
            if (entryData['created_at'] != null &&
                entryData['created_at'].toString().isNotEmpty &&
                entryData['created_at'] != '') {
              try {
                createdAt = DateTime.parse(entryData['created_at']);
              } catch (e) {
                // Parse hatası varsa timestamp veya tarih anahtarından oluştur
                final timestampValue = entryData['timestamp'] ?? timestamp;
                createdAt = timestampValue is int
                    ? DateTime.fromMillisecondsSinceEpoch(timestampValue)
                    : DateTime.tryParse(dateKey) ?? DateTime.now();
              }
            } else {
              // created_at yoksa timestamp veya tarih anahtarından oluştur
              final timestampValue = entryData['timestamp'] ?? timestamp;
              if (timestampValue is int) {
                createdAt = DateTime.fromMillisecondsSinceEpoch(timestampValue);
              } else {
                // Tarih anahtarından oluştur (YYYY-MM-DD formatında)
                createdAt = DateTime.tryParse(dateKey) ?? DateTime.now();
              }
            }

            entries.add(
              ConsumptionEntry(
                electricityKwh: (entryData['electricity'] ?? 0.0).toDouble(),
                waterCubicMeters: waterCubicMeters,
                fuelLiters: (entryData['fuel'] ?? entryData['co2_ppm'] ?? 0.0)
                    .toDouble(), // Gaz (CO2 ppm) değeri
                wasteKg: (entryData['waste'] ?? 0.0).toDouble(),
                createdAt: createdAt,
              ),
            );
          });
        }
      });

      // Tarihe göre sırala
      entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      return entries;
    } catch (e, st) {
      dev.log(
        'Firebase geçmiş veri hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Latest verisini ConsumptionEntry olarak getir
  Future<ConsumptionEntry?> getLatestData(String deviceId) async {
    try {
      final snapshot = await _databaseRef
          .child('esp8266_data')
          .child(deviceId)
          .child('latest')
          .get();

      if (snapshot.value == null) {
        return null;
      }

      final data = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      // Tarih oluştur
      DateTime createdAt;
      if (data['created_at'] != null &&
          data['created_at'].toString().isNotEmpty &&
          data['created_at'] != '') {
        try {
          createdAt = DateTime.parse(data['created_at']);
        } catch (e) {
          final timestamp =
              data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
          createdAt = DateTime.fromMillisecondsSinceEpoch(
            timestamp is int
                ? timestamp
                : int.tryParse(timestamp.toString()) ??
                    DateTime.now().millisecondsSinceEpoch,
          );
        }
      } else {
        final timestamp =
            data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
        createdAt = DateTime.fromMillisecondsSinceEpoch(
          timestamp is int
              ? timestamp
              : int.tryParse(timestamp.toString()) ??
                  DateTime.now().millisecondsSinceEpoch,
        );
      }

      // Su verisi
      final waterCubicMeters = data['water_flow_liters'] != null &&
              (data['water_flow_liters'] as num).toDouble() > 0
          ? (data['water_flow_liters'] as num).toDouble() * 0.001
          : (data['water'] ?? 0.0).toDouble();

      return ConsumptionEntry(
        electricityKwh: (data['electricity'] ?? 0.0).toDouble(),
        waterCubicMeters: waterCubicMeters,
        fuelLiters: (data['fuel'] ?? data['co2_ppm'] ?? 0.0).toDouble(),
        wasteKg: (data['waste'] ?? 0.0).toDouble(),
        createdAt: createdAt,
      );
    } catch (e, st) {
      dev.log(
        'Firebase latest veri hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Tüm cihazların listesini getir
  Future<List<String>> getDeviceList() async {
    try {
      final snapshot = await _databaseRef.child('esp8266_data').get();

      if (snapshot.value == null) {
        return [];
      }

      final data = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      return data.keys.toList();
    } catch (e, st) {
      dev.log(
        'Firebase cihaz listesi hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Yeşil puanı getir
  Future<int> getGreenScore(String userId) async {
    try {
      final snapshot = await _databaseRef
          .child('users')
          .child(userId)
          .child('green_score')
          .get();

      if (snapshot.value == null) {
        return 0;
      }

      return (snapshot.value as num).toInt();
    } catch (e, st) {
      dev.log(
        'Firebase yeşil puan getirme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }

  /// Yeşil puanı real-time dinle
  Stream<int> listenToGreenScore(String userId) {
    try {
      return _databaseRef
          .child('users')
          .child(userId)
          .child('green_score')
          .onValue
          .map((event) {
        if (event.snapshot.value == null) {
          return 0;
        }
        return (event.snapshot.value as num).toInt();
      });
    } catch (e, st) {
      dev.log(
        'Firebase yeşil puan dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value(0);
    }
  }

  /// Yeşil puanı kaydet
  Future<void> saveGreenScore(String userId, int score) async {
    try {
      await _databaseRef
          .child('users')
          .child(userId)
          .child('green_score')
          .set(score);

      dev.log(
        'Yeşil puan Firebase\'e kaydedildi: $userId -> $score',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase yeşil puan kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Hedefleri getir
  Future<List<Map<String, dynamic>>> getGoals(String userId) async {
    try {
      final snapshot =
          await _databaseRef.child('users').child(userId).child('goals').get();

      if (snapshot.value == null) {
        return [];
      }

      final data = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      return data.values
          .map(
            (goal) => Map<String, dynamic>.from(goal as Map<Object?, Object?>),
          )
          .toList();
    } catch (e, st) {
      dev.log(
        'Firebase hedef getirme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Hedefleri real-time dinle
  Stream<List<Map<String, dynamic>>> listenToGoals(String userId) {
    try {
      return _databaseRef
          .child('users')
          .child(userId)
          .child('goals')
          .onValue
          .map((event) {
        if (event.snapshot.value == null) {
          return <Map<String, dynamic>>[];
        }

        final data = Map<String, dynamic>.from(
          event.snapshot.value as Map<Object?, Object?>,
        );

        return data.values
            .map(
              (goal) =>
                  Map<String, dynamic>.from(goal as Map<Object?, Object?>),
            )
            .toList();
      });
    } catch (e, st) {
      dev.log(
        'Firebase hedef dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value(<Map<String, dynamic>>[]);
    }
  }

  /// Hedefleri kaydet
  Future<void> saveGoals(
    String userId,
    List<Map<String, dynamic>> goals,
  ) async {
    try {
      final goalsMap = <String, dynamic>{};
      for (var i = 0; i < goals.length; i++) {
        final goal = Map<String, dynamic>.from(goals[i]);
        goal['id'] = goal['id'] ?? 'goal_$i';
        goalsMap[goal['id']] = goal;
      }

      await _databaseRef
          .child('users')
          .child(userId)
          .child('goals')
          .set(goalsMap);

      dev.log(
        'Hedefler Firebase\'e kaydedildi: $userId -> ${goals.length} hedef',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase hedef kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Rozetleri getir
  Future<Map<String, bool>> getBadges(String userId) async {
    try {
      final snapshot =
          await _databaseRef.child('users').child(userId).child('badges').get();

      if (snapshot.value == null) {
        return {
          'environment_friendly': false,
          'energy_saving': false,
          'water_protector': false,
          'goal_master': false,
          'eco_warrior': false,
        };
      }

      return Map<String, bool>.from(snapshot.value as Map<Object?, Object?>);
    } catch (e, st) {
      dev.log(
        'Firebase rozet getirme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return {
        'environment_friendly': false,
        'energy_saving': false,
        'water_protector': false,
        'goal_master': false,
        'eco_warrior': false,
      };
    }
  }

  /// Rozetleri real-time dinle
  Stream<Map<String, bool>> listenToBadges(String userId) {
    try {
      return _databaseRef
          .child('users')
          .child(userId)
          .child('badges')
          .onValue
          .map((event) {
        if (event.snapshot.value == null) {
          return {
            'environment_friendly': false,
            'energy_saving': false,
            'water_protector': false,
            'goal_master': false,
            'eco_warrior': false,
          };
        }

        return Map<String, bool>.from(
          event.snapshot.value as Map<Object?, Object?>,
        );
      });
    } catch (e, st) {
      dev.log(
        'Firebase rozet dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value({
        'environment_friendly': false,
        'energy_saving': false,
        'water_protector': false,
        'goal_master': false,
        'eco_warrior': false,
      });
    }
  }

  /// Rozetleri kaydet
  Future<void> saveBadges(String userId, Map<String, bool> badges) async {
    try {
      await _databaseRef
          .child('users')
          .child(userId)
          .child('badges')
          .set(badges);

      dev.log(
        'Rozetler Firebase\'e kaydedildi: $userId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase rozet kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Hedef ekle
  Future<void> addGoal(String userId, Map<String, dynamic> goal) async {
    try {
      final goalId =
          goal['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      final goalData = Map<String, dynamic>.from(goal);
      goalData['id'] = goalId;

      await _databaseRef
          .child('users')
          .child(userId)
          .child('goals')
          .child(goalId)
          .set(goalData);

      dev.log(
        'Hedef Firebase\'e eklendi: $userId -> $goalId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase hedef ekleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Hedef sil
  Future<void> deleteGoal(String userId, String goalId) async {
    try {
      await _databaseRef
          .child('users')
          .child(userId)
          .child('goals')
          .child(goalId)
          .remove();

      dev.log(
        'Hedef Firebase\'den silindi: $userId -> $goalId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase hedef silme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Shelly Plug S verilerini Firebase'e kaydet
  /// Path: /shelly_data/{deviceId}/latest
  Future<void> saveShellyData({
    required String deviceId,
    required ShellyData shellyData,
  }) async {
    try {
      final data = shellyData.toMap();

      // Latest veriyi kaydet
      await _databaseRef
          .child('shelly_data')
          .child(deviceId)
          .child('latest')
          .set(data);

      // Geçmiş verileri de kaydet (tarih bazlı)
      final dateKey =
          DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
      await _databaseRef
          .child('shelly_data')
          .child(deviceId)
          .child('history')
          .child(dateKey)
          .child(shellyData.timestamp.millisecondsSinceEpoch.toString())
          .set(data);

      dev.log(
        'Shelly verisi Firebase\'e kaydedildi: $deviceId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase Shelly kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Real-time dinleme - Shelly verilerini anlık olarak dinle
  /// Stream döndürür, widget'ta StreamBuilder ile kullanılabilir
  Stream<ShellyData?> listenToShellyData(String deviceId) {
    try {
      return _databaseRef
          .child('shelly_data')
          .child(deviceId)
          .child('latest')
          .onValue
          .map((event) {
        if (event.snapshot.value == null) {
          return null;
        }

        final data = Map<String, dynamic>.from(
          event.snapshot.value as Map<Object?, Object?>,
        );

        return ShellyData.fromMap(data);
      });
    } catch (e, st) {
      dev.log(
        'Firebase Shelly dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value(null);
    }
  }

  /// Shelly durum bilgisini kaydet
  Future<void> saveShellyStatus({
    required String deviceId,
    required Map<String, dynamic> status,
  }) async {
    try {
      await _databaseRef.child('shelly_status').child(deviceId).set({
        ...status,
        'last_update': DateTime.now().toIso8601String(),
      });

      dev.log(
        'Shelly durumu Firebase\'e kaydedildi: $deviceId',
        name: 'FirebaseRealtimeService',
      );
    } catch (e, st) {
      dev.log(
        'Firebase Shelly durum kayıt hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Shelly durumunu real-time dinle
  Stream<Map<String, dynamic>?> listenToShellyStatus(String deviceId) {
    try {
      return _databaseRef.child('shelly_status').child(deviceId).onValue.map((
        event,
      ) {
        if (event.snapshot.value == null) {
          return null;
        }

        return Map<String, dynamic>.from(
          event.snapshot.value as Map<Object?, Object?>,
        );
      });
    } catch (e, st) {
      dev.log(
        'Firebase Shelly durum dinleme hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return Stream.value(null);
    }
  }

  /// Belirli bir tarih aralığındaki Shelly geçmiş verilerini getir
  Future<List<ShellyData>> getShellyHistory({
    required String deviceId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startKey = startDate.toIso8601String().split('T')[0];
      final endKey = endDate.toIso8601String().split('T')[0];

      final snapshot = await _databaseRef
          .child('shelly_data')
          .child(deviceId)
          .child('history')
          .get();

      if (snapshot.value == null) {
        return [];
      }

      final historyData = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      final List<ShellyData> entries = [];

      historyData.forEach((dateKey, timestamps) {
        if (dateKey.compareTo(startKey) >= 0 &&
            dateKey.compareTo(endKey) <= 0) {
          final timestampMap = Map<String, dynamic>.from(
            timestamps as Map<Object?, Object?>,
          );

          timestampMap.forEach((timestamp, data) {
            final entryData = Map<String, dynamic>.from(
              data as Map<Object?, Object?>,
            );

            entries.add(ShellyData.fromMap(entryData));
          });
        }
      });

      // Tarihe göre sırala
      entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return entries;
    } catch (e, st) {
      dev.log(
        'Firebase Shelly geçmiş veri hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Latest Shelly verisini getir
  Future<ShellyData?> getLatestShellyData(String deviceId) async {
    try {
      final snapshot = await _databaseRef
          .child('shelly_data')
          .child(deviceId)
          .child('latest')
          .get();

      if (snapshot.value == null) {
        return null;
      }

      final data = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>,
      );

      return ShellyData.fromMap(data);
    } catch (e, st) {
      dev.log(
        'Firebase latest Shelly veri hatası: $e',
        name: 'FirebaseRealtimeService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
