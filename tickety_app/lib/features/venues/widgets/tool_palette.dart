import 'package:flutter/material.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/venue_provider.dart';

/// Data carried during a drag from the tool palette.
class ToolDragData {
  final VenueBuilderTool tool;
  final String label;
  final IconData icon;

  const ToolDragData({
    required this.tool,
    required this.label,
    required this.icon,
  });

  /// Default size of the item that will be placed.
  Size get defaultSize => switch (tool) {
    VenueBuilderTool.seatedSection => const Size(200, 150),
    VenueBuilderTool.standingArea => const Size(180, 120),
    VenueBuilderTool.tableSection => const Size(150, 100),
    VenueBuilderTool.stage => const Size(250, 80),
    VenueBuilderTool.bar => const Size(120, 50),
    VenueBuilderTool.entrance => const Size(80, 40),
    VenueBuilderTool.restroom => const Size(60, 60),
    VenueBuilderTool.label => const Size(100, 30),
    VenueBuilderTool.select => Size.zero,
  };

  /// Color used for the drag preview ghost.
  Color get previewColor => switch (tool) {
    VenueBuilderTool.seatedSection => const Color(0xFF6366F1),
    VenueBuilderTool.standingArea => const Color(0xFF10B981),
    VenueBuilderTool.tableSection => const Color(0xFFF59E0B),
    VenueBuilderTool.stage => const Color(0xFF8B5CF6),
    VenueBuilderTool.bar => const Color(0xFFF59E0B),
    VenueBuilderTool.entrance => const Color(0xFF10B981),
    VenueBuilderTool.restroom => const Color(0xFF3B82F6),
    VenueBuilderTool.label => const Color(0xFF6B7280),
    VenueBuilderTool.select => Colors.transparent,
  };
}

/// Tool palette for the venue builder. Non-select tools are draggable.
class ToolPalette extends StatelessWidget {
  final VenueBuilderTool activeTool;
  final ValueChanged<VenueBuilderTool> onToolChanged;
  final bool vertical;

  const ToolPalette({
    super.key,
    required this.activeTool,
    required this.onToolChanged,
    this.vertical = true,
  });

  static final _tools = [
    (VenueBuilderTool.select, Icons.near_me_outlined, L.tr('Select')),
    (VenueBuilderTool.seatedSection, Icons.event_seat_outlined, L.tr('Seated')),
    (VenueBuilderTool.standingArea, Icons.people_outline, L.tr('Standing')),
    (VenueBuilderTool.tableSection, Icons.table_restaurant_outlined, L.tr('Tables')),
    (VenueBuilderTool.stage, Icons.music_note_outlined, L.tr('Stage')),
    (VenueBuilderTool.bar, Icons.local_bar_outlined, L.tr('Bar')),
    (VenueBuilderTool.entrance, Icons.door_front_door_outlined, L.tr('Entry')),
    (VenueBuilderTool.restroom, Icons.wc_outlined, L.tr('WC')),
    (VenueBuilderTool.label, Icons.text_fields, L.tr('Label')),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final children = _tools.map((tool) {
      final (toolType, icon, label) = tool;
      final isActive = activeTool == toolType;
      final isSelect = toolType == VenueBuilderTool.select;

      final buttonContent = SizedBox(
        width: vertical ? 62 : null,
        height: vertical ? 62 : 48,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: vertical ? 0 : 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              if (vertical) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.w600 : null,
                    color: isActive
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      final dragData = ToolDragData(tool: toolType, label: label, icon: icon);

      // Select tool is just a button, everything else is draggable
      Widget toolWidget;
      if (isSelect) {
        toolWidget = Tooltip(
          message: label,
          child: Material(
            color: isActive ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onToolChanged(toolType),
              child: buttonContent,
            ),
          ),
        );
      } else {
        toolWidget = Tooltip(
          message: '$label (${L.tr('drag onto canvas')})',
          child: Draggable<ToolDragData>(
            data: dragData,
            feedback: _DragFeedback(data: dragData),
            childWhenDragging: Material(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              child: Opacity(opacity: 0.4, child: buttonContent),
            ),
            onDragStarted: () => onToolChanged(toolType),
            child: Material(
              color: isActive ? colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onToolChanged(toolType),
                child: buttonContent,
              ),
            ),
          ),
        );
      }

      return toolWidget;
    }).toList();

    if (vertical) {
      // Generous left padding keeps the palette well clear of system edge gestures
      final leftSafe = MediaQuery.of(context).padding.left;
      return Container(
        width: 88 + leftSafe,
        padding: EdgeInsets.only(left: leftSafe + 16, top: 8, bottom: 8, right: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(children: children),
        ),
      );
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      ),
    );
  }
}

/// The ghost widget shown while dragging a tool from the palette.
class _DragFeedback extends StatelessWidget {
  final ToolDragData data;

  const _DragFeedback({required this.data});

  @override
  Widget build(BuildContext context) {
    final size = data.defaultSize;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: size.width * 0.6,
        height: size.height * 0.6,
        decoration: BoxDecoration(
          color: data.previewColor.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: data.previewColor.withValues(alpha: 0.8),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: data.previewColor.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(
                data.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
