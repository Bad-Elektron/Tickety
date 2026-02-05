import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../staff/data/ticket_repository.dart';
import '../../staff/presentation/cash_reconciliation_screen.dart';
import '../../staff/presentation/manage_staff_screen.dart';
import '../models/event_model.dart';
import 'event_data_screen.dart';

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
  @override
  void initState() {
    super.initState();
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
                            'Event Admin',
                            style: theme.textTheme.labelMedium?.copyWith(
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
                    'Admin Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AdminActionCard(
                    icon: Icons.pie_chart,
                    title: 'Data',
                    subtitle: 'View event analytics and statistics',
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
                    title: 'Mint Tickets',
                    subtitle: 'Create more tickets for this event',
                    color: colorScheme.primary,
                    onTap: () => _showMintTicketsSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.content_cut,
                    customIcon: const _TicketTearIcon(size: 28),
                    title: 'Manage Staff',
                    subtitle: 'Add and manage your event team',
                    color: colorScheme.tertiary,
                    onTap: () => _showManageUshersSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.edit_outlined,
                    title: 'Edit Event',
                    subtitle: 'Update event details',
                    color: colorScheme.secondary,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coming soon'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.payments_outlined,
                    title: 'Cash Sales',
                    subtitle: event.cashSalesEnabled
                        ? 'View cash transactions'
                        : 'Enable cash payments at door',
                    color: Colors.green,
                    onTap: () => _showCashSalesSheet(context),
                  ),
                  const SizedBox(height: 24),
                  // Event info
                  Text(
                    'Event Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  _InfoCard(
                    icon: Icons.attach_money,
                    title: 'Ticket Price',
                    value: event.formattedPrice,
                    color: colorScheme.secondary,
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

  void _showMintTicketsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _MintTicketsSheet(),
    );
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
            label: 'Tickets Sold',
            value: '${ticketStats?.totalSold ?? 0}',
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Revenue',
            value: ticketStats?.formattedRevenue ?? '\$0.00',
            color: colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Staff',
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

/// Bottom sheet for minting more tickets.
class _MintTicketsSheet extends StatefulWidget {
  const _MintTicketsSheet();

  @override
  State<_MintTicketsSheet> createState() => _MintTicketsSheetState();
}

class _MintTicketsSheetState extends State<_MintTicketsSheet> {
  int _quantity = 10;

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
            Icons.confirmation_number,
            size: 48,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Mint More Tickets',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current supply: 100 tickets',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MintButton(
                icon: Icons.remove,
                onTap: _quantity > 1 ? () => setState(() => _quantity -= 10) : null,
              ),
              const SizedBox(width: 24),
              Text(
                '$_quantity',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 24),
              _MintButton(
                icon: Icons.add,
                onTap: _quantity < 100 ? () => setState(() => _quantity += 10) : null,
              ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Minted $_quantity new tickets'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Mint Tickets',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MintButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MintButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;

    return Material(
      color: isEnabled ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(
            icon,
            color: isEnabled ? colorScheme.onPrimaryContainer : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 28,
          ),
        ),
      ),
    );
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
            const SnackBar(
              content: Text('Cash sales are already enabled'),
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
          const SnackBar(
            content: Text('Cash sales enabled! Staff can now accept cash payments.'),
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
            'Enable Cash Sales',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Allow staff to sell tickets for cash at the door',
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
                        '5% Platform Fee',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A 5% fee will be charged to your card for each cash sale to cover platform costs.',
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
                  'How it works:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  context,
                  Icons.credit_card,
                  'Add a payment method for platform fees',
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  Icons.point_of_sale,
                  'Staff can sell tickets for cash via POS',
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  Icons.receipt_long,
                  'Track all cash sales in reconciliation',
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
                    _isSettingUpStripe ? 'Complete Setup' : 'Add Payment Method',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
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
