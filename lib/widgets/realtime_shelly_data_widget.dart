import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/shelly_data.dart';

/// Shelly Plug S verilerini Firebase'den real-time dinleyen widget
/// StreamBuilder kullanarak anlık veri güncellemelerini gösterir
class RealtimeShellyDataWidget extends StatefulWidget {
  final ApiService apiService;
  final String deviceId;

  // ignore: prefer_const_constructors_in_immutables
  RealtimeShellyDataWidget({
    super.key,
    required this.apiService,
    required this.deviceId,
  });

  @override
  State<RealtimeShellyDataWidget> createState() =>
      _RealtimeShellyDataWidgetState();
}

class _RealtimeShellyDataWidgetState extends State<RealtimeShellyDataWidget> {
  bool _hasTriedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    // Widget ilk yüklendiğinde otomatik veri çekmeyi dene
    _tryInitialDataLoad();
  }

  Future<void> _tryInitialDataLoad() async {
    if (_hasTriedInitialLoad) return;
    _hasTriedInitialLoad = true;

    // Kısa bir gecikme sonrası veri çekmeyi dene
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await widget.apiService.getShellyData(saveToFirebase: true);
    } catch (e) {
      // Hata olsa bile devam et (Firebase stream'den gelebilir)
      debugPrint('İlk veri çekme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ShellyData?>(
      stream: widget.apiService.listenToFirebaseShellyData(widget.deviceId),
      builder: (context, snapshot) {
        // Stream hata durumunu yakala
        if (snapshot.connectionState == ConnectionState.none) {
          return Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.wifi_off, color: Colors.orange.shade700),
                  const SizedBox(height: 8),
                  Text(
                    'Firebase bağlantısı yok',
                    style: TextStyle(color: Colors.orange.shade700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shelly verilerini görmek için Firebase bağlantısı gerekli',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        // Bağlantı durumu kontrolü
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Hata durumu
        if (snapshot.hasError) {
          return Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(height: 8),
                  Text(
                    'Hata: ${snapshot.error}',
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // Veri yok durumu
        if (!snapshot.hasData || snapshot.data == null) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.power_outlined,
                      color: Colors.white.withValues(alpha: 0.7)),
                  const SizedBox(height: 8),
                  Text(
                    'Henüz Shelly verisi yok',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Manuel olarak Shelly'den veri çek
                      try {
                        await widget.apiService
                            .getShellyData(saveToFirebase: true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Veri başarıyla çekildi!'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          String errorMessage = 'Shelly bağlantı hatası: $e';
                          if (e.toString().contains('TimeoutException')) {
                            errorMessage = 'Zaman aşımı! Lütfen kontrol edin:\n'
                                '• IP adresi doğru mu?\n'
                                '• Aynı WiFi ağında mı?\n'
                                '• Cihaz çalışıyor mu?';
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errorMessage),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Veri Çek'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'İpucu: İlk yüklemede otomatik veri çekme deneniyor...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // Veri var - göster
        final data = snapshot.data!;

        return Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.power, color: Colors.blue.shade300),
                    const SizedBox(width: 8),
                    Text(
                      'Shelly Plug S',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.circle,
                      color: data.isOn ? Colors.green : Colors.grey,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      data.isOn ? 'Açık' : 'Kapalı',
                      style: TextStyle(
                        color: data.isOn
                            ? Colors.green.shade300
                            : Colors.grey.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Divider(color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                _DataRow(
                  icon: Icons.bolt,
                  label: 'Güç',
                  value: '${data.powerWatt.toStringAsFixed(2)} W',
                  color: Colors.amber,
                  isDarkBackground: true,
                ),
                const SizedBox(height: 12),
                _DataRow(
                  icon: Icons.electric_bolt,
                  label: 'Enerji',
                  value: '${data.energyKwh.toStringAsFixed(3)} kWh',
                  color: Colors.yellow,
                  isDarkBackground: true,
                ),
                const SizedBox(height: 12),
                _DataRow(
                  icon: Icons.flash_on,
                  label: 'Voltaj',
                  value: '${data.voltage.toStringAsFixed(1)} V',
                  color: Colors.blue,
                  isDarkBackground: true,
                ),
                const SizedBox(height: 12),
                _DataRow(
                  icon: Icons.electric_meter,
                  label: 'Akım',
                  value: '${data.current.toStringAsFixed(2)} A',
                  color: Colors.orange,
                  isDarkBackground: true,
                ),
                if (data.temperature != null) ...[
                  const SizedBox(height: 12),
                  _DataRow(
                    icon: Icons.thermostat,
                    label: 'Sıcaklık',
                    value: '${data.temperature!.toStringAsFixed(1)} °C',
                    color: Colors.red,
                    isDarkBackground: true,
                  ),
                ],
                Divider(color: Colors.white.withValues(alpha: 0.3)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Son Güncelleme: ${_formatDateTime(data.timestamp)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                    ),
                    // Cihazı aç/kapat butonu
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final newState =
                              await widget.apiService.setShellyRelayState(
                            turn: data.isOn ? 'off' : 'on',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  newState ? 'Cihaz açıldı' : 'Cihaz kapatıldı',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Hata: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: Icon(data.isOn ? Icons.power_off : Icons.power),
                      label: Text(data.isOn ? 'Kapat' : 'Aç'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: data.isOn
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Veri satırı widget'ı
class _DataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDarkBackground;

  const _DataRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.isDarkBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isDarkBackground ? Colors.white : null,
                ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }
}
