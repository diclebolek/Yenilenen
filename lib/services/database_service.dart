import 'dart:collection';

/// Simple in-memory store to share latest readings and goals across screens.
/// Replace with persistent DB in the future.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  final Map<String, double> _latestReadings = HashMap();
  final Map<String, double> _goalThresholds = HashMap.from({
    // Key names match input fields in the form
    'Elektrik (kWh)': 1000.0,
    'Yakıt (litre)': 100.0,
    'Su (m³)': 50.0,
    'Atık (kg)': 100.0,
  });

  Map<String, double> get latestReadings => Map.unmodifiable(_latestReadings);
  Map<String, double> get goalThresholds => Map.unmodifiable(_goalThresholds);

  void updateReading(String label, double value) {
    _latestReadings[label] = value;
  }

  void setGoalThreshold(String label, double threshold) {
    _goalThresholds[label] = threshold;
  }
}
