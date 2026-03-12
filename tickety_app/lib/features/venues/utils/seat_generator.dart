import 'dart:math';

import '../models/seat_data.dart';

/// Parameters for generating seats within a section.
class SeatGenerationParams {
  final int rowCount;
  final int seatsPerRow;
  final double spacing;
  final double curveRadius;
  final String labelStart;
  final bool numberLeftToRight;
  final double sectionWidth;
  final double sectionHeight;

  const SeatGenerationParams({
    this.rowCount = 5,
    this.seatsPerRow = 10,
    this.spacing = 1.0,
    this.curveRadius = 0,
    this.labelStart = 'A',
    this.numberLeftToRight = true,
    this.sectionWidth = 200,
    this.sectionHeight = 150,
  });
}

/// Generates positioned seat rows from parameters.
List<SeatRow> generateSeats(SeatGenerationParams params) {
  final rows = <SeatRow>[];
  final seatSize = 16.0 * params.spacing;
  final totalRowHeight = params.rowCount * seatSize;
  final totalRowWidth = params.seatsPerRow * seatSize;

  // Center seats within section bounds
  final startY = (params.sectionHeight - totalRowHeight) / 2;
  final startX = (params.sectionWidth - totalRowWidth) / 2;

  for (var r = 0; r < params.rowCount; r++) {
    final rowLabel = String.fromCharCode(
      params.labelStart.codeUnitAt(0) + r,
    );
    final rowId = 'row_${rowLabel.toLowerCase()}';
    final seats = <SeatData>[];

    for (var s = 0; s < params.seatsPerRow; s++) {
      final seatNum = params.numberLeftToRight ? s + 1 : params.seatsPerRow - s;

      double x, y;
      if (params.curveRadius > 0) {
        // Arc layout
        final angle = pi * (0.2 + 0.6 * s / (params.seatsPerRow - 1).clamp(1, 999));
        x = params.sectionWidth / 2 + (params.curveRadius + r * seatSize) * cos(angle) - seatSize / 2;
        y = params.sectionHeight - (params.curveRadius + r * seatSize) * sin(angle) - seatSize / 2;
      } else {
        // Grid layout
        x = startX + s * seatSize;
        y = startY + r * seatSize;
      }

      seats.add(SeatData(
        id: '${rowId}_s$seatNum',
        number: seatNum,
        x: x,
        y: y,
      ));
    }

    rows.add(SeatRow(
      id: rowId,
      label: rowLabel,
      seats: seats,
      curveRadius: params.curveRadius,
      spacing: params.spacing,
    ));
  }

  return rows;
}
