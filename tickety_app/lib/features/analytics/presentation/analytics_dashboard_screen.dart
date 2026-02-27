import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/analytics_provider.dart';
import '../widgets/widgets.dart';
import 'tag_detail_screen.dart';

/// Main analytics dashboard showing trending tags, market overview, and charts.
///
/// Enterprise-tier only. Reads from pre-computed cache tables.
class AnalyticsDashboardScreen extends ConsumerStatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  ConsumerState<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState
    extends ConsumerState<AnalyticsDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(analyticsProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Market Analytics'),
        actions: [
          if (state.lastRefreshed != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Updated ${_formatRelativeTime(state.lastRefreshed!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: state.isLoading && state.trendingTags.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.trendingTags.isEmpty
              ? _ErrorView(
                  message: state.error!,
                  onRetry: () =>
                      ref.read(analyticsProvider.notifier).loadDashboard(),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(analyticsProvider.notifier).loadDashboard(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Location filter
                        if (state.availableCities.isNotEmpty)
                          LocationFilter(
                            cities: state.availableCities,
                            selectedCity: state.selectedCity,
                            onChanged: (city) => ref
                                .read(analyticsProvider.notifier)
                                .setCity(city),
                          ),
                        const SizedBox(height: 24),

                        // Market overview cards
                        _MarketOverview(state: state),
                        const SizedBox(height: 24),

                        // Trending tags section
                        Text(
                          'Trending Tags',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tags ranked by week-over-week growth',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Market insights section (external data)
                        if (state.marketComparisonsByTag.isNotEmpty) ...[
                          MarketInsightsSection(
                            comparisonsByTag: state.marketComparisonsByTag,
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (state.trendingTags.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'No trending data available yet',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else
                          _TrendingTagsList(
                            state: state,
                            onTagTap: (tagId) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TagDetailScreen(tagId: tagId),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MarketOverview extends StatelessWidget {
  final AnalyticsState state;

  const _MarketOverview({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: 'This Week',
            value: '${state.totalEventsThisWeek}',
            subtitle: 'events',
            icon: Icons.event,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: 'Hottest Tag',
            value: state.hottestTag?.label ?? '-',
            subtitle: state.hottestTag?.formattedTrendScore,
            icon: Icons.local_fire_department,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: 'Top Price',
            value: state.highestPriceTag?.formattedAvgPrice ?? '-',
            subtitle: state.highestPriceTag?.label,
            icon: Icons.attach_money,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}

class _TrendingTagsList extends StatelessWidget {
  final AnalyticsState state;
  final ValueChanged<String> onTagTap;

  const _TrendingTagsList({
    required this.state,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: state.trendingTags.map((tag) {
        return TrendingTagChip(
          tag: tag,
          isSelected: state.selectedTagId == tag.tagId,
          onTap: () => onTagTap(tag.tagId),
        );
      }).toList(),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load analytics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
