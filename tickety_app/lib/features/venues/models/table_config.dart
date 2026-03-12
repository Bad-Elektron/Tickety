/// Shape of a table section.
enum TableShape {
  round,
  rectangular;

  static TableShape fromString(String? value) {
    return TableShape.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TableShape.round,
    );
  }
}

/// Configuration for table-type sections.
class TableConfig {
  final TableShape shape;
  final int seatsPerTable;
  final int tableCount;

  const TableConfig({
    this.shape = TableShape.round,
    this.seatsPerTable = 8,
    this.tableCount = 10,
  });

  int get totalSeats => seatsPerTable * tableCount;

  TableConfig copyWith({
    TableShape? shape,
    int? seatsPerTable,
    int? tableCount,
  }) {
    return TableConfig(
      shape: shape ?? this.shape,
      seatsPerTable: seatsPerTable ?? this.seatsPerTable,
      tableCount: tableCount ?? this.tableCount,
    );
  }

  factory TableConfig.fromJson(Map<String, dynamic> json) {
    return TableConfig(
      shape: TableShape.fromString(json['shape'] as String?),
      seatsPerTable: json['seatsPerTable'] as int? ?? 8,
      tableCount: json['tableCount'] as int? ?? 10,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shape': shape.name,
      'seatsPerTable': seatsPerTable,
      'tableCount': tableCount,
    };
  }
}
