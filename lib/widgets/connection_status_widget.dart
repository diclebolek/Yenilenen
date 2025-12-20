import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// İnternet ve ağ bağlantı durumunu gösteren widget
class ConnectionStatusWidget extends StatefulWidget {
  const ConnectionStatusWidget({super.key});

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  final ConnectivityService _connectivityService = ConnectivityService();
  Map<String, dynamic>? _connectionStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _isLoading = true);
    final status = await _connectivityService.getConnectionStatus();
    setState(() {
      _connectionStatus = status;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Bağlantı kontrol ediliyor...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_connectionStatus == null) {
      return const SizedBox.shrink();
    }

    final hasInternet = _connectionStatus!['hasInternet'] as bool;
    final hasWifi = _connectionStatus!['hasWifi'] as bool;
    final hasMobileData = _connectionStatus!['hasMobileData'] as bool;
    final hasAnyConnection = _connectionStatus!['hasAnyConnection'] as bool;

    return Card(
      color: hasInternet
          ? Colors.green.shade50
          : hasAnyConnection
              ? Colors.orange.shade50
              : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasInternet
                      ? Icons.cloud_done
                      : hasAnyConnection
                          ? Icons.cloud_off
                          : Icons.cloud_off_outlined,
                  color: hasInternet
                      ? Colors.green
                      : hasAnyConnection
                          ? Colors.orange
                          : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasInternet
                        ? 'İnternet Bağlantısı: Aktif'
                        : hasAnyConnection
                            ? 'Ağ Bağlantısı: Aktif (İnternet Yok)'
                            : 'Bağlantı Yok',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hasInternet
                              ? Colors.green.shade700
                              : hasAnyConnection
                                  ? Colors.orange.shade700
                                  : Colors.red.shade700,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _checkConnection,
                  tooltip: 'Yenile',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(
              icon: Icons.wifi,
              label: 'WiFi',
              isActive: hasWifi,
            ),
            const SizedBox(height: 8),
            _StatusRow(
              icon: Icons.signal_cellular_alt,
              label: 'Mobil Veri',
              isActive: hasMobileData,
            ),
            const SizedBox(height: 8),
            _StatusRow(
              icon: Icons.language,
              label: 'İnternet Erişimi',
              isActive: hasInternet,
            ),
            if (!hasInternet && hasAnyConnection) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'WiFi bağlı ancak internet erişimi yok. Firebase ve dış servisler çalışmayabilir.',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isActive ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Spacer(),
        Icon(
          isActive ? Icons.check_circle : Icons.cancel,
          size: 20,
          color: isActive ? Colors.green : Colors.grey,
        ),
      ],
    );
  }
}
