import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/services.dart';
import '../../../core/utils/utils.dart';
import '../../../shared/widgets/limit_reached_banner.dart';
import '../../../shared/widgets/widgets.dart' show PlacesAutocompleteField;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../auth/auth.dart';
import '../../profile/presentation/verification_screen.dart';
import '../../subscriptions/presentation/subscription_screen.dart';
import '../../venues/models/venue.dart';
import '../../venues/models/venue_section.dart';
import '../../venues/presentation/venue_builder_screen.dart';
import '../../venues/widgets/venue_picker_sheet.dart';
import '../data/data.dart';
import '../models/event_model.dart';
import '../models/event_series.dart';
import '../models/event_tag.dart';
import '../../../core/state/app_state.dart';
import '../../subscriptions/models/tier_limits.dart';

/// Screen for creating a new event, or editing an existing one.
class CreateEventScreen extends ConsumerStatefulWidget {
  final EventModel? editingEvent;

  const CreateEventScreen({super.key, this.editingEvent});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
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

/// Represents a ticket type with name, price, quantity, and description.
class _TicketType {
  String name;
  String description;
  double price;
  int quantity;
  String? venueSectionId;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController priceController;
  final TextEditingController quantityController;

  _TicketType({
    required this.name,
    this.description = '',
    this.price = 0,
    this.quantity = 10,
    this.venueSectionId,
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

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _descriptionController = TextEditingController();

  final _repository = SupabaseEventRepository();

  bool get isEditing => widget.editingEvent != null;

  // Google Places selection
  PlaceDetails? _selectedPlace;

  bool _isPublic = true;
  bool _isLoading = false;
  bool _hideLocation = false;

  // Virtual event fields
  String _eventFormat = 'in_person';
  final _virtualUrlController = TextEditingController();
  final _virtualPasswordController = TextEditingController();
  bool _nftEnabled = true;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);

  // Venue selection (enterprise only)
  Venue? _selectedVenue;

  // Recurring event state
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.weekly;
  DateTime? _seriesEndDate;
  Set<EventTag> _selectedTags = {};

  // Similarity detection
  List<Map<String, dynamic>> _similarEvents = [];
  bool _checkingSimilarity = false;

  // Ticket types
  late List<_TicketType> _ticketTypes;

  // Track which step we're on (0 = design, 1 = details, 2 = tags, 3 = tickets)
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

    final event = widget.editingEvent;
    if (event != null) {
      // Pre-populate fields from existing event
      _nameController.text = event.title;
      _subtitleController.text = event.subtitle;
      _descriptionController.text = event.description ?? '';
      _selectedDate = event.date;
      _selectedTime = TimeOfDay(hour: event.date.hour, minute: event.date.minute);
      _isPublic = !event.isPrivate;
      _hideLocation = event.hideLocation;
      _nftEnabled = event.nftEnabled;
      _noiseSeed = event.noiseSeed;

      // Resolve tags from IDs
      _selectedTags = event.tags
          .map((id) {
            try {
              return PredefinedTags.all.firstWhere((t) => t.id == id);
            } catch (_) {
              return EventTag.custom(id);
            }
          })
          .toSet();

      // Build PlaceDetails stub from event location data
      if (event.venue != null || event.formattedAddress != null) {
        _selectedPlace = PlaceDetails(
          placeId: '',
          formattedAddress: event.formattedAddress ?? event.displayLocation ?? '',
          name: event.venue ?? '',
          lat: event.latitude ?? 0,
          lng: event.longitude ?? 0,
          city: event.city,
          country: event.country,
        );
      }

      // Virtual event fields
      _eventFormat = event.eventFormat;
      if (event.virtualEventUrl != null) {
        _virtualUrlController.text = event.virtualEventUrl!;
      }
      if (event.virtualEventPassword != null) {
        _virtualPasswordController.text = event.virtualEventPassword!;
      }

      // Start with empty ticket types; will be loaded async
      _ticketTypes = [];
      _loadExistingTicketTypes(event.id);
    } else {
      _noiseSeed = Random().nextInt(10000);
      // Initialize with default General Admission ticket
      _ticketTypes = [_TicketType(name: _predefinedTicketNames[0])];
    }

    _fromColorIndex = Random().nextInt(_colorSchemes.length);
    _toColorIndex = (_fromColorIndex + 1) % _colorSchemes.length;
  }

