import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/connection_service.dart';
import '../home/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  bool _loading = false;

  Future<void> _onStart() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama tampilan Anda terlebih dahulu')),
      );
      return;
    }
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefDisplayName, name);
    await ConnectionService().setDisplayName(name);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald.withAlpha(30),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.primaryEmerald, width: 2),
                  ),
                  child: const Icon(
                    Icons.wifi_tethering,
                    color: AppTheme.primaryEmerald,
                    size: 50,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Center(
                child: Text(
                  'OFFMAS',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Off-Grid Mesh Messenger',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withAlpha(160),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              // Features
              _featureRow(Icons.bluetooth, 'Tanpa internet, tanpa menara seluler'),
              const SizedBox(height: 12),
              _featureRow(Icons.hub, 'Jaringan mesh multi-hop otomatis'),
              const SizedBox(height: 12),
              _featureRow(Icons.lock_outline, 'Enkripsi AES-256 end-to-end'),
              const SizedBox(height: 12),
              _featureRow(Icons.sos, 'Siaran darurat SOS satu sentuhan'),
              const Spacer(),
              const Text(
                'Nama Tampilan Anda',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Contoh: Budi Santoso',
                  prefixIcon: Icon(Icons.person_outline, color: AppTheme.primaryEmerald),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _onStart,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('MULAI OFFMAS', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryEmerald, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}
