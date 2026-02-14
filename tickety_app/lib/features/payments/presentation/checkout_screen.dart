import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../events/models/event_model.dart';
import '../models/payment.dart';
import 'payment_success_screen.dart';

/// Checkout screen for purchasing tickets.
///
/// Supports primary purchase, resale purchase, and vendor POS payments.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.event,
    required this.amountCents,
    required this.paymentType,
    this.quantity = 1,
    this.baseUnitPriceCents,
    this.resaleListingId,
    this.sellerId,
    this.metadata,
  });

  final EventModel event;
  final int amountCents;
  final PaymentType paymentType;
  final int quantity;
  final int? baseUnitPriceCents;
  final String? resaleListingId;
  final String? sellerId;
  final Map<String, dynamic>? metadata;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isInitializing = false;
  bool _isPaymentReady = false;
  bool _isOwnListing = false;

  @override
  void initState() {
    super.initState();
    // Check if this is the user's own listing
    _checkOwnListing();
    // Delay initialization until after the build phase completes
    // to avoid "modifying provider while widget tree is building" error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isOwnListing) {
        _initializePayment();
      }
    });
  }

  void _checkOwnListing() {
    if (widget.paymentType == PaymentType.resalePurchase && widget.sellerId != null) {
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null && currentUserId == widget.sellerId) {
        _isOwnListing = true;
      }
    }
  }

  Future<void> _initializePayment() async {
    if (_isOwnListing) return;

    setState(() => _isInitializing = true);

    final notifier = ref.read(paymentProcessProvider.notifier);
    bool success;

    switch (widget.paymentType) {
      case PaymentType.primaryPurchase:
        success = await notifier.initializePrimaryPurchase(
          eventId: widget.event.id,
          amountCents: widget.amountCents,
          quantity: widget.quantity,
          metadata: widget.metadata,
        );
      case PaymentType.resalePurchase:
        if (widget.resaleListingId == null) {
          setState(() => _isInitializing = false);
          return;
        }
        success = await notifier.initializeResalePurchase(
          resaleListingId: widget.resaleListingId!,
          amountCents: widget.amountCents,
        );
      case PaymentType.vendorPos:
        success = await notifier.initializeVendorPOS(
          eventId: widget.event.id,
          amountCents: widget.amountCents,
          metadata: widget.metadata,
        );
      case PaymentType.favorTicketPurchase:
        final offerId = widget.metadata?['offer_id'] as String?;
        if (offerId == null) {
          setState(() => _isInitializing = false);
          return;
        }
        success = await notifier.initializeFavorTicketPurchase(
          offerId: offerId,
          eventId: widget.event.id,
          amountCents: widget.amountCents,
        );
      case PaymentType.subscription:
        // Subscriptions are handled separately via SubscriptionScreen
        success = false;
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isPaymentReady = success;
      });
    }
  }

  Future<void> _handlePay() async {
    final notifier = ref.read(paymentProcessProvider.notifier);
    final success = await notifier.presentPaymentSheet();

    if (success && mounted) {
      // Navigate to success screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            event: widget.event,
            amountCents: widget.amountCents,
            quantity: widget.quantity,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paymentState = ref.watch(paymentProcessProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(paymentProcessProvider.notifier).clear();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Event summary card
                    _EventSummaryCard(
                      event: widget.event,
                      quantity: widget.quantity,
                    ),
                    const SizedBox(height: 24),

                    // Order summary
                    Text(
                      'Order Summary',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _OrderSummaryCard(
                      quantity: widget.quantity,
                      unitPriceCents: widget.baseUnitPriceCents ??
                          widget.event.priceInCents ??
                          (widget.amountCents ~/ widget.quantity),
                      totalCents: widget.amountCents,
                      paymentType: widget.paymentType,
                    ),
                    const SizedBox(height: 24),

                    // Payment method info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.credit_card,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Payment Method',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Card, Apple Pay, or Google Pay',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.check_circle,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),

                    // Error message
                    if (paymentState.hasError) ...[
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
                              color: colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                paymentState.error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              onPressed: _initializePayment,
                              color: colorScheme.error,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom pay button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Total row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _formatAmount(widget.amountCents),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Pay button or own listing message
                  if (_isOwnListing) ...[
                    // Own listing - show disabled state
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          'Cannot buy your own ticket',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Info message
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'This is your listing',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Normal pay button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_isInitializing || paymentState.isLoading || !_isPaymentReady)
                            ? null
                            : _handlePay,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isInitializing || paymentState.isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                'Pay ${_formatAmount(widget.amountCents)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Secure payment notice
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Secured by Stripe',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(int cents) {
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}

class _EventSummaryCard extends StatelessWidget {
  const _EventSummaryCard({
    required this.event,
    required this.quantity,
  });

  final EventModel event;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event image placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.secondary,
                ],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.event,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Event details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      quantity == 1 ? '1 ticket' : '$quantity tickets',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
    required this.paymentType,
  });

  final int quantity;
  final int unitPriceCents;
  final int totalCents;
  final PaymentType paymentType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isResale = paymentType == PaymentType.resalePurchase;
    final isPrimaryOrFavor = paymentType == PaymentType.primaryPurchase ||
        paymentType == PaymentType.favorTicketPurchase;

    // Resale fee (5%) — unchanged
    final resaleFeeCents = isResale ? (totalCents * 0.05).round() : 0;
    final resaleSubtotalCents = isResale ? totalCents - resaleFeeCents : totalCents;

    // Primary/favor fee calculation
    final baseCents = isPrimaryOrFavor ? unitPriceCents * quantity : 0;
    final fees = isPrimaryOrFavor && baseCents > 0
        ? ServiceFeeCalculator.calculate(baseCents)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Ticket line
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ticket ${quantity > 1 ? "x$quantity" : ""}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                _formatAmount(isResale
                    ? resaleSubtotalCents
                    : (isPrimaryOrFavor ? baseCents : unitPriceCents * quantity)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),

          // Service fee for primary/favor purchases
          if (fees != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Service fee',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Includes payment processing and platform fees',
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Text(
                  _formatAmount(fees.serviceFeeCents),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],

          // Platform fee for resale (unchanged)
          if (isResale) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Service fee (5%)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Platform fee for secure resale transactions',
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Text(
                  _formatAmount(resaleFeeCents),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          Divider(color: colorScheme.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 12),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatAmount(totalCents),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatAmount(int cents) {
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}
