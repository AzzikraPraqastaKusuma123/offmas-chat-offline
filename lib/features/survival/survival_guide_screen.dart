import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SurvivalGuideScreen extends StatelessWidget {
  const SurvivalGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: AppTheme.primaryEmerald),
            SizedBox(width: 8),
            Text('Panduan Darurat Offline'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryEmerald.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryEmerald.withAlpha(80)),
            ),
            child: const Row(
              children: [
                Icon(Icons.offline_pin, color: AppTheme.primaryEmerald, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Panduan ini tersimpan 100% di memori ponsel. Dapat dibuka saat listrik padam atau tanpa internet.',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GuideCard(
            icon: Icons.favorite,
            iconColor: AppTheme.emergencyRed,
            title: '1. CPR (Resusitasi Jantung Paru)',
            subtitle: 'Bila korban tidak sadar & tidak bernapas',
            steps: const [
              'Pastikan lingkungan sekitar aman bagi Anda dan korban.',
              'Cek respon korban (panggil dan tepuk bahu dengan kuat).',
              'Posisikan tumit telapak tangan di tengah dada (tulang dada).',
              'Tekan dada sedalam 5-6 cm dengan kecepatan 100-120 kali/menit.',
              'Lakukan kompresi terus-menerus tanpa jeda hingga bantuan tiba.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.bloodtype,
            iconColor: AppTheme.emergencyRed,
            title: '2. Menghentikan Pendarahan Hebat',
            subtitle: 'Tekanan langsung dan pembalutan darurat',
            steps: const [
              'Gunakan kain bersih atau kassa tebal langsung di atas luka.',
              'Tekan kuat dengan kedua telapak tangan secara konstan minimal 5 menit.',
              'Tinggikan bagian tubuh yang terluka melebihi posisi jantung jika memungkinkan.',
              'Jika darah tetap tembus, tambahkan kain di atasnya tanpa melepas kain pertama.',
              'Gunakan torniket darurat pada pangkal lengan/paha jika darah memancar deras.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.landscape,
            iconColor: AppTheme.warningOrange,
            title: '3. Evakuasi Gempa Bumi',
            subtitle: 'Protokol Drop, Cover, and Hold On',
            steps: const [
              'Jatuhkan badan ke lantai (DROP) sebelum guncangan menjatuhkan Anda.',
              'Lindungi kepala dan leher di bawah meja kokoh (COVER).',
              'Pegang kaki meja hingga guncangan berhenti total (HOLD ON).',
              'Jauhi jendela kaca, cermin, dan lemari gantung yang rentan roboh.',
              'Setelah guncangan reda, gunakan tangga darurat. JANGAN gunakan lift!',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.waves,
            iconColor: AppTheme.accentCyan,
            title: '4. Sinyal Darurat Morse SOS',
            subtitle: 'Sinyal suara & senter tanpa radio',
            steps: const [
              'Kode Morse SOS: • • •  — — —  • • • (3 Pendek, 3 Panjang, 3 Pendek).',
              'Dengan peluit: Tiup 3 kali cepat, 3 kali panjang, 3 kali cepat.',
              'Dengan senter: Nyalakan 3 kedipan cepat, 3 kedipan panjang, 3 kedipan cepat.',
              'Ulangi pola setiap jeda 1 menit agar regu SAR dapat melacak lokasi Anda.',
            ],
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<String> steps;

  const _GuideCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: CircleAvatar(
          backgroundColor: iconColor.withAlpha(35),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(color: Colors.white12),
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: const TextStyle(
                      color: AppTheme.primaryEmerald,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
