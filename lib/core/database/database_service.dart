import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/group_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offmas.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Table: peers (daftar kontak)
    await db.execute('''
      CREATE TABLE peers (
        node_id       TEXT PRIMARY KEY,
        display_name  TEXT NOT NULL,
        bio           TEXT DEFAULT 'Siaga Offline',
        role          TEXT DEFAULT 'Umum',
        last_seen     TEXT NOT NULL,
        is_saved      INTEGER DEFAULT 0,
        is_verified   INTEGER DEFAULT 0,
        is_favorite   INTEGER DEFAULT 0
      )
    ''');

    // Table: conversations
    await db.execute('''
      CREATE TABLE conversations (
        id               TEXT PRIMARY KEY,
        peer_id          TEXT,
        group_id         TEXT,
        title            TEXT NOT NULL,
        is_group         INTEGER DEFAULT 0,
        last_message     TEXT,
        last_message_at  TEXT,
        unread_count     INTEGER DEFAULT 0
      )
    ''');

    // Table: groups
    await db.execute('''
      CREATE TABLE groups (
        id           TEXT PRIMARY KEY,
        name         TEXT NOT NULL,
        description  TEXT DEFAULT '',
        created_at   TEXT NOT NULL,
        created_by   TEXT NOT NULL
      )
    ''');

    // Table: group_members
    await db.execute('''
      CREATE TABLE group_members (
        group_id   TEXT NOT NULL,
        node_id    TEXT NOT NULL,
        joined_at  TEXT NOT NULL,
        PRIMARY KEY (group_id, node_id)
      )
    ''');

    // Table: messages
    await db.execute('''
      CREATE TABLE messages (
        id               TEXT PRIMARY KEY,
        conversation_id  TEXT NOT NULL,
        sender_node_id   TEXT NOT NULL,
        sender_name      TEXT DEFAULT 'Kontak',
        content          TEXT NOT NULL,
        message_type     TEXT DEFAULT 'TEXT',
        timestamp        TEXT NOT NULL,
        status           TEXT DEFAULT 'SENT',
        hop_count        INTEGER DEFAULT 0,
        is_mine          INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE peers ADD COLUMN bio TEXT DEFAULT 'Siaga Offline'");
        await db.execute("ALTER TABLE peers ADD COLUMN role TEXT DEFAULT 'Umum'");
        await db.execute("ALTER TABLE peers ADD COLUMN is_saved INTEGER DEFAULT 0");
      } catch (_) {}

      try {
        await db.execute("ALTER TABLE conversations ADD COLUMN group_id TEXT");
      } catch (_) {}

      try {
        await db.execute("ALTER TABLE messages ADD COLUMN sender_name TEXT DEFAULT 'Kontak'");
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS groups (
          id           TEXT PRIMARY KEY,
          name         TEXT NOT NULL,
          description  TEXT DEFAULT '',
          created_at   TEXT NOT NULL,
          created_by   TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS group_members (
          group_id   TEXT NOT NULL,
          node_id    TEXT NOT NULL,
          joined_at  TEXT NOT NULL,
          PRIMARY KEY (group_id, node_id)
        )
      ''');
    }
  }

  // ── PEERS (KONTAK) ────────────────────────────────────────────────
  Future<void> upsertPeer(Map<String, dynamic> peer) async {
    final db = await database;
    await db.insert('peers', peer,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllPeers() async {
    final db = await database;
    return db.query('peers', orderBy: 'is_saved DESC, is_favorite DESC, last_seen DESC');
  }

  Future<List<Map<String, dynamic>>> getSavedPeers() async {
    final db = await database;
    return db.query('peers', where: 'is_saved = 1', orderBy: 'display_name ASC');
  }

  Future<void> setContactSaved(String nodeId, bool isSaved) async {
    final db = await database;
    await db.update(
      'peers',
      {'is_saved': isSaved ? 1 : 0},
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
  }

  Future<void> togglePeerFavorite(String nodeId, bool isFav) async {
    final db = await database;
    await db.update(
      'peers',
      {'is_favorite': isFav ? 1 : 0},
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
  }

  Future<void> updatePeerProfile({
    required String nodeId,
    required String displayName,
    String? bio,
    String? role,
  }) async {
    final db = await database;
    final data = <String, dynamic>{
      'display_name': displayName,
    };
    if (bio != null) data['bio'] = bio;
    if (role != null) data['role'] = role;

    await db.update(
      'peers',
      data,
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );

    // Also update conversation title
    await db.update(
      'conversations',
      {'title': displayName},
      where: 'peer_id = ? AND is_group = 0',
      whereArgs: [nodeId],
    );
  }

  // ── GROUPS (GRUP OFFLINE) ─────────────────────────────────────────
  Future<void> createGroup({
    required GroupModel group,
    required List<String> memberNodeIds,
  }) async {
    final db = await database;
    await db.insert('groups', group.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    // Add members
    for (final memberId in memberNodeIds) {
      await db.insert(
        'group_members',
        {
          'group_id': group.id,
          'node_id': memberId,
          'joined_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Create group conversation
    await db.insert(
      'conversations',
      {
        'id': 'group_${group.id}',
        'group_id': group.id,
        'title': group.name,
        'is_group': 1,
        'last_message': 'Grup offline dibuat',
        'last_message_at': DateTime.now().toIso8601String(),
        'unread_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<GroupModel>> getAllGroups() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT g.*, COUNT(gm.node_id) as member_count 
      FROM groups g 
      LEFT JOIN group_members gm ON g.id = gm.group_id 
      GROUP BY g.id 
      ORDER BY g.created_at DESC
    ''');
    return rows.map(GroupModel.fromMap).toList();
  }

  Future<bool> isGroupMember(String groupId, String nodeId) async {
    final db = await database;
    final res = await db.query(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, nodeId],
    );
    return res.isNotEmpty;
  }

  Future<GroupModel?> getGroup(String groupId) async {
    final db = await database;
    final res = await db.query('groups', where: 'id = ?', whereArgs: [groupId]);
    if (res.isEmpty) return null;
    return GroupModel.fromMap(res.first);
  }

  // ── CONVERSATIONS (DAFTAR CHAT) ───────────────────────────────────
  Future<String> upsertConversation(Map<String, dynamic> conv) async {
    final db = await database;
    await db.insert('conversations', conv,
        conflictAlgorithm: ConflictAlgorithm.replace);
    return conv['id'] as String;
  }

  Future<void> updateConversationSnippet({
    required String conversationId,
    required String lastMessage,
    required String lastMessageAt,
    bool incrementUnread = false,
  }) async {
    final db = await database;
    if (incrementUnread) {
      await db.rawUpdate('''
        UPDATE conversations 
        SET last_message = ?, last_message_at = ?, unread_count = unread_count + 1 
        WHERE id = ?
      ''', [lastMessage, lastMessageAt, conversationId]);
    } else {
      await db.update(
        'conversations',
        {
          'last_message': lastMessage,
          'last_message_at': lastMessageAt,
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllConversations() async {
    final db = await database;
    return db.query('conversations', orderBy: 'last_message_at DESC');
  }

  Future<void> resetUnread(String conversationId) async {
    final db = await database;
    await db.update(
      'conversations',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    final db = await database;
    await db.delete('conversations', where: 'id = ?', whereArgs: [conversationId]);
    await db.delete('messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
  }

  // ── MESSAGES (PESAN & CENTANG DIBACA) ─────────────────────────────
  Future<void> insertMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.insert('messages', msg,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final db = await database;
    return db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<void> updateMessageStatus(String messageId, String status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Mark all received messages in conversation as READ
  Future<List<String>> markMessagesAsReadLocally(String conversationId) async {
    final db = await database;
    final unreadIncoming = await db.query(
      'messages',
      columns: ['id'],
      where: 'conversation_id = ? AND is_mine = 0 AND status != ?',
      whereArgs: [conversationId, 'READ'],
    );

    if (unreadIncoming.isEmpty) return [];

    final ids = unreadIncoming.map((r) => r['id'] as String).toList();
    await db.rawUpdate('''
      UPDATE messages 
      SET status = 'READ' 
      WHERE conversation_id = ? AND is_mine = 0
    ''', [conversationId]);

    return ids;
  }

  /// When we receive READ_ACK from peer, mark our sent messages as READ (Centang 2 Biru)
  Future<void> markSentMessagesAsRead(List<String> messageIds) async {
    final db = await database;
    for (final id in messageIds) {
      await db.update(
        'messages',
        {'status': 'READ'},
        where: 'id = ? AND is_mine = 1',
        whereArgs: [id],
      );
    }
  }

  /// When we receive DELIVERY_ACK from peer, mark our sent message as DELIVERED (Centang 2 Abu)
  Future<void> markSentMessageAsDelivered(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': 'DELIVERED'},
      where: 'id = ? AND is_mine = 1 AND status = ?',
      whereArgs: [messageId, 'SENT'],
    );
  }
}
