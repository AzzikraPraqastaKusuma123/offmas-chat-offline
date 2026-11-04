import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/connection_service.dart';

class PinVerifyDialog extends StatelessWidget {
  final String peerName;
  final String endpointId;
  final String authToken;

  const PinVerifyDialog({
    super.key,
    required this.peerName,
    required this.endpointId,
    required this.authToken,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String peerName,
    required String endpointId,
    required String authToken,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinVerifyDialog(
        peerName: peerName,
        endpointId: endpointId,
        authToken: authToken,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.verified_user, color: AppTheme.primaryEmerald),
          SizedBox(width: 10),
          Text('Permintaan Koneksi', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primaryEmerald.withAlpha(40),
            child: const Icon(Icons.phone_android, color: AppTheme.primaryEmerald, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            peerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ingin terhubung dengan Anda',
            style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryEmerald.withAlpha(120)),
            ),
            child: Column(
              children: [
                Text(
                  'Cocokkan kode ini di kedua perangkat:',
                  style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  authToken,
                  style: const TextStyle(
                    color: AppTheme.primaryEmerald,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pastikan kode sama persis sebelum menekan Terima.\nJangan terima jika Anda tidak mengenal perangkat ini.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            ConnectionService().rejectConnection(endpointId);
            Navigator.pop(context, false);
          },
          child: const Text('Tolak', style: TextStyle(color: AppTheme.emergencyRed)),
        ),
        ElevatedButton(
          onPressed: () {
            ConnectionService().acceptConnection(endpointId);
            Navigator.pop(context, true);
          },
          child: const Text('Terima'),
        ),
      ],
    );
  }
}

