import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../data/supabase_event_repository.dart';
import '../models/event_model.dart';
import '../models/ticket_type.dart';

/// Screen for managing all ticket types for an event.
/// Shows each ticket type with sold/available counts and actions
/// for minting more tickets and applying discounts.
class ManageTicketsScreen extends ConsumerStatefulWidget {
  final EventModel event;

  const ManageTicketsScreen({super.key, required this.event});

  @override
  ConsumerState<ManageTicketsScreen> createState() =>
      _ManageTicketsScreenState();
}

class _ManageTicketsScreenState extends ConsumerState<ManageTicketsScreen> {
  List<TicketType> _ticketTypes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTicketTypes();
  }

  Future<void> _loadTicketTypes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ref.read(eventRepositoryProvider);
      final types = await (repository as SupabaseEventRepository)
          .getEventTicketTypes(widget.event.id);
      if (mounted) {
        setState(() {
          _ticketTypes = types;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = widget.event.getNoiseConfig();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Tickets',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GradientBackground(colors: config.colors),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x90000000),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: _ErrorState(
                error: _error!,
                onRetry: _loadTicketTypes,
              ),
            )
          else if (_ticketTypes.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(colorScheme: colorScheme, theme: theme),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return _buildSummaryBar(theme, colorScheme);
                    }
                    final ticketIndex = index - 1;
                    if (ticketIndex >= _ticketTypes.length) return null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _TicketTypeCard(
                        ticketType: _ticketTypes[ticketIndex],
                        onMint: () => _showMintDialog(
                          context,
                          _ticketTypes[ticketIndex],
                        ),
                        onDiscount: () => _showDiscountDialog(
                          context,
                          _ticketTypes[ticketIndex],
                        ),
                      ),
                    );
                  },
                  childCount: _ticketTypes.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(ThemeData theme, ColorScheme colorScheme) {
    final totalSold = _ticketTypes.fold<int>(
      0,
      (sum, t) => sum + t.soldCount,
    );
    final totalMax = _ticketTypes.fold<int?>(
      0,
      (sum, t) {
        if (sum == null || t.maxQuantity == null) return null;
        return sum + t.maxQuantity!;
      },
    );
    final totalRevenue = _ticketTypes.fold<int>(
      0,
      (sum, t) => sum + (t.soldCount * t.priceInCents),
    );
    final revenueStr = totalRevenue == 0
        ? '\$0'
        : '\$${(totalRevenue / 100).toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.event.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryChip(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Sold',
                  value: totalMax != null ? '$totalSold / $totalMax' : '$totalSold',
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryChip(
                  icon: Icons.attach_money,
                  label: 'Revenue',
                  value: revenueStr,
                  color: colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryChip(
                  icon: Icons.style_outlined,
                  label: 'Types',
                  value: '${_ticketTypes.length}',
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMintDialog(BuildContext context, TicketType ticketType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MintTicketsSheet(
        ticketType: ticketType,
        onMinted: (quantity) {
          // Refresh after minting
          _loadTicketTypes();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Minted $quantity ${ticketType.name} tickets'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _showDiscountDialog(BuildContext context, TicketType ticketType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DiscountSheet(
        ticketType: ticketType,
        onApplied: () {
          _loadTicketTypes();
        },
      ),
    );
  }
}

// ============================================================
// Summary chip
// ============================================================

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
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
      ),
    );
  }
}

// ============================================================
// Ticket Type Card
// ============================================================

class _TicketTypeCard extends StatelessWidget {
  final TicketType ticketType;
  final VoidCallback onMint;
  final VoidCallback onDiscount;

