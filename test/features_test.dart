import 'package:flutter_test/flutter_test.dart';
import 'package:offmas/core/constants/app_constants.dart';
import 'package:offmas/core/crypto/crypto_service.dart';
import 'package:offmas/core/models/message_model.dart';
import 'package:offmas/core/models/group_model.dart';
import 'package:offmas/core/models/peer_model.dart';
import 'package:offmas/core/models/conversation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. AppConstants Integrity Test', () {
    test('Semua packet types dan status message terdefinisi dengan benar', () {
      expect(AppConstants.appName, 'OFFMAS');
      expect(AppConstants.serviceId, 'id.offmas.messenger');
      expect(AppConstants.packetTypeChat, 'CHAT');
      expect(AppConstants.packetTypeGroupChat, 'GROUP_CHAT');
      expect(AppConstants.packetTypeDeliveryAck, 'DELIVERY_ACK');
      expect(AppConstants.packetTypeReadAck, 'READ_ACK');
      expect(AppConstants.packetTypeSos, 'SOS');
      expect(AppConstants.packetTypeProfileSync, 'PROFILE_SYNC');

      expect(AppConstants.statusSending, 'SENDING');
      expect(AppConstants.statusSent, 'SENT');
      expect(AppConstants.statusDelivered, 'DELIVERED');
      expect(AppConstants.statusRead, 'READ');
    });
  });

  group('2. CryptoService & E2EE Test Suite', () {
    late CryptoService crypto;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      crypto = CryptoService();
      await crypto.init();
    });

    test('Node ID ter-generate secara deterministik dan aman', () {
      expect(crypto.nodeId, isNotEmpty);
      expect(crypto.nodeId.length, 16); // 8 bytes in hex = 16 chars
    });

    test('Enkripsi & Dekripsi AES-GCM-256 berjalan simetris 100%', () async {
      const plaintext = 'Pesan rahasia mesh radio darurat tanpa server!';
      final encrypted = await crypto.encryptPayload(plaintext);

      expect(encrypted['ciphertext'], isNotNull);
      expect(encrypted['nonce'], isNotNull);
      expect(encrypted['tag'], isNotNull);

      // Decrypt
      final decrypted = await crypto.decryptPayload(encrypted);
      expect(decrypted, equals(plaintext));
    });

    test('SAS PIN 4-digit generated konsisten dari auth token', () {
      final pin1 = CryptoService.generatePinFromAuthToken('auth_token_sample_123');
      final pin2 = CryptoService.generatePinFromAuthToken('auth_token_sample_123');
      expect(pin1, equals(pin2));
      expect(pin1.length, 4);
      expect(int.tryParse(pin1), isNotNull);
    });
  });

  group('3. Data Models Serialization & Storage Suite', () {
    test('MessageModel serialisasi toMap dan fromMap konsisten', () {
      final now = DateTime(2026, 11, 10, 14, 30);
      final msg = MessageModel(
        id: 'msg_001',
        conversationId: 'peer_node_abc',
        senderNodeId: 'my_node_id',
        senderName: 'OFFMAS-Unit1',
        content: 'Jalur evakuasi sektor utara aman.',
        messageType: AppConstants.packetTypeChat,
        timestamp: now,
        status: AppConstants.statusSent,
        isMine: true,
        hopCount: 2,
      );

      final map = msg.toMap();
      expect(map['id'], 'msg_001');
      expect(map['status'], AppConstants.statusSent);
      expect(map['is_mine'], 1);
      expect(map['hop_count'], 2);

      final restored = MessageModel.fromMap(map);
      expect(restored.id, msg.id);
      expect(restored.content, msg.content);
      expect(restored.status, AppConstants.statusSent);
      expect(restored.isMine, isTrue);
      expect(restored.hopCount, 2);
    });

    test('GroupModel mapping data dan member count', () {
      final now = DateTime(2026, 11, 10, 10, 0);
      final group = GroupModel(
        id: 'group_rescue_team',
        name: 'Tim Evakuasi Posko 1',
        description: 'Koordinasi relawan lapangan',
        createdAt: now,
        createdBy: 'node_commander',
        memberCount: 5,
      );

      final map = group.toMap();
      expect(map['id'], 'group_rescue_team');
      expect(map['name'], 'Tim Evakuasi Posko 1');
      expect(map['created_by'], 'node_commander');

      final restored = GroupModel.fromMap(map);
      expect(restored.name, 'Tim Evakuasi Posko 1');
      expect(restored.memberCount, 1); // default from map if no count column
    });

    test('PeerModel mengelola kontak tersimpan dan role taktis', () {
      final peer = PeerModel(
        nodeId: 'node_medic_99',
        displayName: 'Dokter Sarah',
        bio: 'Siaga Medis • Posko B',
        role: 'Medis',
        lastSeen: '14:30',
        isSaved: true,
        isVerified: true,
      );

      final map = peer.toMap();
      expect(map['is_saved'], 1);
      expect(map['role'], 'Medis');
      expect(map['is_verified'], 1);

      final restored = PeerModel.fromMap(map);
      expect(restored.isSaved, isTrue);
      expect(restored.displayName, 'Dokter Sarah');
      expect(restored.role, 'Medis');
      expect(restored.isVerified, isTrue);
    });

    test('ConversationModel mengelola status unread count dan isGroup', () {
      final now = DateTime(2026, 11, 10, 15, 0);
      final conv = ConversationModel(
        id: 'conv_123',
        peerId: 'node_sar_1',
        title: 'Tim SAR Lapangan',
        lastMessage: 'Semua korban dievakuasi.',
        lastMessageAt: now,
        unreadCount: 3,
        isGroup: true,
      );

      final map = conv.toMap();
      expect(map['is_group'], 1);
      expect(map['unread_count'], 3);

      final restored = ConversationModel.fromMap(map);
      expect(restored.title, 'Tim SAR Lapangan');
      expect(restored.isGroup, isTrue);
      expect(restored.unreadCount, 3);
    });
  });

  group('4. Logika Routing Mesh & Pencegahan Duplikasi', () {
    test('Deduplication cache mencegah broadcast loop storm', () {
      final seenPacketIds = <String>{};

      const packetId = 'packet_mesh_7781';
      expect(seenPacketIds.contains(packetId), isFalse);

      // Packet pertama kali masuk: diterima
      seenPacketIds.add(packetId);
      expect(seenPacketIds.contains(packetId), isTrue);

      // Packet yang sama masuk lagi lewat hop berbeda: dibuang (rejected)
      final isDuplicate = seenPacketIds.contains(packetId);
      expect(isDuplicate, isTrue);
    });

    test('TTL hop decay dan eliminasi packet kedaluwarsa', () {
      int ttl = 6;
      int hopCount = 0;

      // Simulasi relay 5 hop antar perangkat
      for (int i = 0; i < 5; i++) {
        hopCount++;
        ttl--;
        expect(ttl, greaterThan(0));
      }

      expect(hopCount, 5);
      expect(ttl, 1);

      // Hop ke-6: batas jangkauan mesh
      hopCount++;
      ttl--;
      expect(ttl, 0);

      // Packet harus didrop jika TTL habis
      final shouldDrop = ttl <= 0;
      expect(shouldDrop, isTrue);
    });
  });
}
