import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/analytics_provider.dart';
import '../models/platform_engagement.dart';
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
        title: Text(L.tr('market_analytics')),
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

                        // Engagement section
                        if (state.engagement != null)
                          _EngagementSection(
                            engagement: state.engagement!,
                          ),
                        if (state.engagement != null)
                          const SizedBox(height: 24),

                        // Trending tags section
                        Text(
                          L.tr('trending_tags'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          L.tr('tags_ranked_by_growth'),
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
                                L.tr('no_trending_data_yet'),
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
            label: L.tr('this_week'),
            value: '${state.totalEventsThisWeek}',
            subtitle: 'events',
            icon: Icons.event,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: L.tr('hottest_tag'),
            value: state.hottestTag?.label ?? '-',
            subtitle: state.hottestTag?.formattedTrendScore,
            icon: Icons.local_fire_department,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: L.tr('top_price'),
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

class _EngagementSection extends StatelessWidget {
  final PlatformEngagement engagement;

  const _EngagementSection({required this.engagement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L.tr('engagement'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          L.tr('views_and_conversion_30d'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        // KPI row
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: L.tr('views'),
                value: _formatCompact(engagement.totalViews30d),
                subtitle: '30 days',
                icon: Icons.visibility,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: L.tr('unique'),
                value: _formatCompact(engagement.uniqueViewers30d),
                subtitle: 'viewers',
                icon: Icons.people,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: L.tr('conversion'),
                value: '${engagement.avgConversionRate}%',
                subtitle: 'avg rate',
                icon: Icons.trending_up,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Weekly views bar chart
        if (engagement.weeklyViews.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L.tr('weekly_views'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: _SimpleBarChart(
                    values: engagement.weeklyViews
                        .map((e) => e.views.toDouble())
                        .toList(),
                    labels: engagement.weeklyViews
                        .map((e) => e.weekStart.length >= 10
                            ? e.weekStart.substring(5, 10)
                            : e.weekStart)
                        .toList(),
                    color: colorScheme.primary,
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Top events by views
        if (engagement.topEvents.isNotEmpty) ...[
          Text(
            L.tr('top_events_by_views'),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...engagement.topEvents.take(5).map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatCompact(event.totalViews)} views',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${event.conversionRate}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatCompact(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }
}

class _SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final TextStyle? labelStyle;

  const _SimpleBarChart({
    required this.values,
    required this.labels,
    required this.color,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = values.fold(0.0, (a, b) => math.max(a, b));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (i) {
        final fraction = maxVal > 0 ? values[i] / maxVal : 0.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction.clamp(0.05, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }),
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
              L.tr('unable_to_load_analytics'),
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
              label: Text(L.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}
