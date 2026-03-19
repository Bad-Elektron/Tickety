import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/services.dart';

/// Bottom sheet for joining the waitlist.
class WaitlistSheet extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final int? eventPriceCents;

  const WaitlistSheet({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.eventPriceCents,
  });

  @override
  ConsumerState<WaitlistSheet> createState() => _WaitlistSheetState();
}

class _WaitlistSheetState extends ConsumerState<WaitlistSheet> {
  bool _isAutoBuy = false;
  final _maxPriceController = TextEditingController();
  String? _selectedPaymentMethodId;

  @override
  void initState() {
    super.initState();
    // Default max price to event price + 20% buffer
    if (widget.eventPriceCents != null && widget.eventPriceCents! > 0) {
      final defaultMax = (widget.eventPriceCents! * 1.2 / 100).ceil();
      _maxPriceController.text = defaultMax.toString();
    }
    // Load payment methods
    ref.read(paymentMethodsProvider.notifier).load();
  }

  @override
  void dispose() {
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final waitlistState = ref.watch(waitlistProvider(widget.eventId));
    final paymentMethodsState = ref.watch(paymentMethodsProvider);

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
              L.tr('waitlist_join_title'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              widget.eventTitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          // Already on waitlist
          if (waitlistState.isOnWaitlist) ...[
            _ActiveWaitlistCard(
              entry: waitlistState.entry!,
              position: waitlistState.position,
              isLoading: waitlistState.isLoading,
              onLeave: () {
                ref.read(waitlistProvider(widget.eventId).notifier).leave();
              },
            ),
          ] else ...[
            // Mode selector
            _ModeSelector(
              isAutoBuy: _isAutoBuy,
              onChanged: (value) => setState(() => _isAutoBuy = value),
            ),
            const SizedBox(height: 20),

            // Auto-buy options
            if (_isAutoBuy) ...[
              // Max price input
              Text(
                L.tr('waitlist_max_price'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _maxPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  hintText: 'e.g. 50',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Payment method selection
              Text(
                L.tr('waitlist_payment_method'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              if (paymentMethodsState.isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (paymentMethodsState.methods.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          L.tr('waitlist_no_payment_methods'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...paymentMethodsState.methods.map(
                  (method) {
                    final selectedId = _selectedPaymentMethodId ??
                        paymentMethodsState.defaultMethod?.id;
                    final isSelected = method.id == selectedId;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        '${method.brand.toUpperCase()} ****${method.last4}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        'Expires ${method.expMonth}/${method.expYear}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => setState(
                          () => _selectedPaymentMethodId = method.id),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
            ],

            // Error message
            if (waitlistState.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  waitlistState.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),

            // Join button
            FilledButton(
              onPressed: waitlistState.isLoading ? null : _onJoin,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: waitlistState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isAutoBuy
                          ? L.tr('waitlist_enable_auto_purchase')
                          : L.tr('waitlist_notify_when_available'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  void _onJoin() {
    final notifier = ref.read(waitlistProvider(widget.eventId).notifier);

    if (_isAutoBuy) {
      final maxPriceText = _maxPriceController.text.trim();
      if (maxPriceText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('waitlist_enter_max_price'))),
        );
        return;
      }

      final maxPriceDollars = int.tryParse(maxPriceText);
      if (maxPriceDollars == null || maxPriceDollars <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('waitlist_enter_valid_price'))),
        );
        return;
      }

      final paymentMethodsState = ref.read(paymentMethodsProvider);
      final selectedId =
          _selectedPaymentMethodId ?? paymentMethodsState.defaultMethod?.id;
      if (selectedId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L.tr('waitlist_add_payment_method'))),
        );
        return;
      }

      // Get Stripe customer ID from current user's profile
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;

      // We need the stripe_customer_id — fetch it
      _fetchCustomerIdAndJoin(
        maxPriceCents: maxPriceDollars * 100,
        paymentMethodId: selectedId,
      );
    } else {
      notifier.joinNotify();
    }
  }

  Future<void> _fetchCustomerIdAndJoin({
    required int maxPriceCents,
    required String paymentMethodId,
  }) async {
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;

      final response = await SupabaseService.instance.client
          .from('profiles')
          .select('stripe_customer_id')
          .eq('id', userId)
          .single();

      final stripeCustomerId = response['stripe_customer_id'] as String?;
      if (stripeCustomerId == null || stripeCustomerId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  L.tr('waitlist_no_stripe_customer')),
            ),
          );
        }
        return;
      }

      ref.read(waitlistProvider(widget.eventId).notifier).joinAutoBuy(
            maxPriceCents: maxPriceCents,
            paymentMethodId: paymentMethodId,
            stripeCustomerId: stripeCustomerId,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

/// Toggle between Notify and Auto-Buy modes.
class _ModeSelector extends StatelessWidget {
  final bool isAutoBuy;
  final ValueChanged<bool> onChanged;

  const _ModeSelector({
    required this.isAutoBuy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: _ModeOption(
            icon: Icons.notifications_outlined,
            label: L.tr('waitlist_notify_me'),
            description: L.tr('waitlist_notify_description'),
            isSelected: !isAutoBuy,
            onTap: () => onChanged(false),
            colorScheme: colorScheme,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeOption(
            icon: Icons.flash_on_outlined,
            label: L.tr('waitlist_auto_buy'),
            description: L.tr('waitlist_auto_buy_description'),
            isSelected: isAutoBuy,
            onTap: () => onChanged(true),
            colorScheme: colorScheme,
            theme: theme,
          ),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card showing active waitlist status with option to leave.
class _ActiveWaitlistCard extends StatelessWidget {
  final dynamic entry;
  final int? position;
  final bool isLoading;
  final VoidCallback onLeave;

  const _ActiveWaitlistCard({
    required this.entry,
    required this.position,
    required this.isLoading,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            entry.isAutoBuy
                ? Icons.flash_on_rounded
                : Icons.notifications_active_rounded,
            size: 40,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            L.tr('waitlist_on_waitlist'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.isAutoBuy
                ? 'Auto-buy enabled up to ${entry.formattedMaxPrice}'
                : "We'll notify you when tickets are available",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (position != null) ...[
            const SizedBox(height: 8),
            Text(
              'Position #$position in queue',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: isLoading ? null : onLeave,
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(L.tr('waitlist_leave')),
          ),
        ],
      ),
    );
  }
}
