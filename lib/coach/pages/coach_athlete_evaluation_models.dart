class AthleteEvaluationStatus {
  AthleteEvaluationStatus({
    required this.athleteId,
    required this.athleteName,
    required this.avatarUrl,
    required this.gender,
    required this.generalEvolution,
    required this.mainFocus,
    required this.evaluationsSinceLastFull,
    required this.isPresent,
    required this.totalEvaluations,
    required this.destaques,
    required this.atencoes,
    required this.hasMonthlyComplete,
    required this.lastEvaluationAt,
  });

  final String athleteId;
  final String athleteName;
  final String avatarUrl;
  final String gender;
  final String generalEvolution;
  final String mainFocus;
  final int evaluationsSinceLastFull;
  final bool isPresent;
  final int totalEvaluations;
  final int destaques;
  final int atencoes;
  final bool hasMonthlyComplete;
  final DateTime? lastEvaluationAt;

  String get lastEvaluationLabel {
    if (lastEvaluationAt == null) return 'Sem avaliação registrada';
    final d = lastEvaluationAt!.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool get requiresCompleteEvaluation => evaluationsSinceLastFull >= 2;

  AthleteEvaluationStatus copyWith({
    String? athleteId,
    String? athleteName,
    String? avatarUrl,
    String? gender,
    String? generalEvolution,
    String? mainFocus,
    int? evaluationsSinceLastFull,
    bool? isPresent,
    int? totalEvaluations,
    int? destaques,
    int? atencoes,
    bool? hasMonthlyComplete,
    DateTime? lastEvaluationAt,
  }) {
    return AthleteEvaluationStatus(
      athleteId: athleteId ?? this.athleteId,
      athleteName: athleteName ?? this.athleteName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      generalEvolution: generalEvolution ?? this.generalEvolution,
      mainFocus: mainFocus ?? this.mainFocus,
      evaluationsSinceLastFull:
          evaluationsSinceLastFull ?? this.evaluationsSinceLastFull,
      isPresent: isPresent ?? this.isPresent,
      totalEvaluations: totalEvaluations ?? this.totalEvaluations,
      destaques: destaques ?? this.destaques,
      atencoes: atencoes ?? this.atencoes,
      hasMonthlyComplete: hasMonthlyComplete ?? this.hasMonthlyComplete,
      lastEvaluationAt: lastEvaluationAt ?? this.lastEvaluationAt,
    );
  }
}
