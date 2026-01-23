import 'package:flutter/material.dart';

import '../models/event_tag.dart';

/// Widget for selecting event tags with predefined options and custom input.
class TagSelector extends StatefulWidget {
  const TagSelector({
    super.key,
    required this.selectedTags,
    required this.onTagsChanged,
    this.maxTags = 5,
  });

  /// Currently selected tags.
  final Set<EventTag> selectedTags;

  /// Callback when tags change.
  final ValueChanged<Set<EventTag>> onTagsChanged;

  /// Maximum number of tags allowed.
  final int maxTags;

  @override
  State<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<TagSelector> {
  final _customTagController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showInput = false;

  @override
  void dispose() {
    _customTagController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleTag(EventTag tag) {
    final newTags = Set<EventTag>.from(widget.selectedTags);
    if (newTags.contains(tag)) {
      newTags.remove(tag);
    } else if (newTags.length < widget.maxTags) {
      newTags.add(tag);
    }
    widget.onTagsChanged(newTags);
  }

  void _addCustomTag() {
    final text = _customTagController.text.trim();
    if (text.isEmpty) return;
    if (widget.selectedTags.length >= widget.maxTags) return;

    // Check if tag already exists
    final existingTag = PredefinedTags.all.where(
      (t) => t.label.toLowerCase() == text.toLowerCase(),
    );

    final tag = existingTag.isNotEmpty
        ? existingTag.first
        : EventTag.custom(text);

    if (!widget.selectedTags.contains(tag)) {
      final newTags = Set<EventTag>.from(widget.selectedTags)..add(tag);
      widget.onTagsChanged(newTags);
    }

    _customTagController.clear();
    setState(() => _showInput = false);
  }

  void _removeTag(EventTag tag) {
    final newTags = Set<EventTag>.from(widget.selectedTags)..remove(tag);
    widget.onTagsChanged(newTags);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tags',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${widget.selectedTags.length}/${widget.maxTags}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Selected tags
        if (widget.selectedTags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedTags.map((tag) {
              return _SelectedTagChip(
                tag: tag,
                onRemove: () => _removeTag(tag),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Custom tag input
        if (_showInput)
          _CustomTagInput(
            controller: _customTagController,
            focusNode: _focusNode,
            onSubmit: _addCustomTag,
            onCancel: () {
              _customTagController.clear();
              setState(() => _showInput = false);
            },
          )
        else if (widget.selectedTags.length < widget.maxTags)
          _AddCustomTagButton(
            onTap: () {
              setState(() => _showInput = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _focusNode.requestFocus();
              });
            },
          ),

        const SizedBox(height: 16),

        // Predefined tags by category
        ...PredefinedTags.grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.value.map((tag) {
                  final isSelected = widget.selectedTags.contains(tag);
                  final isDisabled = !isSelected &&
                      widget.selectedTags.length >= widget.maxTags;

                  return _TagChip(
                    tag: tag,
                    isSelected: isSelected,
                    isDisabled: isDisabled,
                    onTap: isDisabled ? null : () => _toggleTag(tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          );
        }),
      ],
    );
  }
}

class _SelectedTagChip extends StatelessWidget {
  final EventTag tag;
  final VoidCallback onRemove;

  const _SelectedTagChip({
    required this.tag,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tagColor = tag.color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tagColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag.icon != null) ...[
            Icon(tag.icon, size: 16, color: tagColor),
            const SizedBox(width: 6),
          ],
          Text(
            tag.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: tagColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 16,
                color: tagColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final EventTag tag;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _TagChip({
    required this.tag,
    required this.isSelected,
    required this.isDisabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tagColor = tag.color ?? colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? tagColor.withValues(alpha: 0.15)
              : isDisabled
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? tagColor.withValues(alpha: 0.5)
                : isDisabled
                    ? colorScheme.outline.withValues(alpha: 0.1)
                    : colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag.icon != null) ...[
              Icon(
                tag.icon,
                size: 16,
                color: isSelected
                    ? tagColor
                    : isDisabled
                        ? colorScheme.onSurface.withValues(alpha: 0.3)
                        : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              tag.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isSelected
                    ? tagColor
                    : isDisabled
                        ? colorScheme.onSurface.withValues(alpha: 0.3)
                        : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCustomTagButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCustomTagButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Add custom tag',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTagInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _CustomTagInput({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Enter tag name...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            color: colorScheme.onSurfaceVariant,
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 20),
            onPressed: onSubmit,
            visualDensity: VisualDensity.compact,
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
