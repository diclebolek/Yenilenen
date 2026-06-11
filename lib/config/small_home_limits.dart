/// Küçük ev (≈1–2 kişi, ~60–90 m²) için günlük evsel utility emisyon üst sınırı.
///
/// Yalnızca sensörle izlenen elektrik + su + doğalgaz (kg CO₂e).
/// Tipik küçük ev günlük tüketimi ~4–6 kg; 8 kg güvenli uyarı eşiği.
class SmallHomeLimits {
  SmallHomeLimits._();

  static const double dailyKgCo2e = 8.0;
}