  Future<void> _loadExistingTicketTypes(String eventId) async {
    try {
      final types = await _repository.getEventTicketTypes(eventId);
      if (mounted) {
        setState(() {
          _ticketTypes = types.map((t) => _TicketType(
            name: t.name,
            description: t.description ?? '',
            price: t.priceInCents / 100.0,
            quantity: t.maxQuantity ?? 0,
          )).toList();
          if (_ticketTypes.isEmpty) {
            _ticketTypes = [_TicketType(name: _predefinedTicketNames[0])];
          }
        });
      }
    } catch (_) {
      // If ticket types can't be loaded, keep the default
      if (mounted && _ticketTypes.isEmpty) {
        setState(() {
          _ticketTypes = [_TicketType(name: _predefinedTicketNames[0])];
        });
      }
    }
  }

  @override
  void dispose() {
    _noiseAnimationTimer?.cancel();
    _nameController.dispose();
    _subtitleController.dispose();
    _descriptionController.dispose();
    _virtualUrlController.dispose();
    _virtualPasswordController.dispose();
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

    // Check if total capacity exceeds 250 and organizer is unverified
    final totalCapacity = _ticketTypes.fold<int>(0, (sum, tt) {
      final qty = int.tryParse(tt.quantityController.text) ?? 0;
      return sum + qty;
    });

    if (totalCapacity >= 250) {
      try {
        final userId = SupabaseService.instance.currentUser?.id;
        if (userId != null) {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('identity_verification_status')
              .eq('id', userId)
              .single();

          final status = profile['identity_verification_status'] as String? ?? 'none';
          if (status != 'verified' && mounted) {
            final shouldVerify = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                icon: const Icon(Icons.shield_outlined, size: 40),
                title: const Text('Verification Required'),
                content: const Text(
                  'Events with 250+ total ticket capacity require identity verification '
                  'to protect ticket buyers. Please verify your identity to continue.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Get Verified'),
                  ),
                ],
              ),
            );

            if (shouldVerify == true && mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VerificationScreen()),
              );
            }
            return;
          }
        }
      } catch (_) {
        // Column may not exist yet — allow event creation (DB trigger will catch it)
      }
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
      debugPrint('Converting ${_ticketTypes.length} ticket types');
      final ticketTypeInputs = _ticketTypes.map((tt) {
        final priceDollars = double.tryParse(tt.priceController.text) ?? 0;
        final priceCents = (priceDollars * 100).round();
        final quantity = int.tryParse(tt.quantityController.text);
        debugPrint('Ticket type: ${tt.nameController.text}, price: $priceCents cents, qty: $quantity');
        return TicketTypeInput(
          name: Validators.sanitize(tt.nameController.text).isNotEmpty
              ? Validators.sanitize(tt.nameController.text)
              : 'General Admission',
          description: Validators.sanitize(tt.descriptionController.text).isNotEmpty
              ? Validators.sanitize(tt.descriptionController.text)
              : null,
          priceCents: priceCents,
          maxQuantity: quantity,
          venueSectionId: tt.venueSectionId,
        );
      }).toList();
      debugPrint('Created ${ticketTypeInputs.length} TicketTypeInput objects');

      // Get all selected tag IDs
      final tagIds = _selectedTags.map((tag) => tag.id).toList();

      // Sanitize all text inputs to prevent XSS/injection
      final sanitizedTitle = Validators.sanitize(_nameController.text);
      final sanitizedSubtitle = Validators.sanitize(_subtitleController.text);
      final sanitizedDescription = Validators.sanitize(_descriptionController.text);

      // Use place details if selected, otherwise null
      final venue = _selectedPlace?.name;
      final city = _selectedPlace?.city;
      final country = _selectedPlace?.country;

      // Use the lowest NON-ZERO ticket price as the event's display price
      final nonZeroPrices = ticketTypeInputs
          .where((t) => t.priceCents > 0)
          .map((t) => t.priceCents);
      final lowestPrice = ticketTypeInputs.isEmpty
          ? null
          : nonZeroPrices.isEmpty
              ? 0
              : nonZeroPrices.reduce((a, b) => a < b ? a : b);

      if (isEditing) {
        // Update existing event
        final virtualUrl = _virtualUrlController.text.trim().isNotEmpty
            ? Validators.sanitize(_virtualUrlController.text.trim())
            : null;
        final virtualPassword = _virtualPasswordController.text.trim().isNotEmpty
            ? _virtualPasswordController.text.trim()
            : null;

        final updatedEvent = widget.editingEvent!.copyWith(
          title: sanitizedTitle,
          subtitle: sanitizedSubtitle.isNotEmpty
              ? sanitizedSubtitle
              : 'An exciting event',
          description: sanitizedDescription.isNotEmpty
              ? sanitizedDescription
              : null,
          date: eventDateTime,
          venue: venue,
          city: city,
          country: country,
          tags: tagIds,
          noiseSeed: _noiseSeed,
          hideLocation: _hideLocation,
          isPrivate: !_isPublic,
          nftEnabled: _nftEnabled,
          latitude: _selectedPlace?.lat,
          longitude: _selectedPlace?.lng,
          formattedAddress: _selectedPlace?.formattedAddress,
          priceInCents: lowestPrice,
          eventFormat: _eventFormat,
          virtualEventUrl: virtualUrl,
          virtualEventPassword: virtualPassword,
        );

        await _repository.updateEvent(updatedEvent);
        await _repository.updateEventTicketTypes(
          widget.editingEvent!.id,
          ticketTypeInputs,
        );
      } else if (_isRecurring) {
        // Create recurring event series
        final templateSnapshot = <String, dynamic>{
          'title': sanitizedTitle,
          'subtitle': sanitizedSubtitle.isNotEmpty
              ? sanitizedSubtitle
              : 'An exciting event',
          'description': sanitizedDescription.isNotEmpty
              ? sanitizedDescription
              : null,
          'venue': venue,
          'city': city,
          'country': country,
          'tags': tagIds,
          'category': tagIds.isNotEmpty ? tagIds.first : null,
          'noise_seed': _noiseSeed,
          'hide_location': _hideLocation,
          'is_private': !_isPublic,
          'nft_enabled': _nftEnabled,
          'price_in_cents': lowestPrice,
          'currency': 'USD',
          'cash_sales_enabled': true,
          'location': _selectedPlace?.formattedAddress ?? (venue != null && city != null ? '$venue, $city' : venue ?? city),
          if (_selectedPlace?.lat != null) 'latitude': _selectedPlace!.lat,
          if (_selectedPlace?.lng != null) 'longitude': _selectedPlace!.lng,
          if (_selectedPlace?.formattedAddress != null)
            'formatted_address': _selectedPlace!.formattedAddress,
          if (_eventFormat != 'in_person') 'event_format': _eventFormat,
          if (_virtualUrlController.text.trim().isNotEmpty)
            'virtual_event_url': Validators.sanitize(_virtualUrlController.text.trim()),
          if (_virtualPasswordController.text.trim().isNotEmpty)
            'virtual_event_password': _virtualPasswordController.text.trim(),
        };

        final ticketTypesSnapshot = ticketTypeInputs.asMap().entries.map((e) => {
          'name': e.value.name,
          'description': e.value.description,
          'price_cents': e.value.priceCents,
          'max_quantity': e.value.maxQuantity,
          'sort_order': e.key,
        }).toList();

        // Compute recurrence_day
        int recurrenceDay;
        if (_recurrenceType == RecurrenceType.monthly) {
          recurrenceDay = _selectedDate.day;
        } else {
          // Convert Dart weekday (1=Mon..7=Sun) to PostgreSQL DOW (0=Sun..6=Sat)
          recurrenceDay = _selectedDate.weekday % 7;
        }

        final timeStr =
            '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';

        await _repository.createEventSeries(
          recurrenceType: _recurrenceType,
          recurrenceDay: recurrenceDay,
          recurrenceTime: timeStr,
          startsAt: eventDateTime,
          endsAt: _seriesEndDate,
          templateSnapshot: templateSnapshot,
          ticketTypesSnapshot: ticketTypesSnapshot,
        );
      } else {
        // Create single event
        await _repository.createEventWithTicketTypes(
          title: sanitizedTitle,
          subtitle: sanitizedSubtitle.isNotEmpty
              ? sanitizedSubtitle
              : 'An exciting event',
          description: sanitizedDescription.isNotEmpty
              ? sanitizedDescription
              : null,
          date: eventDateTime,
          venue: venue,
          city: city,
          country: country,
          ticketTypes: ticketTypeInputs,
          tags: tagIds,
          noiseSeed: _noiseSeed,
          hideLocation: _hideLocation,
          isPrivate: !_isPublic,
          nftEnabled: _nftEnabled,
          latitude: _selectedPlace?.lat,
          longitude: _selectedPlace?.lng,
          formattedAddress: _selectedPlace?.formattedAddress,
          venueId: _selectedVenue?.id,
          eventFormat: _eventFormat,
          virtualEventUrl: _virtualUrlController.text.trim().isNotEmpty
              ? Validators.sanitize(_virtualUrlController.text.trim())
              : null,
          virtualEventPassword: _virtualPasswordController.text.trim().isNotEmpty
              ? _virtualPasswordController.text.trim()
              : null,
        );
      }

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(isEditing
                    ? 'Event updated successfully!'
                    : _isRecurring
                        ? 'Recurring event created!'
                        : 'Event created successfully!'),
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
            content: Text(isEditing
                ? 'Failed to update event: $e'
                : 'Failed to create event: $e'),
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
    if (_currentStep < 3) {
      // Check for similar events when leaving step 1 (details)
      if (_currentStep == 1 && _nameController.text.trim().isNotEmpty) {
        _checkSimilarEvents();
      }
      setState(() => _currentStep++);
    } else {
      _createEvent();
    }
  }

  Future<void> _checkSimilarEvents() async {
    if (_checkingSimilarity) return;
    setState(() => _checkingSimilarity = true);

    try {
      final results = await _repository.findSimilarEvents(
        title: _nameController.text.trim(),
        venue: _selectedPlace?.name,
        date: _selectedDate,
      );
      if (mounted) {
        setState(() {
          _similarEvents = results;
          _checkingSimilarity = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingSimilarity = false);
      }
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
              // Labeled step indicator
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                child: _StepIndicator(
                  currentStep: _currentStep,
                  labels: const ['Design', 'Details', 'Tags', 'Tickets'],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
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
                          _currentStep < 3
                              ? 'Continue'
                              : isEditing
                                  ? 'Update Event'
                                  : 'Create Event',
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

  Widget _buildCurrentStep(ThemeData theme, ColorScheme colorScheme) {
    switch (_currentStep) {
      case 0:
        return _buildDesignStep(theme, colorScheme);
      case 1:
        return _buildDetailsStep(theme, colorScheme);
      case 2:
        return _buildTagStep(theme, colorScheme);
      case 3:
        return _buildTicketsStep(theme, colorScheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDesignStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('design'),
      children: [
        // Private event info banner
        if (!_isPublic) ...[
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Private event \u2014 a unique invite code will be generated. Share it so people can find your event.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildDetailsStep(ThemeData theme, ColorScheme colorScheme) {
    final isVirtual = _eventFormat == 'virtual';
    final isHybrid = _eventFormat == 'hybrid';
    final showLocation = !isVirtual; // in_person or hybrid
    final showVirtualFields = isVirtual || isHybrid;

    return Column(
      key: const ValueKey('details'),
      children: [
        const SizedBox(height: 8),
        // Event format selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Event Format',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'in_person',
                      label: Text('In-Person'),
                      icon: Icon(Icons.location_on_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 'virtual',
                      label: Text('Virtual'),
                      icon: Icon(Icons.videocam_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 'hybrid',
                      label: Text('Hybrid'),
                      icon: Icon(Icons.groups_outlined, size: 18),
                    ),
                  ],
                  selected: {_eventFormat},
                  onSelectionChanged: (value) {
                    setState(() => _eventFormat = value.first);
                  },
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Location card (shown for in_person and hybrid)
        if (showLocation) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                // Header row: location icon + "Location" + Spacer + toggle
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Location',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _HideLocationToggle(
                      value: _hideLocation,
                      onChanged: (value) => setState(() => _hideLocation = value),
                    ),
                  ],
                ),
                // Secret location hint (conditional)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _hideLocation
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _SecretLocationHint(),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                // Location (Google Places autocomplete)
                PlacesAutocompleteField(
                  onPlaceSelected: (details) {
                    setState(() => _selectedPlace = details);
                  },
                  onCleared: () {
                    setState(() => _selectedPlace = null);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Virtual meeting fields (shown for virtual and hybrid)
        if (showVirtualFields) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.videocam_outlined, size: 20, color: Colors.cyan),
                    const SizedBox(width: 8),
                    Text(
                      'Meeting Details',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Hidden until 1 hour before the event starts.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _virtualUrlController,
                  decoration: InputDecoration(
                    labelText: 'Meeting URL',
                    hintText: 'https://zoom.us/j/...',
                    prefixIcon: const Icon(Icons.link, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _virtualPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Meeting Password (optional)',
                    hintText: 'Enter password if required',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Description card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notes_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Description',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe your event (optional)',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Date & Time card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Date & Time',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Date picker
                  Expanded(
                    flex: 3,
                    child: _PickerCard(
                      icon: Icons.calendar_today_rounded,
                      label: _formatDate(_selectedDate),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Time picker
                  Expanded(
                    flex: 2,
                    child: _PickerCard(
                      icon: Icons.access_time_rounded,
                      label: _formatTime(_selectedTime),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Venue Layout card (enterprise only)
        if (TierLimits.canUseVenueBuilder(
          ref.watch(subscriptionProvider).effectiveTier,
        ))
          _buildVenueCard(theme, colorScheme),
        const SizedBox(height: 16),
        // Repeat / Recurring card (not shown when editing)
        if (!isEditing)
          _buildRecurrenceCard(theme, colorScheme),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildVenueCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.map_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Venue Layout',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_selectedVenue != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selectedVenue = null),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedVenue != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.map, size: 20, color: colorScheme.onPrimaryContainer),
              ),
              title: Text(_selectedVenue!.name),
              subtitle: Text(
                '${_selectedVenue!.layout.totalCapacity} capacity',
                style: theme.textTheme.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VenueBuilderScreen(venueId: _selectedVenue!.id),
                    ),
                  );
                },
                child: const Text('Edit'),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => VenuePickerSheet(
                    onVenueSelected: (venue) {
                      setState(() => _selectedVenue = venue);
                    },
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Select Venue'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecurrenceCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Header with toggle
          Row(
            children: [
              Icon(Icons.repeat_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Repeat',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _isRecurring,
                onChanged: (value) => setState(() => _isRecurring = value),
              ),
            ],
          ),

          // Expanded recurrence options
          if (_isRecurring) ...[
            const SizedBox(height: 12),
            // Frequency selector
            SegmentedButton<RecurrenceType>(
              segments: const [
                ButtonSegment(value: RecurrenceType.daily, label: Text('Daily')),
                ButtonSegment(value: RecurrenceType.weekly, label: Text('Weekly')),
                ButtonSegment(value: RecurrenceType.biweekly, label: Text('2 Wks')),
                ButtonSegment(value: RecurrenceType.monthly, label: Text('Monthly')),
              ],
              selected: {_recurrenceType},
              onSelectionChanged: (set) =>
                  setState(() => _recurrenceType = set.first),
              style: SegmentedButton.styleFrom(
                textStyle: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),

            // Info text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _recurrenceInfoText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // End date option
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ends',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Never'),
                  selected: _seriesEndDate == null,
                  onSelected: (_) => setState(() => _seriesEndDate = null),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    _seriesEndDate != null
                        ? _formatDate(_seriesEndDate!)
                        : 'Pick date',
                  ),
                  selected: _seriesEndDate != null,
                  onSelected: (_) => _pickSeriesEndDate(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String get _recurrenceInfoText {
    final dayName = _getDayName(_selectedDate.weekday);
    return switch (_recurrenceType) {
      RecurrenceType.daily => 'Repeats every day at ${_formatTime(_selectedTime)}',
      RecurrenceType.weekly => 'Repeats every $dayName at ${_formatTime(_selectedTime)}',
      RecurrenceType.biweekly => 'Repeats every other $dayName at ${_formatTime(_selectedTime)}',
      RecurrenceType.monthly => 'Repeats on the ${_selectedDate.day}${_ordinalSuffix(_selectedDate.day)} of each month',
    };
  }

  String _getDayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  String _ordinalSuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    return switch (day % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }

  Future<void> _pickSeriesEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _seriesEndDate ?? _selectedDate.add(const Duration(days: 90)),
      firstDate: _selectedDate.add(const Duration(days: 1)),
      lastDate: _selectedDate.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _seriesEndDate = picked);
    }
  }

  Widget _buildTagStep(ThemeData theme, ColorScheme colorScheme) {
    final tier = ref.watch(currentTierProvider);

    return Column(
      key: const ValueKey('tags'),
      children: [
        // Similarity warning
        if (_similarEvents.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Similar events found',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Events with similar names already exist. Please make sure you\'re not creating a duplicate.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                ..._similarEvents.take(3).map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '\u2022 ${e['title']}${e['venue'] != null ? ' at ${e['venue']}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )),
              ],
            ),
          ),
        _TagStep(
          selectedTags: _selectedTags,
          onTagsChanged: (tags) => setState(() => _selectedTags = tags),
          userTier: tier,
        ),
      ],
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
    final limitCheck = ref.read(canAddTicketTypeProvider(_ticketTypes.length));
    if (!limitCheck.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(limitCheck.message ?? 'Ticket type limit reached'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Upgrade',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SubscriptionScreen(),
              ),
            ),
          ),
        ),
      );
      return;
    }
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
    final limitCheck = ref.watch(canAddTicketTypeProvider(_ticketTypes.length));
    final venueSections = _selectedVenue?.layout.sections ?? [];

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
              venueSections: venueSections,
              canRemove: _ticketTypes.length > 1,
              onRemove: () => _removeTicketType(index),
              onNameChanged: (value) => ticketType.name = value,
              onDescriptionChanged: (value) => ticketType.description = value,
              onPriceChanged: (value) => ticketType.price = double.tryParse(value) ?? 0,
              onQuantityChanged: (value) => ticketType.quantity = int.tryParse(value) ?? 10,
              onSectionChanged: (sectionId) => setState(() => ticketType.venueSectionId = sectionId),
            ),
          );
        }),
        // Limit banner
        if (limitCheck.isAtLimit) ...[
          const SizedBox(height: 4),
          LimitReachedBanner(
            message: 'Ticket type limit reached (${limitCheck.limitText})',
          ),
          const SizedBox(height: 8),
        ],
        // Add ticket type button
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: limitCheck.isAtLimit ? null : _addTicketType,
          icon: const Icon(Icons.add, size: 20),
          label: Text('Add Ticket Type (${limitCheck.limitText})'),
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
  final List<VenueSection> venueSections;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onDescriptionChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String> onQuantityChanged;
  final ValueChanged<String?> onSectionChanged;

  const _TicketTypeRow({
    required this.ticketType,
    this.venueSections = const [],
    required this.canRemove,
    required this.onRemove,
    required this.onNameChanged,
    required this.onDescriptionChanged,
    required this.onPriceChanged,
    required this.onQuantityChanged,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          Divider(
            height: 20,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          // Price and quantity row with labels above
          Row(
            children: [
              // Price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ticketType.priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        hintText: '0',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      onChanged: onPriceChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Quantity
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantity',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ticketType.quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '10',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: onQuantityChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Venue section picker (only when venue is linked)
          if (venueSections.isNotEmpty) ...[
            Divider(
              height: 20,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 16,
                  color: ticketType.venueSectionId != null
                      ? Colors.teal
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: ticketType.venueSectionId,
                    decoration: InputDecoration(
                      labelText: 'Venue Section',
                      labelStyle: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.teal,
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No section (general)'),
                      ),
                      ...venueSections.map((section) {
                        return DropdownMenuItem<String?>(
                          value: section.id,
                          child: Text(
                            '${section.name} (${section.seatCount} seats)',
                          ),
                        );
                      }),
                    ],
                    onChanged: onSectionChanged,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Labeled step indicator with circles, connecting lines, and labels.
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> labels;

  const _StepIndicator({
    required this.currentStep,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        for (int i = 0; i < labels.length; i++) ...[
          // Step circle + label
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < currentStep
                        ? colorScheme.primary
                        : i == currentStep
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                    border: i > currentStep
                        ? Border.all(
                            color: colorScheme.outlineVariant,
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Center(
                    child: i < currentStep
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: colorScheme.onPrimary,
                          )
                        : Text(
                            '${i + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: i == currentStep
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                // Label
                Text(
                  labels[i],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: i == currentStep
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: i == currentStep ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Connecting line between circles
          if (i < labels.length - 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: SizedBox(
                width: 24,
                child: Divider(
                  thickness: 1.5,
                  color: i < currentStep
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => onChanged(!isPublic),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isPublic
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPublic
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPublic ? Icons.public : Icons.lock_outline,
              size: 16,
              color: isPublic
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              isPublic ? 'Public' : 'Private',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isPublic
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.swap_horiz,
              size: 14,
              color: isPublic
                  ? colorScheme.primary.withValues(alpha: 0.6)
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 16,
            color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            value ? 'Secret location' : 'Public location',
            style: theme.textTheme.labelSmall?.copyWith(
              color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 24,
            child: FittedBox(
              child: Switch(
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecretLocationHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          Icons.lock_outlined,
          size: 14,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Text(
          'Location revealed after purchase',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
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

/// Tag selection step with browsable category and vibe tag grids.
class _TagStep extends StatefulWidget {
  final Set<EventTag> selectedTags;
  final ValueChanged<Set<EventTag>> onTagsChanged;
  final AccountTier userTier;

  const _TagStep({
    required this.selectedTags,
    required this.onTagsChanged,
    required this.userTier,
  });

  @override
  State<_TagStep> createState() => _TagStepState();
}

class _TagStepState extends State<_TagStep> {
  final _customTagController = TextEditingController();

  @override
  void dispose() {
    _customTagController.dispose();
    super.dispose();
  }

  int get _maxTags => TierLimits.getMaxTags(widget.userTier);
  bool get _canUseCustomTags => TierLimits.canUseCustomTags(widget.userTier);
  bool get _isAtLimit => widget.selectedTags.length >= _maxTags;

  void _toggleTag(EventTag tag) {
    final newTags = Set<EventTag>.from(widget.selectedTags);
    if (newTags.contains(tag)) {
      newTags.remove(tag);
    } else {
      if (_isAtLimit) return;
      newTags.add(tag);
    }
    widget.onTagsChanged(newTags);
  }

  void _removeTag(EventTag tag) {
    final newTags = Set<EventTag>.from(widget.selectedTags)..remove(tag);
    widget.onTagsChanged(newTags);
  }

  void _submitCustomTag() {
    final text = _customTagController.text.trim();
    if (text.isEmpty || _isAtLimit) return;
    final existing = PredefinedTags.all.where(
      (t) => t.label.toLowerCase() == text.toLowerCase(),
    );
    final tag = existing.isNotEmpty ? existing.first : EventTag.custom(text);
    final newTags = Set<EventTag>.from(widget.selectedTags)..add(tag);
    widget.onTagsChanged(newTags);
    _customTagController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        // Header with count
        Row(
          children: [
            Icon(Icons.label_outline, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Tags',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${widget.selectedTags.length}/$_maxTags',
              style: theme.textTheme.labelMedium?.copyWith(
                color: _isAtLimit
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose tags that describe your event',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        // Selected tags with close buttons
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
          const SizedBox(height: 16),
        ],

        // Limit banner
        if (_isAtLimit) ...[
          LimitReachedBanner(
            message: 'Tag limit reached (${widget.selectedTags.length}/$_maxTags)',
          ),
          const SizedBox(height: 12),
        ],

        // Category tags grid
        _TagGroupHeader(title: 'Category'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PredefinedTags.categories.map((tag) {
            final isSelected = widget.selectedTags.contains(tag);
            final tagColor = tag.color ?? colorScheme.primary;
            return _TagChip(
              tag: tag,
              isSelected: isSelected,
              isDisabled: !isSelected && _isAtLimit,
              tagColor: tagColor,
              onTap: () => _toggleTag(tag),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Vibe tags grid
        _TagGroupHeader(title: 'Vibe'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PredefinedTags.vibes.map((tag) {
            final isSelected = widget.selectedTags.contains(tag);
            final tagColor = tag.color ?? colorScheme.primary;
            return _TagChip(
              tag: tag,
              isSelected: isSelected,
              isDisabled: !isSelected && _isAtLimit,
              tagColor: tagColor,
              onTap: () => _toggleTag(tag),
            );
          }).toList(),
        ),

        // Custom tag input (Pro+ only)
        const SizedBox(height: 20),
        if (_canUseCustomTags) ...[
          TextField(
            controller: _customTagController,
            decoration: InputDecoration(
              hintText: 'Create custom tag...',
              prefixIcon: const Icon(Icons.add, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.check, size: 20),
                onPressed: _isAtLimit ? null : _submitCustomTag,
              ),
            ),
            enabled: !_isAtLimit,
            style: theme.textTheme.bodyMedium,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submitCustomTag(),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.diamond_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Upgrade to Pro for custom tags',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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

/// Header for a group of tags.
class _TagGroupHeader extends StatelessWidget {
  final String title;

  const _TagGroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A single tappable tag chip for the grid.
class _TagChip extends StatelessWidget {
  final EventTag tag;
  final bool isSelected;
  final bool isDisabled;
  final Color tagColor;
  final VoidCallback onTap;

  const _TagChip({
    required this.tag,
    required this.isSelected,
    required this.isDisabled,
    required this.tagColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? tagColor.withValues(alpha: 0.15)
              : colorScheme.surfaceContainerHighest.withValues(alpha: isDisabled ? 0.2 : 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? tagColor.withValues(alpha: 0.6)
                : colorScheme.outlineVariant.withValues(alpha: isDisabled ? 0.15 : 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag.icon != null) ...[
              Icon(
                tag.icon,
                size: 14,
                color: isSelected
                    ? tagColor
                    : (isDisabled
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                        : colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              tag.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? tagColor
                    : (isDisabled
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                        : colorScheme.onSurfaceVariant),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
