class ConversationModel {
  final String id;
  final String? peerId;
  final String title;
  final bool isGroup;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const ConversationModel({
    required this.id,
    this.peerId,
    required this.title,
    this.isGroup = false,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory ConversationModel.fromMap(Map<String, dynamic> map) =>
      ConversationModel(
        id: map['id'] as String,
        peerId: map['peer_id'] as String?,
        title: map['title'] as String,
        isGroup: (map['is_group'] as int? ?? 0) == 1,
        lastMessage: map['last_message'] as String?,
        lastMessageAt: map['last_message_at'] != null
            ? DateTime.tryParse(map['last_message_at'] as String)
            : null,
        unreadCount: map['unread_count'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'peer_id': peerId,
        'title': title,
        'is_group': isGroup ? 1 : 0,
        'last_message': lastMessage,
        'last_message_at': lastMessageAt?.toIso8601String(),
        'unread_count': unreadCount,
      };
}
