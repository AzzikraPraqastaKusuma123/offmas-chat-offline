class PeerModel {
  final String nodeId;
  final String displayName;
  final String bio;
  final String role;
  final String lastSeen;
  final bool isSaved;
  final bool isVerified;
  final bool isFavorite;

  const PeerModel({
    required this.nodeId,
    required this.displayName,
    this.bio = 'Siaga Offline',
    this.role = 'Umum',
    required this.lastSeen,
    this.isSaved = false,
    this.isVerified = false,
    this.isFavorite = false,
  });

  factory PeerModel.fromMap(Map<String, dynamic> map) => PeerModel(
        nodeId: map['node_id'] as String,
        displayName: map['display_name'] as String,
        bio: map['bio'] as String? ?? 'Siaga Offline',
        role: map['role'] as String? ?? 'Umum',
        lastSeen: map['last_seen'] as String,
        isSaved: (map['is_saved'] as int? ?? 0) == 1,
        isVerified: (map['is_verified'] as int? ?? 0) == 1,
        isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        'node_id': nodeId,
        'display_name': displayName,
        'bio': bio,
        'role': role,
        'last_seen': lastSeen,
        'is_saved': isSaved ? 1 : 0,
        'is_verified': isVerified ? 1 : 0,
        'is_favorite': isFavorite ? 1 : 0,
      };
}
