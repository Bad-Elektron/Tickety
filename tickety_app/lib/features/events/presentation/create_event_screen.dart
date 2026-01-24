import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/services.dart';
import '../../auth/auth.dart';
import '../data/data.dart';
import '../models/event_tag.dart';
import '../widgets/tag_selector.dart';

/// Screen for creating a new event.
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final _cityController = TextEditingController();
  final _priceController = TextEditingController(text: '0');

  final _repository = SupabaseEventRepository();

  bool _isPublic = false;
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  int _ticketCount = 10;
  Set<EventTag> _selectedTags = {};

  // Track which step we're on (0 = basics, 1 = details, 2 = pricing)
  int _currentStep = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _subtitleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _createEvent() async {
    // Check authentication first
    if (!SupabaseService.instance.isAuthenticated) {
      final shouldLogin = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign In Required'),
          content: const Text(
            'You need to sign in to create events. Would you like to sign in now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign In'),
            ),
          ],
        ),
      );

      if (shouldLogin == true && mounted) {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        // If they didn't successfully log in, abort
        if (result != true && !SupabaseService.instance.isAuthenticated) {
          return;
        }
      } else {
        return;
      }
    }

    if (!mounted) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an event name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Combine date and time
      final eventDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      // Parse price (convert dollars to cents)
      final priceText = _priceController.text.replaceAll(RegExp(r'[^\d.]'), '');
      final priceDollars = double.tryParse(priceText) ?? 0;
      final priceCents = (priceDollars * 100).round();

      // Get category from first selected tag
      final category = _selectedTags.isNotEmpty
          ? _selectedTags.first.label
          : null;

      await _repository.createEventFromParams(
        title: _nameController.text.trim(),
        subtitle: _subtitleController.text.trim().isNotEmpty
            ? _subtitleController.text.trim()
            : 'An exciting event',
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        date: eventDateTime,
        venue: _venueController.text.trim().isNotEmpty
            ? _venueController.text.trim()
            : null,
        city: _cityController.text.trim().isNotEmpty
            ? _cityController.text.trim()
            : null,
        priceInCents: priceCents > 0 ? priceCents : null,
        category: category,
        noiseSeed: Random().nextInt(10000),
      );

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Event created successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create event: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _createEvent();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
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
        title: Text(_getStepTitle()),
        centerTitle: true,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
              )
            : null,
        actions: [
          _VisibilityToggle(
            isPublic: _isPublic,
            onChanged: (value) => setState(() => _isPublic = value),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Step indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _currentStep
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (i < 2) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildCurrentStep(theme, colorScheme),
                  ),
                ),
              ),
              // Navigation buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: FilledButton(
                  onPressed: _isLoading ? null : _nextStep,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _currentStep < 2 ? 'Continue' : 'Create Event',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Event Basics';
      case 1:
        return 'Location & Details';
      case 2:
        return 'Pricing & Category';
      default:
        return 'Create Event';
    }
  }

  Widget _buildCurrentStep(ThemeData theme, ColorScheme colorScheme) {
    switch (_currentStep) {
      case 0:
        return _buildBasicsStep(theme, colorScheme);
      case 1:
        return _buildDetailsStep(theme, colorScheme);
      case 2:
        return _buildPricingStep(theme, colorScheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBasicsStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('basics'),
      children: [
        const SizedBox(height: 32),
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
        const SizedBox(height: 16),
        TextField(
          controller: _subtitleController,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
          decoration: InputDecoration(
            hintText: 'A short tagline (optional)',
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 32),
        _DateTimePicker(
          date: _selectedDate,
          time: _selectedTime,
          formattedDate: _formatDate(_selectedDate),
          formattedTime: _formatTime(_selectedTime),
          onDateTap: _pickDate,
          onTimeTap: _pickTime,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildDetailsStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('details'),
      children: [
        const SizedBox(height: 32),
        Text(
          'Where is it happening?',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _venueController,
          decoration: const InputDecoration(
            labelText: 'Venue Name',
            hintText: 'e.g., Madison Square Garden',
            prefixIcon: Icon(Icons.place_outlined),
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _cityController,
          decoration: const InputDecoration(
            labelText: 'City',
            hintText: 'e.g., New York',
            prefixIcon: Icon(Icons.location_city_outlined),
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 32),
        Text(
          'Tell us more about it',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'What can attendees expect?',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildPricingStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('pricing'),
      children: [
        const SizedBox(height: 32),
        Text(
          'Set your ticket price',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
            hintText: '0.00',
            border: const OutlineInputBorder(),
            helperText: 'Leave as 0 for free events',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
        ),
        const SizedBox(height: 32),
        _TicketSelector(
          count: _ticketCount,
          onChanged: (value) => setState(() => _ticketCount = value),
        ),
        const SizedBox(height: 32),
        Text(
          'Choose a category',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TagSelector(
          selectedTags: _selectedTags,
          onTagsChanged: (tags) => setState(() => _selectedTags = tags),
          maxTags: 3,
        ),
        const SizedBox(height: 32),
      ],
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
