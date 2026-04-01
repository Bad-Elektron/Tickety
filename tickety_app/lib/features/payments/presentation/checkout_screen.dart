import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../events/models/event_model.dart';
import '../models/payment_method.dart';
import '../../wallet/data/wallet_repository.dart';
import '../../wallet/models/linked_bank_account.dart';
import '../models/payment.dart';
import 'payment_success_screen.dart';

/// Checkout screen for purchasing tickets.
///
/// Supports primary purchase, resale purchase, and vendor POS payments.
/// When the user has a linked bank account, offers an "ACH Bank Payment"
/// option with lower fees (5% platform + 0.8% ACH, no Stripe card processing).
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

enum _PaymentMethod { bank, card }

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isInitializing = false;
  bool _isPaymentReady = false;
  bool _isOwnListing = false;
  bool _isBankPurchasing = false;
  _PaymentMethod _selectedMethod = _PaymentMethod.card;
  List<LinkedBankAccount> _bankAccounts = [];
  bool _isBankLoading = true;
  bool _promoExpanded = false;
  final _promoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkOwnListing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isOwnListing) {
        _initializePayment();
        _loadBankAccounts();
      }
    });
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
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

  Future<void> _loadBankAccounts() async {
    try {
      final repo = WalletRepository();
      final accounts = await repo.getBankAccounts();
      if (mounted) {
        setState(() {
          _bankAccounts = accounts;
          _isBankLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isBankLoading = false);
    }
  }

  /// Whether bank payment is available for this purchase type.
  bool get _canUseBank =>
      widget.paymentType == PaymentType.primaryPurchase &&
      widget.event.priceInCents != null &&
      widget.event.priceInCents! > 0;

  /// Whether user has a linked bank account.
  bool get _hasLinkedBank => _bankAccounts.isNotEmpty;

  /// Get the default bank account.
  LinkedBankAccount? get _defaultBank =>
      _bankAccounts.isEmpty ? null : _bankAccounts.first;

  /// The raw base cents before any discount.
  int get _rawBaseCents =>
      (widget.baseUnitPriceCents ?? widget.event.priceInCents ?? 0) *
      widget.quantity;

  /// Discount cents from promo code.
  int get _promoDiscountCents {
    final promoState = ref.read(promoValidationProvider);
    return promoState.discountCents;
  }

  /// The discounted base (base - promo discount).
  int get _discountedBaseCents =>
      (_rawBaseCents - _promoDiscountCents).clamp(0, _rawBaseCents);

  /// The total for a bank (ACH) purchase.
  ACHPurchaseFeeBreakdown get _bankFees {
    return ACHPurchaseFeeCalculator.calculate(_discountedBaseCents);
  }

  /// The total for a card purchase (existing fee structure).
  FeeBreakdown get _cardFees {
    return ServiceFeeCalculator.calculate(_discountedBaseCents);
  }

  /// The savings when using bank vs card.
  int get _bankSavings => _cardFees.totalCents - _bankFees.totalCents;

  Future<void> _initializePayment() async {
    if (_isOwnListing) return;

    setState(() => _isInitializing = true);

    final notifier = ref.read(paymentProcessProvider.notifier);
    bool success;

    switch (widget.paymentType) {
      case PaymentType.primaryPurchase:
        final promoState = ref.read(promoValidationProvider);
        final effectiveAmount = promoState.hasDiscount
            ? _cardFees.totalCents
            : widget.amountCents;
        // Extract seat_selections from metadata if present
        final seatSelections = widget.metadata?['seat_selections'] as List?;
        success = await notifier.initializePrimaryPurchase(
          eventId: widget.event.id,
          amountCents: effectiveAmount,
          currency: ref.read(currencyCodeProvider),
          quantity: widget.quantity,
          metadata: widget.metadata,
          promoCodeId: promoState.promoCodeId,
          seatSelections: seatSelections?.cast<Map<String, dynamic>>(),
        );
      case PaymentType.resalePurchase:
        if (widget.resaleListingId == null) {
          setState(() => _isInitializing = false);
          return;
        }
        success = await notifier.initializeResalePurchase(
          resaleListingId: widget.resaleListingId!,
          amountCents: widget.amountCents,
          currency: ref.read(currencyCodeProvider),
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
      case PaymentType.achPurchase:
      case PaymentType.waitlistAutoPurchase:
      case PaymentType.merchPurchase:
        success = false;
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isPaymentReady = success;
      });
    }
  }

  void _applyPromoCode() {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    ref.read(promoValidationProvider.notifier).validateCode(
      eventId: widget.event.id,
      code: code,
      basePriceCents: _rawBaseCents,
    );

    // Re-initialize card payment after validation completes
    Future.delayed(const Duration(milliseconds: 100), () {
      // Watch for state changes via listener below
    });
  }

  Future<void> _handlePay() async {
    if (_selectedMethod == _PaymentMethod.bank) {
      await _handleBankPay();
    } else {
      await _handleCardPay();
    }
  }

  /// Whether to use the inline payment flow instead of native PaymentSheet.
  /// Stripe SDK 25.6.x crashes on iOS 26+ when presenting PaymentSheet.
  bool get _useInlinePayment {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    // iOS 26.0 = Darwin version string starts with "26"
    final osVersion = Platform.operatingSystemVersion;
    final majorMatch = RegExp(r'(\d+)\.').firstMatch(osVersion);
    final major = int.tryParse(majorMatch?.group(1) ?? '') ?? 0;
    return major >= 26;
  }

  Future<void> _handleCardPay() async {
    if (_useInlinePayment) {
      await _showInlinePaymentSheet();
      return;
    }

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

  Future<void> _showInlinePaymentSheet() async {
    // Load saved cards
    await ref.read(paymentMethodsProvider.notifier).load();

    if (!mounted) return;

    final paymentState = ref.read(paymentProcessProvider);
    final clientSecret = paymentState.paymentIntent?.clientSecret;
    if (clientSecret == null) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InlinePaymentSheet(
        clientSecret: clientSecret,
        methods: ref.read(paymentMethodsProvider).methods,
      ),
    );

    if (result == true && mounted) {
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

  Future<void> _handleBankPay() async {
    final bank = _defaultBank;
    if (bank == null) return;

    setState(() => _isBankPurchasing = true);

    try {
      final repo = WalletRepository();
      final promoState = ref.read(promoValidationProvider);
      final seatSelections = widget.metadata?['seat_selections'] as List?;
      await repo.purchaseWithBank(
        eventId: widget.event.id,
        quantity: widget.quantity,
        paymentMethodId: bank.stripePaymentMethodId,
        amountCents: _bankFees.totalCents,
        promoCodeId: promoState.promoCodeId,
        seatSelections: seatSelections?.cast<Map<String, dynamic>>(),
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PaymentSuccessScreen(
              event: widget.event,
              amountCents: _bankFees.totalCents,
              quantity: widget.quantity,
              isACH: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBankPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paymentState = ref.watch(paymentProcessProvider);

    final promoState = ref.watch(promoValidationProvider);

    // Re-initialize card payment when promo code is applied/removed
    ref.listen<PromoValidationState>(promoValidationProvider, (prev, next) {
      final hadDiscount = prev?.hasDiscount ?? false;
      final hasDiscount = next.hasDiscount;
      if (hadDiscount != hasDiscount && !next.isValidating) {
        _initializePayment();
      }
    });

    final bankAvailable = _canUseBank && _hasLinkedBank && !_isBankLoading;

    final isBankSelected = _selectedMethod == _PaymentMethod.bank;
    final displayTotal = isBankSelected
        ? _bankFees.totalCents
        : (promoState.hasDiscount ? _cardFees.totalCents : widget.amountCents);

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('payments_checkout_title')),
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

                    // Promo code section (primary purchases only)
                    if (widget.paymentType == PaymentType.primaryPurchase) ...[
                      if (promoState.hasDiscount) ...[
                        // Applied state: green chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${promoState.appliedCode}: -${_formatAmount(promoState.discountCents)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: Colors.green.shade700,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  ref
                                      .read(promoValidationProvider.notifier)
                                      .clearCode();
                                  _promoController.clear();
                                  // Re-initialize payment with original amount
                                  _initializePayment();
                                },
                              ),
                            ],
                          ),
                        ),
                      ] else if (_promoExpanded) ...[
                        // Expanded: input field + apply button
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _promoController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: L.tr('payments_promo_code'),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  errorText: promoState.error,
                                ),
                                onSubmitted: (_) => _applyPromoCode(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: promoState.isValidating
                                    ? null
                                    : _applyPromoCode,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: promoState.isValidating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(L.tr('common_apply')),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Collapsed: "Have a promo code?" button
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => _promoExpanded = true),
                            icon: const Icon(
                              Icons.discount_outlined,
                              size: 18,
                            ),
                            label: Text(L.tr('payments_have_promo_code')),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],

                    // Payment method selector (only for primary purchases with linked bank)
                    if (bankAvailable) ...[
                      Text(
                        L.tr('payments_payment_method'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PaymentMethodSelector(
                        selectedMethod: _selectedMethod,
                        bankName: _defaultBank?.displayName ?? 'Bank Account',
                        savings: _bankSavings,
                        onSelect: (method) =>
                            setState(() => _selectedMethod = method),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Order summary
                    Text(
                      L.tr('payments_order_summary'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (isBankSelected)
                      _BankOrderSummaryCard(
                        quantity: widget.quantity,
                        unitPriceCents: widget.baseUnitPriceCents ??
                            widget.event.priceInCents ??
                            0,
                        bankFees: _bankFees,
                        cardTotal: _cardFees.totalCents,
                        discountCents: _promoDiscountCents,
                        promoCode: promoState.appliedCode,
                      )
                    else
                      _OrderSummaryCard(
                        quantity: widget.quantity,
                        unitPriceCents: widget.baseUnitPriceCents ??
                            widget.event.priceInCents ??
                            (widget.amountCents ~/ widget.quantity),
                        totalCents: promoState.hasDiscount
                            ? _cardFees.totalCents
                            : widget.amountCents,
                        paymentType: widget.paymentType,
                        discountCents: _promoDiscountCents,
                        promoCode: promoState.appliedCode,
                      ),
                    const SizedBox(height: 24),

                    // Payment method info (only show for card)
                    if (!isBankSelected)
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
                                    L.tr('payments_payment_method'),
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    L.tr('payments_card_apple_google_pay'),
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
                    if (paymentState.hasError && !isBankSelected) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(
                        message: paymentState.error!,
                        onRetry: _initializePayment,
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
                        L.tr('payments_total'),
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
                          L.tr('payments_cannot_buy_own_ticket'),
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
                          L.tr('payments_this_is_your_listing'),
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
                            isBankSelected, paymentState),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isInitializing ||
                                paymentState.isLoading ||
                                _isBankPurchasing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                isBankSelected
                                    ? 'Pay with Bank ${_formatAmount(displayTotal)}'
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
                          isBankSelected
                              ? Icons.account_balance
                              : Icons.lock_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isBankSelected
                              ? L.tr('ach_bank_transfer_info')
                              : L.tr('secured_by_stripe'),
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
      bool isBank, PaymentProcessState paymentState) {
    if (isBank) {
      return _isBankPurchasing ? null : _handlePay;
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
  final String bankName;
  final int savings;
  final void Function(_PaymentMethod) onSelect;

  const _PaymentMethodSelector({
    required this.selectedMethod,
    required this.bankName,
    required this.savings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Bank option
        _MethodTile(
          icon: Icons.account_balance,
          title: L.tr('payments_bank_transfer'),
          subtitle: bankName,
          isSelected: selectedMethod == _PaymentMethod.bank,
          onTap: () => onSelect(_PaymentMethod.bank),
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
          title: L.tr('payments_card_payment'),
          subtitle: L.tr('payments_card_apple_google_pay'),
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
// BANK ORDER SUMMARY (5% platform + 0.8% ACH fee)
// ============================================================

class _BankOrderSummaryCard extends StatelessWidget {
  final int quantity;
  final int unitPriceCents;
  final ACHPurchaseFeeBreakdown bankFees;
  final int cardTotal;
  final int discountCents;
  final String? promoCode;

  const _BankOrderSummaryCard({
    required this.quantity,
    required this.unitPriceCents,
    required this.bankFees,
    required this.cardTotal,
    this.discountCents = 0,
    this.promoCode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final savings = cardTotal - bankFees.totalCents;

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
            amount: _formatAmount(unitPriceCents * quantity),
          ),
          if (discountCents > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Discount${promoCode != null ? ' ($promoCode)' : ''}',
              amount: '-${_formatAmount(discountCents)}',
              isDiscount: true,
            ),
          ],
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Platform fee (5%)',
            amount: _formatAmount(bankFees.platformFeeCents),
            isSubtle: true,
          ),
          const SizedBox(height: 4),
          _SummaryRow(
            label: 'ACH processing (0.8%)',
            amount: _formatAmount(bankFees.achFeeCents),
            isSubtle: true,
          ),
          const SizedBox(height: 12),
          Divider(color: colorScheme.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'Total',
            amount: _formatAmount(bankFees.totalCents),
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
  final bool isDiscount;

  const _SummaryRow({
    required this.label,
    required this.amount,
    this.isSubtle = false,
    this.isBold = false,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color? textColor;
    if (isDiscount) {
      textColor = Colors.green.shade700;
    } else if (isSubtle) {
      textColor = colorScheme.onSurfaceVariant;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: isDiscount ? FontWeight.w600 : null,
                ),
        ),
        Text(
          amount,
          style: isBold
              ? theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: isDiscount ? FontWeight.w600 : null,
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
    this.discountCents = 0,
    this.promoCode,
  });

  final int quantity;
  final int unitPriceCents;
  final int totalCents;
  final PaymentType paymentType;
  final int discountCents;
  final String? promoCode;

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
          if (discountCents > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Discount${promoCode != null ? ' ($promoCode)' : ''}',
              amount: '-${_formatAmount(discountCents)}',
              isDiscount: true,
            ),
          ],
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

// ============================================================
// INLINE PAYMENT SHEET (iOS 26+ fallback)
// Stripe SDK 25.6.x crashes when presenting native PaymentSheet on iOS 26.
// This bottom sheet mimics the PaymentSheet UX using Flutter widgets.
// ============================================================

class _InlinePaymentSheet extends StatefulWidget {
  const _InlinePaymentSheet({
    required this.clientSecret,
    required this.methods,
  });

  final String clientSecret;
  final List<PaymentMethodCard> methods;

  @override
  State<_InlinePaymentSheet> createState() => _InlinePaymentSheetState();
}

class _InlinePaymentSheetState extends State<_InlinePaymentSheet> {
  String? _selectedMethodId;
  bool _useNewCard = false;
  bool _cardComplete = false;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.methods.isNotEmpty) {
      final defaultCard = widget.methods.where((m) => m.isDefault).firstOrNull;
      _selectedMethodId = defaultCard?.id ?? widget.methods.first.id;
    } else {
      _useNewCard = true;
    }
  }

  Future<void> _pay() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      if (_useNewCard) {
        await Stripe.instance.confirmPayment(
          paymentIntentClientSecret: widget.clientSecret,
          data: const PaymentMethodParams.card(
            paymentMethodData: PaymentMethodData(),
          ),
        );
      } else {
        await Stripe.instance.confirmPayment(
          paymentIntentClientSecret: widget.clientSecret,
          data: PaymentMethodParams.cardFromMethodId(
            paymentMethodData: PaymentMethodDataCardFromMethod(
              paymentMethodId: _selectedMethodId!,
            ),
          ),
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e.error.localizedMessage ?? 'Payment failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Select payment method',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Saved cards
              if (widget.methods.isNotEmpty) ...[
                ...widget.methods.map((card) {
                  final isSelected = !_useNewCard && _selectedMethodId == card.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setState(() {
                        _selectedMethodId = card.id;
                        _useNewCard = false;
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                          color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.15) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.credit_card, size: 28, color: colorScheme.onSurface),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${card.displayBrand} ····${card.last4}',
                                    style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                                  ),
                                  Text(
                                    'Expires ${card.formattedExpiry}',
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: colorScheme.primary, size: 22),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),

                // Add new card option
                InkWell(
                  onTap: () => setState(() => _useNewCard = true),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _useNewCard ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
                        width: _useNewCard ? 2 : 1,
                      ),
                      color: _useNewCard ? colorScheme.primaryContainer.withValues(alpha: 0.15) : null,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline, size: 28, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'New card',
                            style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                          ),
                        ),
                        if (_useNewCard)
                          Icon(Icons.check_circle, color: colorScheme.primary, size: 22),
                      ],
                    ),
                  ),
                ),
              ],

              // Card field for new card entry
              if (_useNewCard) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: CardField(
                    enablePostalCode: true,
                    autofocus: widget.methods.isEmpty,
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                      ),
                    ),
                    onCardChanged: (details) {
                      setState(() => _cardComplete = details?.complete ?? false);
                    },
                  ),
                ),
              ],

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colorScheme.error, fontSize: 13)),
              ],

              const SizedBox(height: 20),

              // Pay button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isProcessing ||
                          (_useNewCard && !_cardComplete) ||
                          (!_useNewCard && _selectedMethodId == null)
                      ? null
                      : _pay,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Pay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
