# OFFMAS - Dokumen Analisis & Rencana Ekstensi Jangkauan (Extended Range Plan)

> **Analisis Fisika Radio, Rekayasa Multi-Hop Mesh, dan Integrasi Jarak Jauh (Kilometer)**  
> *Target:* Meningkatkan Jangkauan Komunikasi OFFMAS dari Puluhan Meter Menjadi Ratusan Meter hingga Belasan Kilometer  

---

## 1. Analisis Fisika & Batasan Perangkat Keras Smartphone

### 1.1 Realitas Antena & Daya Pancar Smartphone
Setiap smartphone (Android & iPhone) dirancang untuk komunikasi jarak dekat hingga menengah:
* **Daya Pancar (TX Power):** 10 mW – 100 mW (dibatasi demi hemat baterai dan regulasi SAR).
* **Frekuensi 2.4 GHz:** Gelombang pendek memiliki bandwidth besar, tetapi pelemahan sinyal (*path loss*) sangat tinggi ketika melewati dinding beton, pepohonan lebat, dan tanah.
* **Jangkauan Efektif Antar-Smartphone Langsung:**
  * Bluetooth LE: 15 – 35 meter (terhalang) / 40 – 60 meter (lapangan terbuka).
  * Wi-Fi Direct: 30 – 50 meter (terhalang) / 70 – 100 meter (lapangan terbuka).

---

## 2. Tiga Solusi Memperpanjang Jangkauan

### Solusi 1: Multi-Hop Mesh Relaying (100% Software - Nol Biaya)
* **Konsep:** Setiap smartphone yang menjalankan OFFMAS bertindak sebagai *router* / *relai* otomatis.
* **Mekanisme:** Jika Node A ingin menghubungi Node C yang berjarak 120 meter, paket melompat melalui Node B di tengah.
* **Pencegahan Loop:** Setiap paket memiliki `ttl` (Time-to-Live) dan `packet_id` yang dicatat di cache deduplikasi (*seen packets*) agar tidak terjadi badai data (*broadcast storm*).
* **Store-and-Forward (DTN):** Paket yang ditujukan ke node yang sedang di luar jangkauan disimpan di antrean lokal (*outbox*), lalu otomatis diteruskan saat perangkat pengguna berpindah tempat mendekati node tujuan.

### Solusi 2: Autonomous Battery Relay Beacon (Hardware Murah ~Rp 40.000)
* Menempatkan mikrokontroler ESP32 mandiri bertenaga powerbank atau panel surya mini di pohon, atap, atau tiang bendera posko.
* Node ini secara otomatis mengulang (*repeat*) setiap paket OFFMAS yang lewat, memperluas jangkauan area posko darurat hingga ratusan meter tanpa membebani HP relawan.

### Solusi 3: Long-Range LoRa Bridge (Jarak 2 – 15+ Kilometer)
* Menggunakan modul radio LoRa Sub-GHz (frekuensi resmi Indonesia 920–923 MHz).
* Smartphone dihubungkan via Bluetooth hemat daya ke modul saku mini (seperti *Heltec V3* atau *LilyGO T-Beam*).
* Gelombang radio LoRa menembus bukit, hutan, dan lembah hingga belasan kilometer untuk teks darurat dan koordinat GPS.

---

## 3. Matriks Perbandingan Teknologi

| Metode | Jangkauan Maksimal | Biaya Tambahan | Kecepatan Data | Kebutuhan Alat |
| :--- | :---: | :---: | :---: | :---: |
| **Koneksi Langsung (P2P)** | 30 – 80 meter | Rp 0 | Sangat Cepat (MB/s) | Hanya Smartphone |
| **Multi-Hop Mesh (Software)** | 100 – 400 meter | Rp 0 | Cepat (KB/s) | Rantai Smartphone |
| **Store-and-Forward (DTN)** | Tak Terbatas (Mobilitas) | Rp 0 | Tertunda (*Delay-Tolerant*) | Kurir Fisik |
| **ESP32 Relay Beacon** | 100 – 300 meter/node | ~Rp 40.000 | Cepat | Modul ESP32 |
| **LoRa Meshtastic Bridge** | **2.000 – 15.000 meter** | ~Rp 250.000 | Rendah (Teks/GPS) | Modul LoRa Saku |

---

## 4. Rencana Implementasi Bertahap

- [x] **Tahap 1:** Perancangan Wire Protocol Multi-Hop (`id`, `src`, `dst`, `ttl`, `hops`, `relayed_by`).
- [ ] **Tahap 2:** Integrasi Cache Deduplikasi (`mesh_seen_packets`) & Outbox DTN di SQLite lokal.
- [ ] **Tahap 3:** Engine Relai Otomatis di `ConnectionService` (meneruskan pesan jika bukan penerima akhir).
- [ ] **Tahap 4:** Tampilan UI Lencana Estafet di Gelembung Chat (`📡 Estafet X Hop`).
- [ ] **Tahap 5:** Verifikasi bebas error (`flutter analyze`) dan kompilasi APK rilis terbaru.

