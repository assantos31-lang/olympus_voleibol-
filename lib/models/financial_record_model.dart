class FinancialRecord {
  final String id;
  final String athleteId;
  final String type;
  final String? description;
  final double value;
  final int day; // ADICIONADO
  final int month;
  final int year;
  final String? receiptUrl;
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;

  FinancialRecord({
    required this.id,
    required this.athleteId,
    required this.type,
    this.description,
    required this.value,
    required this.day, // ADICIONADO
    required this.month,
    required this.year,
    this.receiptUrl,
    this.status = 'pending',
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
  });

  factory FinancialRecord.fromMap(Map<String, dynamic> map) {
    return FinancialRecord(
      id: map['id'],
      athleteId: map['athlete_id'],
      type: map['type'],
      description: map['description'],
      value: double.parse(map['value'].toString()),
      day: map['day'] ?? DateTime.now().day, // ADICIONADO
      month: map['month'],
      year: map['year'],
      receiptUrl: map['receipt_url'],
      status: map['status'] ?? 'pending',
      approvedBy: map['approved_by'],
      approvedAt: map['approved_at'] != null
          ? DateTime.parse(map['approved_at'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'athlete_id': athleteId,
      'type': type,
      'description': description,
      'value': value,
      'day': day, // ADICIONADO
      'month': month,
      'year': year,
      'receipt_url': receiptUrl,
      'status': status,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get typeLabel {
    switch (type) {
      case 'monthly':
        return 'Mensalidade';
      case 'games':
        return 'Jogos';
      case 'maintenance':
        return 'Manutenção';
      case 'other':
        return 'Outros';
      default:
        return type;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'approved':
        return 'Aprovado';
      case 'rejected':
        return 'Rejeitado';
      default:
        return status;
    }
  }
}
