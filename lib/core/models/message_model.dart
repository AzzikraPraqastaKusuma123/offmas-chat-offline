class MessageModel {
  final String id;
  final String conversationId;
  final String senderNodeId;
  final String senderName;
  final String content;
  final String messageType; // TEXT, GROUP_CHAT, SOS
  final DateTime timestamp;
  final String status;       // SENT, DELIVERED, READ
  final int hopCount;
  final bool isMine;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderNodeId,
    this.senderName = 'Saya',
    required this.content,
    this.messageType = 'TEXT',
    required this.timestamp,
    this.status = 'SENT',
    this.hopCount = 0,
    this.isMine = false,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) => MessageModel(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String,
        senderNodeId: map['sender_node_id'] as String,
        senderName: map['sender_name'] as String? ?? 'Kontak',
        content: map['content'] as String,
        messageType: map['message_type'] as String? ?? 'TEXT',
        timestamp: DateTime.parse(map['timestamp'] as String),
        status: map['status'] as String? ?? 'SENT',
        hopCount: map['hop_count'] as int? ?? 0,
        isMine: (map['is_mine'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_node_id': senderNodeId,
        'sender_name': senderName,
        'content': content,
        'message_type': messageType,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'hop_count': hopCount,
        'is_mine': isMine ? 1 : 0,
      };
}
