import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../staff/data/cash_transaction_repository.dart';
import '../../staff/presentation/cash_sale_screen.dart';
import '../../staff/presentation/tap_to_pay_screen.dart';
import '../data/supabase_event_repository.dart';
import '../models/event_model.dart';
import '../models/ticket_type.dart';
import 'usher_event_screen.dart';

/// Screen for vendors to sell tickets at an event.
///
/// Features a point-of-sale interface for on-the-spot ticket sales.
class VendorEventScreen extends ConsumerStatefulWidget {
  const VendorEventScreen({
    super.key,
    required this.event,
    this.canSwitchToUsher = false,
  });

  final EventModel event;
  final bool canSwitchToUsher;

  @override
  ConsumerState<VendorEventScreen> createState() => _VendorEventScreenState();
}

class _VendorEventScreenState extends ConsumerState<VendorEventScreen> {
  bool _isLoading = false;
  bool _isLoadingTicketTypes = true;
  bool _isCheckingCashSales = true;
  int _ticketsSoldThisSession = 0;
  _SoldTicket? _lastSoldTicket;

  // Cash sales
  bool _cashSalesEnabled = false;
  final _cashRepo = CashTransactionRepository();

  // Ticket types
  List<TicketType> _ticketTypes = [];
  TicketType? _selectedTicketType;

  int get _ticketPrice => _selectedTicketType?.priceInCents ?? widget.event.priceInCents ?? 0;

  String get _formattedPrice {
    if (_ticketPrice == 0) return 'Free';
    final dollars = _ticketPrice / 100;
    return '\$${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
  }

