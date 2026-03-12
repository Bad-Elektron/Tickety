/// Status of an individual seat.
enum SeatStatus {
  available,
  blocked,
  accessible;

  static SeatStatus fromString(String? value) {
    return SeatStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SeatStatus.available,
    );
  }
}

/// A single seat within a row.
class SeatData {
  final String id;
  final int number;
  final double x;
  final double y;
  final SeatStatus status;

  const SeatData({
    required this.id,
    required this.number,
    required this.x,
    required this.y,
    this.status = SeatStatus.available,
  });

  SeatData copyWith({
    String? id,
    int? number,
    double? x,
    double? y,
    SeatStatus? status,
  }) {
    return SeatData(
      id: id ?? this.id,
      number: number ?? this.number,
      x: x ?? this.x,
      y: y ?? this.y,
      status: status ?? this.status,
    );
  }

  factory SeatData.fromJson(Map<String, dynamic> json) {
    return SeatData(
      id: json['id'] as String,
      number: json['number'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      status: SeatStatus.fromString(json['status'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'x': x,
      'y': y,
      'status': status.name,
    };
  }
}

/// A row of seats within a section.
class SeatRow {
  final String id;
  final String label;
  final List<SeatData> seats;
  final double curveRadius;
  final double spacing;

  const SeatRow({
    required this.id,
    required this.label,
    required this.seats,
    this.curveRadius = 0,
    this.spacing = 1.0,
  });

  int get seatCount => seats.length;

  SeatRow copyWith({
    String? id,
    String? label,
    List<SeatData>? seats,
    double? curveRadius,
    double? spacing,
  }) {
    return SeatRow(
      id: id ?? this.id,
      label: label ?? this.label,
      seats: seats ?? this.seats,
      curveRadius: curveRadius ?? this.curveRadius,
      spacing: spacing ?? this.spacing,
    );
  }

  factory SeatRow.fromJson(Map<String, dynamic> json) {
    final seatsList = json['seats'] as List<dynamic>? ?? [];
    return SeatRow(
      id: json['id'] as String,
      label: json['label'] as String,
      seats: seatsList
          .map((s) => SeatData.fromJson(s as Map<String, dynamic>))
          .toList(),
      curveRadius: (json['curveRadius'] as num?)?.toDouble() ?? 0,
      spacing: (json['spacing'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'seats': seats.map((s) => s.toJson()).toList(),
      'curveRadius': curveRadius,
      'spacing': spacing,
    };
  }
}
