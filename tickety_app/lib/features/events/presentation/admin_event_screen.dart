import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../../core/state/state.dart';
import '../../../shared/widgets/widgets.dart';
import '../../merch/presentation/organizer_products_screen.dart';
import '../../subscriptions/subscriptions.dart';
import '../../staff/data/ticket_repository.dart';
import '../data/supabase_event_repository.dart';
import '../../staff/presentation/cash_reconciliation_screen.dart';
import '../../staff/presentation/manage_staff_screen.dart';
import '../../venues/presentation/venue_builder_screen.dart';
import '../../venues/widgets/venue_picker_sheet.dart';
import '../models/event_model.dart';
import '../models/event_series.dart';
import '../../payments/presentation/promo_codes_screen.dart';
import 'create_event_screen.dart';
import 'event_data_screen.dart';
import '../../widget/presentation/widget_settings_screen.dart';
import 'manage_tickets_screen.dart';

/// Admin screen for managing an event created by the user.
class AdminEventScreen extends ConsumerStatefulWidget {
  final EventModel event;

  const AdminEventScreen({
    super.key,
    required this.event,
  });

  @override
  ConsumerState<AdminEventScreen> createState() => _AdminEventScreenState();
}

class _AdminEventScreenState extends ConsumerState<AdminEventScreen> {
  /// Tracks venue linkage locally so UI updates immediately after linking.
  String? _linkedVenueId;
  String? get _effectiveVenueId => _linkedVenueId ?? widget.event.venueId;

