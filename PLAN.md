# OFFMAS (Offline Messenger) - Master Engineering Plan & Technical Specification

> **Dokumen Arsitektur, Desain Sistem, dan Roadmap Pengembangan Komprehensif**  
> *Versi:* 1.0.0-PROD-DRAFT  
> *Target Platform:* Cross-Platform (Android & iOS via Flutter)  
> *Kategori:* Decentralized P2P & Mesh Communications / Disaster-Resilient Network  

---

## 1. Ringkasan Eksekutif & Pemahaman Masalah

### 1.1 Visi Proyek
**OFFMAS** (*Offline Messenger*) adalah aplikasi perpesanan terdesentralisasi (*peer-to-peer* dan *ad-hoc mesh*) yang dirancang untuk beroperasi secara **100% mandiri tanpa ketergantungan pada infrastruktur internet, menara BTS seluler, maupun server pusat**. 

Aplikasi ini ditujukan untuk skenario:
1. **Bencana Alam & Krisis:** Gempa bumi, tsunami, banjir bandang di mana infrastruktur telekomunikasi lumpuh.
2. **Kawasan Terpencil (*Off-Grid*):** Ekspedisi hutan, pegunungan, laut, dan area pedalaman tanpa sinyal seluler.
3. **Privasi & Keamanan Maksimal:** Komunikasi lokal tanpa risiko *man-in-the-middle* eksternal, penyadapan internet, atau sensor server pusat.

### 1.2 Pemahaman Mendalam atas Tantangan Teknis Utama
Membangun aplikasi offline messenger di smartphone modern menghadapi hambatan teknis yang nyata:
* **Asimetri Protokol Android vs iOS:** Android mendukung Wi-Fi Direct P2P secara native, sedangkan iOS mengunci Wi-Fi Direct dan lebih mengandalkan *Multipeer Connectivity framework* (AWDL/Bonjour) atau BLE. Solusinya membutuhkan lapisan abstraksi hybrid (*BLE Discovery + Local Hotspot/Socket + Wi-Fi Aware*).
* **Restriksi Latar Belakang (OS Background Execution):** iOS membunuh proses background yang tidak aktif dalam hitungan detik hingga menit dan membatasi BLE background scanning/advertising. Android menerapkan *Doze Mode* dan *battery optimization* agresif pada vendor tertentu (Xiaomi MIUI/HyperOS, Samsung OneUI).
* **Bandwidth vs Jangkauan (Trade-off):** 
  * BLE: Konsumsi daya sangat hemat (~10-30 meter), tetapi bandwidth sangat sempit (~1-2 Mbps PHY, riil ~10-50 KB/s). Cocok untuk teks, metadata, sinyal discovery, dan mesh beacon.
  * Wi-Fi Direct / Local Wi-Fi: Kecepatan tinggi (10-50+ Mbps), jangkauan sedang (~30-80 meter), konsumsi baterai lebih tinggi. Cocok untuk pengiriman foto, rekaman suara, dan dokumen.
  * LoRa (Meshtastic via companion device): Jangkauan sangat jauh (1-10+ km), namun bandwidth sangat sempit (< 5.4 kbps). Hanya untuk teks pendek, lokasi GPS, dan sinyal darurat SOS.

---

## 2. Arsitektur Berlapis (Multi-Tier Architecture)

Arsitektur OFFMAS dibagi menjadi 5 lapisan independen (*decoupled layers*) agar setiap modul dapat diuji, dimutasi, dan diganti tanpa merusak modul lainnya:

