class GroupModel {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final String createdBy;
  final int memberCount;

  const GroupModel({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.createdBy,
    this.memberCount = 1,
  });

  factory GroupModel.fromMap(Map<String, dynamic> map) => GroupModel(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        createdBy: map['created_by'] as String? ?? 'me',
        memberCount: map['member_count'] as int? ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.toIso8601String(),
        'created_by': createdBy,
      };
}

