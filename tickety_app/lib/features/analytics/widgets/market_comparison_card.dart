import 'package:flutter/material.dart';

import '../../../core/localization/localization.dart';
import '../models/market_snapshot.dart';

/// Tag-detail card comparing Tickety data with external market data.
class MarketComparisonCard extends StatelessWidget {
  final MarketComparison comparison;

  /// Tickety-side metrics for the tag.
  final int ticketyEventCount;
  final int? ticketyAvgPriceCents;

  const MarketComparisonCard({
    super.key,
    required this.comparison,
    required this.ticketyEventCount,
    this.ticketyAvgPriceCents,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.compare_arrows, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                L.tr('Tickety vs Market'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (comparison.hasStaleData)
                Tooltip(
                  message: L.tr('Market data may be outdated'),
                  child: Icon(
                    Icons.schedule,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Side-by-side comparison
          Row(
            children: [
              // Tickety column
              Expanded(
                child: _Column(
                  header: 'Tickety',
                  headerColor: colorScheme.primary,
                  eventCount: ticketyEventCount,
                  avgPrice: ticketyAvgPriceCents != null
                      ? '\$${(ticketyAvgPriceCents! / 100).toStringAsFixed(2)}'
                      : '-',
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: colorScheme.outlineVariant,
              ),
              // Market column
              Expanded(
                child: _Column(
                  header: 'Market',
                  headerColor: Colors.deepPurple,
                  eventCount: comparison.totalExternalEvents,
                  avgPrice: comparison.formattedWeightedAvgPrice,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Per-source breakdown
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            L.tr('By source'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),

          if (comparison.ticketmaster != null)
            _SourceRow(
              snapshot: comparison.ticketmaster!,
              colorScheme: colorScheme,
              theme: theme,
            ),
          if (comparison.seatgeek != null) ...[
            const SizedBox(height: 6),
            _SourceRow(
              snapshot: comparison.seatgeek!,
              colorScheme: colorScheme,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final String header;
  final Color headerColor;
  final int eventCount;
  final String avgPrice;

  const _Column({
    required this.header,
    required this.headerColor,
    required this.eventCount,
    required this.avgPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Text(
            header,
            style: theme.textTheme.labelMedium?.copyWith(
              color: headerColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$eventCount',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            L.tr('events'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            avgPrice,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            L.tr('avg price'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final MarketSnapshot snapshot;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _SourceRow({
    required this.snapshot,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = !snapshot.isValid;

    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            snapshot.source.label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (hasError)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
              const SizedBox(width: 4),
              Text(
                L.tr('Error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade400,
                ),
              ),
            ],
          )
        else ...[
          Expanded(
            child: Text(
              '${snapshot.eventCount ?? 0} events',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            snapshot.formattedAvgPrice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