```
+-------------------------------------------------------------------------+
|                         APPLICATION & PRESENTATION                      |
|      (Flutter UI / BLoC / Chat Screens / Map / SOS Emergency Mode)       |
+-------------------------------------------------------------------------+
                                    |
+-------------------------------------------------------------------------+
|                         SERVICES & ORCHESTRATION                        |
|  (MessageService, PeerManager, MediaManager, SessionManager, SyncQueue) |
+-------------------------------------------------------------------------+
                                    |
+-------------------------------------------------------------------------+
|                       SECURITY & STORAGE LAYER                          |
|   - End-to-End Encryption (E2EE): X25519 + ChaCha20-Poly1305 / Ed25519 |
|   - Local Database: SQLite (SQLCipher) / Isar terenkripsi               |
+-------------------------------------------------------------------------+
                                    |
+-------------------------------------------------------------------------+
|                         ROUTING & MESH ENGINE                           |
|   - Delay-Tolerant Networking (DTN) / Store-and-Forward                 |
|   - Epidemic / Flood Routing dengan Hop-Limit (TTL) & Deduplication     |
+-------------------------------------------------------------------------+
                                    |
+-------------------------------------------------------------------------+
|                        HARDWARE & TRANSPORT LAYER                       |
|   - BLE (Discovery & Tiny Packet Relay)                                |
|   - Local Wi-Fi / Wi-Fi Direct / Multipeer / TCP-UDP Socket             |
|   - External Gateway: LoRa 433/868/915 MHz (Meshtastic over BLE/Serial) |
+-------------------------------------------------------------------------+
```

---

## 3. Desain Protokol Jaringan & Transport

### 3.1 Mode Komunikasi Hybrid (Triple-Transport Protocol)

| Protokol | Peran Utama | Ukuran Payload | Estimasi Jangkauan |
| :--- | :--- | :--- | :--- |
| **BLE (Bluetooth Low Energy)** | Discovery, Handshake, Heartbeat, Teks Singkat, Mesh Signaling | < 512 bytes (MTU tuned) | 10 - 40 meter |
| **Wi-Fi Socket / Wi-Fi Direct** | Transfer Foto, Dokumen, Voice Note, Chat Berkelanjutan | Megabytes | 30 - 80 meter |
| **LoRa (Meshtastic Bridge)** | Komunikasi Luar Jangkauan, Broadcast SOS, Koordinat GPS | < 237 bytes per packet | 2 - 15 km (Line-of-sight) |

### 3.2 Strategi Discovery & Pairing Cross-Platform
1. **Fase I: Discovery (BLE Advertising & Scanning)**
   * Setiap node mengiklankan `Service UUID` unik OFFMAS: `0000FF01-0000-1000-8000-00805F9B34FB`.
   * Payload advertising memuat identitas publik singkat: `NodeID (8 byte) + Nickname (max 12 byte) + Status Flags`.
2. **Fase II: Handshake & Autentikasi Keamanan (Out-of-band Verification)**
   * Menggunakan SAS (*Short Authentication String*) berupa 4 atau 6 digit PIN numerik atau visual QR-Code.
   * Pertukaran kunci publik sementara (ephemeral X25519) dilakukan pada sesi terenkripsi.
3. **Fase III: Transport Upgrade (Koneksi Data Cepat)**
   * Jika kedua perangkat adalah Android dan mendukung Wi-Fi Direct: negosiasi Group Owner (GO) dan sambungkan soket TCP berkecepatan tinggi.
   * Jika campuran Android-iOS: Android/iOS membuat Local Hotspot/SoftAP sementara atau menggunakan koneksi Wi-Fi jaringan lokal (jika berada dalam jangkauan access point offline tanpa internet yang sama).
   * Fallback otomatis: jika Wi-Fi gagal atau dimatikan, semua pesan tetap dapat dikirim lewat BLE chunks.

---

## 4. Keamanan & Kriptografi End-to-End (E2EE)

Keamanan OFFMAS tidak mengandalkan keamanan bawaan transport (seperti PIN bawaan Bluetooth) saja, melainkan menerapkan enkripsi tingkat aplikasi:

1. **Identitas Kriptografis (Identity Keypair):**
   * Setiap instalasi membuat pasangan kunci Ed25519 unik untuk tanda tangan digital (*Signing Key*) dan X25519 untuk pertukaran kunci enkripsi (*Diffie-Hellman Key*).
2. **Proses Enkripsi Pesan (Double Ratchet / Forward Secrecy Lite):**
   * Untuk komunikasi 1-on-1: Setiap sesi menggunakan algoritma pertukaran kunci X25519 menghasilkan *Shared Secret* bersama.
   * Enkripsi simetris menggunakan **ChaCha20-Poly1305** atau **AES-GCM-256** dengan Nonce acak 96-bit (menjamin kerahasiaan dan integritas pesan).
