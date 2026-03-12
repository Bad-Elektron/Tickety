/// A seat selection made during checkout.
class SeatSelection {
  final String sectionId;
  final String seatId;
  final String seatLabel;
  final String sectionName;
  final String rowLabel;
  final int seatNumber;

  const SeatSelection({
    required this.sectionId,
    required this.seatId,
    required this.seatLabel,
    required this.sectionName,
    required this.rowLabel,
    required this.seatNumber,
  });

  Map<String, dynamic> toJson() => {
    'section_id': sectionId,
    'seat_id': seatId,
    'seat_label': seatLabel,
    'section_name': sectionName,
    'row_label': rowLabel,
    'seat_number': seatNumber,
  };

  factory SeatSelection.fromJson(Map<String, dynamic> json) {
    return SeatSelection(
      sectionId: json['section_id'] as String,
      seatId: json['seat_id'] as String,
      seatLabel: json['seat_label'] as String,
      sectionName: json['section_name'] as String,
      rowLabel: json['row_label'] as String,
      seatNumber: json['seat_number'] as int,
    );
  }

  @override
  String toString() => seatLabel;
}
