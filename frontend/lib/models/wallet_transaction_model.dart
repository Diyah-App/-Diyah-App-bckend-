class WalletTransaction {
  final int? id;
  final int memberId;
  final String? memberName;
  final int? diyahId;
  final String? diyahTitle;
  final double amount;
  final String transactionType; // 'diyah_share', 'cash_payment', 'admin_adjustment'
  final String? description;
  final DateTime createdAt;

  WalletTransaction({
    this.id,
    required this.memberId,
    this.memberName,
    this.diyahId,
    this.diyahTitle,
    required this.amount,
    required this.transactionType,
    this.description,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'],
      memberId: json['member_id'] ?? 0,
      memberName: json['member_name'],
      diyahId: json['diyah_id'],
      diyahTitle: json['diyah_title'],
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      transactionType: json['transaction_type'] ?? '',
      description: json['description'],
      createdAt: json['created_at'] != null ? (DateTime.tryParse(json['created_at']) ?? DateTime.now()) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'diyah_id': diyahId,
      'amount': amount,
      'transaction_type': transactionType,
      'description': description,
    };
  }
}