  @override
  void initState() {
    super.initState();
    _loadTicketTypes();
    _checkCashSalesEnabled();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _checkCashSalesEnabled() async {
    setState(() => _isCheckingCashSales = true);
    try {
      final enabled = await _cashRepo.isCashSalesEnabled(widget.event.id);
      if (mounted) {
        setState(() {
          _cashSalesEnabled = enabled;
          _isCheckingCashSales = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking cash sales status: $e');
      if (mounted) {
        setState(() => _isCheckingCashSales = false);
      }
    }
  }

  Future<void> _loadTicketTypes() async {
    setState(() => _isLoadingTicketTypes = true);
    try {
      final repository = SupabaseEventRepository();
      debugPrint('VendorEventScreen: Loading ticket types for event: ${widget.event.id}');
      final types = await repository.getEventTicketTypes(widget.event.id);
      debugPrint('VendorEventScreen: Loaded ${types.length} ticket types');
      if (mounted) {
        setState(() {
          _ticketTypes = types;
          // Auto-select first available ticket type
          _selectedTicketType = types.where((t) => t.isAvailable).firstOrNull;
          _isLoadingTicketTypes = false;
        });
      }
    } catch (e) {
      debugPrint('VendorEventScreen: Error loading ticket types: $e');
      if (mounted) {
        setState(() => _isLoadingTicketTypes = false);
      }
    }
  }

  Future<void> _sellTicket() async {
    // Check if cash sales are enabled
    if (!_cashSalesEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash sales are not enabled for this event. Ask the organizer to enable them.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate ticket type selection if types exist
    if (_ticketTypes.isNotEmpty && _selectedTicketType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a ticket type'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if selected ticket type is still available
    if (_selectedTicketType != null && !_selectedTicketType!.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_selectedTicketType!.name} is sold out'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Navigate to Cash Sale screen with NFC flow
    final result = await Navigator.of(context).push<CashSaleScreenResult>(
      MaterialPageRoute(
        builder: (_) => CashSaleScreen(
          event: widget.event,
          ticketType: _selectedTicketType!,
        ),
      ),
    );

    if (result != null && result.success && mounted) {
      setState(() {
        _lastSoldTicket = _SoldTicket(
          ticketNumber: result.ticketNumber ?? 'Unknown',
        );
        _ticketsSoldThisSession++;
      });

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Ticket ${result.ticketNumber} sold!'),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _openTapToPay() async {
    if (_selectedTicketType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a ticket type first'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TapToPayScreen(
          event: widget.event,
          ticketType: _selectedTicketType!,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _ticketsSoldThisSession++);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Tap-to-pay ticket sold successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = widget.event.getNoiseConfig();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.event.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: config.colors,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              // Role switch button (if user has both roles)
              if (widget.canSwitchToUsher)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => UsherEventScreen(
                              event: widget.event,
                              canSwitchToSelling: true,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.qr_code_scanner,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Scan',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Vendor badge
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.point_of_sale,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Vendor',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Stats bar
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    icon: Icons.confirmation_number,
                    value: '$_ticketsSoldThisSession',
                    label: 'Sold Today',
                    color: Colors.green,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  _StatItem(
                    icon: Icons.attach_money,
                    value: _formattedPrice,
                    label: _selectedTicketType?.name ?? 'Per Ticket',
                    color: colorScheme.primary,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  _StatItem(
                    icon: Icons.payments,
                    value: _formatRevenue(),
                    label: 'Revenue',
                    color: Colors.amber.shade700,
                  ),
                ],
              ),
            ),
          ),

          // Ticket type selector
          if (_isLoadingTicketTypes)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_ticketTypes.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Ticket Type',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._ticketTypes.map((ticketType) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TicketTypeCard(
                        ticketType: ticketType,
                        isSelected: _selectedTicketType?.id == ticketType.id,
                        onTap: ticketType.isAvailable
                            ? () => setState(() => _selectedTicketType = ticketType)
                            : null,
                      ),
                    )),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

          // Sale buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tap to Pay button (only if ticket type is selected)
                  if (_selectedTicketType != null) ...[
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _openTapToPay,
                      icon: const Icon(Icons.contactless),
                      label: Text('Tap to Pay - $_formattedPrice'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Divider with "or"
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or anonymous sale',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Manual sell button (creates anonymous ticket)
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _sellTicket,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.point_of_sale),
                    label: Text(
                      _isLoading
                          ? 'Processing...'
                          : 'Cash Sale - $_formattedPrice',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: _cashSalesEnabled ? null : Colors.grey,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cashSalesEnabled
                        ? 'Cash sale - collect payment and give ticket number'
                        : 'Cash sales not enabled - ask organizer to enable',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Last sold ticket info
          if (_lastSoldTicket != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Last Sold Ticket',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.green.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Ticket #'),
                                Text(
                                  _lastSoldTicket!.ticketNumber,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Status'),
                                Chip(
                                  label: const Text('Valid'),
                                  backgroundColor: Colors.green.withValues(alpha: 0.2),
                                  labelStyle: const TextStyle(color: Colors.green),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  String _formatRevenue() {
    final totalCents = _ticketsSoldThisSession * _ticketPrice;
    final dollars = totalCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SoldTicket {
  final String ticketNumber;

  _SoldTicket({
    required this.ticketNumber,
  });
}

/// Card widget for selecting ticket type.
class _TicketTypeCard extends StatelessWidget {
  const _TicketTypeCard({
    required this.ticketType,
    required this.isSelected,
    required this.onTap,
  });

  final TicketType ticketType;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDisabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : isDisabled
                  ? colorScheme.surfaceContainerLow.withValues(alpha: 0.5)
                  : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : isDisabled
                    ? colorScheme.outline.withValues(alpha: 0.2)
                    : colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : isDisabled
                          ? colorScheme.outline.withValues(alpha: 0.3)
                          : colorScheme.outline,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 16),
            // Ticket type info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticketType.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDisabled
                                ? colorScheme.onSurface.withValues(alpha: 0.5)
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (ticketType.isSoldOut)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Sold Out',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (ticketType.hasLimit && ticketType.remainingQuantity! <= 10)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${ticketType.remainingQuantity} left',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (ticketType.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      ticketType.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Price
            Text(
              ticketType.formattedPrice,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? colorScheme.primary
                    : isDisabled
                        ? colorScheme.onSurface.withValues(alpha: 0.5)
                        : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
