/// Source of external market data.
enum MarketSource {
  ticketmaster,
  seatgeek;

  String get label => switch (this) {
    ticketmaster => 'Ticketmaster',
    seatgeek => 'SeatGeek',
  };

  static MarketSource fromDb(String value) => switch (value) {
    'ticketmaster' => ticketmaster,
    'seatgeek' => seatgeek,
    _ => throw ArgumentError('Unknown market source: $value'),
  };
}

/// A single row from `analytics_market_snapshot`.
class MarketSnapshot {
  final String tagId;
  final MarketSource source;
  final int? eventCount;
  final int? avgPriceCents;
  final int? minPriceCents;
  final int? maxPriceCents;
  final DateTime fetchedAt;
  final String? errorMessage;

  const MarketSnapshot({
    required this.tagId,
    required this.source,
    this.eventCount,
    this.avgPriceCents,
    this.minPriceCents,
    this.maxPriceCents,
    required this.fetchedAt,
    this.errorMessage,
  });

  factory MarketSnapshot.fromJson(Map<String, dynamic> json) {
    return MarketSnapshot(
      tagId: json['tag_id'] as String,
      source: MarketSource.fromDb(json['source'] as String),
      eventCount: json['event_count'] as int?,
      avgPriceCents: json['avg_price_cents'] as int?,
      minPriceCents: json['min_price_cents'] as int?,
      maxPriceCents: json['max_price_cents'] as int?,
      fetchedAt: DateTime.parse(json['fetched_at'] as String),
      errorMessage: json['error_message'] as String?,
    );
  }

  /// Whether this snapshot has valid (non-error) data.
  bool get isValid => errorMessage == null;

  /// Whether the data is older than 48 hours.
  bool get isStale =>
      DateTime.now().difference(fetchedAt).inHours > 48;

  String get formattedAvgPrice {
    if (avgPriceCents == null) return '-';
    return '\$${(avgPriceCents! / 100).toStringAsFixed(2)}';
  }

  String get formattedPriceRange {
    if (minPriceCents == null && maxPriceCents == null) return '-';
    final min = minPriceCents != null
        ? '\$${(minPriceCents! / 100).toStringAsFixed(0)}'
        : '?';
    final max = maxPriceCents != null
        ? '\$${(maxPriceCents! / 100).toStringAsFixed(0)}'
        : '?';
    return '$min - $max';
  }
}

/// Groups Ticketmaster + SeatGeek snapshots for one tag.
class MarketComparison {
  final String tagId;
  final MarketSnapshot? ticketmaster;
  final MarketSnapshot? seatgeek;

  const MarketComparison({
    required this.tagId,
    this.ticketmaster,
    this.seatgeek,
  });

  /// Total event count across both sources.
  int get totalExternalEvents =>
      (ticketmaster?.eventCount ?? 0) + (seatgeek?.eventCount ?? 0);

  /// Weighted average price (cents) across both sources.
  int? get weightedAvgPriceCents {
    final tmAvg = ticketmaster?.avgPriceCents;
    final sgAvg = seatgeek?.avgPriceCents;
    if (tmAvg == null && sgAvg == null) return null;
    if (tmAvg == null) return sgAvg;
    if (sgAvg == null) return tmAvg;
    return ((tmAvg + sgAvg) / 2).round();
  }

  String get formattedWeightedAvgPrice {
    final cents = weightedAvgPriceCents;
    if (cents == null) return '-';
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }

  /// True if at least one source has valid data.
  bool get hasData =>
      (ticketmaster?.isValid ?? false) || (seatgeek?.isValid ?? false);

  /// True if any source has stale data.
  bool get hasStaleData =>
      (ticketmaster?.isStale ?? false) || (seatgeek?.isStale ?? false);
}
