import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/event_model.dart';
import 'usher_event_screen.dart';

/// Screen for vendors to sell tickets at an event.
///
/// Features a point-of-sale interface for on-the-spot ticket sales.
class VendorEventScreen extends StatefulWidget {
  const VendorEventScreen({
    super.key,
    required this.event,
    this.canSwitchToUsher = false,
  });

  final EventModel event;
  final bool canSwitchToUsher;

  @override
  State<VendorEventScreen> createState() => _VendorEventScreenState();
}

class _VendorEventScreenState extends State<VendorEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _walletController = TextEditingController();

  bool _isLoading = false;
  int _ticketsSoldThisSession = 0;
  _SoldTicket? _lastSoldTicket;

  int get _ticketPrice => widget.event.priceInCents ?? 0;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  Future<void> _sellTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Simulate network delay
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // Generate a fake ticket number
    final ticketNumber = 'TKT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}-${(_ticketsSoldThisSession + 1).toString().padLeft(4, '0')}';

    setState(() {
      _lastSoldTicket = _SoldTicket(
        ticketNumber: ticketNumber,
        customerName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : null,
      );
      _ticketsSoldThisSession++;
      _isLoading = false;
    });

    // Clear form for next sale
    _nameController.clear();
    _emailController.clear();
    _walletController.clear();

    HapticFeedback.mediumImpact();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Ticket $ticketNumber sold!'),
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
                    value: widget.event.formattedPrice,
                    label: 'Per Ticket',
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

          // Sale form
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Customer Details',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Name field
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'For ticket delivery (optional)',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Wallet field
                    TextFormField(
                      controller: _walletController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Cardano Wallet Address',
                        hintText: 'For NFT ticket (optional)',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Sell button
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _sellTicket,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.point_of_sale),
                      label: Text(
                        _isLoading
                            ? 'Processing...'
                            : 'Sell Ticket - ${widget.event.formattedPrice}',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
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
                            if (_lastSoldTicket!.customerName != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Customer'),
                                  Text(_lastSoldTicket!.customerName!),
                                ],
                              ),
                            ],
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
  final String? customerName;

  _SoldTicket({
    required this.ticketNumber,
    this.customerName,
  });
}
