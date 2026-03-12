import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/venues/data/venue_repository.dart';
import '../../features/venues/models/models.dart';

/// Repository provider.
final venueRepositoryProvider = Provider<VenueRepository>((ref) {
  return VenueRepository();
});

/// List of organizer's venues.
final myVenuesProvider =
    AsyncNotifierProvider<MyVenuesNotifier, List<Venue>>(MyVenuesNotifier.new);

class MyVenuesNotifier extends AsyncNotifier<List<Venue>> {
  @override
  Future<List<Venue>> build() async {
    return ref.read(venueRepositoryProvider).getMyVenues();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(venueRepositoryProvider).getMyVenues(),
    );
  }

  Future<Venue> create(String name) async {
    final venue = await ref.read(venueRepositoryProvider).createVenue(name: name);
    await refresh();
    return venue;
  }

  Future<void> delete(String venueId) async {
    await ref.read(venueRepositoryProvider).deleteVenue(venueId);
    await refresh();
  }
}

/// Active tool in the venue builder.
enum VenueBuilderTool {
  select,
  seatedSection,
  standingArea,
  tableSection,
  stage,
  bar,
  entrance,
  restroom,
  label,
}

/// State for the venue builder canvas.
@immutable
class VenueBuilderState {
  final VenueLayout layout;
  final String? selectedId;
  final String? resizingId;
  final String? morphingId;
  final String? rotatingId;
  final VenueBuilderTool activeTool;
  final bool isDirty;
  final List<VenueLayout> undoStack;
  final List<VenueLayout> redoStack;
  final String venueName;
  final int canvasWidth;
  final int canvasHeight;

  const VenueBuilderState({
    this.layout = const VenueLayout(),
    this.selectedId,
    this.resizingId,
    this.morphingId,
    this.rotatingId,
    this.activeTool = VenueBuilderTool.select,
    this.isDirty = false,
    this.undoStack = const [],
    this.redoStack = const [],
    this.venueName = '',
    this.canvasWidth = 1200,
    this.canvasHeight = 800,
  });

  VenueBuilderState copyWith({
    VenueLayout? layout,
    String? selectedId,
    bool clearSelection = false,
    String? resizingId,
    bool clearResize = false,
    String? morphingId,
    bool clearMorph = false,
    String? rotatingId,
    bool clearRotating = false,
    VenueBuilderTool? activeTool,
    bool? isDirty,
    List<VenueLayout>? undoStack,
    List<VenueLayout>? redoStack,
    String? venueName,
    int? canvasWidth,
    int? canvasHeight,
  }) {
    return VenueBuilderState(
      layout: layout ?? this.layout,
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
      resizingId: clearResize ? null : (resizingId ?? this.resizingId),
      morphingId: clearMorph ? null : (morphingId ?? this.morphingId),
      rotatingId: clearRotating ? null : (rotatingId ?? this.rotatingId),
      activeTool: activeTool ?? this.activeTool,
      isDirty: isDirty ?? this.isDirty,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      venueName: venueName ?? this.venueName,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
    );
  }

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;
}

/// Venue builder notifier — family by venue ID (null for new venues).
final venueBuilderProvider =
    StateNotifierProvider.family<VenueBuilderNotifier, VenueBuilderState, String?>(
  (ref, venueId) => VenueBuilderNotifier(ref, venueId),
);

class VenueBuilderNotifier extends StateNotifier<VenueBuilderState> {
  final Ref _ref;
  final String? _venueId;
  static const _maxUndoStack = 50;

  VenueBuilderNotifier(this._ref, this._venueId)
      : super(const VenueBuilderState()) {
    if (_venueId != null) _loadVenue();
  }

  Future<void> _loadVenue() async {
    final venue = await _ref.read(venueRepositoryProvider).getVenue(_venueId!);
    if (venue != null) {
      state = state.copyWith(
        layout: venue.layout,
        venueName: venue.name,
        canvasWidth: venue.canvasWidth,
        canvasHeight: venue.canvasHeight,
      );
    }
  }

  void _pushUndo() {
    final stack = [...state.undoStack, state.layout];
    if (stack.length > _maxUndoStack) stack.removeAt(0);
    state = state.copyWith(
      undoStack: stack,
      redoStack: [],
      isDirty: true,
    );
  }

