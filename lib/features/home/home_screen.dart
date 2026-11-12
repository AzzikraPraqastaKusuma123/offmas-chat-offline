import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/database/database_service.dart';
import '../../core/models/conversation_model.dart';
import '../../core/models/group_model.dart';
import '../../core/models/peer_model.dart';
import '../../core/utils/permission_helper.dart';
import '../../services/connection_service.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/survival/survival_guide_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _conn = ConnectionService();
  final _db = DatabaseService();
  final _uuid = const Uuid();

  late TabController _tabController;
  StreamSubscription<List<DiscoveredPeerInfo>>? _peerSub;
  StreamSubscription<IncomingRequest>? _requestSub;
  StreamSubscription<IncomingMessage>? _messageSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<String>? _receiptSub;
  StreamSubscription<DiscoveredPeerInfo>? _connectedPeerSub;
  List<DiscoveredPeerInfo> _peers = [];
  List<ConversationModel> _conversations = [];
  Set<String> _savedPeerNodeIds = {};
  String _searchQuery = '';
  String _statusText = 'Tidak aktif';
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await _conn.init();
    await PermissionHelper.checkPermissionsGranted();
    _subscribeStreams();
    await _loadSavedPeers();
    await _loadConversations();
    setState(() {
      _isActive = _conn.isActive;
    });
  }

  Future<void> _loadSavedPeers() async {
    final rows = await _db.getSavedPeers();
    if (mounted) {
      setState(() {
        _savedPeerNodeIds = rows.map((r) => r['node_id'] as String).toSet();
      });
    }
  }

  void _subscribeStreams() {
    _peerSub = _conn.peersStream.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
    _statusSub = _conn.statusStream.listen((s) {
      // Never show raw exception strings in the status bar
      if (mounted) {
        final clean = s.contains('Exception') || s.contains('Error') || s.contains('Failure')
            ? 'Radar aktif · Memindai gelombang sekitar...'
            : s;
        setState(() => _statusText = clean);
      }
    });
    _receiptSub = _conn.receiptStream.listen((_) {
      _loadConversations();
    });
    _requestSub = _conn.requestStream.listen(_handleIncomingRequest);
    _messageSub = _conn.messageStream.listen(_handleIncomingMessage);

    // Auto-open chat when connection is accepted and established
    _connectedPeerSub = _conn.connectedPeerStream.listen((peer) {
      if (!mounted) return;
      _loadConversations();
      // Show snackbar that we're now connected
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🟢 Terhubung dengan ${peer.displayName}! Memulai sesi chat...'),
          backgroundColor: AppTheme.primaryEmerald,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'BUKA CHAT',
            textColor: Colors.black,
            onPressed: () => _openChat(peer.endpointId, peer.displayName),
          ),
        ),
      );
    });
  }

  Future<void> _loadConversations() async {
    final rows = await _db.getAllConversations();
    if (mounted) {
      setState(() {
        _conversations = rows.map(ConversationModel.fromMap).toList();
      });
    }
  }

  void _handleIncomingRequest(IncomingRequest req) {
    if (!mounted) return;

    // Auto-dismiss after 30 seconds (auto-reject)
    Timer? autoRejectTimer;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConnectionRequestSheet(
        request: req,
        onAccept: () {
          autoRejectTimer?.cancel();
          Navigator.of(ctx).pop();
          _conn.acceptConnection(req.endpointId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Permintaan dari ${req.displayName} diterima. Menunggu koneksi...'),
              backgroundColor: AppTheme.primaryEmerald,
              duration: const Duration(seconds: 3),
            ),
          );
        },
        onReject: () {
          autoRejectTimer?.cancel();
          Navigator.of(ctx).pop();
          _conn.rejectConnection(req.endpointId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Permintaan dari ${req.displayName} ditolak.'),
              backgroundColor: AppTheme.surfaceLight,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );

    // Start countdown — auto-reject after 30s
    autoRejectTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        _conn.rejectConnection(req.endpointId);
      }
    });
  }

  void _handleIncomingMessage(IncomingMessage msg) {
    if (!mounted) return;
    _loadConversations();
  }

  Future<void> _toggleService() async {
    if (_isActive) {
      try {
        await _conn.stopAll();
      } catch (_) {}
      setState(() {
        _isActive = false;
        _peers = [];
      });
      return;
    }

    bool granted = false;
    try {
      granted = await PermissionHelper.requestNearbyPermissions();
    } catch (_) {
      granted = true; // assume granted if check fails (let Nearby handle it)
    }

    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Izin Bluetooth & Lokasi diperlukan untuk mendeteksi perangkat sekitar.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      final started = await _conn.startAll();
      if (mounted) setState(() => _isActive = started);
    } catch (e) {
      // Any unexpected error — treat as active, Nearby will handle retry
      debugPrint('OFFMAS _toggleService error (ignored): $e');
      if (mounted) setState(() => _isActive = true);
    }
  }

  void _connectToPeer(DiscoveredPeerInfo peer) {
    _conn.connectToPeer(peer.endpointId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Menghubungkan gelombang radio ke ${peer.displayName}...')),
    );
  }

  void _openChat(String endpointId, String peerName, {bool isGroup = false, String? groupId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          endpointId: endpointId,
          peerName: peerName,
          isGroup: isGroup,
          groupId: groupId,
        ),
      ),
    ).then((_) {
      _loadConversations();
      _loadSavedPeers();
    });
  }

  Future<void> _toggleSaveContact(DiscoveredPeerInfo peer) async {
    final isAlreadySaved = _savedPeerNodeIds.contains(peer.endpointId);
    final newSaveState = !isAlreadySaved;

    await _db.upsertPeer({
      'node_id': peer.endpointId,
      'display_name': peer.displayName,
      'bio': peer.bio,
      'role': peer.role,
      'last_seen': DateTime.now().toIso8601String(),
      'is_saved': newSaveState ? 1 : 0,
      'is_verified': 1,
    });
    await _db.setContactSaved(peer.endpointId, newSaveState);
    await _loadSavedPeers();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newSaveState
              ? '✓ Kontak ${peer.displayName} disimpan ke daftar terpercaya.'
              : 'Kontak ${peer.displayName} dihapus dari daftar tersimpan.'),
          backgroundColor: newSaveState ? AppTheme.primaryEmerald : AppTheme.surfaceLight,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showCreateGroupModal() async {
    final savedRows = await _db.getSavedPeers();
    final savedPeers = savedRows.map(PeerModel.fromMap).toList();

    if (!mounted) return;

    if (savedPeers.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_person_outlined, color: AppTheme.warningOrange, size: 28),
              SizedBox(width: 10),
              Text('Simpan Kontak Dahulu', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: const Text(
            'Untuk keamanan jaringan offline, Anda harus saling menyimpan kontak terlebih dahulu sebelum membuat grup.\n\nBuka tab Radar Mesh, lalu tekan tombol "Simpan Kontak" pada perangkat rekan Anda.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryEmerald),
              child: const Text('Mengerti', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
      return;
    }

    final groupNameCtrl = TextEditingController();
    final selectedMembers = <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.group_add_rounded, color: AppTheme.accentCyan, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buat Grup Offline Baru',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Hanya kontak yang sudah tersimpan',
                        style: TextStyle(color: AppTheme.accentCyan, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: groupNameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Nama grup (cth: Tim Relawan Posko A)',
                  prefixIcon: Icon(Icons.title, color: AppTheme.primaryEmerald),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih Anggota Tersimpan:',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: savedPeers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final p = savedPeers[i];
                    final isChecked = selectedMembers.contains(p.nodeId);
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setModalState(() {
                          if (isChecked) {
                            selectedMembers.remove(p.nodeId);
                          } else {
                            selectedMembers.add(p.nodeId);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isChecked ? AppTheme.surfaceLight.withAlpha(80) : AppTheme.darkBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isChecked ? AppTheme.primaryEmerald : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isChecked ? AppTheme.primaryEmerald : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.displayName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  Text(
                                    '${p.role} · ${p.bio}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, color: Colors.black),
                  label: const Text('Buat & Mulai Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    final name = groupNameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Masukkan nama grup terlebih dahulu.')),
                      );
                      return;
                    }

                    final newGroupId = _uuid.v4();
                    final group = GroupModel(
                      id: newGroupId,
                      name: name,
                      createdAt: DateTime.now(),
                      createdBy: _conn.localDisplayName,
                      memberCount: selectedMembers.length + 1,
                    );

                    await _db.createGroup(
                      group: group,
                      memberNodeIds: selectedMembers.toList(),
                    );

                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadConversations();

                    _openChat(
                      'group_$newGroupId',
                      name,
                      isGroup: true,
                      groupId: newGroupId,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPeerDetailSheet(DiscoveredPeerInfo peer, bool isConnected) {
    final isSaved = _savedPeerNodeIds.contains(peer.endpointId);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isConnected
                        ? AppTheme.primaryEmerald.withAlpha(40)
                        : AppTheme.surfaceLight.withAlpha(80),
                    child: Icon(
                      Icons.person,
                      color: isConnected ? AppTheme.primaryEmerald : Colors.white70,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                peer.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
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
                                peer.role,
                                style: const TextStyle(
                                  color: AppTheme.accentCyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isConnected ? AppTheme.primaryEmerald : AppTheme.accentCyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isConnected ? '🟢 Terhubung Langsung' : '🔵 Terdeteksi di Udara',
                              style: TextStyle(
                                color: isConnected ? AppTheme.primaryEmerald : AppTheme.accentCyan,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.surfaceLight.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status & Bio Pengguna:',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      peer.bio,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Node ID: ${peer.endpointId}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _toggleSaveContact(peer);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: Icon(
                        isSaved ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                        color: isSaved ? AppTheme.primaryEmerald : Colors.white70,
                        size: 18,
                      ),
                      label: Text(isSaved ? 'Tersimpan' : 'Simpan Kontak'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isSaved ? AppTheme.primaryEmerald : Colors.white38,
                        ),
                        foregroundColor: isSaved ? AppTheme.primaryEmerald : Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (isConnected) {
                          _openChat(peer.endpointId, peer.displayName);
                        } else {
                          _connectToPeer(peer);
                        }
                      },
                      icon: Icon(
                        isConnected ? Icons.chat_bubble : Icons.wifi_tethering,
                        color: Colors.black,
                        size: 18,
                      ),
                      label: Text(isConnected ? 'Buka Chat' : 'Hubungkan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryEmerald,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _requestSub?.cancel();
    _messageSub?.cancel();
    _statusSub?.cancel();
    _receiptSub?.cancel();
    _connectedPeerSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Row(
          children: [
            // Custom Phantom Signal ("Ghost + Signal") Icon
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryEmerald.withAlpha(120), width: 1.2),
              ),
              child: CustomPaint(
                painter: _PhantomSignalPainter(),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OFFMAS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'MESH NETWORK',
                  style: TextStyle(
                    color: AppTheme.primaryEmerald,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.medical_services_outlined, color: AppTheme.accentCyan),
            tooltip: 'Panduan Darurat',
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SurvivalGuideScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Profil & Pengaturan',
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) {
                _loadSavedPeers();
              });
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryEmerald,
          indicatorWeight: 3,
          labelColor: AppTheme.primaryEmerald,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.radar_rounded), text: 'Radar Mesh'),
            Tab(icon: Icon(Icons.forum_outlined), text: 'Pesan'),
            Tab(icon: Icon(Icons.health_and_safety_outlined), text: 'P3K & Darurat'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Connection Status Bar
          _StatusBar(
            isActive: _isActive,
            statusText: _statusText,
            connectedCount: _conn.connectedPeers.length,
            onToggle: _toggleService,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Real-time Interactive Radar Mesh
                _RealtimeRadarTab(
                  isActive: _isActive,
                  peers: _peers,
                  connectedPeers: _conn.connectedPeers,
                  savedPeerIds: _savedPeerNodeIds,
                  onPeerTap: _showPeerDetailSheet,
                  onConnect: _connectToPeer,
                  onOpenChat: (id, name) => _openChat(id, name),
                  onSaveContact: _toggleSaveContact,
                ),

                // Tab 2: Conversations & Groups
                _ConversationsTab(
                  conversations: _conversations,
                  connectedPeers: _conn.connectedPeers,
                  searchQuery: _searchQuery,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  onCreateGroup: _showCreateGroupModal,
                  onOpen: (id, title, isGroup, groupId) =>
                      _openChat(id, title, isGroup: isGroup, groupId: groupId),
                  onDelete: (id) async {
                    await _db.deleteConversation(id);
                    await _loadConversations();
                  },
                ),

                // Tab 3: Survival Guide embedded
                const SurvivalGuideScreen(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _isActive
          ? FloatingActionButton.extended(
              onPressed: _showSosBroadcast,
              backgroundColor: AppTheme.emergencyRed,
              icon: const Icon(Icons.sos, color: Colors.white, size: 28),
              label: const Text(
                'SIARAN SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            )
          : null,
    );
  }

  void _showSosBroadcast() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.emergencyRed, size: 30),
            SizedBox(width: 10),
            Text('Siaran SOS Darurat', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pesan SOS akan disiarkan ke SEMUA perangkat sekitar yang terhubung (${_conn.connectedPeers.length} node mesh).',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Tulis situasi darurat Anda...',
                prefixIcon: Icon(Icons.edit_note, color: AppTheme.emergencyRed),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emergencyRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final text = ctrl.text.trim().isEmpty
                  ? 'TOLONG BANTU SAYA! SITUASI DARURAT!'
                  : ctrl.text.trim();
              await _conn.broadcastSos(text);
              await _loadConversations();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pesan SOS berhasil disiarkan ke seluruh perangkat!'),
                    backgroundColor: AppTheme.emergencyRed,
                  ),
                );
              }
            },
            child: const Text('SIARKAN SEKARANG'),
          ),
        ],
      ),
    );
  }
}

