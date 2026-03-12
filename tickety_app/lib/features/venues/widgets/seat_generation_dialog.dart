import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/seat_data.dart';
import '../utils/seat_generator.dart';

/// Dialog for configuring and previewing seat generation.
class SeatGenerationDialog extends StatefulWidget {
  final double sectionWidth;
  final double sectionHeight;
  final ValueChanged<List<SeatRow>> onGenerate;

  const SeatGenerationDialog({
    super.key,
    required this.sectionWidth,
    required this.sectionHeight,
    required this.onGenerate,
  });

  @override
  State<SeatGenerationDialog> createState() => _SeatGenerationDialogState();
}

class _SeatGenerationDialogState extends State<SeatGenerationDialog> {
  int _rowCount = 5;
  int _seatsPerRow = 10;
  double _spacing = 1.0;
  double _curveRadius = 0;
  String _labelStart = 'A';
  bool _leftToRight = true;

  SeatGenerationParams get _params => SeatGenerationParams(
    rowCount: _rowCount,
    seatsPerRow: _seatsPerRow,
    spacing: _spacing,
    curveRadius: _curveRadius,
    labelStart: _labelStart,
    numberLeftToRight: _leftToRight,
    sectionWidth: widget.sectionWidth,
    sectionHeight: widget.sectionHeight,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalSeats = _rowCount * _seatsPerRow;

    return AlertDialog(
      title: const Text('Generate Seats'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CustomPaint(
                  painter: _SeatPreviewPainter(
                    rows: generateSeats(_params),
                    sectionWidth: widget.sectionWidth,
                    sectionHeight: widget.sectionHeight,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalSeats seats',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // Row count
              _SliderRow(
                label: 'Rows',
                value: _rowCount.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                displayValue: '$_rowCount',
                onChanged: (v) => setState(() => _rowCount = v.round()),
              ),
              // Seats per row
              _SliderRow(
                label: 'Seats/Row',
                value: _seatsPerRow.toDouble(),
                min: 1,
                max: 50,
                divisions: 49,
                displayValue: '$_seatsPerRow',
                onChanged: (v) => setState(() => _seatsPerRow = v.round()),
              ),
              // Spacing
              _SliderRow(
                label: 'Spacing',
                value: _spacing,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                displayValue: '${_spacing.toStringAsFixed(1)}x',
                onChanged: (v) => setState(() => _spacing = v),
              ),
              // Curve radius
              _SliderRow(
                label: 'Curve',
                value: _curveRadius,
                min: 0,
                max: 300,
                divisions: 30,
                displayValue: _curveRadius == 0 ? 'Flat' : '${_curveRadius.round()}',
                onChanged: (v) => setState(() => _curveRadius = v),
              ),
              const SizedBox(height: 8),
              // Label start
              Row(
                children: [
                  Text('Start Label', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'A', label: Text('A')),
                      ButtonSegment(value: '1', label: Text('1')),
                    ],
                    selected: {_labelStart == 'A' ? 'A' : '1'},
                    onSelectionChanged: (v) {
                      setState(() => _labelStart = v.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Numbering direction
              Row(
                children: [
                  Text('Direction', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('L→R')),
                      ButtonSegment(value: false, label: Text('R→L')),
                    ],
                    selected: {_leftToRight},
                    onSelectionChanged: (v) {
                      setState(() => _leftToRight = v.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onGenerate(generateSeats(_params));
            Navigator.pop(context);
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            displayValue,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _SeatPreviewPainter extends CustomPainter {
  final List<SeatRow> rows;
  final double sectionWidth;
  final double sectionHeight;
  final Color color;

  _SeatPreviewPainter({
    required this.rows,
    required this.sectionWidth,
    required this.sectionHeight,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / sectionWidth;
    final scaleY = size.height / sectionHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (size.width - sectionWidth * scale) / 2;
    final offsetY = (size.height - sectionHeight * scale) / 2;

    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    final points = <Offset>[];
    for (final row in rows) {
      for (final seat in row.seats) {
        points.add(Offset(
          offsetX + (seat.x + 8) * scale,
          offsetY + (seat.y + 8) * scale,
        ));
      }
    }

    if (points.isNotEmpty) {
      canvas.drawPoints(
        ui.PointMode.points,
        points,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SeatPreviewPainter oldDelegate) => true;
}