  @override
  void initState() {
    super.initState();
    _linkedVenueId = widget.event.venueId;
    // Load ticket stats when screen opens
    Future.microtask(() {
      ref.read(ticketProvider.notifier).loadStats(widget.event.id);
      ref.read(staffProvider.notifier).loadStaff(widget.event.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GradientBackground(colors: config.colors),
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
                  // Admin badge
                  Positioned(
                    top: 100,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.admin_panel_settings,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            L.tr('admin_event_badge'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Date & location overlay (bottom-right)
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 13,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatDateTime(event.date),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (event.displayLocation != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 13,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    event.displayLocation!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white70,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
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
                  // Pending review banner
                  if (event.isPendingReview) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.hourglass_top,
                            color: Colors.amber,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L.tr('admin_pending_review'),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  event.statusReason ?? L.tr('admin_pending_review_description'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Suspended banner
                  if (event.isSuspended) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.block,
                            color: colorScheme.onErrorContainer,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L.tr('admin_event_suspended'),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  event.statusReason ?? L.tr('admin_event_suspended_description'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Invite code card for private events
                  if (event.isPrivate && event.inviteCode != null) ...[
                    _InviteCodeCard(
                      inviteCode: event.inviteCode!,
                      eventTitle: event.title,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Recurring series banner
                  if (event.isPartOfSeries) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.deepPurple.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.repeat, size: 20, color: Colors.deepPurple[400]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${RecurrenceType.fromString(event.recurrenceType)?.label ?? "Recurring"} Series',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.deepPurple[400],
                                  ),
                                ),
                                if (event.occurrenceIndex != null)
                                  Text(
                                    'Occurrence #${event.occurrenceIndex! + 1}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Virtual/Hybrid event banner
                  if (event.hasVirtualComponent) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.cyan.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.videocam, size: 20, color: Colors.cyan[600]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.isVirtual ? 'Virtual Event' : 'Hybrid Event',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.cyan[600],
                                  ),
                                ),
                                if (event.virtualEventUrl != null)
                                  Text(
                                    event.virtualEventUrl!.replaceRange(
                                      (event.virtualEventUrl!.length * 0.4).round().clamp(8, event.virtualEventUrl!.length),
                                      event.virtualEventUrl!.length,
                                      '\u2026',
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                if (event.virtualLocked)
                                  Text(
                                    L.tr('admin_link_revealed'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.cyan[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Title
                  Text(
                    event.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Stats cards
                  _StatsSection(
                    ticketStats: ref.watch(ticketProvider).stats,
                    staffCount: ref.watch(staffProvider).staff.length,
                  ),
                  const SizedBox(height: 24),
                  // Admin actions
                  Text(
                    L.tr('admin_actions'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AdminActionCard(
                    icon: Icons.pie_chart,
                    title: L.tr('admin_data'),
                    subtitle: L.tr('admin_data_subtitle'),
                    color: Colors.deepPurple,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDataScreen(event: event),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.confirmation_number,
                    title: L.tr('admin_tickets'),
                    subtitle: L.tr('admin_tickets_subtitle'),
                    color: colorScheme.primary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ManageTicketsScreen(event: event),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.discount_outlined,
                    title: L.tr('admin_promo_codes'),
                    subtitle: L.tr('admin_promo_codes_subtitle'),
                    color: Colors.orange,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PromoCodesScreen(event: event),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.content_cut,
                    customIcon: const _TicketTearIcon(size: 28),
                    title: L.tr('admin_manage_staff'),
                    subtitle: L.tr('admin_manage_staff_subtitle'),
                    color: colorScheme.tertiary,
                    onTap: () => _showManageUshersSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.edit_outlined,
                    title: L.tr('admin_edit_event'),
                    subtitle: L.tr('admin_edit_event_subtitle'),
                    color: colorScheme.secondary,
                    onTap: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              CreateEventScreen(editingEvent: event),
                        ),
                      );
                      if (result == true && mounted) {
                        // Refresh event data
                        ref.read(ticketProvider.notifier).loadStats(event.id);
                      }
                    },
                  ),
                  // Venue Layout action — always visible, enterprise-gated
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.map_outlined,
                    title: L.tr('admin_venue_layout'),
                    subtitle: _effectiveVenueId != null
                        ? L.tr('admin_venue_edit_chart')
                        : L.tr('admin_venue_link'),
                    color: Colors.teal,
                    onTap: () => _handleVenueAction(context, ref, event),
                  ),
                  // Event Branding — Pro+ gated
                  // Merch Store action — enterprise-gated
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.shopping_bag_outlined,
                    title: L.tr('admin_merch_store'),
                    subtitle: AppState().tier == AccountTier.enterprise
                        ? L.tr('admin_merch_subtitle')
                        : L.tr('admin_enterprise_required'),
                    color: Colors.amber,
                    onTap: () {
                      if (AppState().tier == AccountTier.enterprise) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrganizerProductsScreen(event: event),
                          ),
                        );
                      } else {
                        _showEnterpriseGate(context, L.tr('admin_merch_store'),
                            'Sell physical and digital merchandise for your events. Available on the Enterprise plan.');
                      }
                    },
                  ),
                  // Embed Widget action — enterprise-gated
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.code,
                    title: L.tr('admin_embed_widget'),
                    subtitle: AppState().tier == AccountTier.enterprise
                        ? L.tr('admin_embed_widget_subtitle')
                        : L.tr('admin_enterprise_required'),
                    color: Colors.indigo,
                    onTap: () {
                      if (AppState().tier == AccountTier.enterprise) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WidgetSettingsScreen(
                              eventId: event.id,
                              eventTitle: event.title,
                            ),
                          ),
                        );
                      } else {
                        _showEnterpriseGate(context, L.tr('admin_embed_widget'),
                            'Embed a checkout widget on your website so visitors can buy tickets directly. Available on the Enterprise plan.');
                      }
                    },
                  ),
                  // Cancel Series action (only for series events)
                  if (event.isPartOfSeries && event.seriesId != null) ...[
                    const SizedBox(height: 12),
                    _AdminActionCard(
                      icon: Icons.event_busy,
                      title: L.tr('admin_cancel_series'),
                      subtitle: L.tr('admin_cancel_series_subtitle'),
                      color: Colors.red,
                      onTap: () => _confirmCancelSeries(context, ref),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.payments_outlined,
                    title: L.tr('admin_cash_sales'),
                    subtitle: event.cashSalesEnabled
                        ? L.tr('admin_cash_sales_view')
                        : L.tr('admin_cash_sales_enable'),
                    color: Colors.green,
                    onTap: () => _showCashSalesSheet(context),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
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

  void _showEnterpriseGate(BuildContext context, String featureName, String description) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outlined, size: 32, color: Colors.teal),
        title: Text(L.tr('admin_enterprise_feature')),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L.tr('admin_maybe_later')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
            },
            child: Text(L.tr('admin_view_plans')),
          ),
        ],
      ),
    );
  }

  void _handleVenueAction(BuildContext context, WidgetRef ref, EventModel event) {
    final tier = ref.read(currentTierProvider);
    final canUse = TierLimits.canUseVenueBuilder(tier);

    if (!canUse) {
      // Show upgrade prompt
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lock_outlined, size: 32, color: Colors.teal),
          title: Text(L.tr('admin_enterprise_feature')),
          content: Text(
            L.tr('admin_venue_enterprise_description'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L.tr('admin_maybe_later')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                );
              },
              child: Text(L.tr('admin_view_plans')),
            ),
          ],
        ),
      );
      return;
    }

    if (_effectiveVenueId != null) {
      // Already linked — open builder
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VenueBuilderScreen(venueId: _effectiveVenueId),
        ),
      );
    } else {
      // Show venue picker to link
      _showVenuePicker(context, ref, event);
    }
  }

  void _showVenuePicker(BuildContext context, WidgetRef ref, EventModel event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => VenuePickerSheet(
        onVenueSelected: (venue) async {
          final repo = ref.read(eventRepositoryProvider) as SupabaseEventRepository;
          await repo.linkVenue(event.id, venue.id);
          if (context.mounted) {
            setState(() => _linkedVenueId = venue.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Linked "${venue.name}" to this event'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            // Navigate to builder
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VenueBuilderScreen(venueId: venue.id),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmCancelSeries(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.tr('admin_cancel_series')),
        content: Text(
          L.tr('admin_cancel_series_confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.tr('admin_keep_series')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(L.tr('admin_cancel_series')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final repository = ref.read(eventRepositoryProvider);
      await (repository as SupabaseEventRepository)
          .cancelSeries(widget.event.seriesId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L.tr('admin_series_cancelled')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel series: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showManageUshersSheet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManageStaffScreen(event: widget.event),
      ),
    );
  }

  void _showCashSalesSheet(BuildContext context) {
    if (widget.event.cashSalesEnabled) {
      // Navigate to cash reconciliation screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CashReconciliationScreen(
            eventId: widget.event.id,
            eventTitle: widget.event.title,
          ),
        ),
      );
    } else {
      // Show setup sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _CashSalesSetupSheet(event: widget.event),
      );
    }
  }
}