// ── CUSTOM PHANTOM SIGNAL PAINTER (GHOST + SINYAL) ─────────────────────────
class _PhantomSignalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGhost = Paint()
      ..color = AppTheme.primaryEmerald
      ..style = PaintingStyle.fill;

    final paintWaves = Paint()
      ..color = AppTheme.accentCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // 1. Draw Ghost Silhouette in lower 65%
    final ghostTop = h * 0.38;
    final ghostBottom = h * 0.95;
    final ghostLeft = w * 0.22;
    final ghostRight = w * 0.78;
    final ghostWidth = ghostRight - ghostLeft;

    final path = Path();
    path.moveTo(ghostLeft, ghostBottom);
    path.lineTo(ghostLeft, ghostTop + ghostWidth / 2);
    // Rounded head
    path.arcToPoint(
      Offset(ghostRight, ghostTop + ghostWidth / 2),
      radius: Radius.circular(ghostWidth / 2),
      clockwise: true,
    );
    path.lineTo(ghostRight, ghostBottom);
    // Wavy bottom skirt
    final waveW = ghostWidth / 3;
    path.quadraticBezierTo(ghostRight - waveW * 0.5, ghostBottom - 3, ghostRight - waveW, ghostBottom);
    path.quadraticBezierTo(ghostRight - waveW * 1.5, ghostBottom - 3, ghostRight - waveW * 2, ghostBottom);
    path.quadraticBezierTo(ghostRight - waveW * 2.5, ghostBottom - 3, ghostLeft, ghostBottom);
    path.close();
    canvas.drawPath(path, paintGhost);

    // Ghost Eyes
    final paintEyes = Paint()..color = const Color(0xFF0B0E14);
    canvas.drawCircle(Offset(w * 0.42, ghostTop + ghostWidth * 0.65), 1.6, paintEyes);
    canvas.drawCircle(Offset(w * 0.58, ghostTop + ghostWidth * 0.65), 1.6, paintEyes);

    // 2. Wireless Signal Arcs above head
    final centerArc = Offset(w * 0.5, ghostTop + 2);
    canvas.drawArc(
      Rect.fromCircle(center: centerArc, radius: 7),
      pi * 1.25,
      pi * 0.5,
      false,
      paintWaves,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centerArc, radius: 11),
      pi * 1.25,
      pi * 0.5,
      false,
      paintWaves,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── REAL-TIME RADAR TAB ────────────────────────────────────────────────────