  const _TicketTypeCard({
    required this.ticketType,
    required this.onMint,
    required this.onDiscount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Progress for sold tickets
    final progress = ticketType.hasLimit
        ? ticketType.soldCount / ticketType.maxQuantity!
        : null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ticket icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.confirmation_number_outlined,
                    color: colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticketType.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (ticketType.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          ticketType.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Price badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    ticketType.formattedPrice,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _TicketStat(
                  label: 'Sold',
                  value: '${ticketType.soldCount}',
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 24),
                if (ticketType.hasLimit) ...[
                  _TicketStat(
                    label: 'Remaining',
                    value: '${ticketType.remainingQuantity}',
                    color: ticketType.remainingQuantity! <= 10
                        ? Colors.orange
                        : colorScheme.tertiary,
                  ),
                  const SizedBox(width: 24),
                  _TicketStat(
                    label: 'Total',
                    value: '${ticketType.maxQuantity}',
                    color: colorScheme.onSurfaceVariant,
                  ),
                ] else
                  _TicketStat(
                    label: 'Limit',
                    value: 'Unlimited',
                    color: colorScheme.onSurfaceVariant,
                  ),
                const Spacer(),
                // Status badge
                _StatusBadge(ticketType: ticketType),
              ],
            ),
          ),
          // Progress bar (if limited)
          if (progress != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor:
                      colorScheme.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(
                    progress >= 1.0
                        ? Colors.red
                        : progress >= 0.8
                            ? Colors.orange
                            : colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Divider
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          // Actions row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onMint,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Mint More'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Container(
                  height: 24,
                  width: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDiscount,
                    icon: const Icon(Icons.percent, size: 18),
                    label: const Text('Discount'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TicketStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TicketType ticketType;

  const _StatusBadge({required this.ticketType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color bgColor;
    Color textColor;
    String text;

    if (ticketType.isSoldOut) {
      bgColor = Colors.red.withValues(alpha: 0.1);
      textColor = Colors.red;
      text = 'Sold Out';
    } else if (!ticketType.isActive) {
      bgColor = Colors.grey.withValues(alpha: 0.1);
      textColor = Colors.grey;
      text = 'Inactive';
    } else if (ticketType.hasLimit && ticketType.remainingQuantity! <= 10) {
      bgColor = Colors.orange.withValues(alpha: 0.1);
      textColor = Colors.orange;
      text = 'Low Stock';
    } else {
      bgColor = Colors.green.withValues(alpha: 0.1);
      textColor = Colors.green;
      text = 'On Sale';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ============================================================
// Mint Tickets Bottom Sheet
// ============================================================

class _MintTicketsSheet extends StatefulWidget {
  final TicketType ticketType;
  final ValueChanged<int> onMinted;

  const _MintTicketsSheet({
    required this.ticketType,
    required this.onMinted,
  });

  @override
  State<_MintTicketsSheet> createState() => _MintTicketsSheetState();
}

class _MintTicketsSheetState extends State<_MintTicketsSheet> {
  int _quantity = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final currentSupply = widget.ticketType.maxQuantity;
    final supplyText = currentSupply != null
        ? 'Current supply: $currentSupply tickets'
        : 'Unlimited supply';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.add_circle_outline,
            size: 48,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Mint ${widget.ticketType.name}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            supplyText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.ticketType.formattedPrice,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 32),
          // Quantity selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MintStepButton(
                icon: Icons.remove,
                onTap:
                    _quantity > 10 ? () => setState(() => _quantity -= 10) : null,
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 80,
                child: Text(
                  '$_quantity',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              _MintStepButton(
                icon: Icons.add,
                onTap: _quantity < 500
                    ? () => setState(() => _quantity += 10)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'tickets',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onMinted(_quantity);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Mint $_quantity Tickets',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _MintStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MintStepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;

    return Material(
      color: isEnabled
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            icon,
            color: isEnabled
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 24,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Discount Bottom Sheet
// ============================================================

class _DiscountSheet extends StatefulWidget {
  final TicketType ticketType;
  final VoidCallback onApplied;

  const _DiscountSheet({
    required this.ticketType,
    required this.onApplied,
  });

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  final _codeController = TextEditingController();
  double _percentOff = 10;
  bool _isPercentage = true;
  int _fixedAmountOff = 500; // $5.00

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _discountPreview {
    final originalPrice = widget.ticketType.priceInCents;
    if (originalPrice == 0) return 'Free';

    int discountedPrice;
    if (_isPercentage) {
      discountedPrice =
          (originalPrice * (1 - _percentOff / 100)).round();
    } else {
      discountedPrice = (originalPrice - _fixedAmountOff).clamp(0, originalPrice);
    }

    final original = '\$${(originalPrice / 100).toStringAsFixed(2)}';
    final discounted = '\$${(discountedPrice / 100).toStringAsFixed(2)}';
    return '$original  ->  $discounted';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Icon(
              Icons.percent,
              size: 44,
              color: colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Discount: ${widget.ticketType.name}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Discount type toggle
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ToggleOption(
                      label: 'Percentage',
                      isSelected: _isPercentage,
                      onTap: () => setState(() => _isPercentage = true),
                    ),
                  ),
                  Expanded(
                    child: _ToggleOption(
                      label: 'Fixed Amount',
                      isSelected: !_isPercentage,
                      onTap: () => setState(() => _isPercentage = false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Discount value
            if (_isPercentage) ...[
              Text(
                '${_percentOff.round()}% off',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _percentOff,
                min: 5,
                max: 100,
                divisions: 19,
                label: '${_percentOff.round()}%',
                onChanged: (v) => setState(() => _percentOff = v),
              ),
            ] else ...[
              Text(
                '\$${(_fixedAmountOff / 100).toStringAsFixed(2)} off',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _fixedAmountOff.toDouble(),
                min: 100,
                max: widget.ticketType.priceInCents.toDouble().clamp(100, 100000),
                divisions: ((widget.ticketType.priceInCents.clamp(100, 100000) - 100) / 100)
                    .round()
                    .clamp(1, 100),
                label:
                    '\$${(_fixedAmountOff / 100).toStringAsFixed(2)}',
                onChanged: (v) =>
                    setState(() => _fixedAmountOff = v.round()),
              ),
            ],
            const SizedBox(height: 8),
            // Price preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Price Preview',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _discountPreview,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Discount code (optional)
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Discount Code (optional)',
                hintText: 'e.g. EARLYBIRD20',
                prefixIcon: const Icon(Icons.code, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onApplied();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Discount applied to ${widget.ticketType.name}',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: colorScheme.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Apply Discount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.secondary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isSelected
                ? colorScheme.onSecondary
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Empty and Error states
// ============================================================

class _EmptyState extends StatelessWidget {
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _EmptyState({required this.colorScheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.confirmation_number_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Ticket Types',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This event doesn\'t have any ticket types configured yet.',
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
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load tickets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
