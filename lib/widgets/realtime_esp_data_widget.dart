import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/consumption_entry.dart';

/// ESP8266 verilerini Firebase'den real-time dinleyen widget
/// StreamBuilder kullanarak anlık veri güncellemelerini gösterir
class RealtimeEspDataWidget extends StatelessWidget {
  final ApiService apiService = ApiService();

  RealtimeEspDataWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConsumptionEntry?>(
      stream: apiService.listenToFirebaseData(),
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
                    'ESP8266 verilerini görmek için Firebase bağlantısı gerekli',
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
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600),
                  const SizedBox(height: 8),
                  Text(
                    'Henüz veri yok',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Manuel olarak ESP8266'dan veri çek
                      await apiService.getLiveConsumptionData(
                        saveToFirebase: true,
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Veri Çek'),
                  ),
                ],
              ),
            ),
          );
        }

        // Veri var - göster
        final data = snapshot.data!;
        // Reports screen'de her zaman koyu arka plan kullanılıyor
        // Açık modda da koyu moddaki gibi görünmesi için

        return Container(
          decoration: BoxDecoration(
            color: Colors
                .transparent, // Şeffaf arka plan (BackdropFilter zaten var)
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sensors, color: Colors.green.shade300),
                    const SizedBox(width: 8),
                    Text(
                      'ESP8266 Anlık Veriler',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const Spacer(),
                    const Icon(Icons.circle, color: Colors.green, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Canlı',
                      style: TextStyle(
                        color: Colors.green.shade300,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () async {
                        // Manuel olarak ESP8266'dan veri çek
                        await apiService.getLiveConsumptionData(
                          saveToFirebase: true,
                        );
                      },
                      icon: const Icon(Icons.refresh),
                      color: Colors.white,
                      tooltip: 'Yenile',
                    ),
                  ],
                ),
                Divider(color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                _DataRow(
                  icon: Icons.water_drop,
                  label: 'Su',
                  value: data.waterCubicMeters < 0.01
                      ? '${(data.waterCubicMeters * 1000).toStringAsFixed(2)} L'
                      : '${data.waterCubicMeters.toStringAsFixed(3)} m³',
                  color: Colors.blue,
                  isDarkBackground: true,
                ),
                const SizedBox(height: 12),
                _DataRow(
                  icon: Icons.local_gas_station,
                  label: 'Gaz (CO₂)',
                  value: '${data.fuelLiters.toStringAsFixed(2)} ppm',
                  color: Colors.orange,
                  isDarkBackground: true,
                ),
                Divider(color: Colors.white.withValues(alpha: 0.3)),
                Text(
                  'Son Güncelleme: ${_formatDateTime(data.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
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
