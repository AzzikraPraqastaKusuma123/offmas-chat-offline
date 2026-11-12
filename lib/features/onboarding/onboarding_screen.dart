import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/crypto/crypto_service.dart';
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

  @override
  void initState() {
    super.initState();
    // Default to anonymous tactical callsign
    _nameController.text = CryptoService.generateGhostCallsign();
  }

  void _randomizeCallsign() {
    setState(() {
      _nameController.text = CryptoService.generateGhostCallsign();
    });
  }

  Future<void> _onStart() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih atau acak callsign anonim Anda')),
      );
      return;
    }
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefDisplayName, name);
    await prefs.setString(AppConstants.prefBio, 'Node Anonim Terenkripsi');
    await prefs.setString(AppConstants.prefRole, 'Operatif Anonim');
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
              _featureRow(Icons.security, '100% Anonim: Tanpa nomor HP, email, atau akun'),
              const SizedBox(height: 12),
              _featureRow(Icons.bluetooth, 'Tanpa internet, tanpa menara seluler'),
              const SizedBox(height: 12),
              _featureRow(Icons.hub, 'Jaringan mesh multi-hop otomatis'),
              const SizedBox(height: 12),
              _featureRow(Icons.lock_outline, 'Enkripsi AES-256 end-to-end murni di HP'),
              const SizedBox(height: 12),
              _featureRow(Icons.sos, 'Siaran darurat SOS satu sentuhan'),
              const Spacer(),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Callsign Anonim Anda (Ghost ID)',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Tidak terlacak',
                    style: TextStyle(color: AppTheme.primaryEmerald, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Contoh: Phantom-7F89',
                  prefixIcon: const Icon(Icons.shield_outlined, color: AppTheme.primaryEmerald),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.casino_outlined, color: AppTheme.accentCyan),
                    tooltip: 'Acak Callsign Anonim',
                    onPressed: _randomizeCallsign,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _onStart,
                  icon: const Icon(Icons.visibility_off, size: 18),
                  label: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('MASUK MODE ANONIM', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
