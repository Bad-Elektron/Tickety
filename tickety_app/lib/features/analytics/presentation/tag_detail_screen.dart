import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/models/event_tag.dart';
import '../../../core/providers/analytics_provider.dart';
import '../widgets/widgets.dart';

/// Drill-down screen showing weekly chart data for a single tag.
class TagDetailScreen extends ConsumerStatefulWidget {
  final String tagId;

  const TagDetailScreen({
    super.key,
    required this.tagId,
  });

  @override
  ConsumerState<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends ConsumerState<TagDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(analyticsProvider.notifier).loadTagDetail(widget.tagId);
    });
  }

  String _formatCustomTag(String tagId) {
    final raw = tagId.startsWith('custom_') ? tagId.substring(7) : tagId;
    return raw
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Find the predefined tag for label/color/icon
    final predefined = PredefinedTags.all.where((t) => t.id == widget.tagId);
    final tagLabel = predefined.isNotEmpty
        ? predefined.first.label
        : _formatCustomTag(widget.tagId);
    final tagColor = predefined.isNotEmpty
        ? predefined.first.color ?? colorScheme.primary
        : colorScheme.primary;
    final tagIcon = predefined.isNotEmpty ? predefined.first.icon : null;

    // Find the matching trending tag for summary data
    final trendingTag = state.trendingTags
        .where((t) => t.tagId == widget.tagId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tagIcon != null) ...[
              Icon(tagIcon, size: 20, color: tagColor),
              const SizedBox(width: 8),
            ],
            Text(tagLabel),
          ],
        ),
      ),
      body: state.isLoadingTagDetail && state.selectedTagStats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag summary card
                  if (trendingTag != null) _TagSummary(tag: trendingTag),
                  const SizedBox(height: 24),

                  // Market comparison card
                  if (state.selectedTagMarketComparison != null &&
                      state.selectedTagMarketComparison!.hasData) ...[
                    MarketComparisonCard(
                      comparison: state.selectedTagMarketComparison!,
                      ticketyEventCount: trendingTag?.currentWeekCount ?? 0,
                      ticketyAvgPriceCents: trendingTag?.avgPriceCents,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Events per week bar chart
                  Text(
                    'Events Per Week',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last 12 weeks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  WeeklyChart(stats: state.selectedTagStats),
                  const SizedBox(height: 32),

                  // Average price trend
                  Text(
                    'Average Ticket Price',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Price trend over time',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PriceTrendChart(stats: state.selectedTagStats),
                  const SizedBox(height: 32),

                  // Location breakdown
                  if (state.selectedTagStats.isNotEmpty) ...[
                    Text(
                      'Weekly Breakdown',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _WeeklyBreakdownList(stats: state.selectedTagStats),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _TagSummary extends StatelessWidget {
  final dynamic tag; // TrendingTag

  const _TagSummary({required this.tag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final trendColor =
        tag.isTrendingUp ? Colors.green : tag.isTrendingDown ? Colors.red : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      tag.isTrendingUp
                          ? Icons.trending_up
                          : tag.isTrendingDown
                              ? Icons.trending_down
                              : Icons.trending_flat,
                      color: trendColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tag.formattedTrendScore,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'week-over-week',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _MiniStat(
            label: 'This week',
            value: '${tag.currentWeekCount}',
          ),
          const SizedBox(width: 16),
          _MiniStat(
            label: 'Last 30d',
            value: '${tag.totalEvents30d}',
          ),
          const SizedBox(width: 16),
          _MiniStat(
            label: 'Avg price',
            value: tag.formattedAvgPrice,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _WeeklyBreakdownList extends StatelessWidget {
  final List stats;

  const _WeeklyBreakdownList({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show most recent weeks first
    final reversed = stats.reversed.toList();

    return Column(
      children: reversed.map((stat) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    stat.weekLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${stat.eventCount} events',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    stat.formattedAvgPrice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${stat.totalTicketsSold} sold',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
