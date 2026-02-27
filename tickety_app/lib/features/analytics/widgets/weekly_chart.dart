import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/tag_weekly_stats.dart';

/// Bar chart showing weekly event counts with an optional price line overlay.
class WeeklyChart extends StatelessWidget {
  final List<TagWeeklyStats> stats;
  final bool showPriceLine;

  const WeeklyChart({
    super.key,
    required this.stats,
    this.showPriceLine = true,
  });

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No data available')),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxEvents = stats.map((s) => s.eventCount).reduce(math.max);
    final maxY = (maxEvents * 1.3).ceilToDouble().clamp(1.0, double.infinity);

    return SizedBox(
      height: 220,
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
                  '${stat.weekLabel}\n',
                  TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '${stat.eventCount} events',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                    if (showPriceLine && stat.avgPriceCents > 0) ...[
                      TextSpan(
                        text: '\nAvg ${stat.formattedAvgPrice}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= stats.length) {
                    return const SizedBox.shrink();
                  }
                  // Show every other label if there are many weeks
                  if (stats.length > 8 && index % 2 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      stats[index].weekLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
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
                  if (value == 0 || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toInt().toString(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 4 ? (maxY / 4).ceilToDouble() : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: stats.asMap().entries.map((entry) {
            final i = entry.key;
            final stat = entry.value;
            final isCurrentWeek = i == stats.length - 1;

            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: stat.eventCount.toDouble(),
                  color: isCurrentWeek
                      ? colorScheme.primary
                      : colorScheme.primary.withValues(alpha: 0.5),
                  width: stats.length > 8 ? 12 : 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Line chart showing average price trend over weeks.
class PriceTrendChart extends StatelessWidget {
  final List<TagWeeklyStats> stats;

  const PriceTrendChart({
    super.key,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No data available')),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxPrice = stats.map((s) => s.avgPriceCents).reduce(math.max);
    final maxY = maxPrice > 0
        ? (maxPrice * 1.3 / 100).ceilToDouble()
        : 10.0;

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final stat = stats[spot.x.toInt()];
                return LineTooltipItem(
                  '${stat.weekLabel}\n${stat.formattedAvgPrice}',
                  TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 4 ? maxY / 4 : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: stats.length > 8 ? 2 : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= stats.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      stats[index].weekLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    '\$${value.toStringAsFixed(0)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (stats.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: stats.asMap().entries.map((entry) {
                return FlSpot(
                  entry.key.toDouble(),
                  entry.value.avgPriceCents / 100,
                );
              }).toList(),
              isCurved: true,
              color: colorScheme.secondary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: colorScheme.secondary,
                  strokeWidth: 1.5,
                  strokeColor: colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: colorScheme.secondary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