3. **Perlindungan Terhadap Replay Attack:**
   * Setiap paket memuat `timestamp (UTC ISO8601)`, `sequence_number`, dan `packet_nonce`.
   * Node penerima menolak paket dengan *timestamp drift* > 30 menit atau `sequence_number` yang sudah pernah diproses.
4. **Penyimpanan Lokal:**
   * SQLite dienkripsi menggunakan modul enkripsi database (seperti SQLCipher) menggunakan kunci turunan dari biometrik atau PIN pengguna.

---

## 5. Struktur Paket Protokol OFFMAS (Wire Protocol Specification)

Format biner/JSON terstandarisasi untuk semua paket yang dikirimkan:

```json
{
  "v": 1,
  "id": "e5b8d2b2-6045-42d7-b715-cfd32646d7e1",
  "src": "NODE_ALPHA_PUBKEY_HASH",
  "dst": "NODE_BRAVO_PUBKEY_HASH", 
  "type": "CHAT",
  "ttl": 5,
  "hops": 0,
  "ts": 1793750000,
  "payload": {
    "nonce": "k3f8gL0...",
    "ciphertext": "A8f9b90c1e...",
    "tag": "d13a9f..."
  },
  "sig": "ED25519_SIGNATURE_OVER_HEADER_AND_PAYLOAD"
}
```

### Definisi Tipe Paket:
* `PING / PONG`: Sinyal deteksi node hidup di sekitar.
* `KEY_EXCHANGE`: Pertukaran public key dan negosiasi parameter sesi.
* `CHAT`: Pesan teks terenkripsi.
* `FILE_START / FILE_CHUNK / FILE_ACK`: Pengiriman file dengan mekanisme chunking 32KB - 64KB dan checksum SHA-256 per chunk.
* `ROUTING_RELAY`: Paket mesh yang sedang dilewatkan oleh node perantara.
* `SOS_BROADCAST`: Pesan darurat prioritas tinggi tanpa enkripsi spesifik target (ditampilkan langsung ke semua node terdekat).

---

## 6. Protokol Mesh & Delay-Tolerant Networking (DTN)

Salah satu keunggulan terbesar OFFMAS adalah **kemampuan multi-hop relay**: Jika Node A ingin menghubungi Node C yang berada 60 meter jauhnya, pesan dapat melompat melalui Node B yang berada di tengah.

```
[Node A]  ---- (BLE/Wi-Fi ~30m) ---->  [Node B (Relay)]  ---- (BLE/Wi-Fi ~30m) ---->  [Node C]
(Pengirim)                                (Kurir Paket)                              (Penerima)
```

### Mekanisme Pengiriman:
1. **Loop Mitigation (Pencegahan Badai Paket / Flooding Loop):**
   * Setiap pesan memiliki UUID unik dan `ttl` (Time-To-Live, default: 5 hop).
   * Setiap node memiliki cache ringkas (*Bloom Filter* atau *LRU Cache* berisi 10.000 ID pesan terakhir). Jika pesan dengan ID yang sama diterima kembali, paket langsung di-drop.
2. **Store-and-Forward (DTN):**
   * Jika penerima tidak ditemukan di sekitar, paket masuk ke tabel `outbox_mesh_queue` lokal dengan status `PENDING`.
   * Ketika smartphone pengguna berpindah lokasi fisik dan mendeteksi node baru, node secara otomatis menanyakan apakah node baru tersebut mengenali `dst` atau memiliki rute lebih dekat, lalu meneruskannya.

---

## 7. Desain Database Lokal (SQLite / Encrypted Engine)

Tabel skema relasional offline:

### Tabel `peers`
* `node_id` (TEXT PRIMARY KEY) - Hash unik dari Public Key
* `display_name` (TEXT)
* `public_key` (TEXT)
* `last_seen` (DATETIME)
* `preferred_transport` (TEXT: BLE / WIFI_DIRECT / LORA)
* `is_verified` (BOOLEAN) - Status verifikasi PIN SAS
* `is_favorite` (BOOLEAN)

