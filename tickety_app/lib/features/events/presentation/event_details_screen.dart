import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/providers.dart';
import '../../../core/services/services.dart';
import '../../../shared/widgets/widgets.dart';
import '../../payments/models/payment.dart';
import '../../payments/presentation/checkout_screen.dart';
import '../../payments/presentation/resale_browse_screen.dart';
import '../../payments/presentation/seller_onboarding_screen.dart';
import '../../venues/models/models.dart';
import '../../venues/presentation/seat_picker_screen.dart';
import '../../venues/widgets/venue_mini_map.dart';
import '../../waitlist/presentation/waitlist_sheet.dart';
import '../data/supabase_event_repository.dart';
import '../models/event_model.dart';
import '../models/event_series.dart';
import '../models/ticket_availability.dart';
import '../models/ticket_type.dart';
import 'report_event_sheet.dart';

/// Session-level dedup set for event views (avoids redundant inserts).
final _recentlyViewedEvents = <String>{};

/// Provider that logs a view for engagement analytics (once per session).
final _logEventViewProvider =
    FutureProvider.autoDispose.family<void, String>((ref, eventId) async {
  if (_recentlyViewedEvents.contains(eventId)) return;
  _recentlyViewedEvents.add(eventId);
  final repo = ref.read(eventRepositoryProvider);
  await repo.logEventView(eventId, source: 'direct');
});

/// Provider that checks if the current user owns a ticket for a given event.
final _userHasTicketProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, eventId) async {
  final userId = SupabaseService.instance.currentUser?.id;
  if (userId == null) return false;

  final response = await SupabaseService.instance.client
      .from('tickets')
      .select('id')
      .eq('event_id', eventId)
      .eq('sold_by', userId)
      .limit(1);

  return (response as List).isNotEmpty;
});

/// Provider for ticket availability (official + resale counts).
/// Uses autoDispose so it refetches when the screen is re-entered.
final _ticketAvailabilityProvider =
    FutureProvider.autoDispose.family<TicketAvailability, String>((ref, eventId) async {
  final eventRepo = ref.watch(eventRepositoryProvider);
  final resaleRepo = ref.watch(resaleRepositoryProvider);

  // Fetch both counts in parallel
  final results = await Future.wait([
    eventRepo.getTicketAvailability(eventId),
    resaleRepo.getResaleListingCount(eventId),
  ]);

  final availability = results[0] as TicketAvailability;
  final resaleCount = results[1] as int;

  return availability.copyWith(resaleCount: resaleCount);
});

/// Screen displaying detailed information about an event.
class EventDetailsScreen extends ConsumerWidget {
  final EventModel event;

