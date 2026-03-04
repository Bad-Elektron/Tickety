/// Represents a linked bank account for ACH wallet top-ups.
class LinkedBankAccount {
  final String id;
  final String stripePaymentMethodId;
  final String bankName;
  final String last4;
  final String accountType;
  final bool isDefault;
  final String status;
  final DateTime createdAt;

  const LinkedBankAccount({
    required this.id,
    required this.stripePaymentMethodId,
    required this.bankName,
    required this.last4,
    this.accountType = 'checking',
    this.isDefault = false,
    this.status = 'active',
    required this.createdAt,
  });

  factory LinkedBankAccount.fromJson(Map<String, dynamic> json) {
    return LinkedBankAccount(
      id: json['id'] as String,
      stripePaymentMethodId: json['stripe_payment_method_id'] as String,
      bankName: json['bank_name'] as String? ?? 'Bank Account',
      last4: json['last4'] as String? ?? '****',
      accountType: json['account_type'] as String? ?? 'checking',
      isDefault: json['is_default'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Display name like "Chase ****1234".
  String get displayName => '$bankName ****$last4';

  /// Whether this is a checking account.
  bool get isChecking => accountType == 'checking';

  /// Whether this account is active (not removed).
  bool get isActive => status == 'active';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkedBankAccount &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LinkedBankAccount($displayName)';
}
