import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../events/data/supabase_event_repository.dart';
import '../../events/models/event_model.dart';
import '../../events/models/ticket_type.dart';
import '../data/cash_transaction_repository.dart';
import '../models/cash_transaction.dart';
import '../models/ticket.dart';
import 'nfc_ticket_transfer_screen.dart';

/// Payment method for POS sales.
enum POSPaymentMethod { card, cash }

/// Point of Sale screen for staff to sell tickets on the spot.
class VendorPOSScreen extends ConsumerStatefulWidget {
  final EventModel event;

  const VendorPOSScreen({super.key, required this.event});

  @override
  ConsumerState<VendorPOSScreen> createState() => _VendorPOSScreenState();
}

class _VendorPOSScreenState extends ConsumerState<VendorPOSScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _walletController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingTicketTypes = true;
  bool _isCheckingCashSales = true;
  Ticket? _lastSoldTicket;
  int _ticketsSoldThisSession = 0;
  POSPaymentMethod _paymentMethod = POSPaymentMethod.cash;
  bool _isProcessingPayment = false;

  // Cash sales
  bool _cashSalesEnabled = false;
  CashDeliveryMethod _cashDeliveryMethod = CashDeliveryMethod.inPerson;

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
    _nameController.dispose();
    _emailController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  Future<void> _checkCashSalesEnabled() async {
    setState(() => _isCheckingCashSales = true);
    try {
      final repository = CashTransactionRepository();
      final enabled = await repository.isCashSalesEnabled(widget.event.id);
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
      debugPrint('Loading ticket types for event: ${widget.event.id}');
      final types = await repository.getEventTicketTypes(widget.event.id);
      debugPrint('Loaded ${types.length} ticket types');
      for (final t in types) {
        debugPrint('  - ${t.name}: ${t.formattedPrice} (available: ${t.isAvailable})');
      }
      if (mounted) {
        setState(() {
          _ticketTypes = types;
          // Auto-select first available ticket type
          _selectedTicketType = types.where((t) => t.isAvailable).firstOrNull;
          _isLoadingTicketTypes = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading ticket types: $e');
      debugPrint('Stack: $stack');
      if (mounted) {
        setState(() => _isLoadingTicketTypes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load ticket types: $e'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sellTicket() async {
    if (!_formKey.currentState!.validate()) return;

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

    // For cash payments, use the new cash sale flow
    if (_paymentMethod == POSPaymentMethod.cash) {
      await _processCashSale();
      return;
    }

    // For card payments, process payment first
    if (_paymentMethod == POSPaymentMethod.card) {
      final paymentSuccess = await _processCardPayment();
      if (!paymentSuccess) return;
    }

    setState(() => _isLoading = true);

    try {
      final ticket = await ref.read(ticketProvider.notifier).sellTicket(
            eventId: widget.event.id,
            ownerName: _nameController.text.trim().isNotEmpty
                ? _nameController.text.trim()
                : null,
            ownerEmail: _emailController.text.trim().isNotEmpty
                ? _emailController.text.trim()
                : null,
            priceCents: _ticketPrice,
            walletAddress: _walletController.text.trim().isNotEmpty
                ? _walletController.text.trim()
                : null,
            ticketTypeId: _selectedTicketType?.id,
            ticketTypeName: _selectedTicketType?.name,
          );

      if (ticket != null) {
        setState(() {
          _lastSoldTicket = ticket;
          _ticketsSoldThisSession++;
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
                    child: Text('Ticket ${ticket.ticketNumber} sold!'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Error occurred - check provider state for error message
        final error = ref.read(ticketProvider).error;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to sell ticket: ${error ?? "Unknown error"}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sell ticket: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Process cash sale using the edge function.
  Future<void> _processCashSale() async {
    // Validate email if delivery method is email
    if (_cashDeliveryMethod == CashDeliveryMethod.email) {
      final email = _emailController.text.trim();
      if (email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email is required for email delivery'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // Basic email validation
      if (!email.contains('@') || !email.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid email address'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final repository = CashTransactionRepository();
      final result = await repository.createCashSale(
        eventId: widget.event.id,
        amountCents: _ticketPrice,
        deliveryMethod: _cashDeliveryMethod,
        ticketTypeId: _selectedTicketType?.id,
        customerName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : null,
        customerEmail: _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : null,
      );

      if (!result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to process cash sale'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Sale successful
      setState(() => _ticketsSoldThisSession++);

      HapticFeedback.mediumImpact();

      // Show warning if fee wasn't charged
      if (result.warning != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.warning!),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Handle delivery method
      if (_cashDeliveryMethod == CashDeliveryMethod.nfc &&
          result.transferToken != null) {
        // Navigate to NFC transfer screen
        if (mounted) {
          final transferred = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => NfcTicketTransferScreen(
                ticketId: result.ticketId!,
                ticketNumber: result.ticketNumber!,
                transferToken: result.transferToken!,
                transferTokenExpiresAt: result.transferTokenExpiresAt!,
                eventTitle: widget.event.title,
                amountCents: _ticketPrice,
              ),
            ),
          );

          if (transferred == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Ticket ${result.ticketNumber} transferred!'),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else if (_cashDeliveryMethod == CashDeliveryMethod.email) {
        // Email delivery - show confirmation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.email, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ticket ${result.ticketNumber} sent to ${_emailController.text.trim()}',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // In-person delivery - show ticket number
        if (mounted) {
          _showInPersonTicketDialog(result.ticketNumber!);
        }
      }

      // Clear form for next sale
      _nameController.clear();
      _emailController.clear();
      _walletController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process cash sale: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Show dialog with ticket number for in-person delivery.
  void _showInPersonTicketDialog(String ticketNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Text('Ticket Sold!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tell the customer their ticket number:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ticketNumber,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'They can use this to check in at the event.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Process card payment using Stripe Payment Sheet.
  Future<bool> _processCardPayment() async {
    setState(() => _isProcessingPayment = true);

    try {
      // Initialize payment using the payment provider
      final success = await ref.read(paymentProcessProvider.notifier).initializeVendorPOS(
        eventId: widget.event.id,
        amountCents: _ticketPrice,
        metadata: {
          'customer_name': _nameController.text.trim(),
          'customer_email': _emailController.text.trim(),
          'payment_method': 'card',
          'sale_type': 'vendor_pos',
        },
      );

      if (!success) {
        final error = ref.read(paymentProcessProvider).error;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error ?? 'Failed to initialize payment'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }

      // Present the Stripe Payment Sheet
      final paymentSuccess = await ref.read(paymentProcessProvider.notifier).presentPaymentSheet();

      if (!paymentSuccess) {
        final error = ref.read(paymentProcessProvider).error;
        if (error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        // User cancelled or payment failed
        return false;
      }

      // Payment successful
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      setState(() => _isProcessingPayment = false);
      // Clear payment state for next transaction
      ref.read(paymentProcessProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell Ticket'),
        centerTitle: true,
        actions: [
          if (_ticketsSoldThisSession > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  avatar: const Icon(Icons.confirmation_number, size: 18),
                  label: Text('$_ticketsSoldThisSession sold'),
                  backgroundColor: colorScheme.primaryContainer,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Event info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.secondary,
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.event,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.event.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.event.displayLocation ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formattedPrice,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text(
                          _selectedTicketType?.name ?? 'per ticket',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Ticket type selector (if event has ticket types)
            if (_isLoadingTicketTypes)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_ticketTypes.isNotEmpty) ...[
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
              const SizedBox(height: 16),
            ],

            // Sale form
            Form(
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
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: _paymentMethod == POSPaymentMethod.cash &&
                              _cashDeliveryMethod == CashDeliveryMethod.email
                          ? 'Required for email delivery'
                          : 'For ticket delivery (optional)',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: const OutlineInputBorder(),
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

                  // Payment method selector
                  Text(
                    'Payment Method',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _PaymentMethodCard(
                          icon: Icons.credit_card,
                          label: 'Card',
                          sublabel: 'Apple/Google Pay',
                          isSelected: _paymentMethod == POSPaymentMethod.card,
                          onTap: () => setState(() => _paymentMethod = POSPaymentMethod.card),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PaymentMethodCard(
                          icon: Icons.payments_outlined,
                          label: 'Cash',
                          sublabel: _cashSalesEnabled
                              ? 'Collect manually'
                              : 'Not enabled',
                          isSelected: _paymentMethod == POSPaymentMethod.cash,
                          onTap: _cashSalesEnabled || _isCheckingCashSales
                              ? () => setState(() => _paymentMethod = POSPaymentMethod.cash)
                              : null,
                          isDisabled: !_cashSalesEnabled && !_isCheckingCashSales,
                        ),
                      ),
                    ],
                  ),

                  // Cash delivery method selector (only shown when cash is selected and enabled)
                  if (_paymentMethod == POSPaymentMethod.cash && _cashSalesEnabled) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Ticket Delivery',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DeliveryMethodSelector(
                      selectedMethod: _cashDeliveryMethod,
                      onChanged: (method) => setState(() => _cashDeliveryMethod = method),
                    ),
                  ],

                  // Cash not enabled warning
                  if (_paymentMethod == POSPaymentMethod.cash && !_cashSalesEnabled && !_isCheckingCashSales) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Cash sales are not enabled for this event. The organizer needs to set up a payment method first.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Sell button
                  FilledButton.icon(
                    onPressed: (_isLoading || _isProcessingPayment ||
                            (_paymentMethod == POSPaymentMethod.cash && !_cashSalesEnabled))
                        ? null
                        : _sellTicket,
                    icon: (_isLoading || _isProcessingPayment)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_paymentMethod == POSPaymentMethod.card
                            ? Icons.credit_card
                            : Icons.point_of_sale),
                    label: Text(
                      _isProcessingPayment
                          ? 'Processing Payment...'
                          : _isLoading
                              ? 'Creating Ticket...'
                              : _paymentMethod == POSPaymentMethod.card
                                  ? 'Charge $_formattedPrice'
                                  : 'Sell Ticket - $_formattedPrice',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // Platform fee info for cash sales
                  if (_paymentMethod == POSPaymentMethod.cash && _cashSalesEnabled && _ticketPrice > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '5% platform fee (\$${(_ticketPrice * 0.05 / 100).toStringAsFixed(2)}) will be charged to the organizer',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // Last sold ticket info
            if (_lastSoldTicket != null) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Last Sold Ticket',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                      if (_lastSoldTicket!.ownerName != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Customer'),
                            Text(_lastSoldTicket!.ownerName!),
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
          ],
        ),
      ),
    );
  }
}

/// Card widget for selecting payment method.
class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: isDisabled ? null : onTap,
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
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected
                  ? colorScheme.primary
                  : isDisabled
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? colorScheme.primary
                    : isDisabled
                        ? colorScheme.onSurface.withValues(alpha: 0.5)
                        : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.8)
                    : isDisabled
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector widget for cash delivery method.
class _DeliveryMethodSelector extends StatelessWidget {
  const _DeliveryMethodSelector({
    required this.selectedMethod,
    required this.onChanged,
  });

  final CashDeliveryMethod selectedMethod;
  final ValueChanged<CashDeliveryMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        _DeliveryMethodChip(
          icon: Icons.nfc,
          label: 'NFC',
          isSelected: selectedMethod == CashDeliveryMethod.nfc,
          onTap: () => onChanged(CashDeliveryMethod.nfc),
        ),
        const SizedBox(width: 8),
        _DeliveryMethodChip(
          icon: Icons.email_outlined,
          label: 'Email',
          isSelected: selectedMethod == CashDeliveryMethod.email,
          onTap: () => onChanged(CashDeliveryMethod.email),
        ),
        const SizedBox(width: 8),
        _DeliveryMethodChip(
          icon: Icons.person_outline,
          label: 'In-Person',
          isSelected: selectedMethod == CashDeliveryMethod.inPerson,
          onTap: () => onChanged(CashDeliveryMethod.inPerson),
        ),
      ],
    );
  }
}

class _DeliveryMethodChip extends StatelessWidget {
  const _DeliveryMethodChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
