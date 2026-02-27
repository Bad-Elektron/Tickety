import 'package:flutter/material.dart';

import '../models/market_snapshot.dart';
import 'metric_card.dart';

/// Dashboard section showing aggregated external market data
/// from Ticketmaster + SeatGeek.
class MarketInsightsSection extends StatelessWidget {
  final Map<String, MarketComparison> comparisonsByTag;

  const MarketInsightsSection({
    super.key,
    required this.comparisonsByTag,
  });

  @override
  Widget build(BuildContext context) {
    if (comparisonsByTag.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Aggregate totals across all tags
    int totalEvents = 0;
    int priceSum = 0;
    int priceCount = 0;
    for (final c in comparisonsByTag.values) {
      totalEvents += c.totalExternalEvents;
      final avg = c.weightedAvgPriceCents;
      if (avg != null) {
        priceSum += avg;
        priceCount++;
      }
    }

    final avgPriceFormatted = priceCount > 0
        ? '\$${((priceSum / priceCount) / 100).toStringAsFixed(2)}'
        : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Market Insights',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ticketmaster + SeatGeek',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'External Events',
                value: _formatCount(totalEvents),
                subtitle: '${comparisonsByTag.length} categories',
                icon: Icons.public,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Market Avg Price',
                value: avgPriceFormatted,
                subtitle: 'weighted average',
                icon: Icons.storefront,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }
}
