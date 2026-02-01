import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/services/services.dart';
import '../../../core/utils/utils.dart';
import '../../auth/auth.dart';
import '../data/data.dart';
import '../data/supabase_event_repository.dart' show TicketTypeInput;
import '../models/event_tag.dart';

/// Screen for creating a new event.
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

/// Predefined ticket type names in order of suggestion.
const _predefinedTicketNames = [
  'General Admission',
  'VIP',
  'Early Bird',
  'Student',
  'Group',
  'Premium',
  'Standing',
  'Seated',
  'Backstage',
  'All Access',
];

/// Subscription tiers for promotion access.
enum SubscriptionTier { free, pro, enterprise }

/// Promotion package for event marketing.
class PromotionPackage {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final double priceEur;
  final SubscriptionTier includedIn; // Tier where this is free
  final Color color;

  const PromotionPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.priceEur,
    required this.includedIn,
    required this.color,
  });
}

/// Available promotion packages.
const _promotionPackages = [
  PromotionPackage(
    id: 'featured',
    name: 'Featured',
    description: 'Appear in the Featured carousel on home screen for 7 days',
    icon: Icons.star_rounded,
    priceEur: 15,
    includedIn: SubscriptionTier.pro,
    color: Color(0xFFF59E0B),
  ),
  PromotionPackage(
    id: 'spotlight',
    name: 'Spotlight',
    description: 'Highlighted badge + priority in search results for 14 days',
    icon: Icons.lightbulb_rounded,
    priceEur: 25,
    includedIn: SubscriptionTier.pro,
    color: Color(0xFF8B5CF6),
  ),
  PromotionPackage(
    id: 'push_notification',
    name: 'Push Blast',
    description: 'Send a push notification to users in your city',
    icon: Icons.notifications_active_rounded,
    priceEur: 35,
    includedIn: SubscriptionTier.enterprise,
    color: Color(0xFFEF4444),
  ),
  PromotionPackage(
    id: 'social_boost',
    name: 'Social Boost',
    description: 'We promote your event on our social media channels',
    icon: Icons.share_rounded,
    priceEur: 45,
    includedIn: SubscriptionTier.enterprise,
    color: Color(0xFF3B82F6),
  ),
];

/// Represents a ticket type with name, price, quantity, and description.
class _TicketType {
  String name;
  String description;
  double price;
  int quantity;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController priceController;
  final TextEditingController quantityController;

