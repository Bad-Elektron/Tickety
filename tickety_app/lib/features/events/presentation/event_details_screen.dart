import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../payments/models/payment.dart';
import '../../payments/presentation/checkout_screen.dart';
import '../../payments/presentation/resale_browse_screen.dart';
import '../../payments/presentation/seller_onboarding_screen.dart';
import '../models/event_model.dart';
import '../models/ticket_availability.dart';

/// Provider for ticket availability (official + resale counts).
final _ticketAvailabilityProvider =
    FutureProvider.family<TicketAvailability, String>((ref, eventId) async {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();
    final availabilityAsync = ref.watch(_ticketAvailabilityProvider(event.id));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header with gradient
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
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
                  const SizedBox(height: 24),
                  // Info cards
                  _InfoCard(
                    icon: Icons.calendar_today_rounded,
                    title: 'Date & Time',
                    value: _formatDateTime(event.date),
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  if (event.location != null)
                    _InfoCard(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      value: event.location!,
                      color: colorScheme.tertiary,
                    ),
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

  void _showBuyTicketSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BuyTicketSheet(event: event),
    );
  }
}

/// Information card with icon, title, and value.
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
        ],
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
  int _quantity = 1;
  static const int _maxTickets = 10;

  int get _pricePerTicketCents => widget.event.priceInCents ?? 0;
  int get _totalPriceCents => _quantity * _pricePerTicketCents;

  String _formatPrice(int cents) {
    if (cents == 0) return 'Free';
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final availabilityAsync = ref.watch(_ticketAvailabilityProvider(widget.event.id));

    return Container(
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
          const SizedBox(height: 24),

          // Official Tickets Section
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
                  onTap: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$_quantity',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _SmallQuantityButton(
                  icon: Icons.add,
                  onTap: _quantity < _maxTickets
                      ? () => setState(() => _quantity++)
                      : null,
                ),
              ],
            ),
            onTap: null, // Handled by buy button below
          ),
          const SizedBox(height: 12),

          // Buy Official Button
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CheckoutScreen(
                    event: widget.event,
                    amountCents: _totalPriceCents,
                    paymentType: PaymentType.primaryPurchase,
                    quantity: _quantity,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _totalPriceCents > 0
                  ? 'Buy Official \u2022 ${_formatPrice(_totalPriceCents)}'
                  : 'Get Free Ticket',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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

