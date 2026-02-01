import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../staff/models/ticket.dart';
import 'ticket_screen.dart';

/// Date filter options for tickets.
enum TicketDateFilter {
  recent,   // Upcoming + past week
  upcoming, // Future events only
  all,      // All tickets
  past,     // Past events only
}

/// Screen displaying the user's purchased tickets, grouped by event.
class MyTicketsScreen extends ConsumerStatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  ConsumerState<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends ConsumerState<MyTicketsScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  TicketDateFilter _dateFilter = TicketDateFilter.recent;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Load tickets when screen opens
    Future.microtask(() {
      ref.read(myTicketsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = value.trim().toLowerCase();
      });
    });
  }

  void _onDateFilterChanged(TicketDateFilter filter) {
    setState(() {
      _dateFilter = filter;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _dateFilter = TicketDateFilter.recent;
    });
  }

  /// Group tickets by eventId, apply filters, and sort by event date.
  List<_EventTicketGroup> _groupTicketsByEvent(List<Ticket> tickets) {
    final Map<String, List<Ticket>> grouped = {};

    for (final ticket in tickets) {
      final eventId = ticket.eventId;
      grouped.putIfAbsent(eventId, () => []).add(ticket);
    }

    // Convert to list
    var groups = grouped.entries.map((entry) {
      final eventTickets = entry.value;
      // Sort tickets within group by ticket number
      eventTickets.sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));
      return _EventTicketGroup(
        eventId: entry.key,
        tickets: eventTickets,
      );
    }).toList();

    // Apply filters
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oneWeekAgo = today.subtract(const Duration(days: 7));

    groups = groups.where((group) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesSearch = group.eventTitle.toLowerCase().contains(_searchQuery) ||
            (group.venue?.toLowerCase().contains(_searchQuery) ?? false);
        if (!matchesSearch) return false;
      }

      // Date filter
      final eventDate = group.eventDate;
      if (eventDate == null) return _dateFilter == TicketDateFilter.all;

      final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
      final isUpcoming = !eventDay.isBefore(today);
      final isWithinPastWeek = eventDay.compareTo(oneWeekAgo) >= 0 && eventDay.isBefore(today);

      return switch (_dateFilter) {
        TicketDateFilter.recent => isUpcoming || isWithinPastWeek,
        TicketDateFilter.upcoming => isUpcoming,
        TicketDateFilter.all => true,
        TicketDateFilter.past => !isUpcoming,
      };
    }).toList();

    // Sort groups: upcoming events first (soonest), then past events (most recent)
    groups.sort((a, b) {
      final aDate = a.eventDate;
      final bDate = b.eventDate;

      // Handle null dates (put at end)
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      final aDay = DateTime(aDate.year, aDate.month, aDate.day);
      final bDay = DateTime(bDate.year, bDate.month, bDate.day);
      final aIsUpcoming = !aDay.isBefore(today);
      final bIsUpcoming = !bDay.isBefore(today);

      // Upcoming events come first
      if (aIsUpcoming && !bIsUpcoming) return -1;
      if (!aIsUpcoming && bIsUpcoming) return 1;

      // Within upcoming: soonest first
      // Within past: most recent first
      if (aIsUpcoming) {
        return aDay.compareTo(bDay);
      } else {
        return bDay.compareTo(aDay);
      }
    });

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ticketsState = ref.watch(myTicketsProvider);

    // Check if filters are applied
    final hasFilters = _searchQuery.isNotEmpty || _dateFilter != TicketDateFilter.recent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        centerTitle: true,
      ),
      body: ticketsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ticketsState.error != null
              ? _buildErrorState(context, ticketsState.error!, theme, colorScheme)
              : ticketsState.tickets.isEmpty
                  ? _buildEmptyState(context, theme, colorScheme)
                  : _buildFilteredContent(context, ticketsState.tickets, hasFilters),
    );
  }

  Widget _buildFilteredContent(
    BuildContext context,
    List<Ticket> tickets,
    bool hasFilters,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final groups = _groupTicketsByEvent(tickets);

    return Column(
      children: [
        // Search and filter header
        _buildSearchAndFilters(theme, colorScheme),
        // Content
        Expanded(
          child: groups.isEmpty
              ? _buildNoFilterResults(theme, colorScheme)
              : RefreshIndicator(
                  onRefresh: () => ref.read(myTicketsProvider.notifier).refresh(),
                  child: _buildGroupedTicketList(context, groups),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters(ThemeData theme, ColorScheme colorScheme) {
    final hasSearch = _searchController.text.isNotEmpty;
    final filterLabels = {
      TicketDateFilter.recent: 'Recent',
      TicketDateFilter.upcoming: 'Upcoming',
      TicketDateFilter.all: 'All',
      TicketDateFilter.past: 'Past',
    };

    return Container(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by event name...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: hasSearch
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
              ),
            ),
          ),
          // Filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: TicketDateFilter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = TicketDateFilter.values[index];
                final isSelected = _dateFilter == filter;
                return FilterChip(
                  label: Text(filterLabels[filter]!),
                  selected: isSelected,
                  onSelected: (_) => _onDateFilterChanged(filter),
                  showCheckmark: false,
                  selectedColor: colorScheme.primaryContainer,
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  labelStyle: TextStyle(
                    color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? colorScheme.primary : Colors.transparent,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  Widget _buildNoFilterResults(ThemeData theme, ColorScheme colorScheme) {
    final hasSearch = _searchController.text.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No matching tickets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try a different search term or filter.'
                  : 'No tickets match the selected filter.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedTicketList(
    BuildContext context,
    List<_EventTicketGroup> groups,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _EventTicketCard(group: group),
        );
      },
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String error,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return ErrorDisplay.generic(
      message: error,
      onRetry: () => ref.read(myTicketsProvider.notifier).refresh(),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Large ticket icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(60, 42),
                  painter: _TicketIconPainter(
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No tickets yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When you purchase tickets to events,\nthey\'ll appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Discover Events'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Represents a group of tickets for a single event.
class _EventTicketGroup {
  final String eventId;
  final List<Ticket> tickets;

  const _EventTicketGroup({
    required this.eventId,
    required this.tickets,
  });

  Ticket get firstTicket => tickets.first;

  String get eventTitle =>
      firstTicket.eventData?['title'] as String? ?? 'Unknown Event';

  String? get venue => firstTicket.eventData?['venue'] as String?;

  DateTime? get eventDate {
    final dateStr = firstTicket.eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  int get noiseSeed =>
      firstTicket.eventData?['noise_seed'] as int? ?? eventId.hashCode;

  int get ticketCount => tickets.length;

  int get usedCount => tickets.where((t) => t.isUsed).length;

  int get validCount => tickets.where((t) => t.isValid).length;

  bool get allUsed => usedCount == ticketCount;

  bool get isEventPast {
    final date = eventDate;
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    return eventDay.isBefore(today);
  }
}

/// Card showing an event with expandable ticket list.
class _EventTicketCard extends StatefulWidget {
  const _EventTicketCard({required this.group});

  final _EventTicketGroup group;

  @override
  State<_EventTicketCard> createState() => _EventTicketCardState();
}

class _EventTicketCardState extends State<_EventTicketCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  NoiseConfig _getNoiseConfig() {
    final seed = widget.group.noiseSeed;
    final presetIndex = seed % 5;
    return switch (presetIndex) {
      0 => NoisePresets.vibrantEvents(seed),
      1 => NoisePresets.sunset(seed),
      2 => NoisePresets.ocean(seed),
      3 => NoisePresets.subtle(seed),
      _ => NoisePresets.darkMood(seed),
    };
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final diff = eventDay.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff < -1) return 'Ended · ${months[date.month - 1]} ${date.day}';
    if (diff < 7) return 'In $diff days';
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = _getNoiseConfig();
    final group = widget.group;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Event header (tappable to expand)
          InkWell(
            onTap: _toggleExpand,
            child: Column(
              children: [
                // Gradient header
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: config.colors,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Event title
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.eventTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              group.venue ?? 'Venue TBA',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Ticket count badge
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.confirmation_number,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${group.ticketCount} ticket${group.ticketCount > 1 ? 's' : ''}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Status indicator (all used)
                      if (group.allUsed)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Used',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Summary row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Date chip
                      _InfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: group.eventDate != null
                            ? _formatDate(group.eventDate!)
                            : 'TBA',
                        color: group.isEventPast
                            ? colorScheme.error
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      // Status chip
                      if (group.usedCount > 0 && !group.allUsed)
                        _InfoChip(
                          icon: Icons.check_circle_outline,
                          label: '${group.usedCount}/${group.ticketCount} used',
                          color: Colors.green,
                        ),
                      const Spacer(),
                      // Expand indicator
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Expandable ticket list
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              children: [
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                ...group.tickets.map((ticket) => _TicketListItem(ticket: ticket)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small info chip for displaying date/status.
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual ticket item in the expanded list.
class _TicketListItem extends StatelessWidget {
  const _TicketListItem({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TicketScreen(ticket: ticket),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Ticket icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.confirmation_number_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            // Ticket info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.ticketNumber,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ticket.formattedPrice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Status badge
            if (ticket.isUsed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Used',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (ticket.isListedForSale)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sell,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Listed',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom ticket icon painter.
class _TicketIconPainter extends CustomPainter {
  final Color color;

  _TicketIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final notchRadius = h * 0.15;
    final cornerRadius = h * 0.15;

    final path = Path();

    path.moveTo(cornerRadius, 0);
    path.lineTo(w - cornerRadius, 0);
    path.quadraticBezierTo(w, 0, w, cornerRadius);

    path.lineTo(w, h * 0.35);
    path.arcToPoint(
      Offset(w, h * 0.65),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(w, h - cornerRadius);
    path.quadraticBezierTo(w, h, w - cornerRadius, h);

    path.lineTo(cornerRadius, h);
    path.quadraticBezierTo(0, h, 0, h - cornerRadius);

    path.lineTo(0, h * 0.65);
    path.arcToPoint(
      Offset(0, h * 0.35),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    canvas.drawPath(path, paint);

    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

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