class _StatsSection extends StatelessWidget {
  final TicketStats? ticketStats;
  final int staffCount;

  const _StatsSection({
    required this.ticketStats,
    required this.staffCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: L.tr('admin_tickets_sold'),
            value: '${ticketStats?.totalSold ?? 0}',
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: L.tr('admin_revenue'),
            value: ticketStats?.formattedRevenue ?? '\$0.00',
            color: colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: L.tr('admin_staff'),
            value: '$staffCount',
            color: colorScheme.tertiary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? total;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (total != null) ...[
                Text(
                  '/$total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final Widget? customIcon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.icon,
    this.customIcon,
    required this.title,
    required this.subtitle,
    required this.color,
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
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: customIcon ?? Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

/// Custom icon showing a ticket being torn/cut.
class _TicketTearIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const _TicketTearIcon({
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.tertiary;

    return CustomPaint(
      size: Size(size, size * 0.7),
      painter: _TicketTearPainter(color: iconColor),
    );
  }
}

class _TicketTearPainter extends CustomPainter {
  final Color color;

  _TicketTearPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final gap = w * 0.08;
    final leftW = w * 0.45 - gap / 2;
    final rightX = w * 0.55 + gap / 2;
    final rightW = w - rightX;

    // Left ticket half
    _drawTicketHalf(canvas, paint, 0, 0, leftW, h, true);

    // Right ticket half (slightly rotated/offset to show tear)
    canvas.save();
    canvas.translate(rightX, h * 0.05);
    canvas.rotate(0.05);
    _drawTicketHalf(canvas, paint, 0, 0, rightW, h * 0.95, false);
    canvas.restore();

    // Tear marks (zigzag line)
    final tearPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

    final tearPath = Path();
    final tearX = w * 0.48;
    tearPath.moveTo(tearX, 0);
    for (var i = 0; i < 5; i++) {
      final y1 = h * (i * 2 + 1) / 10;
      final y2 = h * (i * 2 + 2) / 10;
      tearPath.lineTo(tearX + (i.isEven ? w * 0.03 : -w * 0.03), y1);
      tearPath.lineTo(tearX, y2);
    }
    canvas.drawPath(tearPath, tearPaint);
  }

  void _drawTicketHalf(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double w,
    double h,
    bool isLeft,
  ) {
    final notchRadius = h * 0.12;
    final cornerRadius = h * 0.12;

    final path = Path();

    if (isLeft) {
      path.moveTo(x + cornerRadius, y);
      path.lineTo(x + w, y);
      path.lineTo(x + w, y + h * 0.35);
      path.arcToPoint(
        Offset(x + w, y + h * 0.65),
        radius: Radius.circular(notchRadius),
        clockwise: false,
      );
      path.lineTo(x + w, y + h);
      path.lineTo(x + cornerRadius, y + h);
      path.quadraticBezierTo(x, y + h, x, y + h - cornerRadius);
      path.lineTo(x, y + cornerRadius);
      path.quadraticBezierTo(x, y, x + cornerRadius, y);
    } else {
      path.moveTo(x, y);
      path.lineTo(x + w - cornerRadius, y);
      path.quadraticBezierTo(x + w, y, x + w, y + cornerRadius);
      path.lineTo(x + w, y + h - cornerRadius);
      path.quadraticBezierTo(x + w, y + h, x + w - cornerRadius, y + h);
      path.lineTo(x, y + h);
      path.lineTo(x, y + h * 0.65);
      path.arcToPoint(
        Offset(x, y + h * 0.35),
        radius: Radius.circular(notchRadius),
        clockwise: false,
      );
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TicketTearPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Bottom sheet for enabling cash sales - handles Stripe payment method setup.
class _CashSalesSetupSheet extends StatefulWidget {
  final EventModel event;

  const _CashSalesSetupSheet({required this.event});

  @override
  State<_CashSalesSetupSheet> createState() => _CashSalesSetupSheetState();
}

class _CashSalesSetupSheetState extends State<_CashSalesSetupSheet> {
  bool _isLoading = false;
  bool _isSettingUpStripe = false;
  String? _error;
  String? _setupIntentId;

  Future<void> _enableCashSales() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'enable-cash-sales',
        body: {'event_id': widget.event.id},
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Failed to enable cash sales';
        throw Exception(error);
      }

      final data = response.data as Map<String, dynamic>;

      // Check if already enabled
      if (data['already_enabled'] == true) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L.tr('admin_cash_already_enabled')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Check if cash sales were enabled using existing payment method
      if (data['cash_sales_enabled'] == true && data['used_existing_payment_method'] == true) {
        if (mounted) {
          Navigator.pop(context, true);
          final card = data['card'] as Map<String, dynamic>?;
          final cardInfo = card != null
              ? ' (${card['brand']} ****${card['last4']})'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cash sales enabled!$cardInfo'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Need to add a payment method - set up Stripe payment sheet
      if (data['needs_payment_method'] == true) {
        final clientSecret = data['client_secret'] as String;
        _setupIntentId = data['setup_intent_id'] as String;

        setState(() {
          _isLoading = false;
          _isSettingUpStripe = true;
        });

        // Initialize payment sheet for SetupIntent
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            setupIntentClientSecret: clientSecret,
            merchantDisplayName: 'Tickety',
            customerId: data['customer_id'] as String?,
            customerEphemeralKeySecret: data['ephemeral_key'] as String?,
            style: ThemeMode.system,
          ),
        );

        // Present payment sheet
        await Stripe.instance.presentPaymentSheet();

        // Confirm setup with our backend
        await _confirmSetup();
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSettingUpStripe = false;
          if (e is StripeException) {
            if (e.error.code == FailureCode.Canceled) {
              _error = null; // User cancelled, not an error
            } else {
              _error = e.error.localizedMessage ?? 'Payment setup failed';
            }
          } else {
            _error = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    }
  }

  Future<void> _confirmSetup() async {
    if (_setupIntentId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'confirm-cash-sales-setup',
        body: {
          'event_id': widget.event.id,
          'setup_intent_id': _setupIntentId,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Failed to confirm setup';
        throw Exception(error);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L.tr('admin_cash_sales_enabled')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.payments_outlined,
            size: 48,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            L.tr('admin_enable_cash_sales'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            L.tr('admin_cash_sales_description'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Info card about platform fee
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.amber,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L.tr('admin_platform_fee'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L.tr('admin_platform_fee_description'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Requirement info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L.tr('admin_how_it_works'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  context,
                  Icons.credit_card,
                  L.tr('admin_cash_step_payment'),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  Icons.point_of_sale,
                  L.tr('admin_cash_step_pos'),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  Icons.receipt_long,
                  L.tr('admin_cash_step_reconciliation'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isLoading ? null : _enableCashSales,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isSettingUpStripe ? L.tr('admin_complete_setup') : L.tr('admin_add_payment_method'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: Text(L.tr('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  final String inviteCode;
  final String eventTitle;

  const _InviteCodeCard({
    required this.inviteCode,
    required this.eventTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                L.tr('admin_private_event'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            inviteCode,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(L.tr('admin_invite_code_copied')),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(L.tr('copy')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Share.share(
                      'Join my event "$eventTitle" on Tickety! Use invite code: $inviteCode',
                    );
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(L.tr('share')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
