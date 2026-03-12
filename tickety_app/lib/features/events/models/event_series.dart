/// Recurrence frequency for event series.
enum RecurrenceType {
  daily('daily'),
  weekly('weekly'),
  biweekly('biweekly'),
  monthly('monthly');

  const RecurrenceType(this.value);
  final String value;

  static RecurrenceType? fromString(String? value) {
    if (value == null) return null;
    return RecurrenceType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => RecurrenceType.weekly,
    );
  }

  String get label => switch (this) {
        RecurrenceType.daily => 'Daily',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.biweekly => 'Every 2 weeks',
        RecurrenceType.monthly => 'Monthly',
      };

  String get shortLabel => switch (this) {
        RecurrenceType.daily => 'Daily',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.biweekly => 'Biweekly',
        RecurrenceType.monthly => 'Monthly',
      };
}

/// Represents a recurring event series.
class EventSeries {
  final String id;
  final String organizerId;
  final RecurrenceType recurrenceType;
  final int? recurrenceDay;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int? maxOccurrences;
  final Map<String, dynamic> templateSnapshot;
  final List<Map<String, dynamic>>? ticketTypesSnapshot;
  final bool isActive;
  final DateTime createdAt;

  const EventSeries({
    required this.id,
    required this.organizerId,
    required this.recurrenceType,
    this.recurrenceDay,
    required this.startsAt,
    this.endsAt,
    this.maxOccurrences,
    required this.templateSnapshot,
    this.ticketTypesSnapshot,
    this.isActive = true,
    required this.createdAt,
  });

  factory EventSeries.fromJson(Map<String, dynamic> json) {
    return EventSeries(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      recurrenceType: RecurrenceType.fromString(json['recurrence_type'] as String?) ?? RecurrenceType.weekly,
      recurrenceDay: json['recurrence_day'] as int?,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: json['ends_at'] != null ? DateTime.parse(json['ends_at'] as String) : null,
      maxOccurrences: json['max_occurrences'] as int?,
      templateSnapshot: (json['template_snapshot'] as Map<String, dynamic>?) ?? {},
      ticketTypesSnapshot: (json['ticket_types_snapshot'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get frequencyLabel => recurrenceType.label;
}

/// Lightweight representation of a series occurrence for the "all dates" list.
class SeriesOccurrence {
  final String id;
  final String title;
  final DateTime date;
  final int? occurrenceIndex;
  final bool seriesEdited;
  final String status;

  const SeriesOccurrence({
    required this.id,
    required this.title,
    required this.date,
    this.occurrenceIndex,
    this.seriesEdited = false,
    this.status = 'active',
  });

  factory SeriesOccurrence.fromJson(Map<String, dynamic> json) {
    return SeriesOccurrence(
      id: json['id'] as String,
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
      occurrenceIndex: json['occurrence_index'] as int?,
      seriesEdited: json['series_edited'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
    );
  }

  bool get isFuture => date.isAfter(DateTime.now());
  bool get isPast => date.isBefore(DateTime.now());
}
