import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../core/services/services.dart';
import '../models/payment_method.dart';

/// Screen for viewing and managing saved payment methods (cards).
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(paymentMethodsProvider.notifier).load();
    });
  }

  Future<void> _handleAddCard() async {
    if (!StripeService.isSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card management is only available on mobile devices'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await ref.read(paymentMethodsProvider.notifier).addCard();
  }

  Future<void> _handleDelete(PaymentMethodCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Card'),
        content: Text(
          'Remove ${card.displayBrand} ending in ${card.last4}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(paymentMethodsProvider.notifier).deleteCard(card.id);
    }
  }

  Future<void> _handleSetDefault(PaymentMethodCard card) async {
    if (card.isDefault) return;
    await ref.read(paymentMethodsProvider.notifier).setDefault(card.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(paymentMethodsProvider);

    // Show error snackbar
    ref.listen<PaymentMethodsState>(paymentMethodsProvider, (prev, next) {
      if (next.hasError && prev?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            behavior: SnackBarBehavior.floating,
            backgroundColor: theme.colorScheme.error,
          ),
        );
        ref.read(paymentMethodsProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(paymentMethodsProvider.notifier).load(),
        child: state.isLoading && state.methods.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.isEmpty
                ? _EmptyState(onAddCard: _handleAddCard)
                : _CardList(
                    methods: state.methods,
                    isLoading: state.isLoading,
                    onDelete: _handleDelete,
                    onSetDefault: _handleSetDefault,
                    onAddCard: _handleAddCard,
                  ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddCard});

  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Icon(
          Icons.credit_card_off_outlined,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'No cards saved',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add a card to speed up checkout.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: FilledButton.icon(
            onPressed: onAddCard,
            icon: const Icon(Icons.add),
            label: const Text('Add Card'),
          ),
        ),
      ],
    );
  }
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.methods,
    required this.isLoading,
    required this.onDelete,
    required this.onSetDefault,
    required this.onAddCard,
  });

  final List<PaymentMethodCard> methods;
  final bool isLoading;
  final ValueChanged<PaymentMethodCard> onDelete;
  final ValueChanged<PaymentMethodCard> onSetDefault;
  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        ...methods.map(
          (card) => _CardTile(
            card: card,
            onDelete: () => onDelete(card),
            onSetDefault: () => onSetDefault(card),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onAddCard,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add Card'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.onDelete,
    required this.onSetDefault,
  });

  final PaymentMethodCard card;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  IconData _brandIcon(String brand) {
    // Material Icons doesn't have specific card brand icons,
    // so we use a generic credit card icon with color differentiation.
    return Icons.credit_card;
  }

  Color _brandColor(String brand, ColorScheme colorScheme) {
    switch (brand.toLowerCase()) {
      case 'visa':
        return const Color(0xFF1A1F71);
      case 'mastercard':
        return const Color(0xFFEB001B);
      case 'amex':
        return const Color(0xFF2E77BC);
      case 'discover':
        return const Color(0xFFFF6000);
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brandColor = _brandColor(card.brand, colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Dismissible(
        key: ValueKey(card.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDelete();
          return false; // We handle removal via the notifier
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: colorScheme.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.delete_outline,
            color: colorScheme.onError,
          ),
        ),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: card.isDefault
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant,
              width: card.isDefault ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onSetDefault,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Card brand icon
                  Container(
                    width: 48,
                    height: 32,
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _brandIcon(card.brand),
                      color: brandColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Card details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${card.displayBrand} ****${card.last4}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (card.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Default',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Expires ${card.formattedExpiry}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: card.isExpired
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onSelected: (value) {
                      if (value == 'default') onSetDefault();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      if (!card.isDefault)
                        const PopupMenuItem(
                          value: 'default',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 20),
                              SizedBox(width: 12),
                              Text('Set as Default'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20,
                                color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 12),
                            Text('Remove',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
