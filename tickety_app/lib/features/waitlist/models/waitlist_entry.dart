/// Mode of waitlist entry.
enum WaitlistMode {
  notify('notify'),
  autoBuy('auto_buy');

  const WaitlistMode(this.value);
  final String value;

  static WaitlistMode fromString(String? value) {
    if (value == 'auto_buy') return WaitlistMode.autoBuy;
    return WaitlistMode.notify;
  }
}

/// Status of a waitlist entry.
enum WaitlistStatus {
  active('active'),
  notified('notified'),
  purchased('purchased'),
  cancelled('cancelled'),
  expired('expired'),
  failed('failed');

  const WaitlistStatus(this.value);
  final String value;

  static WaitlistStatus fromString(String? value) {
    return WaitlistStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => WaitlistStatus.active,
    );
  }
}

/// Represents a user's waitlist entry for an event.
class WaitlistEntry {
  final String id;
  final String eventId;
  final String userId;
  final WaitlistMode mode;
  final int? maxPriceCents;
  final String? paymentMethodId;
  final WaitlistStatus status;
  final DateTime createdAt;

  const WaitlistEntry({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.mode,
    this.maxPriceCents,
    this.paymentMethodId,
    required this.status,
    required this.createdAt,
  });

  factory WaitlistEntry.fromJson(Map<String, dynamic> json) {
    return WaitlistEntry(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      mode: WaitlistMode.fromString(json['mode'] as String?),
      maxPriceCents: json['max_price_cents'] as int?,
      paymentMethodId: json['payment_method_id'] as String?,
      status: WaitlistStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isActive => status == WaitlistStatus.active;
  bool get isAutoBuy => mode == WaitlistMode.autoBuy;
  bool get isNotify => mode == WaitlistMode.notify;

  String get formattedMaxPrice {
    if (maxPriceCents == null) return 'Any price';
    return '\$${(maxPriceCents! / 100).toStringAsFixed(2)}';
  }
}

/// Waitlist count info for display.
class WaitlistCount {
  final int total;
  final int notify;
  final int autoBuy;

  const WaitlistCount({
    this.total = 0,
    this.notify = 0,
    this.autoBuy = 0,
  });

  factory WaitlistCount.fromJson(Map<String, dynamic> json) {
    return WaitlistCount(
      total: json['total'] as int? ?? 0,
      notify: json['notify'] as int? ?? 0,
      autoBuy: json['auto_buy'] as int? ?? 0,
    );
  }

  bool get isEmpty => total == 0;
}
