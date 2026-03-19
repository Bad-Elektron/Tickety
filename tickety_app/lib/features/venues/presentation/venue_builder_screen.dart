import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/venue_provider.dart';
import '../models/models.dart';
import '../utils/hit_test.dart';
import '../widgets/widgets.dart';

/// Core venue builder screen with interactive canvas.
///
/// Supports:
/// - Drag from palette → drop on canvas to place items
/// - Drag existing items on canvas to reposition them
/// - Floating action bar on selection: Edit Shape, Rotate, Duplicate, Delete
/// - Resize handles when in "Edit Shape" mode
/// - Pinch to zoom, single-finger pan on empty space
class VenueBuilderScreen extends ConsumerStatefulWidget {
  final String? venueId;

  const VenueBuilderScreen({super.key, this.venueId});

  @override
  ConsumerState<VenueBuilderScreen> createState() => _VenueBuilderScreenState();
}

class _VenueBuilderScreenState extends ConsumerState<VenueBuilderScreen> {
  final _transformController = TransformationController();
  double _currentZoom = 1.0;
  bool _isSaving = false;

  // Canvas item dragging state
  String? _draggingItemId;
  bool _didMoveItem = false;

  // Uniform scale handle dragging state
  bool _isScaling = false;

  // Morph point dragging state
  int _activeMorphPoint = -1;
  bool _isMorphingPoint = false;

  // Rotation handle dragging state
  bool _isRotating = false;

  // Panning state (when dragging on empty space)
  bool _isPanning = false;

  // Pinch-to-zoom state
  bool _isPinchZooming = false;
  double _baseZoom = 1.0;
  Offset _pinchFocalStart = Offset.zero; // in screen (global) space
  double _baseTx = 0;
  double _baseTy = 0;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  double get _zoom => _transformController.value.getMaxScaleOnAxis();

