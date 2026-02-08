import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../shared/widgets/limit_reached_banner.dart';
import '../../subscriptions/models/tier_limits.dart';
import '../models/event_analytics.dart';
import '../models/event_model.dart';

/// Dashboard screen showing event statistics and analytics.
class EventDataScreen extends ConsumerStatefulWidget {
  final EventModel event;

  const EventDataScreen({
    super.key,
    required this.event,
  });

  @override
  ConsumerState<EventDataScreen> createState() => _EventDataScreenState();
}

class _EventDataScreenState extends ConsumerState<EventDataScreen> {
  @override
  void initState() {
    super.initState();
    // Load analytics when screen opens (uses server-side aggregation)
    Future.microtask(() {
      ref.read(ticketProvider.notifier).loadAnalytics(widget.event.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ticketState = ref.watch(ticketProvider);
    final config = widget.event.getNoiseConfig();
    final analytics = ticketState.analytics ?? EventAnalytics.empty;

    if (ticketState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event Data')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Event Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: config.colors,
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  ref.read(ticketProvider.notifier).loadAnalytics(widget.event.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing statistics...'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                tooltip: 'Refresh',
              ),
            ],
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Summary cards row (always visible)
                _SummaryCardsSection(analytics: analytics),
                const SizedBox(height: 24),

                // Check-in progress (Pro+)
                if (ref.watch(canViewAnalyticsSectionProvider(AnalyticsSection.checkInProgress)))
                  _CheckInProgressCard(analytics: analytics)
                else
                  const LockedAnalyticsSection(section: AnalyticsSection.checkInProgress),
                const SizedBox(height: 24),

                // Hourly chart (Enterprise)
                _SectionHeader(
                  title: 'Check-ins by Hour',
                  icon: Icons.bar_chart,
                ),
                const SizedBox(height: 12),
                if (ref.watch(canViewAnalyticsSectionProvider(AnalyticsSection.hourlyCheckins)))
                  _HourlyCheckInChart(analytics: analytics)
                else
                  const LockedAnalyticsSection(section: AnalyticsSection.hourlyCheckins),
                const SizedBox(height: 24),

                // Usher performance (Enterprise)
                _SectionHeader(
                  title: 'Usher Performance',
                  icon: Icons.people_outline,
                ),
                const SizedBox(height: 12),
                if (ref.watch(canViewAnalyticsSectionProvider(AnalyticsSection.usherPerformance)))
                  _UsherPerformanceCard(analytics: analytics)
                else
                  const LockedAnalyticsSection(section: AnalyticsSection.usherPerformance),
                const SizedBox(height: 24),

                // Ticket type breakdown (Pro+)
                _SectionHeader(
                  title: 'Ticket Types',
                  icon: Icons.confirmation_number_outlined,
                ),
                const SizedBox(height: 12),
                if (ref.watch(canViewAnalyticsSectionProvider(AnalyticsSection.ticketTypeBreakdown)))
                  _TicketTypeBreakdownCard(analytics: analytics)
                else
                  const LockedAnalyticsSection(section: AnalyticsSection.ticketTypeBreakdown),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SummaryCardsSection extends StatelessWidget {
  final EventAnalytics analytics;

  const _SummaryCardsSection({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.check_circle_outline,
                label: 'Checked In',
                value: '${analytics.checkedIn}',
                subtitle: 'of ${analytics.totalSold} tickets',
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                icon: Icons.trending_up,
                label: 'Check-in Rate',
                value: '${analytics.checkInRate.toStringAsFixed(1)}%',
                subtitle: 'attendance',
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.confirmation_number_outlined,
                label: 'Tickets Sold',
                value: '${analytics.totalSold}',
                subtitle: '${analytics.remaining} remaining',
                color: colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                icon: Icons.attach_money,
                label: 'Revenue',
                value: analytics.formattedRevenue,
                subtitle: 'total earned',
                color: colorScheme.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInProgressCard extends StatelessWidget {
  final EventAnalytics analytics;

  const _CheckInProgressCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = analytics.checkInRate / 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.5),
            colorScheme.primaryContainer.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-in Progress',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${analytics.checkedIn} of ${analytics.totalSold} guests arrived',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Circular progress
              SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _CircularProgressPainter(
                    progress: progress,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    progressColor: colorScheme.primary,
                    strokeWidth: 8,
                  ),
                  child: Center(
                    child: Text(
                      '${analytics.checkInRate.toInt()}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LegendItem(
                color: colorScheme.primary,
                label: 'Checked in',
                value: '${analytics.checkedIn}',
              ),
              _LegendItem(
                color: colorScheme.surfaceContainerHighest,
                label: 'Remaining',
                value: '${analytics.remaining}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HourlyCheckInChart extends StatelessWidget {
  final EventAnalytics analytics;

  const _HourlyCheckInChart({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show placeholder if no data
    if (analytics.hourlyCheckins.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No check-ins yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxCount = analytics.hourlyCheckins.map((e) => e.count).reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: analytics.hourlyCheckins.map((hourData) {
                final heightPercent = maxCount > 0 ? hourData.count / maxCount : 0.0;
                final isPeak = hourData.count == maxCount;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Value label
                        Text(
                          '${hourData.count}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: isPeak ? FontWeight.bold : FontWeight.normal,
                            color: isPeak
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Bar
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: heightPercent.clamp(0.05, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: isPeak
                                      ? [
                                          colorScheme.primary,
                                          colorScheme.primary.withValues(alpha: 0.7),
                                        ]
                                      : [
                                          colorScheme.primary.withValues(alpha: 0.6),
                                          colorScheme.primary.withValues(alpha: 0.3),
                                        ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Hour labels
          Row(
            children: analytics.hourlyCheckins.map((hourData) {
              return Expanded(
                child: Text(
                  hourData.formattedHour,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              );
            }).toList(),
          ),
          if (analytics.peakHour != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Peak: ${_formatHour(analytics.peakHour!)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';
    if (hour < 12) return '$hour AM';
    return '${hour - 12} PM';
  }
}

class _UsherPerformanceCard extends StatelessWidget {
  final EventAnalytics analytics;

  const _UsherPerformanceCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show placeholder if no data
    if (analytics.usherStats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No check-ins yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final totalByUshers = analytics.usherStats.fold<int>(
      0,
      (sum, usher) => sum + usher.count,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Pie chart visualization
          SizedBox(
            height: 140,
            child: Row(
              children: [
                // Pie chart
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _PieChartPainter(
                      values: analytics.usherStats
                          .map((e) => e.count.toDouble())
                          .toList(),
                      colors: _generateColors(
                        analytics.usherStats.length,
                        colorScheme,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Legend
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < analytics.usherStats.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _generateColors(
                                    analytics.usherStats.length,
                                    colorScheme,
                                  )[i],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  analytics.usherStats[i].displayName,
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // Usher list with stats
          ...analytics.usherStats.asMap().entries.map((entry) {
            final i = entry.key;
            final usher = entry.value;
            final percent = totalByUshers > 0
                ? (usher.count / totalByUshers * 100)
                : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _generateColors(
                      analytics.usherStats.length,
                      colorScheme,
                    )[i].withValues(alpha: 0.2),
                    child: Text(
                      usher.displayName[0].toUpperCase(),
                      style: TextStyle(
                        color: _generateColors(
                          analytics.usherStats.length,
                          colorScheme,
                        )[i],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usher.displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: percent / 100,
                            minHeight: 4,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              _generateColors(
                                analytics.usherStats.length,
                                colorScheme,
                              )[i],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${usher.count}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${percent.toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Color> _generateColors(int count, ColorScheme colorScheme) {
    return [
      colorScheme.primary,
      colorScheme.tertiary,
      colorScheme.secondary,
      Colors.orange,
      Colors.purple,
    ].take(count).toList();
  }
}

class _TicketTypeBreakdownCard extends StatelessWidget {
  final EventAnalytics analytics;

  const _TicketTypeBreakdownCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Currently we only have one ticket type (General Admission)
    // This can be expanded when ticket types are added to the database
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.confirmation_number_outlined,
                color: colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'General Admission',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${analytics.checkedIn}/${analytics.totalSold} checked in',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${analytics.checkInRate.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  analytics.formattedRevenue,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  _PieChartPainter({
    required this.values,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final total = values.fold<double>(0, (sum, v) => sum + v);

    if (total == 0) return;

    var startAngle = -math.pi / 2;

    for (var i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * math.pi;

      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      startAngle += sweepAngle;
    }

    // Center hole for donut effect
    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.55, holePaint);
  }

  @override
  bool shouldRepaint(_PieChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
