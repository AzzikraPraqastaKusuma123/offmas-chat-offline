import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/connection_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _conn = ConnectionService();
  final _crypto = CryptoService();

  String _selectedRole = 'Warga';
  String _nodeId = '';
  bool _isSaving = false;
  bool _savedSuccess = false;

  final List<Map<String, dynamic>> _roleOptions = [
    {'title': 'Operatif Anonim', 'icon': Icons.security, 'color': AppTheme.primaryEmerald},
    {'title': 'Relawan Taktis', 'icon': Icons.volunteer_activism, 'color': AppTheme.accentCyan},
    {'title': 'Tim Medis', 'icon': Icons.medical_services, 'color': AppTheme.warningOrange},
    {'title': 'SAR & Evakuasi', 'icon': Icons.emergency, 'color': AppTheme.emergencyRed},
    {'title': 'Sentry Mesh', 'icon': Icons.cell_tower, 'color': const Color(0xFFB388FF)},
  ];

  final List<String> _quickBioPresets = [
    '👻 Node Anonim Terenkripsi',
    '🟢 Sektor Aman & Siaga',
    '🔴 Butuh Dukungan Medis Segera',
    '🟡 Siap Kirim Logistik',
    '🔋 Mode Pasif / Hemat Daya',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(AppConstants.prefDisplayName) ?? _conn.localDisplayName;
    final bio = prefs.getString(AppConstants.prefBio) ?? _conn.localBio;
    final role = prefs.getString(AppConstants.prefRole) ?? _conn.localRole;

    setState(() {
      _nameController.text = name;
      _bioController.text = bio;
      _selectedRole = role;
      _nodeId = _crypto.nodeId;
    });
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama tidak boleh kosong.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _savedSuccess = false;
    });

    await _conn.updateProfile(
      name: name,
      bio: bio.isEmpty ? 'Siaga Offline' : bio,
      role: _selectedRole,
    );

    setState(() {
      _isSaving = false;
      _savedSuccess = true;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _savedSuccess = false);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Profil berhasil disimpan dan disiarkan ke radar mesh!'),
          backgroundColor: AppTheme.primaryEmerald,
        ),
      );
    }
  }

  void _copyNodeId() {
    if (_nodeId.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _nodeId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Node ID disalin ke papan klip')),
      );
    }
  }

  Future<void> _rotateAnonymousIdentity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppTheme.accentCyan),
            SizedBox(width: 8),
            Text('Rotasi Identitas Anonim'),
          ],
        ),
        content: const Text(
          'Tindakan ini akan membuat Node ID acak baru, kunci enkripsi AES baru, dan callsign baru secara instan. Jejak identitas lama Anda akan terputus dari jaringan mesh.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentCyan),
            child: const Text('Acak Identitas Sekarang', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    final newCallsign = await _conn.rotateAnonymousIdentity();
    _nameController.text = newCallsign;
    _bioController.text = '👻 Node Anonim Terenkripsi';
    _selectedRole = 'Operatif Anonim';
    _nodeId = _crypto.nodeId;
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Identitas berhasil diacak menjadi: $newCallsign'),
          backgroundColor: AppTheme.primaryEmerald,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Profil & Pengaturan'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── LIVE PROFILE PREVIEW ──
          _SectionTitle('Pratinjau Tampilan di Radar Orang Lain'),
          _LivePreviewCard(
            displayName: _nameController.text.isEmpty ? 'Nama Anda' : _nameController.text,
            bio: _bioController.text.isEmpty ? 'Siaga Offline' : _bioController.text,
            role: _selectedRole,
            nodeId: _nodeId,
          ),
          const SizedBox(height: 16),

          // ── ANONYMOUS GHOST IDENTITY BANNER ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryEmerald.withAlpha(25),
                  AppTheme.accentCyan.withAlpha(15),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryEmerald.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryEmerald.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppTheme.primaryEmerald, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MODE ANONIM PENUH (GHOST)',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                          Text('Tanpa nomor HP, email, atau jejak identitas pribadi',
                              style: TextStyle(color: Colors.white60, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _rotateAnonymousIdentity,
                    icon: const Icon(Icons.casino_outlined, size: 16),
                    label: const Text('Acak Callsign & Kunci Baru', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.accentCyan),
                      foregroundColor: AppTheme.accentCyan,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── EDIT PROFILE FORM ──
          _SectionTitle('Edit Callsign & Peran Taktis'),
          _SettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Callsign Taktis (Terlihat di Radar)',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Phantom-7F89',
                    prefixIcon: Icon(Icons.shield_outlined, color: AppTheme.primaryEmerald),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Peran / Peruntukan di Lapangan',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _roleOptions.map((opt) {
                    final isSel = _selectedRole == opt['title'];
                    final color = opt['color'] as Color;
                    return ChoiceChip(
                      selected: isSel,
                      selectedColor: color.withAlpha(50),
                      backgroundColor: AppTheme.surfaceLight.withAlpha(60),
                      side: BorderSide(
                        color: isSel ? color : Colors.white24,
                        width: isSel ? 1.5 : 1,
                      ),
                      avatar: Icon(opt['icon'] as IconData, size: 16, color: isSel ? color : Colors.white70),
                      label: Text(
                        opt['title'] as String,
                        style: TextStyle(
                          color: isSel ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedRole = opt['title'] as String);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                const Text('Status Darurat / Bio Singkat',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _bioController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Contoh: 🟢 Aman di shelter tenda 3',
                    prefixIcon: Icon(Icons.edit_note, color: AppTheme.accentCyan),
                  ),
                ),
                const SizedBox(height: 8),

                // Preset bio chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickBioPresets.map((preset) {
                    return ActionChip(
                      backgroundColor: AppTheme.surfaceLight.withAlpha(50),
                      side: BorderSide(color: AppTheme.surfaceLight.withAlpha(120)),
                      label: Text(
                        preset,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      onPressed: () {
                        setState(() {
                          _bioController.text = preset;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Icon(_savedSuccess ? Icons.check_circle : Icons.save_rounded),
                    label: Text(_savedSuccess ? 'Tersimpan & Disiarkan' : 'Simpan Perubahan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _savedSuccess ? const Color(0xFF00C853) : AppTheme.primaryEmerald,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── NODE SECURITY & IDENTITY ──
          _SectionTitle('Identitas Kriptografis Perangkat'),
          _SettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Node ID (Unik & Serverless)',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                    InkWell(
                      onTap: _copyNodeId,
                      child: const Row(
                        children: [
                          Icon(Icons.copy, size: 14, color: AppTheme.accentCyan),
                          SizedBox(width: 4),
                          Text('Salin ID', style: TextStyle(color: AppTheme.accentCyan, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _nodeId.isEmpty ? 'Memuat identitas...' : _nodeId,
                  style: const TextStyle(
                    color: AppTheme.accentCyan,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(color: Colors.white12, height: 20),
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: AppTheme.primaryEmerald),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Enkripsi E2EE: AES-GCM-256 + Diffie-Hellman Key Exchange',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── ABOUT & PROTOCOL ──
          _SectionTitle('Spesifikasi & Versi Sistem'),
          _SettingCard(
            child: Column(
              children: [
                _InfoRow('Versi Aplikasi', '${AppConstants.appVersion} (Stable Production)'),
                const Divider(color: Colors.white12, height: 18),
                _InfoRow('Protokol Jaringan', 'OFFMAS Mesh v2 / Multi-Hop Flood DTN'),
                const Divider(color: Colors.white12, height: 18),
                _InfoRow('Mode Fisik', 'Bluetooth Radio P2P (100% Murni Offline)'),
                const Divider(color: Colors.white12, height: 18),
                _InfoRow('Kompatibilitas', 'Android 6.0+ s/d Android 15 & iOS 13+'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── SAFETY BANNER ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.surfaceLight.withAlpha(120)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppTheme.accentCyan, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'OFFMAS bekerja 100% tanpa internet, pulsa, atau server eksternal. Semua pesan dan data kontak disimpan lokal di perangkat Anda secara aman.',
                    style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ── LIVE PREVIEW CARD ──────────────────────────────────────────────────────
class _LivePreviewCard extends StatelessWidget {
  final String displayName;
  final String bio;
  final String role;
  final String nodeId;

  const _LivePreviewCard({
    required this.displayName,
    required this.bio,
    required this.role,
    required this.nodeId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131922),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryEmerald.withAlpha(120), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryEmerald.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmerald.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryEmerald),
                ),
                child: const Icon(Icons.person_pin_rounded, color: AppTheme.primaryEmerald, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentCyan.withAlpha(35),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.accentCyan.withAlpha(100)),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryEmerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          '🟢 Aktif di Radar Sekitar',
                          style: TextStyle(color: AppTheme.primaryEmerald, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.surfaceLight.withAlpha(100)),
            ),
            child: Text(
              bio,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

// ── REUSABLE HELPERS ───────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final Widget child;
  const _SettingCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withAlpha(100)),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        Text(value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }
}
