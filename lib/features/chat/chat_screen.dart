import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/database/database_service.dart';
import '../../core/models/message_model.dart';
import '../../services/connection_service.dart';

class ChatScreen extends StatefulWidget {
  final String endpointId;
  final String peerName;
  final bool isGroup;
  final String? groupId;

  const ChatScreen({
    super.key,
    required this.endpointId,
    required this.peerName,
    this.isGroup = false,
    this.groupId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _conn = ConnectionService();
  final _db = DatabaseService();
  final _uuid = const Uuid();

  final List<MessageModel> _messages = [];
  StreamSubscription<IncomingMessage>? _msgSub;
  StreamSubscription<String>? _receiptSub;
  String _conversationId = '';
  late String _currentPeerName;
  bool _isSending = false;

  final List<String> _quickResponses = [
    '✅ Posisi aman & siaga',
    '🚨 Butuh bantuan darurat!',
    '📍 Sedang menuju lokasi',
    '⏳ Tunggu konfirmasi sebentar',
    '🔋 Mode hemat baterai',
  ];

  @override
  void initState() {
    super.initState();
    _currentPeerName = widget.peerName;
    if (widget.isGroup && widget.groupId != null) {
      _conversationId = 'group_${widget.groupId}';
      _conn.activeChatEndpointId = _conversationId;
    } else {
      _conversationId = 'conv_${widget.endpointId}';
      _conn.activeChatEndpointId = widget.endpointId;
    }

    _initConversation();
    _listenStreams();
  }

  Future<void> _initConversation() async {
    await _db.resetUnread(_conversationId);
    final unreadIncomingIds = await _db.markMessagesAsReadLocally(_conversationId);

    // If 1-on-1, send read receipts to the peer across mesh
    if (!widget.isGroup && unreadIncomingIds.isNotEmpty) {
      _conn.sendReadReceipt(widget.endpointId, unreadIncomingIds);
    }

    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    final rows = await _db.getMessages(_conversationId);
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.addAll(rows.map(MessageModel.fromMap));
    });
    _scrollToBottom();
  }

