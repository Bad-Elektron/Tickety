import 'package:flutter/material.dart';

import '../models/event_tag.dart';
import '../widgets/tag_selector.dart';

/// Screen for creating a new event.
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _nameController = TextEditingController();
  bool _isPublic = true;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  int _ticketCount = 10;
  Set<EventTag> _selectedTags = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Event'),
        centerTitle: true,
        actions: [
          _VisibilityToggle(
            isPublic: _isPublic,
            onChanged: (value) => setState(() => _isPublic = value),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // Event name input - prominent and centered
                    Text(
                      'What\'s your event called?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Event Name',
                        hintStyle: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                    ),
                    const SizedBox(height: 32),
                    // Date & Time picker
                    _DateTimePicker(
                      date: _selectedDate,
                      time: _selectedTime,
                      formattedDate: _formatDate(_selectedDate),
                      formattedTime: _formatTime(_selectedTime),
                      onDateTap: _pickDate,
                      onTimeTap: _pickTime,
                    ),
                    const SizedBox(height: 32),
                    // Ticket count selector
                    _TicketSelector(
                      count: _ticketCount,
                      onChanged: (value) => setState(() => _ticketCount = value),
                    ),
                    const SizedBox(height: 32),
                    // Tag selector
                    TagSelector(
                      selectedTags: _selectedTags,
                      onTagsChanged: (tags) => setState(() => _selectedTags = tags),
                      maxTags: 5,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            // Create button - fixed at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _selectedTags.isEmpty
                            ? 'Coming soon'
                            : 'Tags: ${_selectedTags.map((t) => t.label).join(", ")}',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact toggle for app bar - public/private visibility.
class _VisibilityToggle extends StatelessWidget {
  final bool isPublic;
  final ValueChanged<bool> onChanged;

  const _VisibilityToggle({
    required this.isPublic,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isPublic ? Icons.public : Icons.lock_outline,
          size: 18,
        ),
        const SizedBox(width: 4),
        Switch(
          value: isPublic,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

/// Date and time picker with friendly UX.
class _DateTimePicker extends StatelessWidget {
  final DateTime date;
  final TimeOfDay time;
  final String formattedDate;
  final String formattedTime;
  final VoidCallback onDateTap;
  final VoidCallback onTimeTap;

  const _DateTimePicker({
    required this.date,
    required this.time,
    required this.formattedDate,
    required this.formattedTime,
    required this.onDateTap,
    required this.onTimeTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Text(
          'When is it happening?',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            // Date picker
            Expanded(
              flex: 3,
              child: _PickerCard(
                icon: Icons.calendar_today_rounded,
                label: formattedDate,
                onTap: onDateTap,
              ),
            ),
            const SizedBox(width: 12),
            // Time picker
            Expanded(
              flex: 2,
              child: _PickerCard(
                icon: Icons.access_time_rounded,
                label: formattedTime,
                onTap: onTimeTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tappable card for date/time selection.
class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ticket quantity selector with +/- buttons.
class _TicketSelector extends StatefulWidget {
  final int count;
  final ValueChanged<int> onChanged;
  static const int maxTickets = 100;
  static const int minTickets = 1;

  const _TicketSelector({
    required this.count,
    required this.onChanged,
  });

  @override
  State<_TicketSelector> createState() => _TicketSelectorState();
}

class _TicketSelectorState extends State<_TicketSelector> {
  bool _isEditing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.count.toString());
  }

  @override
  void didUpdateWidget(_TicketSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.count != widget.count) {
      _editController.text = widget.count.toString();
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.count.toString();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _finishEditing() {
    final value = int.tryParse(_editController.text) ?? widget.count;
    final clamped = value.clamp(
      _TicketSelector.minTickets,
      _TicketSelector.maxTickets,
    );
    widget.onChanged(clamped);
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Text(
          'How many tickets?',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decrease button with hold-to-repeat
              _HoldableCounterButton(
                icon: Icons.remove,
                onTap: widget.count > _TicketSelector.minTickets
                    ? () => widget.onChanged(widget.count - 1)
                    : null,
                onHoldTick: widget.count > _TicketSelector.minTickets
                    ? () {
                        if (widget.count > _TicketSelector.minTickets) {
                          widget.onChanged(widget.count - 1);
                        }
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              // Ticket count display - tappable to edit
              GestureDetector(
                onTap: _startEditing,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 100),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isEditing
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                      width: _isEditing ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _TicketIcon(size: 20),
                      const SizedBox(width: 10),
                      _isEditing
                          ? SizedBox(
                              width: 50,
                              child: TextField(
                                controller: _editController,
                                autofocus: true,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => _finishEditing(),
                                onTapOutside: (_) => _finishEditing(),
                              ),
                            )
                          : Text(
                              '${widget.count}',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Increase button with hold-to-repeat
              _HoldableCounterButton(
                icon: Icons.add,
                onTap: widget.count < _TicketSelector.maxTickets
                    ? () => widget.onChanged(widget.count + 1)
                    : null,
                onHoldTick: widget.count < _TicketSelector.maxTickets
                    ? () {
                        if (widget.count < _TicketSelector.maxTickets) {
                          widget.onChanged(widget.count + 1);
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Maximum ${_TicketSelector.maxTickets} tickets',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Counter button with hold-to-repeat functionality.
class _HoldableCounterButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onHoldTick;

  const _HoldableCounterButton({
    required this.icon,
    this.onTap,
    this.onHoldTick,
  });

  @override
  State<_HoldableCounterButton> createState() => _HoldableCounterButtonState();
}

class _HoldableCounterButtonState extends State<_HoldableCounterButton> {
  bool _isHolding = false;

  void _startHold() {
    if (widget.onHoldTick == null) return;
    _isHolding = true;
    _holdLoop();
  }

  void _stopHold() {
    _isHolding = false;
  }

  Future<void> _holdLoop() async {
    // Initial delay before repeat starts
    await Future.delayed(const Duration(milliseconds: 400));

    // Repeat while holding
    var interval = 150;
    while (_isHolding && mounted) {
      widget.onHoldTick?.call();
      await Future.delayed(Duration(milliseconds: interval));
      // Speed up over time
      if (interval > 50) interval -= 10;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = widget.onTap != null;

    return GestureDetector(
      onLongPressStart: isEnabled ? (_) => _startHold() : null,
      onLongPressEnd: isEnabled ? (_) => _stopHold() : null,
      onLongPressCancel: _stopHold,
      child: Material(
        color: isEnabled
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              widget.icon,
              color: isEnabled
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom ticket icon painter.
class _TicketIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const _TicketIcon({
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.primary;

    return CustomPaint(
      size: Size(size, size * 0.7),
      painter: _TicketIconPainter(color: iconColor),
    );
  }
}

class _TicketIconPainter extends CustomPainter {
  final Color color;

  _TicketIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final notchRadius = h * 0.15;
    final cornerRadius = h * 0.15;

    // Draw ticket shape with notches on sides
    final path = Path();

    // Start from top-left corner
    path.moveTo(cornerRadius, 0);
    path.lineTo(w - cornerRadius, 0);
    path.quadraticBezierTo(w, 0, w, cornerRadius);

    // Right side with notch
    path.lineTo(w, h * 0.35);
    path.arcToPoint(
      Offset(w, h * 0.65),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(w, h - cornerRadius);
    path.quadraticBezierTo(w, h, w - cornerRadius, h);

    // Bottom
    path.lineTo(cornerRadius, h);
    path.quadraticBezierTo(0, h, 0, h - cornerRadius);

    // Left side with notch
    path.lineTo(0, h * 0.65);
    path.arcToPoint(
      Offset(0, h * 0.35),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    canvas.drawPath(path, paint);

    // Draw dashed line
    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.04;

    final dashX = w * 0.35;
    const dashCount = 4;
    final dashHeight = h * 0.12;
    final dashGap = (h - dashHeight * dashCount) / (dashCount + 1);

    for (var i = 0; i < dashCount; i++) {
      final y = dashGap * (i + 1) + dashHeight * i;
      canvas.drawLine(
        Offset(dashX, y),
        Offset(dashX, y + dashHeight),
        dashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TicketIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
