import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../events/models/event_model.dart';
import '../models/payment.dart';
import 'payment_success_screen.dart';

/// Checkout screen for purchasing tickets.
///
/// Supports primary purchase, resale purchase, and vendor POS payments.
/// When the user has sufficient wallet balance, offers a "Tickety Wallet"
/// payment option with lower fees (5% platform only, no Stripe processing).
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

enum _PaymentMethod { wallet, card }

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isInitializing = false;
  bool _isPaymentReady = false;
  bool _isOwnListing = false;
  bool _isWalletPurchasing = false;
  _PaymentMethod _selectedMethod = _PaymentMethod.card;

  @override
  void initState() {
    super.initState();
    _checkOwnListing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isOwnListing) {
        _initializePayment();
        // Load wallet balance to check if wallet payment is available
        ref.read(walletBalanceProvider.notifier).loadBalance();
      }
    });
  }

  void _checkOwnListing() {
    if (widget.paymentType == PaymentType.resalePurchase &&
        widget.sellerId != null) {
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null && currentUserId == widget.sellerId) {
        _isOwnListing = true;
      }
    }
  }

  /// Whether wallet payment is available for this purchase type.
  bool get _canUseWallet =>
      widget.paymentType == PaymentType.primaryPurchase &&
      widget.event.priceInCents != null &&
      widget.event.priceInCents! > 0;

  /// The total for a wallet purchase (5% platform fee only).
  WalletFeeBreakdown get _walletFees {
    final baseCents = (widget.baseUnitPriceCents ?? widget.event.priceInCents ?? 0) *
        widget.quantity;
    return WalletFeeCalculator.calculate(baseCents);
  }

  /// The total for a card purchase (existing fee structure).
  FeeBreakdown get _cardFees {
    final baseCents = (widget.baseUnitPriceCents ?? widget.event.priceInCents ?? 0) *
        widget.quantity;
    return ServiceFeeCalculator.calculate(baseCents);
  }

  /// The savings when using wallet vs card.
  int get _walletSavings => _cardFees.totalCents - _walletFees.totalCents;

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
      case PaymentType.walletPurchase:
      case PaymentType.walletTopUp:
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
    if (_selectedMethod == _PaymentMethod.wallet) {
      await _handleWalletPay();
    } else {
      await _handleCardPay();
    }
  }

  Future<void> _handleCardPay() async {
    final notifier = ref.read(paymentProcessProvider.notifier);
    final success = await notifier.presentPaymentSheet();

    if (success && mounted) {
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

  Future<void> _handleWalletPay() async {
    setState(() => _isWalletPurchasing = true);

    final walletNotifier = ref.read(walletBalanceProvider.notifier);
    final result = await walletNotifier.purchaseFromWallet(
      eventId: widget.event.id,
      quantity: widget.quantity,
    );

    if (result != null && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            event: widget.event,
            amountCents: _walletFees.totalCents,
            quantity: widget.quantity,
          ),
        ),
      );
    } else if (mounted) {
      setState(() => _isWalletPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paymentState = ref.watch(paymentProcessProvider);
    final walletState = ref.watch(walletBalanceProvider);

    final walletAvailable = walletState.availableCents;
    final walletHasFunds = _canUseWallet && walletAvailable >= _walletFees.totalCents;

    // Auto-select wallet if it has enough funds
    if (walletHasFunds && _selectedMethod == _PaymentMethod.card && !_isInitializing) {
      // Don't auto-switch during init, let user see both options
    }

    final isWalletSelected = _selectedMethod == _PaymentMethod.wallet;
    final displayTotal = isWalletSelected ? _walletFees.totalCents : widget.amountCents;

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

                    // Payment method selector (only for primary purchases with wallet funds)
                    if (_canUseWallet && walletHasFunds) ...[
                      Text(
                        'Payment Method',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PaymentMethodSelector(
                        selectedMethod: _selectedMethod,
                        walletBalance: walletState.balance?.formattedAvailable ?? '\$0.00',
                        savings: _walletSavings,
                        onSelect: (method) =>
                            setState(() => _selectedMethod = method),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Order summary
                    Text(
                      'Order Summary',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (isWalletSelected)
                      _WalletOrderSummaryCard(
                        quantity: widget.quantity,
                        unitPriceCents: widget.baseUnitPriceCents ??
                            widget.event.priceInCents ??
                            0,
                        walletFees: _walletFees,
                        cardTotal: _cardFees.totalCents,
                      )
                    else
                      _OrderSummaryCard(
                        quantity: widget.quantity,
                        unitPriceCents: widget.baseUnitPriceCents ??
                            widget.event.priceInCents ??
                            (widget.amountCents ~/ widget.quantity),
                        totalCents: widget.amountCents,
                        paymentType: widget.paymentType,
                      ),
                    const SizedBox(height: 24),

                    // Payment method info (only show for card)
                    if (!isWalletSelected)
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
                                color: colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
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
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Card, Apple Pay, or Google Pay',
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
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

                    // Error messages
                    if (paymentState.hasError && !isWalletSelected) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(
                        message: paymentState.error!,
                        onRetry: _initializePayment,
                      ),
                    ],
                    if (walletState.hasError && isWalletSelected) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(
                        message: walletState.error!,
                        onRetry: () =>
                            ref.read(walletBalanceProvider.notifier).refresh(),
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
                        _formatAmount(displayTotal),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_isOwnListing) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor:
                              colorScheme.surfaceContainerHighest,
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
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _getPayButtonHandler(
                            isWalletSelected, paymentState),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isInitializing ||
                                paymentState.isLoading ||
                                _isWalletPurchasing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                isWalletSelected
                                    ? 'Pay from Wallet ${_formatAmount(displayTotal)}'
                                    : 'Pay ${_formatAmount(displayTotal)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isWalletSelected
                              ? Icons.bolt
                              : Icons.lock_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isWalletSelected
                              ? 'Instant from wallet balance'
                              : 'Secured by Stripe',
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

  VoidCallback? _getPayButtonHandler(
      bool isWallet, PaymentProcessState paymentState) {
    if (isWallet) {
      return _isWalletPurchasing ? null : _handlePay;
    }
    return (_isInitializing || paymentState.isLoading || !_isPaymentReady)
        ? null
        : _handlePay;
  }

  String _formatAmount(int cents) {
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}

// ============================================================
// PAYMENT METHOD SELECTOR
// ============================================================

class _PaymentMethodSelector extends StatelessWidget {
  final _PaymentMethod selectedMethod;
  final String walletBalance;
  final int savings;
  final void Function(_PaymentMethod) onSelect;

  const _PaymentMethodSelector({
    required this.selectedMethod,
    required this.walletBalance,
    required this.savings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Wallet option
        _MethodTile(
          icon: Icons.account_balance_wallet,
          title: 'Tickety Wallet',
          subtitle: 'Balance: $walletBalance',
          isSelected: selectedMethod == _PaymentMethod.wallet,
          onTap: () => onSelect(_PaymentMethod.wallet),
          trailing: savings > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Save \$${(savings / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        // Card option
        _MethodTile(
          icon: Icons.credit_card,
          title: 'Card Payment',
          subtitle: 'Card, Apple Pay, or Google Pay',
          isSelected: selectedMethod == _PaymentMethod.card,
          onTap: () => onSelect(_PaymentMethod.card),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outline.withValues(alpha: 0.15),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.2)
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 20,
                ),
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
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 8),
              ],
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// WALLET ORDER SUMMARY (5% platform fee only)
// ============================================================

class _WalletOrderSummaryCard extends StatelessWidget {
  final int quantity;
  final int unitPriceCents;
  final WalletFeeBreakdown walletFees;
  final int cardTotal;

  const _WalletOrderSummaryCard({
    required this.quantity,
    required this.unitPriceCents,
    required this.walletFees,
    required this.cardTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final savings = cardTotal - walletFees.totalCents;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Ticket ${quantity > 1 ? "x$quantity" : ""}',
            amount: _formatAmount(walletFees.baseCents),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Platform fee (5%)',
            amount: _formatAmount(walletFees.platformFeeCents),
            isSubtle: true,
          ),
          const SizedBox(height: 12),
          Divider(color: colorScheme.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'Total',
            amount: _formatAmount(walletFees.totalCents),
            isBold: true,
          ),
          if (savings > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.savings_outlined,
                    color: Colors.green.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You save ${_formatAmount(savings)} vs card payment',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatAmount(int cents) {
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}

// ============================================================
// EXISTING WIDGETS (kept from original)
// ============================================================

class _SummaryRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isSubtle;
  final bool isBold;

  const _SummaryRow({
    required this.label,
    required this.amount,
    this.isSubtle = false,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodyMedium?.copyWith(
                  color: isSubtle ? colorScheme.onSurfaceVariant : null,
                ),
        ),
        Text(
          amount,
          style: isBold
              ? theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodyMedium?.copyWith(
                  color: isSubtle ? colorScheme.onSurfaceVariant : null,
                ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: onRetry,
            color: colorScheme.error,
          ),
        ],
      ),
    );
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
            child: const Center(
              child: Icon(Icons.event, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(width: 16),
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

    final resaleFeeCents = isResale ? (totalCents * 0.05).round() : 0;
    final resaleSubtotalCents =
        isResale ? totalCents - resaleFeeCents : totalCents;

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
                    : (isPrimaryOrFavor
                        ? baseCents
                        : unitPriceCents * quantity)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
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
                      message:
                          'Includes payment processing and platform fees',
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
                      message:
                          'Platform fee for secure resale transactions',
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
