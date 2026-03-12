import 'element_shape.dart';
import 'seat_data.dart';
import 'table_config.dart';

/// Type of a venue section.
enum SectionType {
  seated,
  standing,
  table;

  static SectionType fromString(String? value) {
    return SectionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SectionType.seated,
    );
  }

  String get label => switch (this) {
    SectionType.seated => 'Seated',
    SectionType.standing => 'Standing',
    SectionType.table => 'Tables',
  };
}

/// A bookable section of the venue (seats, standing area, or tables).
class VenueSection {
  final String id;
  final String name;
  final SectionType type;
  final ElementShape shape;
  final String color;
  final String? pricingTier;
  final int capacity;
  final List<SeatRow> rows;
  final TableConfig? tableConfig;

  const VenueSection({
    required this.id,
    required this.name,
    required this.type,
    required this.shape,
    this.color = '#6366F1',
    this.pricingTier,
    this.capacity = 0,
    this.rows = const [],
    this.tableConfig,
  });

  /// Computed seat count from rows, table config, or explicit capacity.
  int get seatCount {
    if (type == SectionType.seated && rows.isNotEmpty) {
      return rows.fold(0, (sum, row) => sum + row.seatCount);
    }
    if (type == SectionType.table && tableConfig != null) {
      return tableConfig!.totalSeats;
    }
    return capacity;
  }

  VenueSection copyWith({
    String? id,
    String? name,
    SectionType? type,
    ElementShape? shape,
    String? color,
    String? pricingTier,
    int? capacity,
    List<SeatRow>? rows,
    TableConfig? tableConfig,
  }) {
    return VenueSection(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      shape: shape ?? this.shape,
      color: color ?? this.color,
      pricingTier: pricingTier ?? this.pricingTier,
      capacity: capacity ?? this.capacity,
      rows: rows ?? this.rows,
      tableConfig: tableConfig ?? this.tableConfig,
    );
  }

  factory VenueSection.fromJson(Map<String, dynamic> json) {
    final rowsList = json['rows'] as List<dynamic>? ?? [];
    return VenueSection(
      id: json['id'] as String,
      name: json['name'] as String,
      type: SectionType.fromString(json['type'] as String?),
      shape: ElementShape.fromJson(json['shape'] as Map<String, dynamic>),
      color: json['color'] as String? ?? '#6366F1',
      pricingTier: json['pricingTier'] as String?,
      capacity: json['capacity'] as int? ?? 0,
      rows: rowsList
          .map((r) => SeatRow.fromJson(r as Map<String, dynamic>))
          .toList(),
      tableConfig: json['tableConfig'] != null
          ? TableConfig.fromJson(json['tableConfig'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'shape': shape.toJson(),
      'color': color,
      if (pricingTier != null) 'pricingTier': pricingTier,
      'capacity': capacity,
      if (rows.isNotEmpty) 'rows': rows.map((r) => r.toJson()).toList(),
      if (tableConfig != null) 'tableConfig': tableConfig!.toJson(),
    };
  }
}
