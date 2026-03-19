import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../events/models/ticket_type.dart';
import '../models/models.dart';
import '../widgets/venue_mini_map.dart';

/// Full-screen seat picker for checkout.
///
/// Phase A: Shows VenueMiniMap, user taps a seated section.
/// Phase B: Shows seat grid for selected section, user selects seats.
/// Returns `List<SeatSelection>` via Navigator.pop.
class SeatPickerScreen extends ConsumerStatefulWidget {
  final String eventId;
  final Venue venue;
  final List<TicketType>? ticketTypes;

  /// Map of sectionId → max seats the user can pick (based on quantity).
  final Map<String, int> sectionQuantities;

  /// If provided, skip the map phase and go straight to this section.
  final String? initialSectionId;

  const SeatPickerScreen({
    super.key,
    required this.eventId,
    required this.venue,
    required this.sectionQuantities,
    this.ticketTypes,
    this.initialSectionId,
  });

  @override
  ConsumerState<SeatPickerScreen> createState() => _SeatPickerScreenState();
}

class _SeatPickerScreenState extends ConsumerState<SeatPickerScreen> {
  VenueSection? _selectedSection;
  Set<String> _unavailableSeats = {};
  bool _loadingSeats = false;
  bool _skipMapPhase = false;

  @override
  void initState() {
    super.initState();
    // Auto-select section if specified or only one section needs seats
    final needing = _sectionsNeedingSelectionIds;
    String? autoSelectId = widget.initialSectionId;
    if (autoSelectId == null && needing.length == 1) {
      autoSelectId = needing.first;
    }
    if (autoSelectId != null) {
      final section = widget.venue.layout.sections
          .where((s) => s.id == autoSelectId)
          .firstOrNull;
      if (section != null) {
        _skipMapPhase = true;
        Future.microtask(() => _selectSection(section));
      }
    }
  }

  Set<String> get _sectionsNeedingSelectionIds {
    return widget.sectionQuantities.entries
        .where((e) => e.value > 0)
        .where((e) {
          final section = widget.venue.layout.sections
              .where((s) => s.id == e.key)
              .firstOrNull;
          return section != null && section.type == SectionType.seated && section.rows.isNotEmpty;
        })
        .map((e) => e.key)
        .toSet();
  }

  /// Selected seats keyed by sectionId → Set<seatId>.
  final Map<String, Set<String>> _selectedSeats = {};

  /// SeatData lookup: seatId → SeatData.
  final Map<String, SeatData> _seatDataMap = {};

  /// SeatRow lookup: seatId → SeatRow.
  final Map<String, SeatRow> _seatRowMap = {};

  List<SeatSelection> get _allSelections {
    final selections = <SeatSelection>[];
    for (final entry in _selectedSeats.entries) {
      final sectionId = entry.key;
      final section = widget.venue.layout.sections
          .where((s) => s.id == sectionId)
          .firstOrNull;
      if (section == null) continue;

      for (final seatId in entry.value) {
        final seatData = _seatDataMap[seatId];
        final row = _seatRowMap[seatId];
        if (seatData == null || row == null) continue;

        selections.add(SeatSelection(
          sectionId: sectionId,
          seatId: seatId,
          seatLabel: '${section.name} · Row ${row.label} · Seat ${seatData.number}',
          sectionName: section.name,
          rowLabel: row.label,
          seatNumber: seatData.number,
        ));
      }
    }
    return selections;
  }

  int get _totalSelected =>
      _selectedSeats.values.fold(0, (sum, s) => sum + s.length);

  int get _totalNeeded =>
      widget.sectionQuantities.values.fold(0, (sum, q) => sum + q);

  bool get _allSectionsFilled {
    for (final entry in widget.sectionQuantities.entries) {
      final selected = _selectedSeats[entry.key]?.length ?? 0;
      if (selected < entry.value) return false;
    }
    return true;
  }

  Set<String> get _sectionsNeedingSelection => _sectionsNeedingSelectionIds;

