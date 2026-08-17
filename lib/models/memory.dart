class Memory {
  final String id;
  final String userId;
  final String layoutId;
  final String backgroundVariant;
  final List<String> photos;
  final bool isDraft;
  final DateTime createdAt;

  Memory({
    required this.id,
    required this.userId,
    required this.layoutId,
    required this.backgroundVariant,
    required this.photos,
    required this.isDraft,
    required this.createdAt,
  });

  factory Memory.fromMap(Map<String, dynamic> m) => Memory(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        layoutId: m['layout_id'] as String,
        backgroundVariant: (m['background_variant'] as String?) ?? 'default',
        photos: (m['photos'] as List).map((e) => e.toString()).toList(),
        isDraft: (m['is_draft'] as bool?) ?? true,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