class _RealtimeRadarTab extends StatefulWidget {
  final bool isActive;
  final List<DiscoveredPeerInfo> peers;
  final List<DiscoveredPeerInfo> connectedPeers;
  final Set<String> savedPeerIds;
  final void Function(DiscoveredPeerInfo, bool) onPeerTap;
  final void Function(DiscoveredPeerInfo) onConnect;
  final void Function(String, String) onOpenChat;
  final void Function(DiscoveredPeerInfo) onSaveContact;

  const _RealtimeRadarTab({
    required this.isActive,
    required this.peers,
    required this.connectedPeers,
    required this.savedPeerIds,
    required this.onPeerTap,
    required this.onConnect,
    required this.onOpenChat,
    required this.onSaveContact,
  });

  @override
  State<_RealtimeRadarTab> createState() => _RealtimeRadarTabState();
}

class _RealtimeRadarTabState extends State<_RealtimeRadarTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepAnim;

  @override
  void initState() {
    super.initState();
    _sweepAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _sweepAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.surfaceLight.withAlpha(100)),
              ),
              child: const Icon(Icons.wifi_tethering_off, size: 54, color: Colors.white38),
            ),
            const SizedBox(height: 20),
            const Text(
              'Radar OFFMAS Belum Aktif',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Tekan tombol AKTIFKAN di atas untuk memancarkan gelombang radio dan mencari pengguna sekitar secara real-time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final allPeers = <DiscoveredPeerInfo>[...widget.connectedPeers, ...widget.peers];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      children: [
        // Real-time Sonar Radar Canvas
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0D121B),
              border: Border.all(color: AppTheme.primaryEmerald.withAlpha(80), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryEmerald.withAlpha(25),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Sonar Canvas Painter
                CustomPaint(
                  size: const Size(250, 250),
                  painter: _SonarPainter(_sweepAnim),
                ),

                // Center Node ("Anda")
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryEmerald.withAlpha(160),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.person, color: Colors.black, size: 22),
                  ),
                ),

                // Plotted Peer Blips around Radar
                ...allPeers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final peer = entry.value;
                  final isConnected = widget.connectedPeers.any((p) => p.endpointId == peer.endpointId);

                  // Distribute blips in circular orbits
                  final angle = (idx * (2 * pi / max(1, allPeers.length))) - (pi / 4);
                  final distance = 60.0 + (idx % 2 == 0 ? 25.0 : 45.0);
                  final dx = cos(angle) * distance;
                  final dy = sin(angle) * distance;

                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: InkWell(
                      onTap: () => widget.onPeerTap(peer, isConnected),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isConnected ? AppTheme.primaryEmerald : AppTheme.accentCyan,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isConnected ? AppTheme.primaryEmerald : AppTheme.accentCyan).withAlpha(160),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person, color: Colors.black, size: 14),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Distance Indicator labels
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DistanceBadge('~10m (Sangat Dekat)', AppTheme.primaryEmerald),
            const SizedBox(width: 8),
            _DistanceBadge('~30m (Cakupan Mesh)', AppTheme.accentCyan),
          ],
        ),
        const SizedBox(height: 18),

        // List Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PENGGUNA AKTIF DI SEKITAR (${allPeers.length})',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (allPeers.isNotEmpty)
              const Text(
                'Sentuh untuk Profil & Simpan',
                style: TextStyle(color: AppTheme.accentCyan, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 10),

        if (allPeers.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight.withAlpha(80)),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.radar_rounded, color: Colors.white30, size: 36),
                  SizedBox(height: 8),
                  Text(
                    'Memindai gelombang radio sekitar...',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Pastikan perangkat lain juga membuka aplikasi OFFMAS dengan Bluetooth aktif.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          )
        else
          ...allPeers.map((peer) {
            final isConnected = widget.connectedPeers.any((p) => p.endpointId == peer.endpointId);
            final isSaved = widget.savedPeerIds.contains(peer.endpointId);
            return _ActivePeerCard(
              peer: peer,
              isConnected: isConnected,
              isSaved: isSaved,
              onTap: () => widget.onPeerTap(peer, isConnected),
              onConnect: () => widget.onConnect(peer),
              onChat: () => widget.onOpenChat(peer.endpointId, peer.displayName),
              onToggleSave: () => widget.onSaveContact(peer),
            );
          }),
      ],
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _DistanceBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