  void _listenStreams() {
    // Listen for incoming messages
    _msgSub = _conn.messageStream.listen((msg) {
      if (widget.isGroup && msg.groupId == widget.groupId) {
        final m = MessageModel(
          id: _uuid.v4(),
          conversationId: _conversationId,
          senderNodeId: msg.fromEndpointId,
          senderName: msg.fromDisplayName,
          content: msg.content,
          messageType: msg.type,
          timestamp: msg.timestamp,
          status: AppConstants.statusRead,
          hopCount: msg.hopCount,
          isMine: false,
        );
        if (mounted) {
          setState(() => _messages.add(m));
          _db.resetUnread(_conversationId);
          _scrollToBottom();
        }
      } else if (!widget.isGroup &&
          (msg.fromEndpointId == widget.endpointId ||
           _conversationId.contains(msg.fromEndpointId) ||
           msg.fromDisplayName.toLowerCase() == _currentPeerName.toLowerCase())) {
        final m = MessageModel(
          id: _uuid.v4(),
          conversationId: _conversationId,
          senderNodeId: msg.fromEndpointId,
          senderName: msg.fromDisplayName,
          content: msg.content,
          messageType: msg.type,
          timestamp: msg.timestamp,
          status: AppConstants.statusRead,
          hopCount: msg.hopCount,
          isMine: false,
        );
        if (mounted) {
          final exists = _messages.any((x) =>
              x.content == m.content &&
              x.timestamp.difference(m.timestamp).inSeconds.abs() < 3);
          if (!exists) {
            setState(() => _messages.add(m));
            _db.resetUnread(_conversationId);
            _scrollToBottom();
          }
        }
      }
    });

    // Listen for delivery / read receipts (ticks change in real-time)
    _receiptSub = _conn.receiptStream.listen((ackMsgId) {
      if (!mounted) return;
      _loadHistory();
    });
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = presetText ?? _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    bool success;
    if (widget.isGroup && widget.groupId != null) {
      success = await _conn.sendGroupMessage(
        widget.groupId!,
        widget.peerName,
        text,
      );
    } else {
      success = await _conn.sendMessage(widget.endpointId, text);
    }

    if (success) {
      final m = MessageModel(
        id: _uuid.v4(),
        conversationId: _conversationId,
        senderNodeId: 'me',
        senderName: _conn.localDisplayName,
        content: text,
        messageType: widget.isGroup ? AppConstants.packetTypeGroupChat : AppConstants.packetTypeChat,
        timestamp: DateTime.now(),
        status: AppConstants.statusSent,
        isMine: true,
      );
      if (presetText == null) _controller.clear();
      if (mounted) {
        setState(() => _messages.add(m));
        _scrollToBottom();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pesan gagal dikirim. Pastikan perangkat tujuan aktif di Radar Mesh sekitar.',
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showPeerProfile() {
    if (widget.isGroup) {
      _showGroupInfo();
      return;
    }

    final nameCtrl = TextEditingController(text: _currentPeerName);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.primaryEmerald.withAlpha(40),
                  child: const Icon(Icons.person, color: AppTheme.primaryEmerald, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentPeerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryEmerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Terhubung · P2P Mesh',
                            style: TextStyle(color: AppTheme.primaryEmerald, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            const Text('Ubah Nama Kontak', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'Nama panggilan...'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final newName = nameCtrl.text.trim();
                    if (newName.isNotEmpty) {
                      await _db.updatePeerProfile(
                        nodeId: widget.endpointId,
                        displayName: newName,
                      );
                      if (mounted) setState(() => _currentPeerName = newName);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Node Endpoint ID: ${widget.endpointId}',
              style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.accentCyan.withAlpha(40),
                  child: const Icon(Icons.groups_rounded, color: AppTheme.accentCyan, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentPeerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '👥 Grup Siaga Offline (Multi-Hop Mesh)',
                        style: TextStyle(color: AppTheme.accentCyan, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            const Text(
              'Informasi Grup',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Pesan di grup ini disebarkan melalui protokol estafet radio multi-hop mesh ke seluruh anggota yang telah saling menyimpan kontak.',
              style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            Text(
              'Group ID: ${widget.groupId}',
              style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _conn.activeChatEndpointId = null;
    _msgSub?.cancel();
    _receiptSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _showPeerProfile,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: widget.isGroup
                      ? AppTheme.accentCyan.withAlpha(40)
                      : AppTheme.primaryEmerald.withAlpha(40),
                  child: Icon(
                    widget.isGroup ? Icons.groups_rounded : Icons.person,
                    color: widget.isGroup ? AppTheme.accentCyan : AppTheme.primaryEmerald,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentPeerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.isGroup
                            ? '👥 Grup Mesh Offline'
                            : '🟢 Terhubung Offline (Mesh)',
                        style: TextStyle(
                          color: widget.isGroup ? AppTheme.accentCyan : AppTheme.primaryEmerald,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!widget.isGroup)
            IconButton(
              icon: const Icon(Icons.sos, color: AppTheme.emergencyRed),
              tooltip: 'Kirim SOS Cepat',
              onPressed: _showSosDialog,
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showPeerProfile,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.surfaceLight.withAlpha(120)),
                          ),
                          child: Icon(
                            widget.isGroup ? Icons.hub_outlined : Icons.lock_clock_outlined,
                            size: 38,
                            color: widget.isGroup ? AppTheme.accentCyan : AppTheme.primaryEmerald,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.isGroup
                              ? 'Grup Percakapan Mesh Offline'
                              : 'Percakapan Terenkripsi Offline',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Text(
                            widget.isGroup
                                ? 'Setiap pesan di grup ini akan disiarkan ke kontak tersimpan melalui gelombang radio tanpa server.'
                                : 'Pesan langsung dikirimkan lewat gelombang radio ke $_currentPeerName dengan enkripsi P2P.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : _buildMessageListWithDateDividers(),
          ),

          // Quick Response Chips
          Container(
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickResponses.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                backgroundColor: AppTheme.cardBackground,
                side: BorderSide(color: AppTheme.surfaceLight.withAlpha(140)),
                label: Text(
                  _quickResponses[i],
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                onPressed: () => _sendMessage(_quickResponses[i]),
              ),
            ),
          ),

          // Chat Input Bar
          _ChatInputBar(
            controller: _controller,
            isSending: _isSending,
            onSend: () => _sendMessage(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageListWithDateDividers() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final currentMsg = _messages[i];
        final bool showDateHeader;

        if (i == 0) {
          showDateHeader = true;
        } else {
          final prevMsg = _messages[i - 1];
          final curDate = DateTime(currentMsg.timestamp.year, currentMsg.timestamp.month, currentMsg.timestamp.day);
          final prevDate = DateTime(prevMsg.timestamp.year, prevMsg.timestamp.month, prevMsg.timestamp.day);
          showDateHeader = curDate.isAfter(prevDate);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDateHeader) _DateDivider(timestamp: currentMsg.timestamp),
            _MessageBubble(
              msg: currentMsg,
              isGroup: widget.isGroup,
            ),
          ],
        );
      },
    );
  }

  void _showSosDialog() {
    final sosController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sos, color: AppTheme.emergencyRed, size: 28),
            SizedBox(width: 8),
            Text('Kirim SOS Darurat', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: TextField(
          controller: sosController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Pesan darurat Anda (opsional)...',
          ),
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
              final text = sosController.text.trim().isEmpty
                  ? 'BUTUH BANTUAN DARURAT SEGERA!'
                  : sosController.text.trim();
              await _conn.sendSos(widget.endpointId, text);
              await _loadHistory();
            },
            child: const Text('KIRIM SEKARANG'),
          ),
        ],
      ),
    );
  }
}

// ── DATE DIVIDER WITH DAY, DATE, MONTH, YEAR ─────────────────────────────────
class _DateDivider extends StatelessWidget {
  final DateTime timestamp;
  const _DateDivider({required this.timestamp});

  static String _formatIndonesianFullDate(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;

    final monthNames = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final dayNames = [
      '', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
    ];

    final dayName = dayNames[dt.weekday];
    final monthName = monthNames[dt.month];

    if (isToday) {
      return 'Hari Ini · $dayName, ${dt.day} $monthName ${dt.year}';
    } else if (isYesterday) {
      return 'Kemarin · $dayName, ${dt.day} $monthName ${dt.year}';
    } else {
      return '$dayName, ${dt.day} $monthName ${dt.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground.withAlpha(220),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.surfaceLight.withAlpha(90)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 11, color: AppTheme.accentCyan),
              const SizedBox(width: 6),
              Text(
                _formatIndonesianFullDate(timestamp),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── MESSAGE BUBBLE ─────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isGroup;

  const _MessageBubble({
    required this.msg,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSos = msg.messageType == AppConstants.packetTypeSos;
    final isMe = msg.isMine;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isSos
              ? AppTheme.emergencyRed.withAlpha(220)
              : isMe
                  ? const Color(0xFF009650)
                  : AppTheme.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: !isMe && !isSos
              ? Border.all(color: AppTheme.surfaceLight.withAlpha(140))
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(35),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender name in Group Chat
            if (isGroup && !isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, color: AppTheme.accentCyan, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      msg.senderName,
                      style: const TextStyle(
                        color: AppTheme.accentCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Emergency SOS Badge
            if (isSos)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'PERINGATAN SOS DARURAT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

            // Mesh Relay Hop Count badge
            if (!isMe && msg.hopCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hub_outlined, color: AppTheme.accentCyan, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Estafet ${msg.hopCount} hop',
                      style: const TextStyle(
                        color: AppTheme.accentCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Message text
            Text(
              msg.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.white.withAlpha(235),
                fontSize: 14.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),

            // Time and Read Receipt Ticks
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatTime(msg.timestamp),
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.white38,
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildStatusTick(msg.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTick(String status) {
    if (status == AppConstants.statusRead) {
      // Double check cyan/blue: ✓✓ DIBACA
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 14, color: AppTheme.accentCyan),
        ],
      );
    } else if (status == AppConstants.statusDelivered) {
      // Double check grey: ✓✓ TERSAMPAIKAN
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 14, color: Colors.white70),
        ],
      );
    } else {
      // Single check grey: ✓ TERKIRIM
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done, size: 14, color: Colors.white70),
        ],
      );
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m WIB';
  }
}

// ── CHAT INPUT BAR ─────────────────────────────────────────────────────────
class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          top: BorderSide(color: AppTheme.surfaceLight.withAlpha(80)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ketik pesan radio offline...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  filled: true,
                  fillColor: AppTheme.darkBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.primaryEmerald,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: isSending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: isSending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.black, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
