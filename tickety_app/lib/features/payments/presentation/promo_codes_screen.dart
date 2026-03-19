import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../events/models/event_model.dart';
import '../models/promo_code.dart';

/// Organizer screen for managing promo codes for an event.
class PromoCodesScreen extends ConsumerStatefulWidget {
  final EventModel event;

  const PromoCodesScreen({super.key, required this.event});

  @override
  ConsumerState<PromoCodesScreen> createState() => _PromoCodesScreenState();
}

class _PromoCodesScreenState extends ConsumerState<PromoCodesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(promoCodeManagementProvider(widget.event.id).notifier)
          .loadCodes(widget.event.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(promoCodeManagementProvider(widget.event.id));

    return Scaffold(
      appBar: AppBar(title: Text(L.tr('promo_codes_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        icon: const Icon(Icons.add),
        label: Text(L.tr('promo_create_code')),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.codes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.discount_outlined,
                          size: 64,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          L.tr('promo_no_codes'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          L.tr('promo_create_description'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: state.codes.length,
                  itemBuilder: (context, index) {
                    final code = state.codes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PromoCodeCard(
                        code: code,
                        onToggleActive: () {
                          final notifier = ref.read(
                            promoCodeManagementProvider(widget.event.id)
                                .notifier,
                          );
                          if (code.isActive) {
                            notifier.deactivateCode(code.id);
                          } else {
                            notifier.activateCode(code.id);
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreatePromoCodeSheet(
        eventId: widget.event.id,
        ticketPriceCents: widget.event.priceInCents ?? 0,
        onCreated: () {
          // State already updated by notifier
        },
      ),
    );
  }
}

// ============================================================
// Promo Code Card
// ============================================================

class _PromoCodeCard extends StatelessWidget {
  final PromoCode code;
  final VoidCallback onToggleActive;

  const _PromoCodeCard({
    required this.code,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                // Code in monospace
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    code.code,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const Spacer(),
                // Active/Inactive badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: code.isActive
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    code.isActive ? L.tr('common_active') : L.tr('common_inactive'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: code.isActive ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Details row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _DetailChip(
                  icon: Icons.percent,
                  label: code.formattedDiscount,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                _DetailChip(
                  icon: Icons.people_outline,
                  label: code.formattedUsage,
                  color: colorScheme.tertiary,
                ),
                if (code.validUntil != null) ...[
                  const SizedBox(width: 12),
                  _DetailChip(
                    icon: Icons.schedule,
                    label: _formatDate(code.validUntil!),
                    color: code.validUntil!.isBefore(DateTime.now())
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Actions
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextButton.icon(
              onPressed: onToggleActive,
              icon: Icon(
                code.isActive ? Icons.pause : Icons.play_arrow,
                size: 18,
              ),
              label: Text(code.isActive ? L.tr('common_deactivate') : L.tr('common_activate')),
              style: TextButton.styleFrom(
                foregroundColor: code.isActive
                    ? colorScheme.error
                    : Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

// ============================================================
// Create Promo Code Bottom Sheet
// ============================================================

class _CreatePromoCodeSheet extends ConsumerStatefulWidget {
  final String eventId;
  final int ticketPriceCents;
  final VoidCallback onCreated;

  const _CreatePromoCodeSheet({
    required this.eventId,
    required this.ticketPriceCents,
    required this.onCreated,
  });

  @override
  ConsumerState<_CreatePromoCodeSheet> createState() =>
      _CreatePromoCodeSheetState();
}

class _CreatePromoCodeSheetState
    extends ConsumerState<_CreatePromoCodeSheet> {
  final _codeController = TextEditingController();
  bool _isPercentage = true;
  int _percentValue = 20;
  int _fixedValueCents = 500;
  int? _maxUses;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.text = _generateRandomCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  String get _discountPreview {
    if (widget.ticketPriceCents == 0) return 'Free event';
    final price = widget.ticketPriceCents;
    int discounted;
    if (_isPercentage) {
      discounted = (price * (1 - _percentValue / 100)).round();
    } else {
      discounted = (price - _fixedValueCents).clamp(0, price);
    }
    return '\$${(price / 100).toStringAsFixed(2)} -> \$${(discounted / 100).toStringAsFixed(2)}';
  }

  Future<void> _create() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = L.tr('promo_enter_code'));
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    final notifier =
        ref.read(promoCodeManagementProvider(widget.eventId).notifier);
    final success = await notifier.createCode(
      eventId: widget.eventId,
      code: code,
      discountType: _isPercentage
          ? PromoDiscountType.percentage
          : PromoDiscountType.fixed,
      discountValue: _isPercentage ? _percentValue : _fixedValueCents,
      maxUses: _maxUses,
    );

    if (mounted) {
      if (success) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Promo code "$code" created'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _isCreating = false;
          _error = ref
                  .read(promoCodeManagementProvider(widget.eventId))
                  .error ??
              L.tr('promo_create_failed');
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
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: SingleChildScrollView(
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
              Icons.discount_outlined,
              size: 44,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              L.tr('promo_create_title'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Code input
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: L.tr('promo_code_label'),
                hintText: 'e.g. EARLY20',
                prefixIcon: const Icon(Icons.code, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    _codeController.text = _generateRandomCode();
                  },
                  tooltip: L.tr('promo_generate_random'),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            // Discount type toggle
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ToggleButton(
                      label: L.tr('promo_percentage'),
                      isSelected: _isPercentage,
                      onTap: () => setState(() => _isPercentage = true),
                    ),
                  ),
                  Expanded(
                    child: _ToggleButton(
                      label: L.tr('promo_fixed_amount'),
                      isSelected: !_isPercentage,
                      onTap: () => setState(() => _isPercentage = false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Value input
            if (_isPercentage) ...[
              Text(
                '$_percentValue% off',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              Slider(
                value: _percentValue.toDouble(),
                min: 5,
                max: 100,
                divisions: 19,
                label: '$_percentValue%',
                onChanged: (v) =>
                    setState(() => _percentValue = v.round()),
              ),
            ] else ...[
              Text(
                '\$${(_fixedValueCents / 100).toStringAsFixed(2)} off',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              Slider(
                value: _fixedValueCents.toDouble(),
                min: 100,
                max: (widget.ticketPriceCents > 0
                        ? widget.ticketPriceCents
                        : 10000)
                    .toDouble(),
                divisions:
                    ((widget.ticketPriceCents > 0
                                    ? widget.ticketPriceCents
                                    : 10000) -
                                100) ~/
                            100 ==
                        0
                        ? 1
                        : ((widget.ticketPriceCents > 0
                                    ? widget.ticketPriceCents
                                    : 10000) -
                                100) ~/
                            100,
                label: '\$${(_fixedValueCents / 100).toStringAsFixed(2)}',
                onChanged: (v) =>
                    setState(() => _fixedValueCents = v.round()),
              ),
            ],
            // Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    L.tr('promo_price_preview'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _discountPreview,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Max uses (optional)
            TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L.tr('promo_max_uses'),
                hintText: L.tr('promo_max_uses_hint'),
                prefixIcon: const Icon(Icons.people_outline, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                setState(() => _maxUses = parsed);
              },
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
              onPressed: _isCreating ? null : _create,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      L.tr('promo_create_code'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isCreating ? null : () => Navigator.pop(context),
              child: Text(L.tr('common_cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