  const EventDetailsScreen({
    super.key,
    required this.event,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Log view for engagement analytics (fire-and-forget, session deduped)
    ref.watch(_logEventViewProvider(event.id));

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();
    final availabilityAsync = ref.watch(_ticketAvailabilityProvider(event.id));
    final hasTicket = ref.watch(_userHasTicketProvider(event.id)).valueOrNull ?? false;
    final locationText = event.getDisplayLocation(hasTicket: hasTicket);
    final showMapLink = event.hasCoordinates && (!event.hideLocation || hasTicket);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header with gradient
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: () => _shareEvent(context),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GradientBackground(colors: config.colors),
                  // Dark overlay for readability
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x80000000),
                        ],
                      ),
                    ),
                  ),
                  // Category badge
                  if (event.category != null)
                    Positioned(
                      top: 100,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x4DFFFFFF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          event.category!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Private event badge
                  if (event.isPrivate) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Invite Only',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Virtual/Hybrid event chip
                  if (event.hasVirtualComponent) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam,
                            size: 14,
                            color: Colors.cyan[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.isVirtual ? 'Virtual Event' : 'Hybrid Event',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.cyan[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Recurring event chip
                  if (event.isPartOfSeries) ...[
                    GestureDetector(
                      onTap: () => _showAllDatesSheet(context, ref, event.seriesId!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.repeat,
                              size: 14,
                              color: Colors.deepPurple[400],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${RecurrenceType.fromString(event.recurrenceType)?.label ?? "Recurring"} event',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.deepPurple[400],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '\u00B7 See all dates',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.deepPurple[300],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Title
                  Text(
                    event.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    event.subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // Tags row
                  if (event.autoBadges.isNotEmpty || event.eventTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Auto-badges first
                          ...event.autoBadges.map((badge) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: badge.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: badge.color.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(badge.icon, size: 14, color: badge.color),
                                  const SizedBox(width: 4),
                                  Text(
                                    badge.label,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: badge.color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                          // Regular tags
                          ...event.eventTags.map((tag) {
                            final tagColor = tag.color ?? colorScheme.primary;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: tagColor.withValues(alpha: 0.1),
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
                                    Text(
                                      tag.label,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: tagColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Info cards
                  _InfoCard(
                    icon: Icons.calendar_today_rounded,
                    title: 'Date & Time',
                    value: _formatDateTime(event.date),
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  // Location card (hidden for virtual-only events)
                  if (locationText != null && !event.isVirtual)
                    _InfoCard(
                      icon: event.hideLocation && !hasTicket
                          ? Icons.lock_outlined
                          : Icons.location_on_outlined,
                      title: 'Location',
                      value: locationText,
                      color: colorScheme.tertiary,
                      onTap: showMapLink
                          ? () async {
                              final url = Uri.parse(event.mapsUrl!);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            }
                          : null,
                    ),
                  // Virtual event card
                  if (event.hasVirtualComponent) ...[
                    if (locationText != null && !event.isVirtual)
                      const SizedBox(height: 12),
                    _InfoCard(
                      icon: Icons.videocam_outlined,
                      title: event.isVirtual ? 'Online Event' : 'Virtual Access',
                      value: event.virtualLocked && hasTicket && event.virtualEventUrl != null
                          ? 'Meeting link available — check your ticket!'
                          : event.virtualLocked
                              ? 'Link revealed to ticket holders'
                              : 'Link reveals 1 hour before event',
                      color: Colors.cyan,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Official Tickets
                  availabilityAsync.when(
                    loading: () => _InfoCard(
                      icon: Icons.confirmation_number_outlined,
                      title: 'Official Tickets',
                      value: 'Loading...',
                      color: colorScheme.secondary,
                    ),
                    error: (_, __) => _InfoCard(
                      icon: Icons.confirmation_number_outlined,
                      title: 'Official Tickets',
                      value: 'Available',
                      color: colorScheme.secondary,
                    ),
                    data: (availability) => _InfoCard(
                      icon: Icons.confirmation_number_outlined,
                      title: 'Official Tickets',
                      value: availability.officialAvailabilityText,
                      color: colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Resale Tickets
                  availabilityAsync.when(
                    loading: () => _InfoCard(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Resale Tickets',
                      value: 'Loading...',
                      color: colorScheme.tertiary,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (availability) => availability.resaleCount > 0
                        ? _InfoCard(
                            icon: Icons.swap_horiz_rounded,
                            title: 'Resale Tickets',
                            value: availability.resaleAvailabilityText,
                            color: colorScheme.tertiary,
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 24),
                  // Organizer info
                  if (event.organizerName != null || event.organizerHandle != null) ...[
                    Text(
                      'Organizer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_outline,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        event.organizerName ?? 'Organizer',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (event.organizerVerified) ...[
                                      const SizedBox(width: 6),
                                      const VerifiedBadge(size: 16),
                                    ],
                                  ],
                                ),
                                if (event.organizerHandle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    event.organizerHandle!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Report button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showReportSheet(context),
                        icon: Icon(
                          Icons.flag_outlined,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        label: Text(
                          'Report this event',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Description
                  if (event.description != null) ...[
                    Text(
                      'About',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      event.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      // Bottom bar with price and buy button
      bottomNavigationBar: _BottomBuyBar(
        priceInCents: event.priceInCents,
        onBuyPressed: () {
          _showBuyTicketSheet(context);
        },
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    final day = date.day;
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$weekday, $month $day at $hour:$minute $period';
  }

  void _shareEvent(BuildContext context) {
    final location = event.displayLocation;
    final dateStr = _formatDateTime(event.date);
    final buffer = StringBuffer();
    buffer.writeln('Check out "${event.title}" on Tickety!');
    if (location != null) buffer.writeln('📍 $location');
    buffer.writeln('📅 $dateStr');
    if (event.isPrivate && event.inviteCode != null) {
      buffer.writeln('🔒 Invite code: ${event.inviteCode}');
    }
    Share.share(buffer.toString());
  }

  void _showReportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReportEventSheet(eventId: event.id),
    );
  }

  void _showBuyTicketSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BuyTicketSheet(event: event),
    );
  }

  void _showAllDatesSheet(BuildContext context, WidgetRef ref, String seriesId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AllDatesSheet(
        seriesId: seriesId,
        currentEventId: event.id,
      ),
    );
  }
}

/// Information card with icon, title, and value.
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.onTap,
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
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.open_in_new,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
      ),
      ),
    );
  }
}

/// Bottom bar with price display and buy button.
class _BottomBuyBar extends StatelessWidget {
  final int? priceInCents;
  final VoidCallback onBuyPressed;

  const _BottomBuyBar({
    required this.priceInCents,
    required this.onBuyPressed,
  });

  String get _formattedPrice {
    if (priceInCents == null || priceInCents == 0) return 'Free';
    return '\$${(priceInCents! / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Price
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Price per ticket',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formattedPrice,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Buy button
          Expanded(
            child: FilledButton(
              onPressed: onBuyPressed,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.confirmation_number_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Buy Tickets',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for selecting ticket type and purchasing.
class _BuyTicketSheet extends ConsumerStatefulWidget {
  final EventModel event;

  const _BuyTicketSheet({required this.event});

  @override
  ConsumerState<_BuyTicketSheet> createState() => _BuyTicketSheetState();
}

class _BuyTicketSheetState extends ConsumerState<_BuyTicketSheet> {
  // Quantities per ticket type (keyed by ticket type id)
  final Map<String, int> _quantities = {};
  // Fallback quantity for events without ticket types
  int _fallbackQuantity = 1;
  static const int _maxTickets = 10;

  // Venue data
  Venue? _venue;
  List<TicketType> _ticketTypes = [];
  bool _loadingVenue = false;
  String? _highlightedSectionId;

  bool get _hasVenue => widget.event.venueId != null;
  bool get _hasTicketTypes => _ticketTypes.isNotEmpty;

  int get _pricePerTicketCents => widget.event.priceInCents ?? 0;

  @override
  void initState() {
    super.initState();
    if (_hasVenue) _loadVenueData();
  }

  Future<void> _loadVenueData() async {
    setState(() => _loadingVenue = true);
    try {
      final venueRepo = ref.read(venueRepositoryProvider);
      final eventRepo = ref.read(eventRepositoryProvider);
      final results = await Future.wait([
        venueRepo.getVenue(widget.event.venueId!),
        (eventRepo as SupabaseEventRepository).getEventTicketTypes(widget.event.id),
      ]);
      if (mounted) {
        final venue = results[0] as Venue?;
        final types = results[1] as List<TicketType>;
        setState(() {
          _venue = venue;
          _ticketTypes = types.where((t) => t.isActive).toList();
          // Initialize quantities
          for (final t in _ticketTypes) {
            _quantities[t.id] = 0;
          }
          _loadingVenue = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVenue = false);
    }
  }

  int _totalCents() {
    if (_hasTicketTypes) {
      var total = 0;
      for (final t in _ticketTypes) {
        total += (_quantities[t.id] ?? 0) * t.priceInCents;
      }
      return total;
    }
    return _fallbackQuantity * _pricePerTicketCents;
  }

  int _totalQuantity() {
    if (_hasTicketTypes) {
      return _quantities.values.fold(0, (a, b) => a + b);
    }
    return _fallbackQuantity;
  }

  String _formatPrice(int cents) {
    if (cents == 0) return 'Free';
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }

  Set<String> get _highlightedSections {
    // Highlight sections that have tickets in cart, or the tapped section
    final ids = <String>{};
    if (_highlightedSectionId != null) ids.add(_highlightedSectionId!);
    for (final t in _ticketTypes) {
      if ((_quantities[t.id] ?? 0) > 0 && t.venueSectionId != null) {
        ids.add(t.venueSectionId!);
      }
    }
    return ids;
  }

  String? _sectionNameFor(TicketType t) {
    if (t.venueSectionId == null || _venue == null) return null;
    final section = _venue!.layout.sections
        .where((s) => s.id == t.venueSectionId)
        .firstOrNull;
    return section?.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final availabilityAsync = ref.watch(_ticketAvailabilityProvider(widget.event.id));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Center(
              child: Text(
                'Get Tickets',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                widget.event.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Venue mini-map (when venue is linked)
            if (_hasVenue) ...[
              if (_loadingVenue)
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_venue != null) ...[
                VenueMiniMap(
                  layout: _venue!.layout,
                  canvasWidth: _venue!.canvasWidth,
                  canvasHeight: _venue!.canvasHeight,
                  highlightedSectionIds: _highlightedSections,
                  onSectionTap: (sectionId) {
                    setState(() {
                      _highlightedSectionId =
                          _highlightedSectionId == sectionId ? null : sectionId;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context); // Close buy sheet
                      final selections = await Navigator.of(context).push<List<SeatSelection>>(
                        MaterialPageRoute(
                          builder: (_) => SeatPickerScreen(
                            eventId: widget.event.id,
                            venue: _venue!,
                            sectionQuantities: _sectionQuantities.isNotEmpty
                                ? _sectionQuantities
                                : {for (final s in _venue!.layout.sections) s.id: 0},
                            ticketTypes: _ticketTypes,
                          ),
                        ),
                      );
                      // If user selected seats from the full-screen picker, proceed to checkout
                      if (selections != null && selections.isNotEmpty && context.mounted) {
                        _handleSeatSelectionsFromFullScreen(context, selections);
                      }
                    },
                    icon: const Icon(Icons.fullscreen, size: 18),
                    label: const Text('Full Screen'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Ticket types with venue sections (when available)
            if (_hasTicketTypes) ...[
              ..._ticketTypes.map((t) {
                final qty = _quantities[t.id] ?? 0;
                final sectionName = _sectionNameFor(t);
                final isHighlighted = t.venueSectionId != null &&
                    t.venueSectionId == _highlightedSectionId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VenueTicketTypeCard(
                    ticketType: t,
                    quantity: qty,
                    sectionName: sectionName,
                    isHighlighted: isHighlighted,
                    onIncrement: qty < _maxTickets
                        ? () => setState(() => _quantities[t.id] = qty + 1)
                        : null,
                    onDecrement: qty > 0
                        ? () => setState(() => _quantities[t.id] = qty - 1)
                        : null,
                  ),
                );
              }),
              const SizedBox(height: 12),
              // Buy button for multi-type
              FilledButton(
                onPressed: _totalQuantity() > 0 ? () => _checkout(context) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _totalQuantity() > 0
                      ? 'Buy ${_totalQuantity()} ticket${_totalQuantity() > 1 ? 's' : ''} \u2022 ${_formatPrice(_totalCents())}'
                      : 'Select tickets above',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              // Fallback: single ticket type (no venue or types not loaded)
              _TicketOptionCard(
                icon: Icons.verified_outlined,
                iconColor: colorScheme.primary,
                title: 'Official Tickets',
                subtitle: _formatPrice(_pricePerTicketCents),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SmallQuantityButton(
                      icon: Icons.remove,
                      onTap: _fallbackQuantity > 1
                          ? () => setState(() => _fallbackQuantity--)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_fallbackQuantity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _SmallQuantityButton(
                      icon: Icons.add,
                      onTap: _fallbackQuantity < _maxTickets
                          ? () => setState(() => _fallbackQuantity++)
                          : null,
                    ),
                  ],
                ),
                onTap: null,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _checkout(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _totalCents() > 0
                      ? 'Buy Official \u2022 ${_formatPrice(_totalCents())}'
                      : 'Get Free Ticket',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Divider with "or"
            Row(
              children: [
                Expanded(child: Divider(color: colorScheme.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'or',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: colorScheme.outlineVariant)),
              ],
            ),
            const SizedBox(height: 20),

            // Resale Tickets Section
            availabilityAsync.when(
              loading: () => _TicketOptionCard(
                icon: Icons.swap_horiz_rounded,
                iconColor: colorScheme.secondary,
                title: 'Resale Tickets',
                subtitle: 'Loading...',
                trailing: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                onTap: null,
              ),
              error: (_, __) => _TicketOptionCard(
                icon: Icons.swap_horiz_rounded,
                iconColor: colorScheme.secondary,
                title: 'Resale Tickets',
                subtitle: 'Unable to load',
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: null,
              ),
              data: (availability) => _TicketOptionCard(
                icon: Icons.swap_horiz_rounded,
                iconColor: colorScheme.secondary,
                title: 'Resale Tickets',
                subtitle: availability.hasResaleTickets
                    ? '${availability.resaleCount} available from other fans'
                    : 'None available',
                trailing: availability.hasResaleTickets
                    ? Icon(
                        Icons.chevron_right,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : null,
                onTap: availability.hasResaleTickets
                    ? () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ResaleBrowseScreen(event: widget.event),
                          ),
                        );
                      }
                    : null,
                enabled: availability.hasResaleTickets,
              ),
            ),
            const SizedBox(height: 20),

            // Waitlist Section
            availabilityAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (availability) {
                // Show waitlist option when official tickets are sold out
                final isSoldOut = !availability.hasOfficialTickets;
                if (!isSoldOut) return const SizedBox.shrink();

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Divider(color: colorScheme.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'sold out?',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: colorScheme.outlineVariant)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TicketOptionCard(
                      icon: Icons.notifications_outlined,
                      iconColor: Colors.orange,
                      title: 'Join Waitlist',
                      subtitle: 'Get notified or auto-buy when available',
                      trailing: Icon(
                        Icons.chevron_right,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => WaitlistSheet(
                            eventId: widget.event.id,
                            eventTitle: widget.event.title,
                            eventPriceCents: widget.event.priceInCents,
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Checks if any selected ticket types are for seated sections with generated seats.
  bool get _needsSeatPicker {
    if (_venue == null || !_hasTicketTypes) return false;
    for (final t in _ticketTypes) {
      if ((_quantities[t.id] ?? 0) > 0 && t.venueSectionId != null) {
        final section = _venue!.layout.sections
            .where((s) => s.id == t.venueSectionId)
            .firstOrNull;
        if (section != null &&
            section.type == SectionType.seated &&
            section.rows.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// Build sectionId → quantity map for seated sections only.
  Map<String, int> get _sectionQuantities {
    final map = <String, int>{};
    if (_venue == null) return map;
    for (final t in _ticketTypes) {
      final qty = _quantities[t.id] ?? 0;
      if (qty > 0 && t.venueSectionId != null) {
        final section = _venue!.layout.sections
            .where((s) => s.id == t.venueSectionId)
            .firstOrNull;
        if (section != null &&
            section.type == SectionType.seated &&
            section.rows.isNotEmpty) {
          map[t.venueSectionId!] = (map[t.venueSectionId!] ?? 0) + qty;
        }
      }
    }
    return map;
  }

  Future<void> _checkout(BuildContext context) async {
    final baseTotalCents = _totalCents();
    final checkoutAmountCents = baseTotalCents > 0
        ? ServiceFeeCalculator.calculate(baseTotalCents).totalCents
        : 0;

    // Capture everything before popping the bottom sheet (context/ref become invalid after pop)
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final venueRepo = ref.read(venueRepositoryProvider);
    final totalQty = _totalQuantity();
    final unitPrice = _hasTicketTypes
        ? (baseTotalCents / totalQty).round()
        : _pricePerTicketCents;

    List<SeatSelection>? seatSelections;

    // If event has seated sections with seats, show seat picker first
    if (_needsSeatPicker) {
      navigator.pop(); // Close buy sheet
      final sq = _sectionQuantities;
      final selections = await navigator.push<List<SeatSelection>>(
        MaterialPageRoute(
          builder: (_) => SeatPickerScreen(
            eventId: widget.event.id,
            venue: _venue!,
            sectionQuantities: sq,
            ticketTypes: _ticketTypes,
            initialSectionId: sq.length == 1 ? sq.keys.first : null,
          ),
        ),
      );

      if (selections == null || selections.isEmpty) return; // User cancelled

      // Hold the selected seats
      try {
        await venueRepo.holdSeats(
          widget.event.id,
          selections
              .map((s) => (sectionId: s.sectionId, seatId: s.seatId))
              .toList(),
        );
        seatSelections = selections;
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Failed to hold seats: $e')),
        );
        return;
      }
    } else {
      navigator.pop(); // Close buy sheet
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          event: widget.event,
          amountCents: checkoutAmountCents,
          paymentType: PaymentType.primaryPurchase,
          quantity: totalQty,
          baseUnitPriceCents: unitPrice,
          metadata: seatSelections != null
              ? {
                  'seat_selections':
                      seatSelections.map((s) => s.toJson()).toList(),
                }
              : null,
        ),
      ),
    );
  }

  /// Handle seat selections returned from the full-screen venue picker button.
  Future<void> _handleSeatSelectionsFromFullScreen(
    BuildContext context,
    List<SeatSelection> selections,
  ) async {
    final baseTotalCents = _totalCents();
    final checkoutAmountCents = baseTotalCents > 0
        ? ServiceFeeCalculator.calculate(baseTotalCents).totalCents
        : 0;

    // Hold the selected seats
    try {
      final venueRepo = ref.read(venueRepositoryProvider);
      await venueRepo.holdSeats(
        widget.event.id,
        selections
            .map((s) => (sectionId: s.sectionId, seatId: s.seatId))
            .toList(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to hold seats: $e')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          event: widget.event,
          amountCents: checkoutAmountCents,
          paymentType: PaymentType.primaryPurchase,
          quantity: _totalQuantity(),
          baseUnitPriceCents: _hasTicketTypes
              ? (baseTotalCents / _totalQuantity()).round()
              : _pricePerTicketCents,
          metadata: {
            'seat_selections': selections.map((s) => s.toJson()).toList(),
          },
        ),
      ),
    );
  }
}

/// Card for a specific ticket type with venue section info.
class _VenueTicketTypeCard extends StatelessWidget {
  final TicketType ticketType;
  final int quantity;
  final String? sectionName;
  final bool isHighlighted;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  const _VenueTicketTypeCard({
    required this.ticketType,
    required this.quantity,
    this.sectionName,
    this.isHighlighted = false,
    this.onIncrement,
    this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQty = quantity > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : hasQty
                ? colorScheme.primary.withValues(alpha: 0.06)
                : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? colorScheme.primary.withValues(alpha: 0.5)
              : hasQty
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: isHighlighted ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticketType.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      ticketType.formattedPrice,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sectionName != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.map,
                          size: 12,
                          color: Colors.teal.withValues(alpha: 0.7),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          sectionName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.teal,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (ticketType.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    ticketType.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Quantity controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallQuantityButton(
                icon: Icons.remove,
                onTap: onDecrement,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 24,
                  child: Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: hasQty ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              _SmallQuantityButton(
                icon: Icons.add,
                onTap: onIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card for displaying a ticket purchase option.
class _TicketOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const _TicketOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: enabled
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled ? null : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Small quantity adjustment button.
class _SmallQuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _SmallQuantityButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;

    return Material(
      color: isEnabled
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            color: isEnabled
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing all dates in a recurring series.
class _AllDatesSheet extends ConsumerWidget {
  final String seriesId;
  final String currentEventId;

  const _AllDatesSheet({
    required this.seriesId,
    required this.currentEventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final occurrencesAsync = ref.watch(seriesOccurrencesProvider(seriesId));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.repeat, size: 20, color: Colors.deepPurple[400]),
              const SizedBox(width: 8),
              Text(
                'All Dates',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: occurrencesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => const Center(
                child: Text('Failed to load dates'),
              ),
              data: (occurrences) {
                if (occurrences.isEmpty) {
                  return const Center(child: Text('No upcoming dates'));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: occurrences.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final occ = occurrences[index];
                    final isCurrent = occ.id == currentEventId;
                    final isPast = occ.date.isBefore(DateTime.now());

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isCurrent
                            ? colorScheme.primary
                            : isPast
                                ? colorScheme.surfaceContainerHighest
                                : colorScheme.primaryContainer,
                        child: Text(
                          '${occ.date.day}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isCurrent
                                ? colorScheme.onPrimary
                                : isPast
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        _formatOccurrenceDate(occ.date),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isCurrent ? FontWeight.bold : null,
                          color: isPast ? colorScheme.onSurfaceVariant : null,
                        ),
                      ),
                      trailing: isCurrent
                          ? Chip(
                              label: const Text('Current'),
                              labelStyle: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                              backgroundColor:
                                  colorScheme.primaryContainer.withValues(alpha: 0.5),
                              side: BorderSide.none,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            )
                          : isPast
                              ? Text(
                                  'Past',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : Icon(
                                  Icons.chevron_right,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                      onTap: isCurrent || isPast
                          ? null
                          : () async {
                              Navigator.pop(context);
                              // Fetch the full event and navigate
                              final repo = ref.read(eventRepositoryProvider);
                              try {
                                final event = await repo.getEventById(occ.id);
                                if (event != null && context.mounted) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EventDetailsScreen(event: event),
                                    ),
                                  );
                                }
                              } catch (_) {}
                            },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatOccurrenceDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, $month ${date.day} at $hour:$minute $period';
  }
}