### Tabel `conversations`
* `id` (TEXT PRIMARY KEY)
* `peer_id` (TEXT FK ke `peers.node_id`, NULL jika grup)
* `title` (TEXT)
* `is_group` (BOOLEAN DEFAULT 0)
* `last_message_at` (DATETIME)
* `unread_count` (INTEGER DEFAULT 0)

### Tabel `messages`
* `id` (TEXT PRIMARY KEY) - UUID paket
* `conversation_id` (TEXT FK ke `conversations.id`)
* `sender_node_id` (TEXT)
* `content` (TEXT) - Teks terdekripsi (disimpan aman di database lokal)
* `message_type` (TEXT: TEXT, IMAGE, FILE, AUDIO, SOS)
* `timestamp` (DATETIME)
* `status` (TEXT: DRAFT, SENDING, SENT, RELAYED, DELIVERED, READ, FAILED)
* `hop_count` (INTEGER)
* `file_path` (TEXT NULL)

### Tabel `mesh_relay_cache` (Pesan milik orang lain yang sedang kita bawakan)
* `packet_id` (TEXT PRIMARY KEY)
* `destination_node_id` (TEXT)
* `raw_packet_data` (BLOB / TEXT terenkripsi)
* `ttl` (INTEGER)
* `received_at` (DATETIME)
* `expires_at` (DATETIME)

---

## 8. Struktur Direktori Proyek (Clean Architecture)

```
offline_messenger/
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml       (Izin BLE, Wi-Fi Direct, Background Service)
│       └── kotlin/id/offmas/app/      (Native bridging jika diperlukan)
├── ios/
│   └── Runner/
│       └── Info.plist                (Bonjour, CoreBluetooth, Multipeer description)
├── lib/
│   ├── main.dart                     (Entry point & Service initialization)
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_constants.dart
│   │   │   └── protocol_constants.dart
│   │   ├── crypto/
│   │   │   ├── crypto_engine.dart    (X25519, ChaCha20, Ed25519)
│   │   │   └── key_manager.dart      (Secure key storage)
│   │   ├── database/
│   │   │   ├── app_database.dart     (SQLite/SQLCipher implementation)
│   │   │   └── daos/                 (PeerDao, MessageDao, OutboxDao)
│   │   ├── errors/
│   │   └── theme/
│   │       ├── app_theme.dart        (High contrast dark mode & tactical styling)
│   │       └── colors.dart
│   ├── services/
│   │   ├── connection_service.dart   (Manajer state BLE & Wi-Fi adapter)
│   │   ├── discovery_service.dart    (Advertising & Scanning orchestrator)
│   │   ├── packet_router.dart        (Parser, validator & dispatcher paket)
│   │   ├── mesh_service.dart         (Multi-hop relay logic & DTN queue)
│   │   ├── file_transfer_service.dart(Chunking, SHA256 integrity, reassembly)
│   │   └── lora_gateway_service.dart (Meshtastic BLE protocol bridge)
│   ├── features/
│   │   ├── home/
│   │   │   ├── screens/home_screen.dart
│   │   │   └── widgets/radar_discovery_view.dart
│   │   ├── chat/
│   │   │   ├── screens/chat_screen.dart
│   │   │   └── widgets/message_bubble.dart
│   │   ├── pairing/
│   │   │   ├── screens/pin_verify_dialog.dart
│   │   │   └── screens/qr_pairing_screen.dart
│   │   ├── network_map/
│   │   │   └── screens/mesh_topology_screen.dart (Visualisasi node sekitar)
│   │   ├── sos/
│   │   │   └── screens/sos_broadcast_screen.dart
│   │   └── settings/
│   │       └── screens/settings_screen.dart
└── pubspec.yaml
```

---

## 9. Roadmap Pengembangan Bertahap (Sprint Execution Plan)

