import '../../../core/state/app_state.dart';

/// Status of a subscription.
enum SubscriptionStatus {
  active,
  canceled,
  pastDue,
  trialing,
  paused,
  incomplete;

  /// Parse status from database string.
  static SubscriptionStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return SubscriptionStatus.active;
      case 'canceled':
        return SubscriptionStatus.canceled;
      case 'past_due':
        return SubscriptionStatus.pastDue;
      case 'trialing':
        return SubscriptionStatus.trialing;
      case 'paused':
        return SubscriptionStatus.paused;
      case 'incomplete':
        return SubscriptionStatus.incomplete;
      default:
        return SubscriptionStatus.incomplete; // Default to incomplete, not active
    }
  }

  /// Convert to database string.
  String toDbString() {
    switch (this) {
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.canceled:
        return 'canceled';
      case SubscriptionStatus.pastDue:
        return 'past_due';
      case SubscriptionStatus.trialing:
        return 'trialing';
      case SubscriptionStatus.paused:
        return 'paused';
      case SubscriptionStatus.incomplete:
        return 'incomplete';
    }
  }

  /// Whether this status grants access to features.
  bool get grantsAccess =>
      this == SubscriptionStatus.active || this == SubscriptionStatus.trialing;

  /// User-friendly label.
  String get label {
    switch (this) {
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.canceled:
        return 'Canceled';
      case SubscriptionStatus.pastDue:
        return 'Past Due';
      case SubscriptionStatus.trialing:
        return 'Trial';
      case SubscriptionStatus.paused:
        return 'Paused';
      case SubscriptionStatus.incomplete:
        return 'Incomplete';
    }
  }
}

/// User subscription data.
class Subscription {
  final String id;
  final String userId;
  final AccountTier tier;
  final SubscriptionStatus status;
  final String? stripeSubscriptionId;
  final String? stripePriceId;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Subscription({
    required this.id,
    required this.userId,
    required this.tier,
    required this.status,
    this.stripeSubscriptionId,
    this.stripePriceId,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create from JSON (database row).
  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      tier: _parseTier(json['tier'] as String?),
      status: SubscriptionStatus.fromString(json['status'] as String? ?? 'active'),
      stripeSubscriptionId: json['stripe_subscription_id'] as String?,
      stripePriceId: json['stripe_price_id'] as String?,
      currentPeriodStart: json['current_period_start'] != null
          ? DateTime.parse(json['current_period_start'] as String)
          : null,
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.parse(json['current_period_end'] as String)
          : null,
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for database.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'tier': tier.name,
      'status': status.toDbString(),
      'stripe_subscription_id': stripeSubscriptionId,
      'stripe_price_id': stripePriceId,
      'current_period_start': currentPeriodStart?.toIso8601String(),
      'current_period_end': currentPeriodEnd?.toIso8601String(),
      'cancel_at_period_end': cancelAtPeriodEnd,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields.
  Subscription copyWith({
    String? id,
    String? userId,
    AccountTier? tier,
    SubscriptionStatus? status,
    String? stripeSubscriptionId,
    String? stripePriceId,
    DateTime? currentPeriodStart,
    DateTime? currentPeriodEnd,
    bool? cancelAtPeriodEnd,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Subscription(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      tier: tier ?? this.tier,
      status: status ?? this.status,
      stripeSubscriptionId: stripeSubscriptionId ?? this.stripeSubscriptionId,
      stripePriceId: stripePriceId ?? this.stripePriceId,
      currentPeriodStart: currentPeriodStart ?? this.currentPeriodStart,
      currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
      cancelAtPeriodEnd: cancelAtPeriodEnd ?? this.cancelAtPeriodEnd,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if user has access to the specified tier level.
  ///
  /// Returns true if the user's current tier is >= the required tier
  /// and the subscription status grants access.
  bool hasAccess(AccountTier requiredTier) {
    if (!status.grantsAccess) {
      return false;
    }

    final currentIndex = AccountTier.values.indexOf(tier);
    final requiredIndex = AccountTier.values.indexOf(requiredTier);
    return currentIndex >= requiredIndex;
  }

  /// Days remaining until subscription ends.
  /// Returns null if no end date or if subscription is not time-limited.
  int? get daysRemaining {
    if (currentPeriodEnd == null) return null;
    final now = DateTime.now();
    if (currentPeriodEnd!.isBefore(now)) return 0;
    return currentPeriodEnd!.difference(now).inDays;
  }

  /// Whether this is a paid subscription.
  bool get isPaid => tier != AccountTier.base;

  /// Whether the subscription is actively granting access.
  bool get isActive => status.grantsAccess;

  /// Whether the subscription will renew.
  bool get willRenew => isActive && !cancelAtPeriodEnd;

  static AccountTier _parseTier(String? value) {
    switch (value?.toLowerCase()) {
      case 'pro':
        return AccountTier.pro;
      case 'enterprise':
        return AccountTier.enterprise;
      case 'base':
      default:
        return AccountTier.base;
    }
  }

  @override
  String toString() => 'Subscription(tier: $tier, status: $status)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Subscription &&
        other.id == id &&
        other.tier == tier &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(id, tier, status);
}

/// Response from creating a subscription checkout session.
///
/// When [isDirectUpdate] is true, the subscription was changed directly
/// (no payment sheet needed). The client should just refresh.
class SubscriptionCheckoutResponse {
  /// Whether this was a direct tier change (no payment needed).
  final bool isDirectUpdate;
  final String? clientSecret;
  final String? customerId;
  final String? ephemeralKey;
  final String? subscriptionId;

  const SubscriptionCheckoutResponse({
    this.isDirectUpdate = false,
    this.clientSecret,
    this.customerId,
    this.ephemeralKey,
    this.subscriptionId,
  });

  factory SubscriptionCheckoutResponse.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;

    if (type == 'updated') {
      return const SubscriptionCheckoutResponse(isDirectUpdate: true);
    }

    return SubscriptionCheckoutResponse(
      clientSecret: json['client_secret'] as String,
      customerId: json['customer_id'] as String,
      ephemeralKey: json['ephemeral_key'] as String,
      subscriptionId: json['subscription_id'] as String?,
    );
  }
}

/// Response containing Stripe customer portal URL.
class CustomerPortalResponse {
  final String url;

  const CustomerPortalResponse({required this.url});

  factory CustomerPortalResponse.fromJson(Map<String, dynamic> json) {
    return CustomerPortalResponse(
      url: json['url'] as String,
    );
  }
}
