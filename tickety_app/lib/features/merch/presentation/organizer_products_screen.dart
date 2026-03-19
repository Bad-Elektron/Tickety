import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/merch_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/utils/feature_gate.dart';
import '../../events/models/event_model.dart';
import '../../subscriptions/subscriptions.dart';
import '../data/merch_repository.dart';
import '../models/models.dart';
import 'product_detail_screen.dart';

/// Organizer screen for managing merch products.
class OrganizerProductsScreen extends ConsumerStatefulWidget {
  final EventModel? event;

  const OrganizerProductsScreen({super.key, this.event});

  @override
  ConsumerState<OrganizerProductsScreen> createState() => _OrganizerProductsScreenState();
}

class _OrganizerProductsScreenState extends ConsumerState<OrganizerProductsScreen> {
  bool _isSyncing = false;

  String get _organizerId => SupabaseService.instance.currentUser!.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FeatureGate.consumer(
      requiredTier: AccountTier.enterprise,
      builder: (context, ref) {
        final configAsync = ref.watch(merchConfigProvider(_organizerId));
        final productsAsync = ref.watch(organizerProductsProvider(_organizerId));

        return Scaffold(
          appBar: AppBar(
            title: Text(L.tr('merch_store')),
            actions: [
              configAsync.when(
                data: (config) {
                  if (config?.isShopify == true) {
                    return IconButton(
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      tooltip: 'Sync from Shopify',
                      onPressed: _isSyncing ? null : () => _syncShopify(ref),
                    );
                  }
                  return const SizedBox.shrink();
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          floatingActionButton: configAsync.when(
            data: (config) {
              if (config?.isStripe == true) {
                return FloatingActionButton.extended(
                  onPressed: () => _showCreateProductDialog(context),
                  icon: const Icon(Icons.add),
                  label: Text(L.tr('add_product')),
                );
              }
              return null;
            },
            loading: () => null,
            error: (_, __) => null,
          ),
          body: Column(
            children: [
              // Config banner
              configAsync.when(
                data: (config) => _ConfigBanner(
                  config: config,
                  onSetup: () => _showSetupSheet(context, ref),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // Product list
              Expanded(
                child: productsAsync.when(
                  data: (products) {
                    if (products.isEmpty) {
                      return _buildEmptyState(theme, colorScheme);
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(organizerProductsProvider(_organizerId));
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return _ProductManagementCard(
                            product: product,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProductDetailScreen(product: product),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Error loading products: $e'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              L.tr('no_products_yet'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              L.tr('merch_empty_state_description'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncShopify(WidgetRef ref) async {
    setState(() => _isSyncing = true);
    try {
      final repo = ref.read(merchRepositoryProvider);
      await repo.syncShopify(_organizerId);
      ref.invalidate(organizerProductsProvider(_organizerId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('products_synced_from_shopify'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('sync_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSetupSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MerchSetupSheet(
        organizerId: _organizerId,
        onSaved: () {
          ref.invalidate(merchConfigProvider(_organizerId));
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showCreateProductDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.tr('new_product')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final title = titleCtrl.text.trim();
              if (title.isEmpty) return;

              final priceDollars = double.tryParse(priceCtrl.text) ?? 0;
              final priceCents = (priceDollars * 100).round();

              final repo = ref.read(merchRepositoryProvider);
              await repo.createProduct(MerchProduct(
                id: '',
                organizerId: _organizerId,
                source: 'stripe',
                title: title,
                description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                basePriceCents: priceCents,
                eventId: widget.event?.id,
                createdAt: DateTime.now(),
              ));
              ref.invalidate(organizerProductsProvider(_organizerId));
              nav.pop();
            },
            child: Text(L.tr('create')),
          ),
        ],
      ),
    );
  }
}

/// Banner showing current merch config status.
class _ConfigBanner extends StatelessWidget {
  final OrganizerMerchConfig? config;
  final VoidCallback onSetup;

  const _ConfigBanner({this.config, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (config == null || !config!.isConfigured) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                L.tr('set_up_merch_store'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: onSetup,
              child: Text(L.tr('set_up')),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(config!.provider.icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            config!.provider.displayLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (config!.isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Active',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: onSetup,
            child: Text(L.tr('configure')),
          ),
        ],
      ),
    );
  }
}

/// Product card for organizer management.
class _ProductManagementCard extends StatelessWidget {
  final MerchProduct product;
  final VoidCallback onTap;

  const _ProductManagementCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: product.thumbnailUrl != null
                    ? Image.network(
                        product.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.image, color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Icons.shopping_bag,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.priceRange,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (product.variants.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${product.variants.length} variant${product.variants.length > 1 ? "s" : ""}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Status
              if (!product.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    L.tr('inactive'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Setup sheet for connecting Shopify or choosing Stripe.
class _MerchSetupSheet extends ConsumerStatefulWidget {
  final String organizerId;
  final VoidCallback onSaved;

  const _MerchSetupSheet({required this.organizerId, required this.onSaved});

  @override
  ConsumerState<_MerchSetupSheet> createState() => _MerchSetupSheetState();
}

class _MerchSetupSheetState extends ConsumerState<_MerchSetupSheet> {
  MerchProvider _selectedProvider = MerchProvider.stripe;
  final _domainController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _domainController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            L.tr('set_up_merch_store'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Provider selection
          SegmentedButton<MerchProvider>(
            segments: const [
              ButtonSegment(
                value: MerchProvider.stripe,
                label: Text('Stripe'),
                icon: Icon(Icons.credit_card),
              ),
              ButtonSegment(
                value: MerchProvider.shopify,
                label: Text('Shopify'),
                icon: Icon(Icons.shopping_bag),
              ),
            ],
            selected: {_selectedProvider},
            onSelectionChanged: (set) => setState(() => _selectedProvider = set.first),
          ),
          const SizedBox(height: 16),
          if (_selectedProvider == MerchProvider.shopify) ...[
            TextField(
              controller: _domainController,
              decoration: const InputDecoration(
                labelText: 'Shopify Domain',
                hintText: 'your-store.myshopify.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Storefront Access Token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ] else ...[
            Text(
              'Products will be managed directly in Tickety.\nCreate products, set prices, and track inventory.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(L.tr('save_configuration')),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final repo = ref.read(merchRepositoryProvider);
      await repo.saveMerchConfig(OrganizerMerchConfig(
        id: '',
        organizerId: widget.organizerId,
        provider: _selectedProvider,
        shopifyDomain: _selectedProvider == MerchProvider.shopify
            ? _domainController.text.trim()
            : null,
        shopifyStorefrontToken: _selectedProvider == MerchProvider.shopify
            ? _tokenController.text.trim()
            : null,
        isActive: true,
      ));
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('save_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
