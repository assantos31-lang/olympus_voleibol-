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
    this.customSourceLabel = '',
  });

  final String id;
  final String title;
  final String description;
  final String sourceType;
  final int winnerCount;
  final bool isVisible;
  final int sortOrder;
  final String coverImageUrl;
  final String customSourceLabel;

  String get sourceLabel =>
      sourceType == 'manual' && customSourceLabel.trim().isNotEmpty
          ? customSourceLabel.trim()
          : awardSourceLabel(sourceType);

  factory AwardDefinition.fromMap(Map<String, dynamic> map) => AwardDefinition(
        id: (map['id'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        sourceType: (map['source_type'] ?? 'manual').toString(),
        winnerCount: (map['winner_count'] as num?)?.toInt() ?? 1,
        isVisible: map['is_visible'] != false,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        coverImageUrl: (map['cover_image_url'] ?? '').toString(),
        customSourceLabel: (map['custom_source_label'] ?? '').toString(),
      );
}

AwardDefinition resolveAwardDefinitionById({
  required List<AwardDefinition> definitions,
  AwardDefinition? preferred,
}) {
  if (definitions.isEmpty) {
    throw StateError('Nenhum tipo de premiação disponível.');
  }
  if (preferred == null) return definitions.first;
  return definitions.firstWhere(
    (item) => item.id == preferred.id,
    orElse: () => definitions.first,
  );
}

String awardAlphabeticalKey(String value) {
  const accents = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const plain = 'aaaaaeeeeiiiiooooouuuuc';
  var normalized = value.trim().toLowerCase();
  for (var index = 0; index < accents.length; index++) {
    normalized = normalized.replaceAll(accents[index], plain[index]);
  }
  return normalized;
}

List<Map<String, dynamic>> sortAwardProfilesAlphabetically(
  Iterable<Map<String, dynamic>> profiles,
) {
  final ordered =
      profiles.map((profile) => Map<String, dynamic>.from(profile)).toList();
  ordered.sort((a, b) {
    final byName = awardAlphabeticalKey(
      (a['full_name'] ?? '').toString(),
    ).compareTo(
      awardAlphabeticalKey((b['full_name'] ?? '').toString()),
    );
    if (byName != 0) return byName;
    return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
  });
  return ordered;
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

class AwardImage {
  const AwardImage({
    required this.id,
    required this.url,
    required this.sortOrder,
    required this.isCover,
  });

  final String id;
  final String url;
  final int sortOrder;
  final bool isCover;

  factory AwardImage.fromMap(Map<String, dynamic> map) => AwardImage(
        id: (map['id'] ?? '').toString(),
        url: (map['image_url'] ?? '').toString(),
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        isCover: map['is_cover'] == true,
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
    this.images = const [],
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
  final List<AwardImage> images;

  List<String> get galleryImageUrls {
    final ordered = [...images]..sort((a, b) {
        if (a.isCover != b.isCover) return a.isCover ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final urls = <String>[];
    for (final image in ordered) {
      if (image.url.isNotEmpty && !urls.contains(image.url)) {
        urls.add(image.url);
      }
    }
    if (deliveryPhotoUrl.isNotEmpty && !urls.contains(deliveryPhotoUrl)) {
      urls.insert(0, deliveryPhotoUrl);
    }
    if (urls.isEmpty && definition.coverImageUrl.isNotEmpty) {
      urls.add(definition.coverImageUrl);
    }
    return urls;
  }

  String get primaryImageUrl => galleryImageUrls.firstOrNull ?? '';

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