### Fase 1: Fondasi P2P & Transport Stabil (Sprint 1 - 2)
* Setup repository dan dependensi inti (`nearby`, `permission_handler`, `cryptography`, `sqflite`/`sqlcipher`, `uuid`).
* Konfigurasi permissions Android (`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `NEARBY_WIFI_DEVICES`) dan iOS (`NSBluetoothAlwaysUsageDescription`, Bonjour services).
* Implementasi modul `ConnectionService` dan `DiscoveryService`.
* Uji coba koneksi 1-on-1 Android-ke-Android: Pengujian kirim-terima teks dengan autentikasi PIN verification.

### Fase 2: Kriptografi E2EE & Database Lokal (Sprint 3 - 4)
* Implementasi modul `crypto_engine.dart` menggunakan algoritma modern (X25519 key exchange + ChaCha20-Poly1305 encryption).
* Pemasangan database lokal untuk riwayat chat permanen, status read receipt, dan kontak tersimpan.
* Penanganan lifecycle backgrounding dan auto-reconnect saat link koneksi terputus.

### Fase 3: Transfer Berkas & Audio Offline (Sprint 5 - 6)
* Pembuatan `FileTransferService`: Mekanisme pembagian file menjadi potongan *chunks* 32 KB.
* Progress bar transfer, verifikasi hash SHA-256 untuk memastikan keutuhan file foto/dokumen.
* Perekaman dan pemutaran pesan suara (*voice note*) offline.

### Fase 4: Routing Mesh & Store-and-Forward (Sprint 7 - 8)
* Implementasi `MeshService`: Forwarding paket antar perangkat (Hop-limit / TTL tracking).
* Deduplication cache (mencegah loop broadcasting).
* Antrian Store-and-Forward: Menyimpan paket di penyimpanan internal hingga node target atau node tetangga terdeteksi di kemudian waktu.

### Fase 5: Integrasi Gateway LoRa / Meshtastic (Sprint 9 - 10)
* Menghubungkan smartphone ke modul radio LoRa (misal: Heltec V3, T-Beam, LilyGO) lewat Bluetooth BLE.
* Bridging paket protokol OFFMAS ke format protobuf Meshtastic.
* Pengujian transmisi jarak jauh (1 - 5 km) di area tanpa sinyal seluler.

### Fase 6: UI/UX Tactical Refinement & Field Testing (Sprint 11+)
* UI bertema *Tactical / Clean Minimalist* dengan mode kontras tinggi (mudah dibaca di bawah sinar matahari langsung).
* Layar *Mesh Radar*: Peta topologi node-node yang sedang terhubung di sekitar pengguna.
* Tombol Darurat *SOS Broadcast*: Sekali tekan menyiarkan nama, pesan bahaya, dan koordinat GPS terakhir ke seluruh node terdekat.
* Uji coba lapangan simulasi bencana dengan 4-8 perangkat smartphone simultan.

---

## 10. Checklist Prosedur Pengujian (Acceptance Criteria)

- [ ] **Test Case 1 (Airplane Mode):** Aktifkan mode pesawat, hidupkan hanya Bluetooth dan Wi-Fi. Verifikasi pengiriman pesan berhasil tanpa kartu SIM/paket data aktif.
- [ ] **Test Case 2 (Dynamic Reconnect):** Matikan Bluetooth di salah satu perangkat, nyalakan kembali. Aplikasi harus mampu *handshake* ulang secara otomatis tanpa perlu restart aplikasi.
- [ ] **Test Case 3 (Data Integrity):** Kirim file gambar resolusi tinggi (3-5 MB) lewat Wi-Fi Direct. Pastikan hash file pengirim dan penerima identik.
- [ ] **Test Case 4 (3-Node Mesh Relay):** Letakkan Node A dan Node C di jarak 80 meter (tidak saling melihat). Letakkan Node B di tengah (40 meter). Kirim pesan dari A ke C. Pastikan pesan sampai dengan status `Hop Count: 1`.
- [ ] **Test Case 5 (E2EE Proof):** Inspect payload biner lewat packet sniffer; pastikan tidak ada teks biasa (*plaintext*) yang bocor di udara.

---

## 11. Kesimpulan & Langkah Eksekusi Pertama
Dengan arsitektur di atas, **OFFMAS** bukan sekadar tiruan aplikasi chat biasa, melainkan protokol komunikasi mandiri (*sovereign communication system*).

**Langkah Pertama yang Akan Segera Dilakukan:**
1. Menginisialisasi proyek Flutter `offline_messenger` di workspace ini.
2. Mengonfigurasi `pubspec.yaml` dengan dependensi yang presisi dan kompatibel.
3. Menyusun arsitektur folder kode dan baseline class untuk `ConnectionService`.