  // ── Section operations ─────────────────────────────────────

  void addSection(VenueSection section) {
    _pushUndo();
    state = state.copyWith(
      layout: state.layout.copyWith(
        sections: [...state.layout.sections, section],
      ),
      selectedId: section.id,
    );
  }

  void updateSection(VenueSection updated) {
    _pushUndo();
    state = state.copyWith(
      layout: state.layout.copyWith(
        sections: state.layout.sections
            .map((s) => s.id == updated.id ? updated : s)
            .toList(),
      ),
    );
  }

  void removeSection(String sectionId) {
    _pushUndo();
    state = state.copyWith(
      layout: state.layout.copyWith(
        sections:
            state.layout.sections.where((s) => s.id != sectionId).toList(),
      ),
      clearSelection: state.selectedId == sectionId,
    );
  }

  // ── Element operations ─────────────────────────────────────

  void addElement(VenueElement element) {
    _pushUndo();
    state = state.copyWith(
      layout: state.layout.copyWith(
        elements: [...state.layout.elements, element],
      ),
      selectedId: element.id,
    );
  }

  void updateElement(VenueElement updated) {
    _pushUndo();
    state = state.copyWith(
      layout: state.layout.copyWith(
        elements: state.layout.elements
            .map((e) => e.id == updated.id ? updated : e)
            .toList(),
      ),
    );
  }

  void removeElement(String elementId) {
    _pushUndo();
    state = state.copyWith(
      layout: state.layout.copyWith(
        elements:
            state.layout.elements.where((e) => e.id != elementId).toList(),
      ),
      clearSelection: state.selectedId == elementId,
    );
  }

  /// Push undo once before a drag sequence starts.
  void beginMove() {
    _pushUndo();
  }

  /// Move an element live during a drag — no undo push per frame.
  void moveElement(String id, double dx, double dy) {
    // Try sections first
    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      final updated = section.copyWith(
        shape: section.shape.copyWith(
          x: section.shape.x + dx,
          y: section.shape.y + dy,
        ),
      );
      final sections = [...state.layout.sections];
      sections[sectionIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(sections: sections),
        isDirty: true,
      );
      return;
    }

