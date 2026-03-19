import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/discovery_provider.dart';
import '../models/discovery_models.dart';

/// Admin screen for tuning the event discovery algorithm weights.
///
/// Features: weight sliders, preview feed, rank change indicators, history.
class AlgorithmTuningScreen extends ConsumerStatefulWidget {
  const AlgorithmTuningScreen({super.key});

  @override
  ConsumerState<AlgorithmTuningScreen> createState() =>
      _AlgorithmTuningScreenState();
}

class _AlgorithmTuningScreenState
    extends ConsumerState<AlgorithmTuningScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(discoveryWeightsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoveryWeightsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final eventWeights =
        state.weights.where((w) => !w.isPersonalization).toList();
    final personalWeights =
        state.weights.where((w) => w.isPersonalization).toList();

    return Scaffold(
      appBar: AppBar(title: Text(L.tr('algorithm_tuning'))),
      body: state.isLoading && state.weights.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.weights.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(state.error!,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.read(discoveryWeightsProvider.notifier).load(),
                        child: Text(L.tr('retry')),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(discoveryWeightsProvider.notifier).load(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Event Scoring Weights
                        Text(
                          L.tr('event_scoring_weights'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          L.tr('controls_event_ranking'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...eventWeights.map((w) => _WeightSlider(
                              weight: w,
                              onChanged: (val) => ref
                                  .read(discoveryWeightsProvider.notifier)
                                  .setLocalWeight(w.key, val),
                            )),

                        const SizedBox(height: 24),

                        // Personalization Weights
                        Text(
                          L.tr('personalization_weights'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          L.tr('personalization_weights_description'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...personalWeights.map((w) => _WeightSlider(
                              weight: w,
                              onChanged: (val) => ref
                                  .read(discoveryWeightsProvider.notifier)
                                  .setLocalWeight(w.key, val),
                            )),

                        const SizedBox(height: 24),

                        // Platform Tag Affinity Chart
                        _TagAffinitySection(),

                        const SizedBox(height: 24),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: state.isPreviewing
                                    ? null
                                    : () => ref
                                        .read(discoveryWeightsProvider.notifier)
                                        .previewFeed(),
                                icon: state.isPreviewing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.visibility, size: 18),
                                label: Text(L.tr('preview_feed')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: state.isSaving
                                    ? null
                                    : () async {
                                        await ref
                                            .read(discoveryWeightsProvider
                                                .notifier)
                                            .applyWeights();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  L.tr('weights_applied')),
                                            ),
                                          );
                                        }
                                      },
                                icon: state.isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.check, size: 18),
                                label: Text(L.tr('apply')),
                              ),
                            ),
                          ],
                        ),

                        if (state.error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            state.error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ],

                        // Preview results
                        if (state.preview.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Preview (top ${state.preview.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...state.preview.map(
                            (item) => _PreviewEventTile(item: item),
                          ),
                        ],

                        // History
                        if (state.history.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            L.tr('history'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...state.history.take(10).map(
                                (entry) => _HistoryTile(entry: entry),
                              ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _WeightSlider extends StatelessWidget {
  final DiscoveryWeight weight;
  final ValueChanged<double> onChanged;

  const _WeightSlider({
    required this.weight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  weight.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                weight.weight.toStringAsFixed(2),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (weight.description != null)
            Text(
              weight.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor:
                  colorScheme.onSurface.withValues(alpha: 0.12),
              thumbColor: colorScheme.primary,
            ),
            child: Slider(
              value: weight.weight,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewEventTile extends StatelessWidget {
  final FeedPreviewItem item;

  const _PreviewEventTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final rankChange = item.rankChange;
    final rankIndicator = _buildRankIndicator(rankChange, colorScheme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Rank number
              SizedBox(
                width: 28,
                child: Text(
                  '${item.previewRank}.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // Event title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.eventTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Score: ${item.previewComposite.toStringAsFixed(3)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              // Rank change indicator
              rankIndicator,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankIndicator(int? change, ColorScheme colorScheme) {
    if (change == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.blue,
          ),
        ),
      );
    }

    if (change == 0) {
      return Text(
        '──',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final isUp = change > 0;
    final color = isUp ? Colors.green : Colors.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: color,
        ),
        Text(
          '${change.abs()}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final WeightHistoryEntry entry;

  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              _formatDate(entry.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.label}: ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '${entry.oldWeight.toStringAsFixed(2)} ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Icon(Icons.arrow_forward, size: 12, color: colorScheme.onSurfaceVariant),
          Text(
            ' ${entry.newWeight.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

/// Horizontal bar chart showing platform-wide tag affinity.
/// Shows what users are most interested in across the platform.
class _TagAffinitySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final affinityAsync = ref.watch(platformTagAffinityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L.tr('user_interest_distribution'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          L.tr('platform_tag_affinity_description'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        affinityAsync.when(
          data: (stats) {
            if (stats.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    L.tr('no_tag_affinity_data_yet'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return _TagAffinityChart(stats: stats);
          },
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(
            'Failed to load: $e',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _TagAffinityChart extends StatelessWidget {
  final List<TagAffinityStat> stats;

  const _TagAffinityChart({required this.stats});

  static const _barColors = [
    Color(0xFF6366F1), // indigo
    Color(0xFF8B5CF6), // violet
    Color(0xFFA78BFA), // light violet
    Color(0xFFC084FC), // purple
    Color(0xFFE879F9), // fuchsia
    Color(0xFFF472B6), // pink
    Color(0xFFFB923C), // orange
    Color(0xFFFBBF24), // amber
    Color(0xFF34D399), // emerald
    Color(0xFF22D3EE), // cyan
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxAffinity = stats.map((s) => s.totalAffinity).reduce(math.max);
    final maxY = (maxAffinity * 1.2).ceilToDouble().clamp(1.0, double.infinity);

    return SizedBox(
      height: stats.length * 40.0 + 24,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final stat = stats[groupIndex];
                return BarTooltipItem(
                  '${stat.label}\n',
                  TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '${stat.userCount} users, avg ${stat.avgAffinity.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= stats.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      stats[idx].label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox();
                  return Text(
                    value.toStringAsFixed(0),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          barGroups: List.generate(stats.length, (i) {
            final color = _barColors[i % _barColors.length];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: stats[i].totalAffinity,
                  color: color,
                  width: 20,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
