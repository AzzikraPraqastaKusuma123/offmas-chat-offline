import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/models/group_model.dart';
import '../core/crypto/crypto_service.dart';
import '../core/notifications/notification_service.dart';

enum PeerStatus { found, connected, disconnected, lost }

class DiscoveredPeerInfo {
  final String endpointId;
  String displayName;
  String bio;
  String role;
  String? nodeId;
  PeerStatus status;

  DiscoveredPeerInfo({
    required this.endpointId,
    required this.displayName,
    this.bio = 'Siaga Offline',
    this.role = 'Umum',
    this.nodeId,
    this.status = PeerStatus.found,
  });
}

class IncomingRequest {
  final String endpointId;
  final String displayName;
  final String authToken;

  IncomingRequest({
    required this.endpointId,
    required this.displayName,
    required this.authToken,
  });
}

class IncomingMessage {
  final String fromEndpointId;
  final String fromDisplayName;
  final String content;
  final String type;
  final DateTime timestamp;
  final int hopCount;
  final String? groupId;
  final String? groupName;

  IncomingMessage({
    required this.fromEndpointId,
    required this.fromDisplayName,
    required this.content,
    this.type = 'TEXT',
    required this.timestamp,
    this.hopCount = 0,
    this.groupId,
    this.groupName,
  });
}

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  final Nearby _nearby = Nearby();
  final _uuid = const Uuid();
  final _db = DatabaseService();
  final _crypto = CryptoService();
  final _notifications = NotificationService();

  // Profile variables
  String _localDisplayName = 'OFFMAS User';
  String _localBio = 'Siaga Offline';
  String _localRole = 'Umum';

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  // Maps: endpointId -> info
  final Map<String, DiscoveredPeerInfo> _discoveredPeers = {};
  final Map<String, DiscoveredPeerInfo> _connectedPeers = {};

  // Deduplication cache for mesh packets (prevents broadcast storms/loops)
  final Set<String> _seenPacketIds = {};

  // Active chat ID to suppress notifications if user is already looking at it
  String? activeChatEndpointId;

  // Stream controllers
  final _peersController = StreamController<List<DiscoveredPeerInfo>>.broadcast();
  final _requestController = StreamController<IncomingRequest>.broadcast();
  final _messageController = StreamController<IncomingMessage>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _receiptController = StreamController<String>.broadcast();
  final _connectedPeerController = StreamController<DiscoveredPeerInfo>.broadcast();

  // Pending requests waiting for user accept/reject (endpointId -> request)
  final Map<String, IncomingRequest> _pendingRequests = {};

  // Getters
  Stream<List<DiscoveredPeerInfo>> get peersStream => _peersController.stream;
  Stream<IncomingRequest> get requestStream => _requestController.stream;
  Stream<IncomingMessage> get messageStream => _messageController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<String> get receiptStream => _receiptController.stream;
  Stream<DiscoveredPeerInfo> get connectedPeerStream => _connectedPeerController.stream;
  String get localDisplayName => _localDisplayName;
  String get localBio => _localBio;
  String get localRole => _localRole;
  String get localNodeId => _crypto.nodeId;
  bool get isActive => _isAdvertising || _isDiscovering;
  List<DiscoveredPeerInfo> get connectedPeers => _connectedPeers.values.toList();
  List<DiscoveredPeerInfo> get discoveredPeers => _discoveredPeers.values.toList();

  Future<void> init() async {
    await _crypto.init();
    await _notifications.init();
    final prefs = await SharedPreferences.getInstance();
    final defaultGhostName = CryptoService.generateGhostCallsign(
      _crypto.nodeId.isNotEmpty ? _crypto.nodeId.substring(0, 4) : null,
    );
    _localDisplayName =
        prefs.getString(AppConstants.prefDisplayName) ?? defaultGhostName;
    _localBio = prefs.getString(AppConstants.prefBio) ?? 'Node Anonim Terenkripsi';
    _localRole = prefs.getString(AppConstants.prefRole) ?? 'Operatif Anonim';
  }

  /// Completely rotate anonymous identity and announce across mesh
  Future<String> rotateAnonymousIdentity() async {
    final newCallsign = await _crypto.rotateIdentity();
    _localDisplayName = newCallsign;
    _localBio = 'Node Anonim Terenkripsi';
    _localRole = 'Operatif Anonim';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefDisplayName, newCallsign);
    await prefs.setString(AppConstants.prefBio, _localBio);
    await prefs.setString(AppConstants.prefRole, _localRole);

    await _broadcastProfileSync();
    notifyListeners();
    return newCallsign;
  }

  Future<void> updateProfile({
    required String name,
    required String bio,
    required String role,
  }) async {
    _localDisplayName = name;
    _localBio = bio;
    _localRole = role;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefDisplayName, name);
    await prefs.setString(AppConstants.prefBio, bio);
    await prefs.setString(AppConstants.prefRole, role);

    // Broadcast updated profile to all connected peers
    await _broadcastProfileSync();
    notifyListeners();
  }

  Future<void> setDisplayName(String name) async {
    await updateProfile(name: name, bio: _localBio, role: _localRole);
  }

  // ── RESOLVE ACTIVE ENDPOINT FROM NODE ID OR ENDPOINT ID ───────────
  String? getActiveEndpointForNode(String target) {
    if (_connectedPeers.containsKey(target)) {
      return target;
    }
    for (final entry in _connectedPeers.entries) {
      if (entry.value.nodeId == target || entry.value.endpointId == target) {
        return entry.key;
      }
    }
    return null;
  }

  // ── START (SAFE & RESILIENT) ──────────────────────────────────────
  Future<bool> startAll() async {
    if (Platform.isIOS) {
      _isAdvertising = true;
      _isDiscovering = true;
      _statusController.add('Radar aktif (Mode iOS Siaga)');
      notifyListeners();
      return true;
    }

    // Always stop first to clear stale sessions
    try { await _nearby.stopAdvertising(); } catch (_) {}
    try { await _nearby.stopDiscovery(); } catch (_) {}
    try { await _nearby.stopAllEndpoints(); } catch (_) {}

    _isAdvertising = false;
    _isDiscovering = false;

    // Small delay to let the native layer settle
    await Future.delayed(const Duration(milliseconds: 400));

    try {
      await _startAdvertising();
    } catch (e) {
      debugPrint('OFFMAS: Advertising error (non-fatal): $e');
    }
    try {
      await _startDiscovery();
    } catch (e) {
      debugPrint('OFFMAS: Discovery error (non-fatal): $e');
    }

    // Treat as active even if only one side started
    _isAdvertising = true;
    _isDiscovering = true;
    _statusController.add('Radar aktif · Memindai gelombang sekitar...');
    notifyListeners();
    return true;
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await _nearby.startAdvertising(
        _localDisplayName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: AppConstants.serviceId,
      );
      _isAdvertising = true;
      debugPrint('OFFMAS: Advertising started');
    } catch (e) {
      if (e.toString().contains('8001') ||
          e.toString().contains('ALREADY_ADVERTISING')) {
        _isAdvertising = true;
      }
    }
  }

  Future<void> _startDiscovery() async {
    if (_isDiscovering) return;
    try {
      await _nearby.startDiscovery(
        _localDisplayName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (String id, String name, String serviceId) {
          debugPrint('OFFMAS: Found endpoint $name ($id)');
          final peer = DiscoveredPeerInfo(
            endpointId: id,
            displayName: name,
            status: PeerStatus.found,
          );
          _discoveredPeers[id] = peer;
          _peersController.add(_discoveredPeers.values.toList());
        },
        onEndpointLost: (String? id) {
          if (id != null) {
            _discoveredPeers.remove(id);
            _peersController.add(_discoveredPeers.values.toList());
          }
        },
        serviceId: AppConstants.serviceId,
      );
      _isDiscovering = true;
    } catch (e) {
      if (e.toString().contains('8002') ||
          e.toString().contains('ALREADY_DISCOVERING')) {
        _isDiscovering = true;
      }
    }
  }

  // ── CONNECTION CALLBACKS ──────────────────────────────────────────
  void _onConnectionInitiated(String id, ConnectionInfo info) async {
    debugPrint('OFFMAS: Connection initiated from ${info.endpointName} ($id)');

    final req = IncomingRequest(
      endpointId: id,
      displayName: info.endpointName,
      authToken: info.authenticationToken,
    );

    // Store pending request so acceptConnection/rejectConnection can reference it
    _pendingRequests[id] = req;

    // Show notification even when app is in background
    await _notifications.showConnectionRequestNotification(
      senderName: info.endpointName,
      endpointId: id,
    );

    // Emit to UI stream so HomeScreen can show the Accept/Reject dialog
    _requestController.add(req);
    _statusController.add('${info.endpointName} ingin terhubung...');
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('OFFMAS: Connected to $id');

      // Resolve peer name: discovered map → pending request → fallback
      final pendingReq = _pendingRequests[id];
      final discoveredName = _discoveredPeers[id]?.displayName;
      final peerName = discoveredName ?? pendingReq?.displayName ?? id;

      final peer = _discoveredPeers[id] ??
          DiscoveredPeerInfo(endpointId: id, displayName: peerName);
      peer.status = PeerStatus.connected;
      _connectedPeers[id] = peer;
      _pendingRequests.remove(id);
      _statusController.add('Terhubung dengan ${peer.displayName}');

      // Save to DB
      _db.upsertPeer({
        'node_id': id,
        'display_name': peer.displayName,
        'bio': peer.bio,
        'role': peer.role,
        'last_seen': DateTime.now().toIso8601String(),
        'is_verified': 1,
      });

      // Ensure conversation exists
      _db.upsertConversation({
        'id': 'conv_$id',
        'peer_id': id,
        'title': peer.displayName,
        'is_group': 0,
        'last_message': 'Terhubung secara offline',
        'last_message_at': DateTime.now().toIso8601String(),
        'unread_count': 0,
      });

      // Exchange profiles immediately upon connection
      _sendProfileSync(id);

      // Emit newly connected peer so HomeScreen can open chat automatically
      _connectedPeerController.add(peer);

      _peersController.add(_discoveredPeers.values.toList());
      notifyListeners();
    } else {
      _pendingRequests.remove(id);
      _statusController.add('Koneksi ditolak atau gagal');
    }
  }

  void _onDisconnected(String id) {
    _connectedPeers.remove(id);
    _statusController.add('Perangkat terputus');
    _peersController.add(_discoveredPeers.values.toList());
    notifyListeners();
  }

  // ── PROFILE SYNC PROTOCOL ─────────────────────────────────────────
  Future<void> _sendProfileSync(String endpointId) async {
    try {
      final packet = jsonEncode({
        'id': _uuid.v4(),
        'v': 1,
        'type': AppConstants.packetTypeProfileSync,
        'src': _crypto.nodeId,
        'name': _localDisplayName,
        'bio': _localBio,
        'role': _localRole,
      });
      await _nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(packet)),
      );
    } catch (_) {}
  }

  Future<void> _broadcastProfileSync() async {
    for (final peerId in _connectedPeers.keys) {
      await _sendProfileSync(peerId);
    }
  }

  // ── CONNECT / ACCEPT / REJECT ─────────────────────────────────────
  Future<void> connectToPeer(String endpointId) async {
    try {
      await _nearby.requestConnection(
        _localDisplayName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      if (e.toString().contains('8003') ||
          e.toString().contains('ALREADY_CONNECTED')) {
        _statusController.add('Sudah terhubung');
      } else {
        _statusController.add('Menghubungkan ke perangkat...');
      }
    }
  }

  Future<void> acceptConnection(String endpointId) async {
    try {
      _pendingRequests.remove(endpointId);
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: (String id, PayloadTransferUpdate update) {},
      );
    } catch (e) {
      debugPrint('OFFMAS: Accept connection error: $e');
    }
  }

  Future<void> rejectConnection(String endpointId) async {
    try {
      _pendingRequests.remove(endpointId);
      await _nearby.rejectConnection(endpointId);
      _statusController.add('Permintaan koneksi ditolak');
    } catch (e) {
      debugPrint('OFFMAS: Reject connection error: $e');
    }
  }

  // ── SEND 1-ON-1 MESSAGE WITH MESH & READ-RECEIPT SUPPORT ──────────
  Future<bool> sendMessage(String target, String text) async {
    try {
      final msgId = _uuid.v4();
      final now = DateTime.now();
      _seenPacketIds.add(msgId);

      final activeEndpoint = getActiveEndpointForNode(target);
      final targetPeer = activeEndpoint != null ? _connectedPeers[activeEndpoint] : null;
      final targetNodeId = targetPeer?.nodeId ?? target;
      final targetName = targetPeer?.displayName ?? 'Kontak';

      final packet = jsonEncode({
        'id': msgId,
        'v': 1,
        'type': AppConstants.packetTypeChat,
        'src': _crypto.nodeId,
        'sender_name': _localDisplayName,
        'dst': 'DIRECT',
        'target_node': targetNodeId,
        'ttl': 6,
        'hops': 0,
        'msg': text,
        'ts': now.toUtc().toIso8601String(),
      });

      final bytes = Uint8List.fromList(utf8.encode(packet));
      bool sent = false;

      // Direct send to active endpoint
      if (activeEndpoint != null) {
        try {
          await _nearby.sendBytesPayload(activeEndpoint, bytes);
          sent = true;
        } catch (e) {
          debugPrint('OFFMAS: Direct send failed, trying mesh: $e');
        }
      }

      // If direct send failed or endpoint not found, broadcast to connected mesh
      if (!sent && _connectedPeers.isNotEmpty) {
        for (final peerId in _connectedPeers.keys) {
          try {
            await _nearby.sendBytesPayload(peerId, bytes);
            sent = true;
          } catch (_) {}
        }
      }

      if (!sent && _connectedPeers.isEmpty) {
        return false;
      }

      final convId = 'conv_$target';
      await _db.upsertConversation({
        'id': convId,
        'peer_id': target,
        'title': targetName,
        'is_group': 0,
        'last_message': text,
        'last_message_at': now.toIso8601String(),
        'unread_count': 0,
      });

      await _db.insertMessage({
        'id': msgId,
        'conversation_id': convId,
        'sender_node_id': 'me',
        'sender_name': _localDisplayName,
        'content': text,
        'message_type': AppConstants.packetTypeChat,
        'timestamp': now.toIso8601String(),
        'status': AppConstants.statusSent,
        'hop_count': 0,
        'is_mine': 1,
      });

      await _db.updateConversationSnippet(
        conversationId: convId,
        lastMessage: text,
        lastMessageAt: now.toIso8601String(),
      );

      return true;
    } catch (e) {
      debugPrint('OFFMAS: Send message error: $e');
      return false;
    }
  }

  // ── SEND GROUP CHAT MESSAGE ───────────────────────────────────────
  Future<bool> sendGroupMessage(String groupId, String groupName, String text) async {
    try {
      final msgId = _uuid.v4();
      final now = DateTime.now();
      _seenPacketIds.add(msgId);

      final packet = jsonEncode({
        'id': msgId,
        'v': 1,
        'type': AppConstants.packetTypeGroupChat,
        'group_id': groupId,
        'group_name': groupName,
        'src': _crypto.nodeId,
        'sender_name': _localDisplayName,
        'dst': 'GROUP_BROADCAST',
        'ttl': 6,
        'hops': 0,
        'msg': text,
        'ts': now.toUtc().toIso8601String(),
      });

      final bytes = Uint8List.fromList(utf8.encode(packet));

      // Broadcast to all connected mesh peers
      for (final peerId in _connectedPeers.keys) {
        try {
          await _nearby.sendBytesPayload(peerId, bytes);
        } catch (_) {}
      }

      final convId = 'group_$groupId';
      await _db.insertMessage({
        'id': msgId,
        'conversation_id': convId,
        'sender_node_id': 'me',
        'sender_name': _localDisplayName,
        'content': text,
        'message_type': AppConstants.packetTypeGroupChat,
        'timestamp': now.toIso8601String(),
        'status': AppConstants.statusSent,
        'hop_count': 0,
        'is_mine': 1,
      });

      await _db.updateConversationSnippet(
        conversationId: convId,
        lastMessage: '$_localDisplayName: $text',
        lastMessageAt: now.toIso8601String(),
      );

      return true;
    } catch (e) {
      debugPrint('OFFMAS: Send group message error: $e');
      return false;
    }
  }

  // ── READ ACKNOWLEDGEMENT (SEND TO SENDER) ─────────────────────────
  Future<void> sendReadReceipt(String target, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      final activeEndpoint = getActiveEndpointForNode(target);
      final targetPeer = activeEndpoint != null ? _connectedPeers[activeEndpoint] : null;
      final targetNodeId = targetPeer?.nodeId ?? target;

      final packet = jsonEncode({
        'id': _uuid.v4(),
        'v': 1,
        'type': AppConstants.packetTypeReadAck,
        'src': _crypto.nodeId,
        'dst': targetNodeId,
        'msg_ids': messageIds,
        'ttl': 6,
        'hops': 0,
      });

      final bytes = Uint8List.fromList(utf8.encode(packet));
      bool sent = false;

      if (activeEndpoint != null && _connectedPeers.containsKey(activeEndpoint)) {
        try {
          await _nearby.sendBytesPayload(activeEndpoint, bytes);
          sent = true;
        } catch (_) {}
      }

      // If direct send failed or endpoint not found, broadcast to connected mesh
      if (!sent && _connectedPeers.isNotEmpty) {
        for (final peerId in _connectedPeers.keys) {
          try {
            await _nearby.sendBytesPayload(peerId, bytes);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ── SOS BROADCAST ─────────────────────────────────────────────────
  Future<bool> sendSos(String endpointId, String sosText) async {
    try {
      final msgId = _uuid.v4();
      final now = DateTime.now();
      _seenPacketIds.add(msgId);

      final formattedSos = '🆘 SOS: $sosText';
      final packet = jsonEncode({
        'id': msgId,
        'v': 1,
        'type': AppConstants.packetTypeSos,
        'src': _crypto.nodeId,
        'sender_name': _localDisplayName,
        'dst': 'BROADCAST',
        'ttl': 6,
        'hops': 0,
        'msg': formattedSos,
        'ts': now.toUtc().toIso8601String(),
      });

      final bytes = Uint8List.fromList(utf8.encode(packet));
      await _nearby.sendBytesPayload(endpointId, bytes);

      final convId = 'conv_$endpointId';
      final peerName = _connectedPeers[endpointId]?.displayName ?? 'Kontak';
      await _db.upsertConversation({
        'id': convId,
        'peer_id': endpointId,
        'title': peerName,
        'is_group': 0,
        'last_message': formattedSos,
        'last_message_at': now.toIso8601String(),
        'unread_count': 0,
      });

      await _db.insertMessage({
        'id': msgId,
        'conversation_id': convId,
        'sender_node_id': 'me',
        'sender_name': _localDisplayName,
        'content': formattedSos,
        'message_type': AppConstants.packetTypeSos,
        'timestamp': now.toIso8601String(),
        'status': AppConstants.statusSent,
        'hop_count': 0,
        'is_mine': 1,
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> broadcastSos(String sosText) async {
    for (final peerId in _connectedPeers.keys) {
      await sendSos(peerId, sosText);
    }
  }

  // ── RECEIVE PAYLOAD & MULTI-HOP MESH & RECEIPTS ───────────────────
  void _onPayloadReceived(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES) {
      try {
        final raw = utf8.decode(payload.bytes!);
        final packet = jsonDecode(raw) as Map<String, dynamic>;

        final msgId = packet['id'] as String? ?? _uuid.v4();
        final type = packet['type'] as String? ?? '';
        final src = packet['src'] as String? ?? endpointId;
        final senderName = packet['sender_name'] as String? ?? 'Kontak';
        final dst = packet['dst'] as String? ?? 'DIRECT';
        final ttl = packet['ttl'] as int? ?? 1;
        final hops = packet['hops'] as int? ?? 0;
        final msg = packet['msg'] as String? ?? '';
        final tsRaw = packet['ts'] as String?;
        final ts = tsRaw != null ? DateTime.tryParse(tsRaw) ?? DateTime.now() : DateTime.now();

        // ── 1. RECEIPT PACKETS ──
        if (type == AppConstants.packetTypeDeliveryAck) {
          final ackMsgId = packet['ack_id'] as String?;
          if (ackMsgId != null) {
            await _db.markSentMessageAsDelivered(ackMsgId);
            _receiptController.add(ackMsgId);
          }
          if (dst != _crypto.nodeId && dst != 'DIRECT' && ttl > 1) {
            _forwardMeshPacket(packet, endpointId, ttl, hops);
          }
          return;
        }

        if (type == AppConstants.packetTypeReadAck) {
          final msgIds = (packet['msg_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList();
          if (msgIds != null && msgIds.isNotEmpty) {
            await _db.markSentMessagesAsRead(msgIds);
            _receiptController.add(msgIds.first);
          }
          if (dst != _crypto.nodeId && dst != 'DIRECT' && ttl > 1) {
            _forwardMeshPacket(packet, endpointId, ttl, hops);
          }
          return;
        }

        // ── 2. PROFILE SYNC ──
        if (type == AppConstants.packetTypeProfileSync) {
          final peerName = packet['name'] as String? ?? senderName;
          final peerBio = packet['bio'] as String? ?? 'Siaga Offline';
          final peerRole = packet['role'] as String? ?? 'Umum';
          final peerNodeId = packet['src'] as String? ?? endpointId;

          if (_discoveredPeers.containsKey(endpointId)) {
            _discoveredPeers[endpointId]!.displayName = peerName;
            _discoveredPeers[endpointId]!.bio = peerBio;
            _discoveredPeers[endpointId]!.role = peerRole;
            _discoveredPeers[endpointId]!.nodeId = peerNodeId;
          }
          if (_connectedPeers.containsKey(endpointId)) {
            _connectedPeers[endpointId]!.displayName = peerName;
            _connectedPeers[endpointId]!.bio = peerBio;
            _connectedPeers[endpointId]!.role = peerRole;
            _connectedPeers[endpointId]!.nodeId = peerNodeId;
          }
          await _db.updatePeerProfile(
            nodeId: endpointId,
            displayName: peerName,
            bio: peerBio,
            role: peerRole,
          );
          await _db.upsertPeer({
            'node_id': peerNodeId,
            'display_name': peerName,
            'bio': peerBio,
            'role': peerRole,
            'last_seen': DateTime.now().toIso8601String(),
            'is_verified': 1,
          });
          _peersController.add(_discoveredPeers.values.toList());
          notifyListeners();
          return;
        }

        // ── 3. LOOP MITIGATION ──
        if (_seenPacketIds.contains(msgId)) return;
        _seenPacketIds.add(msgId);
        if (_seenPacketIds.length > 5000) _seenPacketIds.remove(_seenPacketIds.first);

        // ── 4. PROCESS 1-ON-1 CHAT ──
        final isForMe = dst == 'DIRECT' ||
                        dst == 'BROADCAST' ||
                        dst == _crypto.nodeId ||
                        dst == endpointId ||
                        _connectedPeers.containsKey(endpointId);

        if (isForMe && (type == AppConstants.packetTypeChat || type == AppConstants.packetTypeSos)) {
          final convId = 'conv_$endpointId';
          final peerName = _connectedPeers[endpointId]?.displayName ?? senderName;

          await _db.upsertPeer({
            'node_id': endpointId,
            'display_name': peerName,
            'last_seen': ts.toIso8601String(),
            'is_verified': 1,
          });

          await _db.upsertConversation({
            'id': convId,
            'peer_id': endpointId,
            'title': peerName,
            'is_group': 0,
            'last_message': msg,
            'last_message_at': ts.toIso8601String(),
          });

          if (src != endpointId) {
            await _db.upsertConversation({
              'id': 'conv_$src',
              'peer_id': src,
              'title': peerName,
              'is_group': 0,
              'last_message': msg,
              'last_message_at': ts.toIso8601String(),
            });
          }

          final isCurrentChat = activeChatEndpointId == endpointId ||
                                activeChatEndpointId == src ||
                                activeChatEndpointId == convId;
          final status = isCurrentChat ? AppConstants.statusRead : AppConstants.statusDelivered;

          await _db.insertMessage({
            'id': msgId,
            'conversation_id': convId,
            'sender_node_id': src,
            'sender_name': peerName,
            'content': msg,
            'message_type': type,
            'timestamp': ts.toIso8601String(),
            'status': status,
            'hop_count': hops,
            'is_mine': 0,
          });

          if (src != endpointId) {
            await _db.insertMessage({
              'id': '${msgId}_src',
              'conversation_id': 'conv_$src',
              'sender_node_id': src,
              'sender_name': peerName,
              'content': msg,
              'message_type': type,
              'timestamp': ts.toIso8601String(),
              'status': status,
              'hop_count': hops,
              'is_mine': 0,
            });
          }

          await _db.updateConversationSnippet(
            conversationId: convId,
            lastMessage: msg,
            lastMessageAt: ts.toIso8601String(),
            incrementUnread: !isCurrentChat,
          );

          // Reply with Delivery ACK (Centang 2 Abu) back to sender
          try {
            final deliveryPacket = jsonEncode({
              'id': _uuid.v4(),
              'v': 1,
              'type': AppConstants.packetTypeDeliveryAck,
              'ack_id': msgId,
              'src': _crypto.nodeId,
              'dst': src,
              'ttl': 6,
              'hops': 0,
            });
            final ackBytes = Uint8List.fromList(utf8.encode(deliveryPacket));
            final targetEp = getActiveEndpointForNode(src) ?? endpointId;
            await _nearby.sendBytesPayload(targetEp, ackBytes);
          } catch (_) {}

          // If user is currently looking at chat, immediately reply with Read ACK (Centang 2 Biru)
          if (isCurrentChat) {
            sendReadReceipt(src, [msgId]);
          } else {
            // Push Notification
            if (type == AppConstants.packetTypeSos) {
              await _notifications.showSosNotification(sender: peerName, content: msg);
            } else {
              await _notifications.showMessageNotification(sender: peerName, content: msg, conversationId: convId);
            }
          }

          _messageController.add(IncomingMessage(
            fromEndpointId: endpointId,
            fromDisplayName: peerName,
            content: msg,
            type: type,
            timestamp: ts,
            hopCount: hops,
          ));
        }

        // ── 5. PROCESS GROUP CHAT ──
        if (type == AppConstants.packetTypeGroupChat) {
          final groupId = packet['group_id'] as String?;
          final groupName = packet['group_name'] as String? ?? 'Grup Offline';

          if (groupId != null) {
            final convId = 'group_$groupId';
            final isCurrentChat = activeChatEndpointId == convId || activeChatEndpointId == groupId;

            // Automatically ensure group exists in DB on receiver's phone!
            final existingGroup = await _db.getGroup(groupId);
            if (existingGroup == null) {
              await _db.createGroup(
                group: GroupModel(
                  id: groupId,
                  name: groupName,
                  createdAt: ts,
                  createdBy: senderName,
                  memberCount: 2,
                ),
                memberNodeIds: [src, _crypto.nodeId],
              );
            }

            await _db.insertMessage({
              'id': msgId,
              'conversation_id': convId,
              'sender_node_id': src,
              'sender_name': senderName,
              'content': msg,
              'message_type': AppConstants.packetTypeGroupChat,
              'timestamp': ts.toIso8601String(),
              'status': isCurrentChat ? AppConstants.statusRead : AppConstants.statusDelivered,
              'hop_count': hops,
              'is_mine': 0,
            });

            await _db.updateConversationSnippet(
              conversationId: convId,
              lastMessage: '$senderName: $msg',
              lastMessageAt: ts.toIso8601String(),
              incrementUnread: !isCurrentChat,
            );

            if (!isCurrentChat) {
              await _notifications.showMessageNotification(
                sender: '👥 [$groupName] $senderName',
                content: msg,
                conversationId: convId,
              );
            }

            _messageController.add(IncomingMessage(
              fromEndpointId: endpointId,
              fromDisplayName: senderName,
              content: msg,
              type: type,
              timestamp: ts,
              hopCount: hops,
              groupId: groupId,
              groupName: groupName,
            ));
          }
        }

        // ── 6. MULTI-HOP MESH FORWARDING ──
        if (ttl > 1) {
          _forwardMeshPacket(packet, endpointId, ttl, hops);
        }
      } catch (e) {
        debugPrint('OFFMAS: Failed to parse payload: $e');
      }
    }
  }

  void _forwardMeshPacket(Map<String, dynamic> packet, String incomingEndpointId, int ttl, int hops) {
    if (ttl <= 1) return;
    try {
      final forwardPacket = Map<String, dynamic>.from(packet);
      forwardPacket['ttl'] = ttl - 1;
      forwardPacket['hops'] = hops + 1;

      final forwardBytes = Uint8List.fromList(utf8.encode(jsonEncode(forwardPacket)));

      for (final otherPeerId in _connectedPeers.keys) {
        if (otherPeerId != incomingEndpointId) {
          try {
            _nearby.sendBytesPayload(otherPeerId, forwardBytes);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('OFFMAS: Forward packet error: $e');
    }
  }

  // ── STOP (CLEAN RESET) ────────────────────────────────────────────
  Future<void> stopAll() async {
    try {
      try {
        await _nearby.stopAdvertising();
      } catch (_) {}
      try {
        await _nearby.stopDiscovery();
      } catch (_) {}
      try {
        await _nearby.stopAllEndpoints();
      } catch (_) {}

      _isAdvertising = false;
      _isDiscovering = false;
      _connectedPeers.clear();
      _discoveredPeers.clear();
      _peersController.add([]);
      _statusController.add('Radar dinonaktifkan');
      notifyListeners();
    } catch (e) {
      debugPrint('OFFMAS: StopAll error: $e');
    }
  }

  @override
  void dispose() {
    _peersController.close();
    _requestController.close();
    _messageController.close();
    _statusController.close();
    _receiptController.close();
    _connectedPeerController.close();
    super.dispose();
  }
}