  Future<void> _selectSection(VenueSection section) async {
    if (section.type != SectionType.seated || section.rows.isEmpty) return;
    if (!widget.sectionQuantities.containsKey(section.id)) return;

    setState(() {
      _selectedSection = section;
      _loadingSeats = true;
    });

    // Build lookup maps
    _seatDataMap.clear();
    _seatRowMap.clear();
    for (final row in section.rows) {
      for (final seat in row.seats) {
        _seatDataMap[seat.id] = seat;
        _seatRowMap[seat.id] = row;
      }
    }

    // Fetch unavailable seats
    try {
      final repo = ref.read(venueRepositoryProvider);
      final unavailable = await repo.getUnavailableSeats(
        widget.eventId,
        section.id,
      );
      if (mounted) {
        setState(() {
          _unavailableSeats = unavailable;
          _loadingSeats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unavailableSeats = {};
          _loadingSeats = false;
        });
      }
    }
  }

  void _toggleSeat(String seatId) {
    if (_selectedSection == null) return;
    final sectionId = _selectedSection!.id;
    final maxForSection = widget.sectionQuantities[sectionId] ?? 0;

    setState(() {
      final sectionSeats = _selectedSeats.putIfAbsent(sectionId, () => {});
      if (sectionSeats.contains(seatId)) {
        // Deselect
        sectionSeats.remove(seatId);
      } else if (sectionSeats.length < maxForSection) {
        // Add
        sectionSeats.add(seatId);
      } else if (maxForSection > 0) {
        // At capacity — replace the first selected seat
        sectionSeats.remove(sectionSeats.first);
        sectionSeats.add(seatId);
      }
    });
  }