  _TicketType({
    required this.name,
    this.description = '',
    this.price = 0,
    this.quantity = 10,
  })  : nameController = TextEditingController(text: name),
        descriptionController = TextEditingController(text: description),
        priceController = TextEditingController(text: price > 0 ? price.toString() : '0'),
        quantityController = TextEditingController(text: quantity.toString());

  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    quantityController.dispose();
  }
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final _cityController = TextEditingController();

  final _repository = SupabaseEventRepository();

  bool _isPublic = false;
  bool _isLoading = false;
  bool _hideLocation = false;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  Set<EventTag> _selectedTags = {};

  // Ticket types
  late List<_TicketType> _ticketTypes;

  // Promotions
  Set<String> _selectedPromotions = {};
  // TODO: Get actual subscription tier from user profile
  final SubscriptionTier _userTier = SubscriptionTier.free;

  // Track which step we're on (0 = basics, 1 = details, 2 = pricing)
  int _currentStep = 0;

  // Noise preview state
  late int _noiseSeed;
  Timer? _noiseAnimationTimer;
  double _noiseTimeOffset = 0;
  double _noiseColorProgress = 0;
  int _fromColorIndex = 0;
  int _toColorIndex = 1;
  bool _isGeneratingNoise = false;

  // Color schemes for noise animation
  static const List<List<Color>> _colorSchemes = [
    [Color(0xFFFF6B6B), Color(0xFF4ECDC4), Color(0xFF45B7D1), Color(0xFFDDA0DD)],
    [Color(0xFFf093fb), Color(0xFFf5576c), Color(0xFFffecd2)],
    [Color(0xFF0077B6), Color(0xFF00B4D8), Color(0xFF90E0EF), Color(0xFFCAF0F8)],
    [Color(0xFF667eea), Color(0xFF764ba2), Color(0xFFf093fb)],
    [Color(0xFFFFE66D), Color(0xFFFF6B6B), Color(0xFF4ECDC4)],
    [Color(0xFF2C3E50), Color(0xFF3498DB), Color(0xFF1ABC9C)],
    [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFFF1C40F)],
    [Color(0xFF8E44AD), Color(0xFF3498DB), Color(0xFF1ABC9C), Color(0xFFE74C3C)],
  ];

  @override
  void initState() {
    super.initState();
    _noiseSeed = Random().nextInt(10000);
    _fromColorIndex = Random().nextInt(_colorSchemes.length);
    _toColorIndex = (_fromColorIndex + 1) % _colorSchemes.length;
    // Initialize with default General Admission ticket
    _ticketTypes = [_TicketType(name: _predefinedTicketNames[0])];
  }

  @override
  void dispose() {
    _noiseAnimationTimer?.cancel();
    _nameController.dispose();
    _subtitleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    for (final ticketType in _ticketTypes) {
      ticketType.dispose();
    }
    super.dispose();
  }

  // Interpolate between two color lists
  List<Color> _lerpColors(List<Color> from, List<Color> to, double t) {
    final maxLen = max(from.length, to.length);
    final result = <Color>[];
    for (var i = 0; i < maxLen; i++) {
      final fromColor = from[i % from.length];
      final toColor = to[i % to.length];
      result.add(Color.lerp(fromColor, toColor, t)!);
    }
    return result;
  }

  List<Color> get _currentNoiseColors {
    final from = _colorSchemes[_fromColorIndex % _colorSchemes.length];
    final to = _colorSchemes[_toColorIndex % _colorSchemes.length];
    return _lerpColors(from, to, _noiseColorProgress);
  }

  void _startNoiseGeneration() {
    setState(() => _isGeneratingNoise = true);
    HapticFeedback.lightImpact();

    _noiseAnimationTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      setState(() {
        _noiseTimeOffset += 0.25;
        _noiseColorProgress += 0.003;
        if (_noiseColorProgress >= 1.0) {
          _noiseColorProgress = 0;
          _fromColorIndex = _toColorIndex;
          _toColorIndex = (_toColorIndex + 1) % _colorSchemes.length;
        }
      });
    });
  }

  void _stopNoiseGeneration() {
    _noiseAnimationTimer?.cancel();
    HapticFeedback.mediumImpact();

    // Just stop generating - keep the current visual state exactly as is
    setState(() {
      _isGeneratingNoise = false;
    });
  }

  Future<void> _pickImage() async {
    // TODO: Implement image picker
    // For now, show a message that this feature is coming
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image upload coming soon! Using generated art for now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

    if (Validators.sanitize(_nameController.text).isEmpty) {
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

      // Convert ticket types to TicketTypeInput list
      final ticketTypeInputs = _ticketTypes.map((tt) {
        final priceDollars = double.tryParse(tt.priceController.text) ?? 0;
        final priceCents = (priceDollars * 100).round();
        final quantity = int.tryParse(tt.quantityController.text);
        return TicketTypeInput(
          name: Validators.sanitize(tt.nameController.text).isNotEmpty
              ? Validators.sanitize(tt.nameController.text)
              : 'General Admission',
          description: Validators.sanitize(tt.descriptionController.text).isNotEmpty
              ? Validators.sanitize(tt.descriptionController.text)
              : null,
          priceCents: priceCents,
          maxQuantity: quantity,
        );
      }).toList();

      // Get all selected tag IDs
      final tagIds = _selectedTags.map((tag) => tag.id).toList();

      // Sanitize all text inputs to prevent XSS/injection
      final sanitizedTitle = Validators.sanitize(_nameController.text);
      final sanitizedSubtitle = Validators.sanitize(_subtitleController.text);
      final sanitizedDescription = Validators.sanitize(_descriptionController.text);
      final sanitizedVenue = Validators.sanitize(_venueController.text);
      final sanitizedCity = Validators.sanitize(_cityController.text);

      await _repository.createEventWithTicketTypes(
        title: sanitizedTitle,
        subtitle: sanitizedSubtitle.isNotEmpty
            ? sanitizedSubtitle
            : 'An exciting event',
        description: sanitizedDescription.isNotEmpty
            ? sanitizedDescription
            : null,
        date: eventDateTime,
        venue: sanitizedVenue.isNotEmpty ? sanitizedVenue : null,
        city: sanitizedCity.isNotEmpty ? sanitizedCity : null,
        ticketTypes: ticketTypeInputs,
        tags: tagIds,
        noiseSeed: _noiseSeed,
        hideLocation: _hideLocation,
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
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
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
              // Step indicator dots
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= _currentStep
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
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
        return _buildPromotionStep(theme, colorScheme);
      case 2:
        return _buildTicketsStep(theme, colorScheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBasicsStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('basics'),
      children: [
        const SizedBox(height: 8),
        // Event name input at the top
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
        // Noise preview card with press-and-hold to generate
        _NoisePreviewCard(
          colors: _currentNoiseColors,
          timeOffset: _noiseTimeOffset,
          seed: _noiseSeed,
          isGenerating: _isGeneratingNoise,
          onLongPressStart: _startNoiseGeneration,
          onLongPressEnd: _stopNoiseGeneration,
          onUploadTap: _pickImage,
        ),
        const SizedBox(height: 8),
        // Tagline below the cover
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
        const SizedBox(height: 16),
        // Venue and City
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _venueController,
                decoration: const InputDecoration(
                  labelText: 'Venue',
                  hintText: 'e.g., Madison Square Garden',
                  prefixIcon: Icon(Icons.place_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  hintText: 'e.g., New York',
                  prefixIcon: Icon(Icons.location_city_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Hide location toggle
        _HideLocationToggle(
          value: _hideLocation,
          onChanged: (value) => setState(() => _hideLocation = value),
        ),
        const SizedBox(height: 16),
        // Description
        TextFormField(
          controller: _descriptionController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'What can attendees expect?',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 24),
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

  Widget _buildPromotionStep(ThemeData theme, ColorScheme colorScheme) {
    return _PromotionStep(
      key: const ValueKey('promotion'),
      selectedTags: _selectedTags,
      onTagsChanged: (tags) => setState(() => _selectedTags = tags),
      selectedPromotions: _selectedPromotions,
      onPromotionsChanged: (promos) => setState(() => _selectedPromotions = promos),
      userTier: _userTier,
    );
  }

  String _getNextTicketName() {
    final usedNames = _ticketTypes.map((t) => t.name).toSet();
    for (final name in _predefinedTicketNames) {
      if (!usedNames.contains(name)) {
        return name;
      }
    }
    // Fallback when all predefined names are used
    return 'Ticket ${_ticketTypes.length + 1}';
  }

  void _addTicketType() {
    setState(() {
      _ticketTypes.add(_TicketType(name: _getNextTicketName()));
    });
  }

  void _removeTicketType(int index) {
    if (_ticketTypes.length <= 1) return; // Keep at least one
    setState(() {
      _ticketTypes[index].dispose();
      _ticketTypes.removeAt(index);
    });
  }

  Widget _buildTicketsStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('tickets'),
      children: [
        const SizedBox(height: 16),
        // Ticket types list
        ...List.generate(_ticketTypes.length, (index) {
          final ticketType = _ticketTypes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _TicketTypeRow(
              ticketType: ticketType,
              canRemove: _ticketTypes.length > 1,
              onRemove: () => _removeTicketType(index),
              onNameChanged: (value) => ticketType.name = value,
              onDescriptionChanged: (value) => ticketType.description = value,
              onPriceChanged: (value) => ticketType.price = double.tryParse(value) ?? 0,
              onQuantityChanged: (value) => ticketType.quantity = int.tryParse(value) ?? 10,
            ),
          );
        }),
        // Add ticket type button
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addTicketType,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add Ticket Type'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Price 0 = free entry',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Row widget for a single ticket type with name, description, price, and quantity.
class _TicketTypeRow extends StatelessWidget {
  final _TicketType ticketType;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onDescriptionChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String> onQuantityChanged;

  const _TicketTypeRow({
    required this.ticketType,
    required this.canRemove,
    required this.onRemove,
    required this.onNameChanged,
    required this.onDescriptionChanged,
    required this.onPriceChanged,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Name row with remove button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ticketType.nameController,
                  decoration: const InputDecoration(
                    hintText: 'Ticket name',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: onNameChanged,
                ),
              ),
              if (canRemove)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          // Description field
          TextField(
            controller: ticketType.descriptionController,
            decoration: InputDecoration(
              hintText: 'Description (optional)',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            onChanged: onDescriptionChanged,
          ),
          const SizedBox(height: 8),
          // Price and quantity row
          Row(
            children: [
              // Price
              Expanded(
                child: TextField(
                  controller: ticketType.priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    hintText: '0',
                    labelText: 'Price',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  onChanged: onPriceChanged,
                ),
              ),
              const SizedBox(width: 12),
              // Quantity
              Expanded(
                child: TextField(
                  controller: ticketType.quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    hintText: '10',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: onQuantityChanged,
                ),
              ),
            ],
          ),
        ],
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

/// Toggle for hiding location until ticket purchase.
class _HideLocationToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _HideLocationToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 20,
              color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secret Location',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: value ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Reveal location only after ticket purchase',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
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

/// Noise preview card with press-and-hold to generate new patterns.
class _NoisePreviewCard extends StatelessWidget {
  final List<Color> colors;
  final double timeOffset;
  final int seed;
  final bool isGenerating;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;
  final VoidCallback onUploadTap;

  const _NoisePreviewCard({
    required this.colors,
    required this.timeOffset,
    required this.seed,
    required this.isGenerating,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onUploadTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        GestureDetector(
          onLongPressStart: (_) => onLongPressStart(),
          onLongPressEnd: (_) => onLongPressEnd(),
          child: Stack(
            children: [
              // Noise card
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.3),
                      blurRadius: isGenerating ? 24 : 12,
                      spreadRadius: isGenerating ? 4 : 0,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CustomPaint(
                    size: const Size(double.infinity, 180),
                    painter: _EventNoisePainter(
                      colors: colors,
                      timeOffset: timeOffset,
                      seed: seed,
                    ),
                  ),
                ),
              ),
              // Upload photo button - fades out while generating
              Positioned(
                bottom: 12,
                right: 12,
                child: AnimatedOpacity(
                  opacity: isGenerating ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: isGenerating ? null : onUploadTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Upload',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Hint text below the cover
        const SizedBox(height: 8),
        Text(
          'Hold to generate new art',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for event noise preview.
class _EventNoisePainter extends CustomPainter {
  final List<Color> colors;
  final double timeOffset;
  final int seed;

  _EventNoisePainter({
    required this.colors,
    required this.timeOffset,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final config = NoiseConfig(
      colors: colors,
      seed: seed,
      scale: 0.015,
      octaves: 3,
      persistence: 0.7,
    );
    final generator = NoiseGenerator(config: config);
    final paint = Paint();

    // Slowly rotating direction
    final angle = timeOffset * 0.004;
    final dirX = cos(angle);
    final dirY = sin(angle);

    const pixelSize = 4.0;
    final cols = (size.width / pixelSize).ceil();
    final rows = (size.height / pixelSize).ceil();

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final color = generator.getColorAt(
          x + timeOffset * dirX,
          y + timeOffset * dirY,
        );
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            x * pixelSize,
            y * pixelSize,
            pixelSize,
            pixelSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EventNoisePainter oldDelegate) =>
      oldDelegate.timeOffset != timeOffset ||
      oldDelegate.colors != colors ||
      oldDelegate.seed != seed;
}

/// Promotion step with tags and marketing packages.
class _PromotionStep extends StatefulWidget {
  final Set<EventTag> selectedTags;
  final ValueChanged<Set<EventTag>> onTagsChanged;
  final Set<String> selectedPromotions;
  final ValueChanged<Set<String>> onPromotionsChanged;
  final SubscriptionTier userTier;

  const _PromotionStep({
    super.key,
    required this.selectedTags,
    required this.onTagsChanged,
    required this.selectedPromotions,
    required this.onPromotionsChanged,
    required this.userTier,
  });

  @override
  State<_PromotionStep> createState() => _PromotionStepState();
}

class _PromotionStepState extends State<_PromotionStep> {
  final _tagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  List<EventTag> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _tagController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final query = _tagController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final matches = PredefinedTags.all.where((tag) {
      if (widget.selectedTags.contains(tag)) return false;
      return tag.label.toLowerCase().contains(query);
    }).toList();
    setState(() => _suggestions = matches.take(5).toList());
  }

  void _addTag(EventTag tag) {
    if (widget.selectedTags.length >= 3) return;
    final newTags = Set<EventTag>.from(widget.selectedTags)..add(tag);
    widget.onTagsChanged(newTags);
    _tagController.clear();
    setState(() => _suggestions = []);
  }

  void _removeTag(EventTag tag) {
    final newTags = Set<EventTag>.from(widget.selectedTags)..remove(tag);
    widget.onTagsChanged(newTags);
  }

  void _submitCustomTag() {
    final text = _tagController.text.trim();
    if (text.isEmpty || widget.selectedTags.length >= 3) return;
    final existing = PredefinedTags.all.where(
      (t) => t.label.toLowerCase() == text.toLowerCase(),
    );
    final tag = existing.isNotEmpty ? existing.first : EventTag.custom(text);
    _addTag(tag);
  }

  void _togglePromotion(String id) {
    final newPromos = Set<String>.from(widget.selectedPromotions);
    if (newPromos.contains(id)) {
      newPromos.remove(id);
    } else {
      newPromos.add(id);
    }
    widget.onPromotionsChanged(newPromos);
  }

  bool _isIncludedFree(PromotionPackage pkg) {
    if (widget.userTier == SubscriptionTier.enterprise) return true;
    if (widget.userTier == SubscriptionTier.pro &&
        pkg.includedIn == SubscriptionTier.pro) return true;
    return false;
  }

  double _calculateTotal() {
    double total = 0;
    for (final pkg in _promotionPackages) {
      if (widget.selectedPromotions.contains(pkg.id) && !_isIncludedFree(pkg)) {
        total += pkg.priceEur;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = _calculateTotal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        // Tags section
        Text(
          'Tags',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        // Selected tags
        if (widget.selectedTags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedTags.map((tag) {
              final tagColor = tag.color ?? colorScheme.primary;
              return Container(
                padding: const EdgeInsets.only(left: 10, right: 2, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tagColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tag.icon != null) ...[
                      Icon(tag.icon, size: 16, color: tagColor),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      tag.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tagColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    InkWell(
                      onTap: () => _removeTag(tag),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 14, color: tagColor),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        // Tag input
        if (widget.selectedTags.length < 3)
          TextField(
            controller: _tagController,
            focusNode: _tagFocusNode,
            decoration: InputDecoration(
              hintText: 'Add tags...',
              prefixIcon: const Icon(Icons.label_outline, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixText: '${widget.selectedTags.length}/3',
            ),
            style: theme.textTheme.bodyMedium,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submitCustomTag(),
          ),
        // Suggestions
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _suggestions.map((tag) {
              final tagColor = tag.color ?? colorScheme.primary;
              return GestureDetector(
                onTap: () => _addTag(tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tag.icon != null) ...[
                        Icon(tag.icon, size: 14, color: tagColor),
                        const SizedBox(width: 4),
                      ],
                      Text(tag.label, style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: 24),
        // Promotion packages section
        Row(
          children: [
            Icon(Icons.campaign_rounded, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Boost Your Event',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Get more visibility with promotion packages',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        // Promotion cards
        ..._promotionPackages.map((pkg) {
          final isSelected = widget.selectedPromotions.contains(pkg.id);
          final isFree = _isIncludedFree(pkg);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PromotionCard(
              package: pkg,
              isSelected: isSelected,
              isFree: isFree,
              userTier: widget.userTier,
              onTap: () => _togglePromotion(pkg.id),
            ),
          );
        }),

        // Total and subscription upsell
        if (total > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Promotion total',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '€${total.toStringAsFixed(0)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.diamond_outlined, size: 18, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Get Pro for €12/mo and promotions are included free!',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Card for a single promotion package.
class _PromotionCard extends StatelessWidget {
  final PromotionPackage package;
  final bool isSelected;
  final bool isFree;
  final SubscriptionTier userTier;
  final VoidCallback onTap;

  const _PromotionCard({
    required this.package,
    required this.isSelected,
    required this.isFree,
    required this.userTier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? package.color.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? package.color.withValues(alpha: 0.6)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: package.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(package.icon, size: 20, color: package.color),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        package.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isFree) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'FREE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    package.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Price / checkbox
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isFree)
                  Text(
                    '€${package.priceEur.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? package.color : colorScheme.onSurface,
                    ),
                  )
                else
                  Text(
                    '€${package.priceEur.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isSelected ? package.color : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? package.color : colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
