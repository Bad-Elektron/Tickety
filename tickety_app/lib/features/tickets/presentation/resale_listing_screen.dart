import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/errors.dart';
import '../../../core/graphics/graphics.dart';
import '../../payments/presentation/seller_onboarding_screen.dart';
import '../../staff/models/ticket.dart';

/// Screen for listing a ticket for resale.
///
/// Allows users to set a price. Requires Stripe Connect onboarding
/// for receiving payouts when the ticket sells.
class ResaleListingScreen extends ConsumerStatefulWidget {
  const ResaleListingScreen({super.key, required this.ticket});

  final Ticket ticket;

  @override
  ConsumerState<ResaleListingScreen> createState() => _ResaleListingScreenState();
}

class _ResaleListingScreenState extends ConsumerState<ResaleListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  bool _isLoading = false;
  bool _agreedToTerms = false;
  bool _isSellerOnboarded = false;
  bool _isCheckingOnboarding = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill with original price as suggestion
    if (widget.ticket.pricePaidCents > 0) {
      final dollars = widget.ticket.pricePaidCents / 100;
      _priceController.text = dollars.toStringAsFixed(2);
    }
    _checkOnboardingStatus();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final repository = ref.read(resaleRepositoryProvider);
      var hasAccount = await repository.hasSellerAccount();

      // Auto-create a minimal seller account if the user doesn't have one
      if (!hasAccount) {
        await repository.createSellerAccount();
        hasAccount = true;
      }

      if (mounted) {
        setState(() {
          _isSellerOnboarded = hasAccount;
          _isCheckingOnboarding = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingOnboarding = false;
        });
      }
    }
  }

  Future<void> _navigateToOnboarding() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SellerOnboardingScreen(),
      ),
    );

    if (result == true && mounted) {
      // Re-check onboarding status
      _checkOnboardingStatus();
    }
  }

  Future<void> _listForSale() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      _showError('Please agree to the terms and conditions');
      return;
    }

    if (!_isSellerOnboarded) {
      _showError('Please complete payout setup first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Parse price
      final priceText = _priceController.text.replaceAll(RegExp(r'[^\d.]'), '');
      final priceDollars = double.tryParse(priceText) ?? 0;
      final priceCents = (priceDollars * 100).round();

      // Create resale listing via repository
      final repository = ref.read(resaleRepositoryProvider);
      await repository.createListing(
        ticketId: widget.ticket.id,
        priceCents: priceCents,
      );

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Ticket listed for sale!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      _showError(appError.userMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell Ticket'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ticket preview header
              _TicketPreviewHeader(ticket: widget.ticket),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Original price info
                    if (widget.ticket.pricePaidCents > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Original price: ${widget.ticket.formattedPrice}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Sale price input
                    Text(
                      'Set Your Price',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                        hintText: '0.00',
                        border: const OutlineInputBorder(),
                        helperText: 'Platform fee: 5% of sale price',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a price';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Please enter a valid price';
                        }
                        if (price > 10000) {
                          return 'Maximum price is \$10,000';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Payout method section
                    Text(
                      'Payout Method',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isCheckingOnboarding)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Checking payout status...'),
                          ],
                        ),
                      )
                    else if (_isSellerOnboarded)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Payouts enabled',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'You\'ll receive 95% of the sale via Stripe',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      InkWell(
                        onTap: _navigateToOnboarding,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.error.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet,
                                  color: colorScheme.error,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Payout setup required',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Tap to set up your bank account for payouts',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: colorScheme.error,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Terms checkbox
                    CheckboxListTile(
                      value: _agreedToTerms,
                      onChanged: (value) {
                        setState(() => _agreedToTerms = value ?? false);
                      },
                      title: Text(
                        'I agree to the resale terms and conditions',
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        'The ticket will be transferred to the buyer upon payment',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 24),

                    // Fee breakdown
                    _FeeBreakdown(
                      priceController: _priceController,
                      platformFeePercent: 5,
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    FilledButton(
                      onPressed: (_isLoading || !_isSellerOnboarded || _isCheckingOnboarding)
                          ? null
                          : _listForSale,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isSellerOnboarded ? 'List for Sale' : 'Set Up Payouts First',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Cancel button
                    OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header showing ticket preview.
class _TicketPreviewHeader extends StatelessWidget {
  const _TicketPreviewHeader({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _getNoiseConfig();

    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: config.colors,
        ),
      ),
      child: Stack(
        children: [
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  ticket.eventTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ticket.ticketType,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(ticket.eventDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
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

  NoiseConfig _getNoiseConfig() {
    final presetIndex = ticket.noiseSeed % 5;
    return switch (presetIndex) {
      0 => NoisePresets.vibrantEvents(ticket.noiseSeed),
      1 => NoisePresets.sunset(ticket.noiseSeed),
      2 => NoisePresets.ocean(ticket.noiseSeed),
      3 => NoisePresets.subtle(ticket.noiseSeed),
      _ => NoisePresets.darkMood(ticket.noiseSeed),
    };
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'TBA';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Dynamic fee breakdown that updates as price changes.
class _FeeBreakdown extends StatefulWidget {
  const _FeeBreakdown({
    required this.priceController,
    required this.platformFeePercent,
  });

  final TextEditingController priceController;
  final double platformFeePercent;

  @override
  State<_FeeBreakdown> createState() => _FeeBreakdownState();
}

class _FeeBreakdownState extends State<_FeeBreakdown> {
  double _salePrice = 0;

  @override
  void initState() {
    super.initState();
    _updatePrice();
    widget.priceController.addListener(_updatePrice);
  }

  @override
  void dispose() {
    widget.priceController.removeListener(_updatePrice);
    super.dispose();
  }

  void _updatePrice() {
    final text = widget.priceController.text;
    setState(() {
      _salePrice = double.tryParse(text) ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final fee = _salePrice * (widget.platformFeePercent / 100);
    final youReceive = _salePrice - fee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _FeeRow(
            label: 'Sale Price',
            value: '\$${_salePrice.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _FeeRow(
            label: 'Platform Fee (${widget.platformFeePercent.toInt()}%)',
            value: '-\$${fee.toStringAsFixed(2)}',
            valueColor: Colors.red.shade400,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _FeeRow(
            label: 'You Receive',
            value: '\$${youReceive.toStringAsFixed(2)}',
            isBold: true,
            valueColor: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isBold ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            fontWeight: isBold ? FontWeight.w600 : null,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: valueColor ?? colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