// ── ACTIVE PEER CARD ───────────────────────────────────────────────────────
class _ActivePeerCard extends StatelessWidget {
  final DiscoveredPeerInfo peer;
  final bool isConnected;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onChat;
  final VoidCallback onToggleSave;

  const _ActivePeerCard({
    required this.peer,
    required this.isConnected,
    required this.isSaved,
    required this.onTap,
    required this.onConnect,
    required this.onChat,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isConnected
                    ? AppTheme.primaryEmerald.withAlpha(40)
                    : AppTheme.surfaceLight.withAlpha(80),
                child: Icon(
                  Icons.person,
                  color: isConnected ? AppTheme.primaryEmerald : Colors.white70,
                  size: 22,
                ),
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
                            peer.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isSaved)
                          const Icon(Icons.bookmark, size: 14, color: AppTheme.primaryEmerald),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentCyan.withAlpha(30),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            peer.role,
                            style: const TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      peer.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isConnected)
                ElevatedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 14),
                  label: const Text('Chat'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              else
                OutlinedButton(
                  onPressed: onConnect,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryEmerald),
                    foregroundColor: AppTheme.primaryEmerald,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Hubungkan', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SONAR PAINTER ──────────────────────────────────────────────────────────
class _SonarPainter extends CustomPainter {
  final Animation<double> animation;
  _SonarPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Outer glow perimeter
    final perimeterPaint = Paint()
      ..color = AppTheme.primaryEmerald.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, maxR - 2, perimeterPaint);

    // Concentric Range Rings
    final ringPaint = Paint()
      ..color = AppTheme.primaryEmerald.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxR * i / 3, ringPaint);
    }

    // Crosshairs
    final crossPaint = Paint()
      ..color = AppTheme.primaryEmerald.withAlpha(40)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(center.dx, 4), Offset(center.dx, size.height - 4), crossPaint);
    canvas.drawLine(Offset(4, center.dy), Offset(size.width - 4, center.dy), crossPaint);

    // Diagonal tactical guides
    final diagPaint = Paint()
      ..color = AppTheme.surfaceLight.withAlpha(45)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(center.dx - maxR * 0.7, center.dy - maxR * 0.7),
        Offset(center.dx + maxR * 0.7, center.dy + maxR * 0.7), diagPaint);
    canvas.drawLine(Offset(center.dx - maxR * 0.7, center.dy + maxR * 0.7),
        Offset(center.dx + maxR * 0.7, center.dy - maxR * 0.7), diagPaint);

    // Compass tick marks on perimeter (every 30 degrees)
    final tickPaint = Paint()
      ..color = AppTheme.primaryEmerald.withAlpha(90)
      ..strokeWidth = 1.2;
    for (int deg = 0; deg < 360; deg += 30) {
      final rad = deg * pi / 180;
      final p1 = Offset(center.dx + (maxR - 6) * cos(rad), center.dy + (maxR - 6) * sin(rad));
      final p2 = Offset(center.dx + (maxR - 1) * cos(rad), center.dy + (maxR - 1) * sin(rad));
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Rotating Radar Sweep
    final angle = animation.value * 2 * pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - 1.2,
        endAngle: angle,
        colors: [
          Colors.transparent,
          AppTheme.primaryEmerald.withAlpha(160),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR));

    canvas.drawCircle(center, maxR, sweepPaint);

    // Cardinal Points ('N', 'E', 'S', 'W')
    _drawLabel(canvas, 'N', Offset(center.dx, 12), const Color(0xFF00E676));
    _drawLabel(canvas, 'S', Offset(center.dx, size.height - 12), Colors.white38);
    _drawLabel(canvas, 'E', Offset(size.width - 12, center.dy), Colors.white38);
    _drawLabel(canvas, 'W', Offset(12, center.dy), Colors.white38);
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── STATUS BAR ─────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final bool isActive;
  final String statusText;
  final int connectedCount;
  final VoidCallback onToggle;

  const _StatusBar({
    required this.isActive,
    required this.statusText,
    required this.connectedCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppTheme.primaryEmerald.withAlpha(140)
              : AppTheme.surfaceLight.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          _PulseDot(isActive: isActive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isActive)
                  Text(
                    '$connectedCount node mesh terhubung di udara',
                    style: const TextStyle(
                      color: AppTheme.primaryEmerald,
                      fontSize: 10.5,
                    ),
                  ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive
                  ? AppTheme.emergencyRed.withAlpha(210)
                  : AppTheme.primaryEmerald,
              foregroundColor: isActive ? Colors.white : Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isActive ? 'NONAKTIFKAN' : 'AKTIFKAN',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final bool isActive;
  const _PulseDot({required this.isActive});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.8, end: 1.35).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(5),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppTheme.primaryEmerald,
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryEmerald.withAlpha(140),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CONVERSATIONS TAB (PRIBADI & GRUP OFFLINE) ──────────────────────────────
class _ConversationsTab extends StatefulWidget {
  final List<ConversationModel> conversations;
  final List<DiscoveredPeerInfo> connectedPeers;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCreateGroup;
  final void Function(String, String, bool, String?) onOpen;
  final void Function(String) onDelete;

  const _ConversationsTab({
    required this.conversations,
    required this.connectedPeers,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onCreateGroup,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<_ConversationsTab> {
  int _selectedFilter = 0; // 0: Semua, 1: Pribadi, 2: Grup

  static String _formatConvDate(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;

    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');

    if (isToday) {
      return '$h:$m';
    } else if (isYesterday) {
      return 'Kemarin';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.conversations.where((c) {
      if (_selectedFilter == 1 && c.isGroup) return false;
      if (_selectedFilter == 2 && !c.isGroup) return false;

      if (widget.searchQuery.isEmpty) return true;
      final q = widget.searchQuery.toLowerCase();
      final title = c.title.toLowerCase();
      final last = (c.lastMessage ?? '').toLowerCase();
      return title.contains(q) || last.contains(q);
    }).toList();

    return Column(
      children: [
        // Action Bar: Search & Buat Grup Button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: widget.onSearchChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Cari percakapan atau kontak...',
                    prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                    filled: true,
                    fillColor: AppTheme.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.surfaceLight.withAlpha(90)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: widget.onCreateGroup,
                icon: const Icon(Icons.group_add, size: 16, color: Colors.black),
                label: const Text('Buat Grup', style: TextStyle(fontSize: 12, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentCyan,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),

        // Filter chips: Semua, Pribadi, Grup
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('Semua (${widget.conversations.length})', 0),
              const SizedBox(width: 6),
              _buildFilterChip('Pribadi', 1),
              const SizedBox(width: 6),
              _buildFilterChip('Grup Offline', 2),
            ],
          ),
        ),

        // Conversation List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.forum_outlined, size: 54, color: Colors.white.withAlpha(50)),
                      const SizedBox(height: 12),
                      Text(
                        widget.searchQuery.isEmpty
                            ? 'Belum ada percakapan.\nHubungkan perangkat di Radar atau buat Grup!'
                            : 'Tidak ada percakapan yang cocok dengan "${widget.searchQuery}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final conv = filtered[i];
                    final isOnline = widget.connectedPeers.any((p) => p.endpointId == conv.peerId);

                    return Dismissible(
                      key: Key(conv.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        padding: const EdgeInsets.only(right: 20),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: AppTheme.emergencyRed.withAlpha(180),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) => widget.onDelete(conv.id),
                      child: ListTile(
                        tileColor: AppTheme.cardBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: AppTheme.surfaceLight.withAlpha(80),
                          ),
                        ),
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: conv.isGroup
                                  ? AppTheme.accentCyan.withAlpha(35)
                                  : AppTheme.primaryEmerald.withAlpha(35),
                              child: Icon(
                                conv.isGroup ? Icons.groups_rounded : Icons.person,
                                color: conv.isGroup ? AppTheme.accentCyan : AppTheme.primaryEmerald,
                              ),
                            ),
                            if (!conv.isGroup && isOnline)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryEmerald,
                                    border: Border.all(
                                      color: AppTheme.cardBackground,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                conv.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            if (conv.isGroup)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentCyan.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'GRUP',
                                  style: TextStyle(
                                    color: AppTheme.accentCyan,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          conv.lastMessage ?? 'Belum ada pesan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: conv.unreadCount > 0 ? Colors.white : Colors.white54,
                            fontWeight: conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12.5,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (conv.lastMessageAt != null)
                              Text(
                                _formatConvDate(conv.lastMessageAt!),
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            const SizedBox(height: 4),
                            if (conv.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryEmerald,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${conv.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          final groupId = conv.isGroup ? conv.id.replaceFirst('group_', '') : null;
                          widget.onOpen(
                            conv.peerId ?? conv.id,
                            conv.title,
                            conv.isGroup,
                            groupId,
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSel = _selectedFilter == index;
    return ChoiceChip(
      selected: isSel,
      selectedColor: AppTheme.primaryEmerald.withAlpha(45),
      backgroundColor: AppTheme.cardBackground,
      side: BorderSide(
        color: isSel ? AppTheme.primaryEmerald : AppTheme.surfaceLight.withAlpha(80),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSel ? AppTheme.primaryEmerald : Colors.white60,
          fontSize: 11.5,
          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onSelected: (_) => setState(() => _selectedFilter = index),
    );
  }
}

// ── CONNECTION REQUEST BOTTOM SHEET ───────────────────────────────────────────
class _ConnectionRequestSheet extends StatefulWidget {
  final IncomingRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _ConnectionRequestSheet({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_ConnectionRequestSheet> createState() => _ConnectionRequestSheetState();
}

class _ConnectionRequestSheetState extends State<_ConnectionRequestSheet> {
  int _secondsLeft = 30;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) widget.onReject();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsLeft / 30.0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A2332),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Animated radar icon
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentCyan.withAlpha(20),
                  border: Border.all(color: AppTheme.accentCyan.withAlpha(80), width: 2),
                ),
              ),
              const Icon(Icons.wifi_tethering_rounded, color: AppTheme.accentCyan, size: 36),
            ],
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'PERMINTAAN TERHUBUNG',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),

          // Peer name
          Text(
            widget.request.displayName,
            style: const TextStyle(
              color: AppTheme.primaryEmerald,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ingin terhubung ke jaringan mesh Anda',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 6),

          // Auth token / PIN for verification
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.surfaceLight.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_outlined, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Token: ${widget.request.authToken.length > 12 ? widget.request.authToken.substring(0, 12) : widget.request.authToken}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Countdown bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Auto-tolak dalam:', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text(
                    '$_secondsLeft detik',
                    style: TextStyle(
                      color: _secondsLeft < 10 ? AppTheme.emergencyRed : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppTheme.surfaceLight.withAlpha(60),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _secondsLeft < 10 ? AppTheme.emergencyRed : AppTheme.accentCyan,
                  ),
                  minHeight: 5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Accept / Reject buttons
          Row(
            children: [
              // TOLAK button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onReject,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: const Text(
                    'TOLAK',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.emergencyRed,
                    side: const BorderSide(color: AppTheme.emergencyRed, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // TERIMA button
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: widget.onAccept,
                  icon: const Icon(Icons.check_rounded, size: 22, color: Colors.black),
                  label: const Text(
                    'TERIMA',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