  void _confirmSeats() {
    Navigator.of(context).pop(_allSelections);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedSection == null ? L.tr('seat_picker_select_section') : _selectedSection!.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_selectedSection != null && !_skipMapPhase) {
              setState(() => _selectedSection = null);
            } else {
              Navigator.of(context).pop(null);
            }
          },
        ),
      ),
      body: _selectedSection == null
          ? _buildMapPhase(theme, colorScheme)
          : _buildSeatPhase(theme, colorScheme),
      bottomNavigationBar: _buildBottomBar(theme, colorScheme),
    );
  }

  // ── Phase A: Map view ──────────────────────────────────────────

  Widget _buildMapPhase(ThemeData theme, ColorScheme colorScheme) {
    final needsSeatPick = _sectionsNeedingSelection;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            L.tr('seat_picker_tap_section'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: VenueMiniMap(
            layout: widget.venue.layout,
            canvasWidth: widget.venue.canvasWidth,
            canvasHeight: widget.venue.canvasHeight,
            highlightedSectionIds: needsSeatPick,
            onSectionTap: (sectionId) {
              final section = widget.venue.layout.sections
                  .where((s) => s.id == sectionId)
                  .firstOrNull;
              if (section != null) _selectSection(section);
            },
          ),
        ),
      ],
    );
  }

  // ── Phase B: Seat grid ─────────────────────────────────────────

  /// Desired rendered seat size in logical pixels.
  static const double _seatDisplaySize = 40.0;
  /// Gap between seats.
  static const double _seatGap = 6.0;
  /// Padding around the grid (top/bottom and right).
  static const double _gridPadding = 20.0;
  /// Extra left padding for row labels.
  static const double _labelWidth = 28.0;

  Widget _buildSeatPhase(ThemeData theme, ColorScheme colorScheme) {
    final section = _selectedSection!;
    final sectionId = section.id;
    final maxForSection = widget.sectionQuantities[sectionId] ?? 0;
    final selectedInSection = _selectedSeats[sectionId]?.length ?? 0;

    if (_loadingSeats) {
      return const Center(child: CircularProgressIndicator());
    }

    // Compute normalized grid: find min/max of raw positions to build a grid
    final gridInfo = _computeNormalizedGrid(section);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Select $maxForSection seat${maxForSection != 1 ? "s" : ""}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selectedInSection / $maxForSection',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(colorScheme.primary, L.tr('seat_picker_your_seat')),
              const SizedBox(width: 16),
              _legendDot(_parseSectionColor(section.color), L.tr('seat_picker_available')),
              const SizedBox(width: 16),
              _legendDot(Colors.grey.shade400, L.tr('seat_picker_taken')),
            ],
          ),
        ),
        // Seat grid — scaled to fit screen
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Scale grid to fit available width
              final totalHPad = _labelWidth + _gridPadding; // left: label area, right: padding
              final availableW = constraints.maxWidth - totalHPad - _gridPadding;
              final availableH = constraints.maxHeight - _gridPadding * 2;
              final gridW = gridInfo.cols * (_seatDisplaySize + _seatGap) - _seatGap;
              final gridH = gridInfo.rows * (_seatDisplaySize + _seatGap) - _seatGap;
              final scaleX = gridW > 0 ? availableW / gridW : 1.0;
              final scaleY = gridH > 0 ? availableH / gridH : 1.0;
              final fitScale = math.min(scaleX, scaleY).clamp(0.3, 1.5);
              final canvasW = _labelWidth + gridW + _labelWidth; // symmetrical padding
              final canvasH = gridH + _gridPadding * 2;

              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Center(
                  child: Transform.scale(
                    scale: fitScale,
                    child: SizedBox(
                      width: canvasW,
                      height: canvasH,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleSeatTap(
                          details, section, gridInfo,
                        ),
                        child: CustomPaint(
                          size: Size(canvasW, canvasH),
                          painter: _SeatGridPainter(
                            gridInfo: gridInfo,
                            seatSize: _seatDisplaySize,
                            seatGap: _seatGap,
                            padding: _gridPadding,
                            labelWidth: _labelWidth,
                            unavailable: _unavailableSeats,
                            selected: _selectedSeats[sectionId] ?? {},
                            sectionColor: _parseSectionColor(section.color),
                            selectedColor: colorScheme.primary,
                            takenColor: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  /// Normalizes raw seat positions into a grid with col/row indices.
  _GridInfo _computeNormalizedGrid(VenueSection section) {
    if (section.rows.isEmpty) return _GridInfo(seats: [], rows: 0, cols: 0);

    // Collect all seat positions
    final allSeats = <_GridSeat>[];
    for (final row in section.rows) {
      for (final seat in row.seats) {
        allSeats.add(_GridSeat(
          seatData: seat,
          seatRow: row,
          rawX: seat.x,
          rawY: seat.y,
        ));
      }
    }

    if (allSeats.isEmpty) return _GridInfo(seats: [], rows: 0, cols: 0);

    // Sort by Y then X to assign grid rows/columns
    allSeats.sort((a, b) {
      final dy = a.rawY.compareTo(b.rawY);
      return dy != 0 ? dy : a.rawX.compareTo(b.rawX);
    });

    // Quantize Y into rows (seats within 12px of each other = same row)
    final yValues = allSeats.map((s) => s.rawY).toList();
    final rowBuckets = <double>[];
    for (final y in yValues) {
      if (rowBuckets.isEmpty || (y - rowBuckets.last).abs() > 12) {
        rowBuckets.add(y);
      }
    }

    // Assign grid row index
    for (final seat in allSeats) {
      int bestRow = 0;
      double bestDist = double.infinity;
      for (int i = 0; i < rowBuckets.length; i++) {
        final dist = (seat.rawY - rowBuckets[i]).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestRow = i;
        }
      }
      seat.gridRow = bestRow;
    }

    // Within each grid row, sort by X and assign column index
    final byRow = <int, List<_GridSeat>>{};
    for (final seat in allSeats) {
      byRow.putIfAbsent(seat.gridRow, () => []).add(seat);
    }
    int maxCol = 0;
    for (final row in byRow.values) {
      row.sort((a, b) => a.rawX.compareTo(b.rawX));
      for (int i = 0; i < row.length; i++) {
        row[i].gridCol = i;
        maxCol = math.max(maxCol, i);
      }
    }

    return _GridInfo(
      seats: allSeats,
      rows: rowBuckets.length,
      cols: maxCol + 1,
    );
  }

  void _handleSeatTap(
    TapUpDetails details,
    VenueSection section,
    _GridInfo gridInfo,
  ) {
    final pos = details.localPosition;
    final hitRadius = _seatDisplaySize * 0.6;

    for (final seat in gridInfo.seats) {
      final cx = _labelWidth + seat.gridCol * (_seatDisplaySize + _seatGap) + _seatDisplaySize / 2;
      final cy = _gridPadding + seat.gridRow * (_seatDisplaySize + _seatGap) + _seatDisplaySize / 2;
      final dx = pos.dx - cx;
      final dy = pos.dy - cy;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) {
        if (_unavailableSeats.contains(seat.seatData.id)) return;
        if (seat.seatData.status == SeatStatus.blocked) return;
        _toggleSeat(seat.seatData.id);
        return;
      }
    }
  }

  // ── Bottom bar ─────────────────────────────────────────────────

  Widget _buildBottomBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected seat chips
          if (_totalSelected > 0)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _allSelections.map((s) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(
                        '${s.sectionName} ${s.rowLabel}${s.seatNumber}',
                        style: theme.textTheme.labelSmall,
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        setState(() {
                          _selectedSeats[s.sectionId]?.remove(s.seatId);
                        });
                      },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList(),
              ),
            ),
          if (_totalSelected > 0) const SizedBox(height: 8),
          // Confirm button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _allSectionsFilled ? _confirmSeats : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _allSectionsFilled
                    ? L.tr('seat_picker_confirm_seats', ['$_totalSelected'])
                    : L.tr('seat_picker_seats_selected', ['$_totalSelected', '$_totalNeeded']),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseSectionColor(String hex) {
    try {
      final hexCode = hex.replaceAll('#', '');
      return Color(int.parse('FF$hexCode', radix: 16));
    } catch (_) {
      return const Color(0xFF6366F1);
    }
  }
}

/// Helper classes for normalized grid layout.
class _GridSeat {
  final SeatData seatData;
  final SeatRow seatRow;
  final double rawX;
  final double rawY;
  int gridRow = 0;
  int gridCol = 0;

  _GridSeat({
    required this.seatData,
    required this.seatRow,
    required this.rawX,
    required this.rawY,
  });
}

class _GridInfo {
  final List<_GridSeat> seats;
  final int rows;
  final int cols;

  _GridInfo({required this.seats, required this.rows, required this.cols});
}

/// Custom painter for a section's seat grid using normalized positions.
class _SeatGridPainter extends CustomPainter {
  final _GridInfo gridInfo;
  final double seatSize;
  final double seatGap;
  final double padding;
  final double labelWidth;
  final Set<String> unavailable;
  final Set<String> selected;
  final Color sectionColor;
  final Color selectedColor;
  final Color takenColor;

  _SeatGridPainter({
    required this.gridInfo,
    required this.seatSize,
    required this.seatGap,
    required this.padding,
    required this.labelWidth,
    required this.unavailable,
    required this.selected,
    required this.sectionColor,
    required this.selectedColor,
    required this.takenColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = seatSize * 0.2;
    final selectedPaint = Paint()..color = selectedColor;
    final takenPaint = Paint()..color = takenColor;
    final availablePaint = Paint()..color = sectionColor;

    // Draw row labels
    final labelStyle = TextStyle(
      color: takenColor,
      fontSize: seatSize * 0.3,
      fontWeight: FontWeight.w500,
    );

    // Track which rows we've labeled
    final labeledRows = <int>{};

    for (final seat in gridInfo.seats) {
      final x = labelWidth + seat.gridCol * (seatSize + seatGap);
      final y = padding + seat.gridRow * (seatSize + seatGap);
      final rect = RRect.fromLTRBR(
        x, y, x + seatSize, y + seatSize,
        Radius.circular(radius),
      );

      Paint paint;
      if (selected.contains(seat.seatData.id)) {
        paint = selectedPaint;
        // Draw checkmark on selected seats
        canvas.drawRRect(rect, paint);
        final iconPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final cx = x + seatSize / 2;
        final cy = y + seatSize / 2;
        final s = seatSize * 0.2;
        canvas.drawPath(
          Path()
            ..moveTo(cx - s, cy)
            ..lineTo(cx - s * 0.3, cy + s * 0.7)
            ..lineTo(cx + s, cy - s * 0.5),
          iconPaint,
        );
        continue;
      } else if (unavailable.contains(seat.seatData.id) ||
          seat.seatData.status == SeatStatus.blocked) {
        paint = takenPaint;
      } else {
        paint = availablePaint;
      }

      canvas.drawRRect(rect, paint);

      // Draw seat number
      if (seatSize >= 28) {
        final tp = TextPainter(
          text: TextSpan(
            text: seat.seatData.number.toString(),
            style: TextStyle(
              color: paint == takenPaint
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.9),
              fontSize: seatSize * 0.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x + (seatSize - tp.width) / 2, y + (seatSize - tp.height) / 2),
        );
      }

      // Draw row label in the label area (left of seats)
      if (!labeledRows.contains(seat.gridRow) && seat.gridCol == 0) {
        labeledRows.add(seat.gridRow);
        final tp = TextPainter(
          text: TextSpan(text: seat.seatRow.label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset((labelWidth - tp.width) / 2, y + (seatSize - tp.height) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeatGridPainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.unavailable != unavailable;
  }
}

