import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/merch_provider.dart';
import '../../payments/models/payment.dart';
import '../models/models.dart';

/// Screen displaying details of a merch product for buyers.
class ProductDetailScreen extends ConsumerStatefulWidget {
  final MerchProduct product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  MerchVariant? _selectedVariant;
  int _quantity = 1;
  FulfillmentType _fulfillmentType = FulfillmentType.ship;
  bool _isPurchasing = false;

  int get _unitPriceCents =>
      _selectedVariant?.priceCents ?? widget.product.basePriceCents;

  int get _totalCents => _unitPriceCents * _quantity;

  @override
  void initState() {
    super.initState();
    if (widget.product.variants.isNotEmpty) {
      _selectedVariant = widget.product.variants.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final product = widget.product;

    return Scaffold(
      appBar: AppBar(title: Text(product.title)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image carousel
            if (product.imageUrls.isNotEmpty)
              SizedBox(
                height: 300,
                child: PageView.builder(
                  itemCount: product.imageUrls.length,
                  itemBuilder: (context, index) => Image.network(
                    product.imageUrls[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.image,
                        size: 64,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                width: double.infinity,
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.shopping_bag,
                  size: 64,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and price
                  Text(
                    product.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.priceRange,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  // Description
                  if (product.description != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      product.description!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],

                  // Variant selector
                  if (product.variants.length > 1) ...[
                    const SizedBox(height: 20),
                    Text(
                      L.tr('options'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: product.variants.map((variant) {
                        final isSelected = _selectedVariant?.id == variant.id;
                        return ChoiceChip(
                          label: Text(
                            '${variant.name} - ${variant.formattedPrice}',
                          ),
                          selected: isSelected,
                          onSelected: variant.inStock
                              ? (selected) {
                                  if (selected) {
                                    setState(() => _selectedVariant = variant);
                                  }
                                }
                              : null,
                        );
                      }).toList(),
                    ),
                  ],

                  // Fulfillment type
                  if (product.eventId != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      L.tr('delivery'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<FulfillmentType>(
                      segments: [
                        ButtonSegment(
                          value: FulfillmentType.ship,
                          label: Text(L.tr('ship_to_me')),
                          icon: Icon(Icons.local_shipping_outlined),
                        ),
                        ButtonSegment(
                          value: FulfillmentType.pickup,
                          label: Text(L.tr('pick_up_at_event')),
                          icon: Icon(Icons.store_outlined),
                        ),
                      ],
                      selected: {_fulfillmentType},
                      onSelectionChanged: (set) =>
                          setState(() => _fulfillmentType = set.first),
                    ),
                  ],

                  // Quantity
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        L.tr('quantity'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$_quantity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: _quantity < 10
                            ? () => setState(() => _quantity++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),

                  // Fee breakdown
                  const SizedBox(height: 16),
                  if (_totalCents > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _PriceRow(
                            label: L.tr('subtotal'),
                            amount: _totalCents,
                          ),
                          _PriceRow(
                            label: L.tr('service_fee'),
                            amount: MerchFeeCalculator.calculate(_totalCents).totalCents - _totalCents,
                          ),
                          Divider(
                            color: colorScheme.outlineVariant,
                            height: 16,
                          ),
                          _PriceRow(
                            label: L.tr('total'),
                            amount: MerchFeeCalculator.calculate(_totalCents).totalCents,
                            isBold: true,
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Buy button
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: product.inStock && !_isPurchasing
                        ? () => _purchase(context)
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isPurchasing
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            product.inStock
                                ? 'Buy Now \u2022 \$${(MerchFeeCalculator.calculate(_totalCents).totalCents / 100).toStringAsFixed(2)}'
                                : L.tr('out_of_stock'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purchase(BuildContext context) async {
    setState(() => _isPurchasing = true);
    try {
      final repo = ref.read(merchRepositoryProvider);
      final result = await repo.purchaseProduct(
        productId: widget.product.id,
        variantId: _selectedVariant?.id,
        quantity: _quantity,
        fulfillmentType: _fulfillmentType.value,
      );

      if (mounted) {
        if (result['client_secret'] != null) {
          // TODO: Present Stripe PaymentSheet
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L.tr('payment_initiated'))),
          );
        } else if (result['checkout_url'] != null) {
          // TODO: Open Shopify checkout URL
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L.tr('redirecting_to_checkout'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final int amount;
  final bool isBold;

  const _PriceRow({
    required this.label,
    required this.amount,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = isBold
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            '\$${(amount / 100).toStringAsFixed(2)}',
            style: style,
          ),
        ],
      ),
    );
  }
}