    // Try elements
    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      final updated = element.copyWith(
        shape: element.shape.copyWith(
          x: element.shape.x + dx,
          y: element.shape.y + dy,
        ),
      );
      final elements = [...state.layout.elements];
      elements[elementIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(elements: elements),
        isDirty: true,
      );
    }
  }

  /// Set rotation live during drag — no undo push per frame.
  void setRotation(String id, double degrees) {
    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      final updated = section.copyWith(
        shape: section.shape.copyWith(rotation: degrees),
      );
      final sections = [...state.layout.sections];
      sections[sectionIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(sections: sections),
        isDirty: true,
      );
      return;
    }

    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      final updated = element.copyWith(
        shape: element.shape.copyWith(rotation: degrees),
      );
      final elements = [...state.layout.elements];
      elements[elementIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(elements: elements),
        isDirty: true,
      );
    }
  }

  /// Resize and reposition an element live during handle drag — no undo push per frame.
  void resizeAndMove(String id, double x, double y, double width, double height) {
    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      final updated = section.copyWith(
        shape: section.shape.copyWith(x: x, y: y, width: width, height: height),
      );
      final sections = [...state.layout.sections];
      sections[sectionIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(sections: sections),
        isDirty: true,
      );
      return;
    }

    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      final updated = element.copyWith(
        shape: element.shape.copyWith(x: x, y: y, width: width, height: height),
      );
      final elements = [...state.layout.elements];
      elements[elementIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(elements: elements),
        isDirty: true,
      );
    }
  }

  /// Uniformly scale an element/section by a factor, keeping its center fixed.
  /// Also scales polygon points proportionally.
  void scaleUniform(String id, double factor) {
    ElementShape? applyScale(ElementShape shape) {
      final cx = shape.x + shape.width / 2;
      final cy = shape.y + shape.height / 2;
      final newW = (shape.width * factor).clamp(30.0, 2000.0);
      final newH = (shape.height * factor).clamp(30.0, 2000.0);
      final actualFactorW = newW / shape.width;
      final actualFactorH = newH / shape.height;
      final newX = cx - newW / 2;
      final newY = cy - newH / 2;

      List<Offset>? newPoints;
      if (shape.points.isNotEmpty) {
        newPoints = shape.points
            .map((p) => Offset(p.dx * actualFactorW, p.dy * actualFactorH))
            .toList();
      }

      return shape.copyWith(
        x: newX, y: newY, width: newW, height: newH,
        points: newPoints,
      );
    }

    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      final sections = [...state.layout.sections];
      sections[sectionIdx] = section.copyWith(shape: applyScale(section.shape));
      state = state.copyWith(
        layout: state.layout.copyWith(sections: sections),
        isDirty: true,
      );
      return;
    }

    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      final elements = [...state.layout.elements];
      elements[elementIdx] = element.copyWith(shape: applyScale(element.shape));
      state = state.copyWith(
        layout: state.layout.copyWith(elements: elements),
        isDirty: true,
      );
    }
  }

  void resizeElement(String id, double newWidth, double newHeight) {
    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      final updated = section.copyWith(
        shape: section.shape.copyWith(width: newWidth, height: newHeight),
      );
      _pushUndo();
      final sections = [...state.layout.sections];
      sections[sectionIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(sections: sections),
      );
      return;
    }

    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      final updated = element.copyWith(
        shape: element.shape.copyWith(width: newWidth, height: newHeight),
      );
      _pushUndo();
      final elements = [...state.layout.elements];
      elements[elementIdx] = updated;
      state = state.copyWith(
        layout: state.layout.copyWith(elements: elements),
      );
    }
  }

  void autoGenerateSeats(String sectionId, List<SeatRow> rows) {
    final idx = state.layout.sections.indexWhere((s) => s.id == sectionId);
    if (idx < 0) return;
    _pushUndo();
    final sections = [...state.layout.sections];
    sections[idx] = sections[idx].copyWith(rows: rows);
    state = state.copyWith(
      layout: state.layout.copyWith(sections: sections),
    );
  }

  // ── Selection & tools ──────────────────────────────────────

  void selectElement(String? id) {
    state = state.copyWith(
      selectedId: id,
      clearSelection: id == null,
      clearResize: true,
      clearMorph: true,
      clearRotating: true,
    );
  }

  /// Select a new element but keep the current mode (rotate/scale/morph).
  void selectElementKeepMode(String id) {
    if (state.rotatingId != null) {
      state = state.copyWith(selectedId: id, rotatingId: id);
    } else if (state.resizingId != null) {
      state = state.copyWith(selectedId: id, resizingId: id);
    } else if (state.morphingId != null) {
      _ensurePolygonShape(id);
      state = state.copyWith(selectedId: id, morphingId: id);
    } else {
      selectElement(id);
    }
  }

  void toggleResize(String id) {
    if (state.resizingId == id) {
      state = state.copyWith(clearResize: true);
    } else {
      state = state.copyWith(resizingId: id, selectedId: id, clearMorph: true, clearRotating: true);
    }
  }

  void clearResize() {
    state = state.copyWith(clearResize: true);
  }

  void toggleMorph(String id) {
    if (state.morphingId == id) {
      state = state.copyWith(clearMorph: true);
    } else {
      _ensurePolygonShape(id);
      state = state.copyWith(morphingId: id, selectedId: id, clearResize: true, clearRotating: true);
    }
  }

  void clearMorph() {
    state = state.copyWith(clearMorph: true);
  }

  void toggleRotating(String id) {
    if (state.rotatingId == id) {
      state = state.copyWith(clearRotating: true);
    } else {
      state = state.copyWith(rotatingId: id, selectedId: id, clearResize: true, clearMorph: true);
    }
  }

  void clearRotating() {
    state = state.copyWith(clearRotating: true);
  }

  /// Convert a rectangle shape to polygon (4 corners) so morph can work.
  void _ensurePolygonShape(String id) {
    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      if (section.shape.shapeType != ShapeType.polygon || section.shape.points.length < 3) {
        _pushUndo();
        final w = section.shape.width;
        final h = section.shape.height;
        final updated = section.copyWith(
          shape: section.shape.copyWith(
            shapeType: ShapeType.polygon,
            points: [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)],
          ),
        );
        final sections = [...state.layout.sections];
        sections[sectionIdx] = updated;
        state = state.copyWith(layout: state.layout.copyWith(sections: sections));
      }
      return;
    }

    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      if (element.shape.shapeType != ShapeType.polygon || element.shape.points.length < 3) {
        _pushUndo();
        final w = element.shape.width;
        final h = element.shape.height;
        final updated = element.copyWith(
          shape: element.shape.copyWith(
            shapeType: ShapeType.polygon,
            points: [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)],
          ),
        );
        final elements = [...state.layout.elements];
        elements[elementIdx] = updated;
        state = state.copyWith(layout: state.layout.copyWith(elements: elements));
      }
    }
  }

  /// Move a single morph point (by index) without undo push per frame.
  void moveMorphPoint(String id, int pointIndex, double dx, double dy) {
    final sectionIdx = state.layout.sections.indexWhere((s) => s.id == id);
    if (sectionIdx >= 0) {
      final section = state.layout.sections[sectionIdx];
      if (pointIndex >= section.shape.points.length) return;
      final points = [...section.shape.points];
      points[pointIndex] = Offset(points[pointIndex].dx + dx, points[pointIndex].dy + dy);
      final updated = section.copyWith(shape: section.shape.copyWith(points: points));
      final sections = [...state.layout.sections];
      sections[sectionIdx] = updated;
      state = state.copyWith(layout: state.layout.copyWith(sections: sections), isDirty: true);
      return;
    }

    final elementIdx = state.layout.elements.indexWhere((e) => e.id == id);
    if (elementIdx >= 0) {
      final element = state.layout.elements[elementIdx];
      if (pointIndex >= element.shape.points.length) return;
      final points = [...element.shape.points];
      points[pointIndex] = Offset(points[pointIndex].dx + dx, points[pointIndex].dy + dy);
      final updated = element.copyWith(shape: element.shape.copyWith(points: points));
      final elements = [...state.layout.elements];
      elements[elementIdx] = updated;
      state = state.copyWith(layout: state.layout.copyWith(elements: elements), isDirty: true);
    }
  }

  void setTool(VenueBuilderTool tool) {
    state = state.copyWith(
      activeTool: tool,
      clearSelection: tool != VenueBuilderTool.select,
      clearResize: true,
      clearMorph: true,
      clearRotating: true,
    );
  }

  // ── Undo / Redo ────────────────────────────────────────────

  void undo() {
    if (!state.canUndo) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    state = state.copyWith(
      layout: previous,
      undoStack: stack,
      redoStack: [...state.redoStack, state.layout],
      isDirty: true,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final stack = [...state.redoStack];
    final next = stack.removeLast();
    state = state.copyWith(
      layout: next,
      redoStack: stack,
      undoStack: [...state.undoStack, state.layout],
      isDirty: true,
    );
  }

  // ── Save ───────────────────────────────────────────────────

  Future<Venue> save() async {
    final repo = _ref.read(venueRepositoryProvider);
    Venue venue;

    if (_venueId != null) {
      final existing = await repo.getVenue(_venueId);
      if (existing == null) throw Exception('Venue not found');
      venue = await repo.updateVenue(existing.copyWith(
        name: state.venueName,
        layout: state.layout,
        totalCapacity: state.layout.totalCapacity,
        canvasWidth: state.canvasWidth,
        canvasHeight: state.canvasHeight,
      ));
    } else {
      venue = await repo.createVenue(name: state.venueName);
      venue = await repo.updateVenue(venue.copyWith(
        layout: state.layout,
        totalCapacity: state.layout.totalCapacity,
        canvasWidth: state.canvasWidth,
        canvasHeight: state.canvasHeight,
      ));
    }

    state = state.copyWith(isDirty: false);
    // Refresh the venues list
    _ref.read(myVenuesProvider.notifier).refresh();
    return venue;
  }

  void setVenueName(String name) {
    state = state.copyWith(venueName: name, isDirty: true);
  }
}
