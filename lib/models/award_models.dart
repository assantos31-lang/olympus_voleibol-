class AwardDefinition {
  const AwardDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceType,
    required this.winnerCount,
    required this.isVisible,
    required this.sortOrder,
    this.coverImageUrl = '',
  });

  final String id;
  final String title;
  final String description;
  final String sourceType;
  final int winnerCount;
  final bool isVisible;
  final int sortOrder;
  final String coverImageUrl;

  factory AwardDefinition.fromMap(Map<String, dynamic> map) => AwardDefinition(
        id: (map['id'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        sourceType: (map['source_type'] ?? 'manual').toString(),
        winnerCount: (map['winner_count'] as num?)?.toInt() ?? 1,
        isVisible: map['is_visible'] != false,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        coverImageUrl: (map['cover_image_url'] ?? '').toString(),
      );
}

class AwardWinner {
  const AwardWinner({
    required this.id,
    required this.profileId,
    required this.name,
    required this.avatarUrl,
    required this.position,
    required this.resultLabel,
  });

  final String id;
  final String profileId;
  final String name;
  final String avatarUrl;
  final int position;
  final String resultLabel;

  factory AwardWinner.fromMap(Map<String, dynamic> map) => AwardWinner(
        id: (map['id'] ?? '').toString(),
        profileId: (map['profile_id'] ?? '').toString(),
        name: (map['winner_name'] ?? '').toString(),
        avatarUrl: (map['winner_avatar_url'] ?? '').toString(),
        position: (map['position'] as num?)?.toInt() ?? 1,
        resultLabel: (map['result_label'] ?? '').toString(),
      );
}

class AwardEdition {
  const AwardEdition({
    required this.id,
    required this.definition,
    required this.year,
    required this.month,
    required this.caption,
    required this.isPublished,
    required this.isVisible,
    required this.winners,
    this.deliveryDate,
    this.deliveryPhotoUrl = '',
  });

  final String id;
  final AwardDefinition definition;
  final int year;
  final int month;
  final String caption;
  final DateTime? deliveryDate;
  final String deliveryPhotoUrl;
  final bool isPublished;
  final bool isVisible;
  final List<AwardWinner> winners;

  DateTime get period => DateTime(year, month);
}

String awardSourceLabel(String sourceType) {
  switch (sourceType) {
    case 'checkin_ranking':
      return 'Ranking de check-ins';
    case 'training_highlight':
      return 'Destaque de treino';
    case 'monthly_evaluation':
      return 'Avaliação mensal';
    default:
      return 'Escolha manual';
  }
}

String awardPeriodKey(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';