  /// Convert a screen-space position (relative to the InteractiveViewer) to canvas coordinates.
  Offset _screenToCanvas(Offset screenPos) {
    final inverse = Matrix4.inverted(_transformController.value);
    return MatrixUtils.transformPoint(inverse, screenPos);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(venueBuilderProvider(widget.venueId));
    final notifier = ref.read(venueBuilderProvider(widget.venueId).notifier);
    final isDesktop = MediaQuery.sizeOf(context).width > 800;

    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldSave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L.tr('unsaved_changes')),
            content: Text(L.tr('unsaved_changes_prompt')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null), // cancel
                child: Text(L.tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), // discard
                child: Text(L.tr('discard')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true), // save
                child: Text(L.tr('save')),
              ),
            ],
          ),
        );
        if (shouldSave == null || !mounted) return; // cancelled
        if (shouldSave) {
          await _save(notifier);
        }
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _editVenueName(context, notifier, state.venueName),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  state.venueName.isEmpty ? L.tr('new_venue') : state.venueName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined, size: 16),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: state.canUndo ? notifier.undo : null,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: state.canRedo ? notifier.redo : null,
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: state.isDirty && !_isSaving ? () => _save(notifier) : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(L.tr('save')),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          isDesktop ? _buildDesktopLayout(state, notifier) : _buildMobileLayout(state, notifier),
          // Floating action bar when an item is selected
          if (state.selectedId != null)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: _SelectionActionBar(
                  isResizing: state.resizingId == state.selectedId,
                  isMorphing: state.morphingId == state.selectedId,
                  isRotating: state.rotatingId == state.selectedId,
                  showProperties: !isDesktop,
                  onEditShape: () {
                    notifier.toggleResize(state.selectedId!);
                    HapticFeedback.mediumImpact();
                  },
                  onMorph: () {
                    notifier.toggleMorph(state.selectedId!);
                    HapticFeedback.mediumImpact();
                  },
                  onRotate: () {
                    notifier.toggleRotating(state.selectedId!);
                    HapticFeedback.mediumImpact();
                  },
                  onDuplicate: () => _duplicateSelected(state, notifier),
                  onDelete: () => _deleteSelected(state, notifier),
                  onProperties: () => _showMobileProperties(state, notifier),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildDesktopLayout(VenueBuilderState state, VenueBuilderNotifier notifier) {
    return Row(
      children: [
        ToolPalette(
          activeTool: state.activeTool,
          onToolChanged: notifier.setTool,
          vertical: true,
        ),
        Expanded(child: _buildCanvas(state, notifier)),
        SizedBox(
          width: 260,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: _buildPropertiesPanel(state, notifier),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(VenueBuilderState state, VenueBuilderNotifier notifier) {
    return Row(
      children: [
        ToolPalette(
          activeTool: state.activeTool,
          onToolChanged: notifier.setTool,
          vertical: true,
        ),
        Expanded(child: _buildCanvas(state, notifier)),
      ],
    );
  }

  // ── Canvas ─────────────────────────────────────────────────

  Widget _buildCanvas(VenueBuilderState state, VenueBuilderNotifier notifier) {
    final canvasW = state.canvasWidth.toDouble();
    final canvasH = state.canvasHeight.toDouble();

    return DragTarget<ToolDragData>(
      onAcceptWithDetails: (details) {
        // Find where on the canvas the drop landed
        final renderBox = context.findRenderObject() as RenderBox;
        final localPos = renderBox.globalToLocal(details.offset);
        final canvasPos = _screenToCanvas(localPos);
        _placeItem(canvasPos, details.data.tool, notifier);
        notifier.setTool(VenueBuilderTool.select);
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;

        return ClipRect(
          child: Container(
            color: isDragOver
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.08)
                : null,
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _onScrollZoom(event);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onTapDown(d, state, notifier),
                onScaleStart: (d) => _onScaleStart(d, state, notifier),
                onScaleUpdate: (d) => _onScaleUpdate(d, notifier),
                onScaleEnd: (d) => _onScaleEnd(notifier),
                child: Transform(
                  transform: _transformController.value,
                  child: SizedBox(
                    width: canvasW,
                    height: canvasH,
                    child: CustomPaint(
                      painter: VenueCanvasPainter(
                        layout: state.layout,
                        canvasWidth: state.canvasWidth,
                        canvasHeight: state.canvasHeight,
                        selectedId: state.selectedId,
                        resizingId: state.resizingId,
                        morphingId: state.morphingId,
                        rotatingId: state.rotatingId,
                        zoom: _currentZoom,
                      ),
                      size: Size(canvasW, canvasH),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Tap: select / deselect ────────────────────────────────

  void _onTapDown(TapDownDetails details, VenueBuilderState state, VenueBuilderNotifier notifier) {
    final canvasPos = _screenToCanvas(details.localPosition);

    // If tapping the rotation handle area, don't change selection
    if (state.rotatingId != null) {
      ElementShape? shape;
      for (final s in state.layout.sections) {
        if (s.id == state.rotatingId) { shape = s.shape; break; }
      }
      if (shape == null) {
        for (final e in state.layout.elements) {
          if (e.id == state.rotatingId) { shape = e.shape; break; }
        }
      }
      if (shape != null && hitTestRotationHandle(shape, canvasPos)) {
        return; // Will be handled by onPanStart
      }
    }

    // If tapping scale handle area, don't change selection
    if (state.resizingId != null) {
      ElementShape? shape;
      for (final s in state.layout.sections) {
        if (s.id == state.resizingId) { shape = s.shape; break; }
      }
      if (shape == null) {
        for (final e in state.layout.elements) {
          if (e.id == state.resizingId) { shape = e.shape; break; }
        }
      }
      if (shape != null && hitTestScaleHandle(shape, canvasPos)) {
        return; // Will be handled by onPanStart
      }
    }

    // If tapping morph point area, don't change selection
    if (state.morphingId != null) {
      ElementShape? shape;
      for (final s in state.layout.sections) {
        if (s.id == state.morphingId) { shape = s.shape; break; }
      }
      if (shape == null) {
        for (final e in state.layout.elements) {
          if (e.id == state.morphingId) { shape = e.shape; break; }
        }
      }
      if (shape != null && hitTestMorphPoint(shape, canvasPos) >= 0) {
        return; // Will be handled by onPanStart
      }
    }

    final result = hitTest(state.layout, canvasPos);

    switch (result) {
      case SectionHit(sectionId: final id):
        if (id != state.selectedId) notifier.selectElementKeepMode(id);
      case ElementHit(elementId: final id):
        if (id != state.selectedId) notifier.selectElementKeepMode(id);
      case SeatHit(sectionId: final id):
        if (id != state.selectedId) notifier.selectElementKeepMode(id);
      case EmptyHit():
        // Only deselect if tap is far from the currently selected item
        if (state.selectedId != null && _isTapNearSelected(canvasPos, state)) {
          return; // Ignore tap — too close to the selected item
        }
        notifier.selectElement(null);
    }
  }

  /// Check if a tap position is within padding of the selected element's bounds
  /// or near the rotation handle.
  bool _isTapNearSelected(Offset pos, VenueBuilderState state) {
    const padding = 30.0;
    ElementShape? shape;
    for (final s in state.layout.sections) {
      if (s.id == state.selectedId) { shape = s.shape; break; }
    }
    if (shape == null) {
      for (final e in state.layout.elements) {
        if (e.id == state.selectedId) { shape = e.shape; break; }
      }
    }
    if (shape == null) return false;

    // Check rotation handle area
    if (hitTestRotationHandle(shape, pos)) return true;
    // Check scale handle area
    if (hitTestScaleHandle(shape, pos)) return true;

    final paddedRect = Rect.fromLTWH(
      shape.x - padding,
      shape.y - padding,
      shape.width + padding * 2,
      shape.height + padding * 2,
    );
    return paddedRect.contains(pos);
  }

  // ── Scale/Pan: drag items, pinch-to-zoom, scroll-to-zoom, pan on empty space ──

  void _onScrollZoom(PointerScrollEvent event) {
    final scaleFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
    _zoomAt(event.localPosition, scaleFactor);
  }

  /// Apply a zoom scale factor centered on a screen-space focal point.
  void _zoomAt(Offset focalScreen, double scaleFactor) {
    final old = _transformController.value;
    final oldZoom = old.getMaxScaleOnAxis();
    final newZoom = (oldZoom * scaleFactor).clamp(0.25, 4.0);
    if (newZoom == oldZoom) return;

    final ratio = newZoom / oldZoom;
    final oldTx = old.entry(0, 3);
    final oldTy = old.entry(1, 3);

    // Keep the focal point fixed on screen:
    // newTx = focal.x - ratio * (focal.x - oldTx)
    final m = Matrix4.identity()
      ..setEntry(0, 0, newZoom)
      ..setEntry(1, 1, newZoom)
      ..setEntry(0, 3, focalScreen.dx - ratio * (focalScreen.dx - oldTx))
      ..setEntry(1, 3, focalScreen.dy - ratio * (focalScreen.dy - oldTy));

    _transformController.value = m;
    setState(() => _currentZoom = newZoom);
  }

  void _onScaleStart(ScaleStartDetails details, VenueBuilderState state, VenueBuilderNotifier notifier) {
    // Two-finger pinch → zoom mode
    if (details.pointerCount >= 2) {
      _isPinchZooming = true;
      final m = _transformController.value;
      _baseZoom = m.getMaxScaleOnAxis();
      _baseTx = m.entry(0, 3);
      _baseTy = m.entry(1, 3);
      _pinchFocalStart = details.focalPoint; // global/screen space
      return;
    }

    final canvasPos = _screenToCanvas(details.localFocalPoint);

    // Check rotation handle
    if (state.rotatingId != null) {
      final shape = _findShape(state, state.rotatingId!);
      if (shape != null && hitTestRotationHandle(shape, canvasPos)) {
        notifier.beginMove();
        _isRotating = true;
        _didMoveItem = false;
        HapticFeedback.selectionClick();
        return;
      }
    }

    // Check scale handle
    if (state.resizingId != null) {
      final shape = _findShape(state, state.resizingId!);
      if (shape != null && hitTestScaleHandle(shape, canvasPos)) {
        notifier.beginMove();
        _isScaling = true;
        _didMoveItem = false;
        HapticFeedback.selectionClick();
        return;
      }
    }

    // Check morph points
    if (state.morphingId != null) {
      final shape = _findShape(state, state.morphingId!);
      if (shape != null) {
        final ptIdx = hitTestMorphPoint(shape, canvasPos);
        if (ptIdx >= 0) {
          notifier.beginMove();
          _activeMorphPoint = ptIdx;
          _isMorphingPoint = true;
          _didMoveItem = false;
          HapticFeedback.selectionClick();
          return;
        }
      }
    }

    // Check items for drag-to-move
    final result = hitTest(state.layout, canvasPos);
    String? hitId;
    switch (result) {
      case SectionHit(sectionId: final id):
        hitId = id;
      case ElementHit(elementId: final id):
        hitId = id;
      case SeatHit(sectionId: final id):
        hitId = id;
      case EmptyHit():
        hitId = null;
    }

    if (hitId != null) {
      notifier.beginMove();
      _draggingItemId = hitId;
      _didMoveItem = false;
      if (hitId != state.selectedId) notifier.selectElementKeepMode(hitId);
      HapticFeedback.selectionClick();
    } else {
      // Nothing hit — pan the canvas
      _isPanning = true;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details, VenueBuilderNotifier notifier) {
    // Pinch-to-zoom
    if (_isPinchZooming) {
      final newZoom = (_baseZoom * details.scale).clamp(0.25, 4.0);
      final ratio = newZoom / _baseZoom;

      // Focal point in screen space (global)
      final fx = _pinchFocalStart.dx;
      final fy = _pinchFocalStart.dy;
      // How much the focal point has moved since pinch start
      final panDx = details.focalPoint.dx - _pinchFocalStart.dx;
      final panDy = details.focalPoint.dy - _pinchFocalStart.dy;

      // Keep the original focal point fixed, then add pan offset
      final m = Matrix4.identity()
        ..setEntry(0, 0, newZoom)
        ..setEntry(1, 1, newZoom)
        ..setEntry(0, 3, fx - ratio * (fx - _baseTx) + panDx)
        ..setEntry(1, 3, fy - ratio * (fy - _baseTy) + panDy);

      _transformController.value = m;
      setState(() => _currentZoom = newZoom);
      return;
    }

    // Pan the canvas view
    if (_isPanning) {
      final m = _transformController.value.clone();
      m.setEntry(0, 3, m.entry(0, 3) + details.focalPointDelta.dx);
      m.setEntry(1, 3, m.entry(1, 3) + details.focalPointDelta.dy);
      _transformController.value = m;
      setState(() {}); // Rebuild Transform widget
      return;
    }

    // Rotation drag
    if (_isRotating) {
      final state = ref.read(venueBuilderProvider(widget.venueId));
      final id = state.rotatingId;
      if (id == null) return;

      final shape = _findShape(state, id);
      if (shape == null) return;

      final center = shape.center;
      final fingerPos = _screenToCanvas(details.localFocalPoint);
      final angle = atan2(fingerPos.dx - center.dx, -(fingerPos.dy - center.dy));
      final degrees = angle * 180 / pi;

      _didMoveItem = true;
      notifier.setRotation(id, degrees);
      return;
    }

    // Morph point drag
    if (_isMorphingPoint && _activeMorphPoint >= 0) {
      final state = ref.read(venueBuilderProvider(widget.venueId));
      final id = state.morphingId;
      if (id == null) return;

      final zoom = _zoom;
      final dx = details.focalPointDelta.dx / zoom;
      final dy = details.focalPointDelta.dy / zoom;
      if (dx.abs() < 0.3 && dy.abs() < 0.3) return;

      _didMoveItem = true;
      notifier.moveMorphPoint(id, _activeMorphPoint, dx, dy);
      return;
    }

    // Scale handle drag
    if (_isScaling) {
      final state = ref.read(venueBuilderProvider(widget.venueId));
      final id = state.resizingId;
      if (id == null) return;

      final shape = _findShape(state, id);
      if (shape == null) return;

      final center = shape.center;
      final currPos = _screenToCanvas(details.localFocalPoint);
      final prevScreen = details.localFocalPoint - details.focalPointDelta;
      final prevPos = _screenToCanvas(prevScreen);
      final prevDist = (prevPos - center).distance;
      final currDist = (currPos - center).distance;
      if (prevDist < 1) return;

      _didMoveItem = true;
      notifier.scaleUniform(id, currDist / prevDist);
      return;
    }

    // Item move drag
    if (_draggingItemId != null) {
      final zoom = _zoom;
      final dx = details.focalPointDelta.dx / zoom;
      final dy = details.focalPointDelta.dy / zoom;
      if (dx.abs() > 0.5 || dy.abs() > 0.5) {
        _didMoveItem = true;
        notifier.moveElement(_draggingItemId!, dx, dy);
      }
    }
  }

  void _onScaleEnd(VenueBuilderNotifier notifier) {
    if ((_draggingItemId != null || _isScaling || _isMorphingPoint || _isRotating) && _didMoveItem) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _draggingItemId = null;
      _didMoveItem = false;
      _isScaling = false;
      _activeMorphPoint = -1;
      _isMorphingPoint = false;
      _isRotating = false;
      _isPanning = false;
      _isPinchZooming = false;
    });
  }

  /// Find shape by id in layout (sections first, then elements).
  ElementShape? _findShape(VenueBuilderState state, String id) {
    for (final s in state.layout.sections) {
      if (s.id == id) return s.shape;
    }
    for (final e in state.layout.elements) {
      if (e.id == id) return e.shape;
    }
    return null;
  }

  // ── Floating action bar actions ─────────────────────────────

  void _duplicateSelected(VenueBuilderState state, VenueBuilderNotifier notifier) {
    final id = state.selectedId;
    if (id == null) return;

    final newId = _generateId();
    const offset = 20.0;

    final section = state.layout.sections.where((s) => s.id == id).firstOrNull;
    if (section != null) {
      notifier.addSection(section.copyWith(
        id: newId,
        name: '${section.name} copy',
        shape: section.shape.copyWith(
          x: section.shape.x + offset,
          y: section.shape.y + offset,
        ),
      ));
      HapticFeedback.lightImpact();
      return;
    }

    final element = state.layout.elements.where((e) => e.id == id).firstOrNull;
    if (element != null) {
      notifier.addElement(element.copyWith(
        id: newId,
        label: '${element.label} copy',
        shape: element.shape.copyWith(
          x: element.shape.x + offset,
          y: element.shape.y + offset,
        ),
      ));
      HapticFeedback.lightImpact();
    }
  }

  void _deleteSelected(VenueBuilderState state, VenueBuilderNotifier notifier) {
    final id = state.selectedId;
    if (id == null) return;

    if (state.layout.sections.any((s) => s.id == id)) {
      notifier.removeSection(id);
    } else {
      notifier.removeElement(id);
    }
    HapticFeedback.mediumImpact();
  }

  // ── Place new item from drop ──────────────────────────────

  void _placeItem(Offset position, VenueBuilderTool tool, VenueBuilderNotifier notifier) {
    final id = _generateId();
    final shape = ElementShape(
      x: position.dx - 75,
      y: position.dy - 50,
      width: 150,
      height: 100,
    );

    switch (tool) {
      case VenueBuilderTool.seatedSection:
        notifier.addSection(VenueSection(
          id: id,
          name: 'Section ${_sectionLetter(notifier)}',
          type: SectionType.seated,
          shape: shape.copyWith(width: 200, height: 150),
          color: _randomSectionColor(),
        ));
      case VenueBuilderTool.standingArea:
        notifier.addSection(VenueSection(
          id: id,
          name: 'Standing ${_sectionLetter(notifier)}',
          type: SectionType.standing,
          shape: shape.copyWith(width: 180, height: 120),
          capacity: 100,
          color: '#10B981',
        ));
      case VenueBuilderTool.tableSection:
        notifier.addSection(VenueSection(
          id: id,
          name: 'Tables ${_sectionLetter(notifier)}',
          type: SectionType.table,
          shape: shape,
          tableConfig: const TableConfig(),
          color: '#F59E0B',
        ));
      case VenueBuilderTool.stage:
        notifier.addElement(VenueElement(
          id: id,
          type: ElementType.stage,
          label: 'Stage',
          shape: shape.copyWith(width: 250, height: 80),
        ));
      case VenueBuilderTool.bar:
        notifier.addElement(VenueElement(
          id: id,
          type: ElementType.bar,
          label: 'Bar',
          shape: shape.copyWith(width: 120, height: 50),
        ));
      case VenueBuilderTool.entrance:
        notifier.addElement(VenueElement(
          id: id,
          type: ElementType.entrance,
          label: 'Entrance',
          shape: shape.copyWith(width: 80, height: 40),
        ));
      case VenueBuilderTool.restroom:
        notifier.addElement(VenueElement(
          id: id,
          type: ElementType.restroom,
          label: 'Restroom',
          shape: shape.copyWith(width: 60, height: 60),
        ));
      case VenueBuilderTool.label:
        notifier.addElement(VenueElement(
          id: id,
          type: ElementType.label,
          label: 'Label',
          shape: shape.copyWith(width: 100, height: 30),
        ));
      case VenueBuilderTool.select:
        break;
    }

    HapticFeedback.lightImpact();
  }

  // ── Properties panel ──────────────────────────────────────

  Widget _buildPropertiesPanel(VenueBuilderState state, VenueBuilderNotifier notifier) {
    return PropertiesPanel(
      key: ValueKey(state.selectedId),
      layout: state.layout,
      selectedId: state.selectedId,
      onSectionUpdated: notifier.updateSection,
      onElementUpdated: notifier.updateElement,
      onDelete: () {
        if (state.selectedId != null) {
          if (state.layout.sections.any((s) => s.id == state.selectedId)) {
            notifier.removeSection(state.selectedId!);
          } else {
            notifier.removeElement(state.selectedId!);
          }
        }
      },
      onGenerateSeats: () {
        final section = state.layout.sections
            .where((s) => s.id == state.selectedId)
            .firstOrNull;
        if (section != null) {
          showDialog(
            context: context,
            builder: (_) => SeatGenerationDialog(
              sectionWidth: section.shape.width,
              sectionHeight: section.shape.height,
              onGenerate: (rows) {
                notifier.autoGenerateSeats(section.id, rows);
              },
            ),
          );
        }
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────

  String _sectionLetter(VenueBuilderNotifier notifier) {
    final count = ref.read(venueBuilderProvider(widget.venueId)).layout.sections.length;
    return String.fromCharCode('A'.codeUnitAt(0) + count);
  }

  String _generateId() => 'v${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  String _randomSectionColor() {
    const colors = ['#6366F1', '#EC4899', '#3B82F6', '#8B5CF6', '#06B6D4', '#EF4444'];
    return colors[Random().nextInt(colors.length)];
  }

  void _showMobileProperties(VenueBuilderState state, VenueBuilderNotifier notifier) {
    final isDesktop = MediaQuery.sizeOf(context).width > 800;
    if (isDesktop) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.7,
        expand: false,
        builder: (sheetCtx, controller) => Consumer(
          builder: (_, ref, __) {
            final liveState = ref.watch(venueBuilderProvider(widget.venueId));
            final liveNotifier = ref.read(venueBuilderProvider(widget.venueId).notifier);
            return SingleChildScrollView(
              controller: controller,
              child: _buildPropertiesPanelFrom(liveState, liveNotifier),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPropertiesPanelFrom(VenueBuilderState state, VenueBuilderNotifier notifier) {
    return PropertiesPanel(
      layout: state.layout,
      selectedId: state.selectedId,
      onSectionUpdated: notifier.updateSection,
      onElementUpdated: notifier.updateElement,
      onDelete: () {
        if (state.selectedId != null) {
          if (state.layout.sections.any((s) => s.id == state.selectedId)) {
            notifier.removeSection(state.selectedId!);
          } else {
            notifier.removeElement(state.selectedId!);
          }
        }
      },
      onGenerateSeats: () {
        final section = state.layout.sections
            .where((s) => s.id == state.selectedId)
            .firstOrNull;
        if (section != null) {
          showDialog(
            context: context,
            builder: (_) => SeatGenerationDialog(
              sectionWidth: section.shape.width,
              sectionHeight: section.shape.height,
              onGenerate: (rows) {
                notifier.autoGenerateSeats(section.id, rows);
              },
            ),
          );
        }
      },
    );
  }

  Future<void> _editVenueName(
    BuildContext context,
    VenueBuilderNotifier notifier,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.tr('venue_name')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: L.tr('name')),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(L.tr('save')),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      notifier.setVenueName(name);
    }
  }

  Future<void> _save(VenueBuilderNotifier notifier) async {
    setState(() => _isSaving = true);
    try {
      await notifier.save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L.tr('venue_saved')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ── Floating selection action bar ───────────────────────────

class _SelectionActionBar extends StatelessWidget {
  final bool isResizing;
  final bool isMorphing;
  final bool isRotating;
  final bool showProperties;
  final VoidCallback onEditShape;
  final VoidCallback onMorph;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback? onProperties;

  const _SelectionActionBar({
    required this.isResizing,
    required this.isMorphing,
    required this.isRotating,
    this.showProperties = false,
    required this.onEditShape,
    required this.onMorph,
    required this.onRotate,
    required this.onDuplicate,
    required this.onDelete,
    this.onProperties,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProperties)
              _ActionButton(
                icon: Icons.tune_outlined,
                label: 'Edit',
                onTap: onProperties!,
              ),
            _ActionButton(
              icon: Icons.open_with_outlined,
              label: 'Scale',
              isActive: isResizing,
              activeColor: const Color(0xFF10B981),
              onTap: onEditShape,
            ),
            _ActionButton(
              icon: Icons.pentagon_outlined,
              label: 'Morph',
              isActive: isMorphing,
              activeColor: const Color(0xFFEC4899),
              onTap: onMorph,
            ),
            _ActionButton(
              icon: Icons.rotate_right,
              label: 'Rotate',
              isActive: isRotating,
              activeColor: const Color(0xFF6366F1),
              onTap: onRotate,
            ),
            _ActionButton(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onTap: onDuplicate,
            ),
            _ActionButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              isDestructive: true,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDestructive;
  final Color? activeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isDestructive = false,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color iconColor;
    Color? bgColor;
    if (isActive) {
      iconColor = activeColor != null ? Colors.white : colorScheme.onPrimaryContainer;
      bgColor = activeColor?.withValues(alpha: 0.85) ?? colorScheme.primaryContainer;
    } else if (isDestructive) {
      iconColor = colorScheme.error;
      bgColor = null;
    } else {
      iconColor = colorScheme.onSurfaceVariant;
      bgColor = null;
    }

    return Material(
      color: bgColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
