/// Type of wallet pass (Apple or Google).
enum WalletPassType {
  apple('apple'),
  google('google');

  const WalletPassType(this.value);
  final String value;

  static WalletPassType fromString(String? value) {
    return WalletPassType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => WalletPassType.apple,
    );
  }
}

/// A wallet pass for a ticket (Apple Wallet or Google Wallet).
class WalletPass {
  final String id;
  final String ticketId;
  final WalletPassType passType;
  final String? passUrl;
  final String? appleSerial;
  final String? googleObjectId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WalletPass({
    required this.id,
    required this.ticketId,
    required this.passType,
    this.passUrl,
    this.appleSerial,
    this.googleObjectId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WalletPass.fromJson(Map<String, dynamic> json) {
    return WalletPass(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      passType: WalletPassType.fromString(json['pass_type'] as String?),
      passUrl: json['pass_url'] as String?,
      appleSerial: json['apple_serial'] as String?,
      googleObjectId: json['google_object_id'] as String?,
      status: json['status'] as String? ?? 'created',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isDelivered => status == 'delivered' || status == 'updated';
  bool get isApple => passType == WalletPassType.apple;
  bool get isGoogle => passType == WalletPassType.google;
}
