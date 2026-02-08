import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/payment_provider.dart';
import '../../payments/models/payment.dart';
import 'transaction_detail_sheet.dart';

/// Filter for transaction currency type.
enum TransactionCurrencyFilter {
  all('All'),
  fiat('Fiat'),
  crypto('Crypto');

  final String label;
  const TransactionCurrencyFilter(this.label);
}

/// Filter for transaction time period.
enum TransactionTimeFilter {
  all('All Time'),
  today('Today'),
  thisWeek('This Week'),
  thisMonth('This Month'),
  last3Months('Last 3 Months');

  final String label;
  const TransactionTimeFilter(this.label);
}

/// Screen displaying transaction history with filters.
class TransactionsScreen extends ConsumerStatefulWidget {
  /// Initial currency filter (used when navigating from wallet).
  final TransactionCurrencyFilter initialCurrencyFilter;

  const TransactionsScreen({
    super.key,
    this.initialCurrencyFilter = TransactionCurrencyFilter.all,
  });

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late TransactionCurrencyFilter _currencyFilter;
  TransactionTimeFilter _timeFilter = TransactionTimeFilter.all;
  final ScrollController _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currencyFilter = widget.initialCurrencyFilter;

    // Load payment history
    Future.microtask(() {
      ref.read(paymentHistoryProvider.notifier).load();
    });

    // Set up infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(paymentHistoryProvider);
      if (state.canLoadMore && _currencyFilter != TransactionCurrencyFilter.crypto) {
        ref.read(paymentHistoryProvider.notifier).loadMore();
      }
    }
  }

  List<Payment> _filterPayments(List<Payment> payments) {
    // Filter by currency type
    // Note: Currently all payments are fiat. Crypto will be added later.
    if (_currencyFilter == TransactionCurrencyFilter.crypto) {
      return []; // No crypto transactions yet
    }

    // Filter by search query
    var results = payments;
    if (_searchQuery.isNotEmpty) {
      results = results.where((payment) {
        final typeLabel = _getTypeLabel(payment.type).toLowerCase();
        final amount = payment.formattedAmount.toLowerCase();
        final status = payment.status.value.toLowerCase();
        return typeLabel.contains(_searchQuery) ||
            amount.contains(_searchQuery) ||
            status.contains(_searchQuery);
      }).toList();
    }

    // Filter by time period
    final now = DateTime.now();
    final filtered = results.where((payment) {
      switch (_timeFilter) {
        case TransactionTimeFilter.all:
          return true;
        case TransactionTimeFilter.today:
          return payment.createdAt.year == now.year &&
              payment.createdAt.month == now.month &&
              payment.createdAt.day == now.day;
        case TransactionTimeFilter.thisWeek:
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return payment.createdAt.isAfter(
            DateTime(weekStart.year, weekStart.month, weekStart.day),
          );
        case TransactionTimeFilter.thisMonth:
          return payment.createdAt.year == now.year &&
              payment.createdAt.month == now.month;
        case TransactionTimeFilter.last3Months:
          final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
          return payment.createdAt.isAfter(threeMonthsAgo);
      }
    }).toList();

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(paymentHistoryProvider);

    final filteredPayments = _filterPayments(state.payments);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                autofocus: true,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                ),
              )
            : const Text('Transactions'),
        centerTitle: !_isSearching,
        actions: [
          // Search toggle
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                  _searchQuery = '';
                }
                _isSearching = !_isSearching;
              });
            },
          ),
          // Currency filter
          PopupMenuButton<TransactionCurrencyFilter>(
            icon: Icon(
              _getCurrencyIcon(_currencyFilter),
              color: _currencyFilter != TransactionCurrencyFilter.all
                  ? colorScheme.primary
                  : null,
            ),
            onSelected: (filter) => setState(() => _currencyFilter = filter),
            itemBuilder: (_) => TransactionCurrencyFilter.values.map((filter) {
              final isSelected = _currencyFilter == filter;
              return PopupMenuItem(
                value: filter,
                child: Row(
                  children: [
                    Icon(
                      _getCurrencyIcon(filter),
                      size: 18,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(filter.label),
                    if (isSelected) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 18, color: colorScheme.primary),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          // Time filter
          PopupMenuButton<TransactionTimeFilter>(
            icon: Icon(
              Icons.filter_list,
              color: _timeFilter != TransactionTimeFilter.all
                  ? colorScheme.primary
                  : null,
            ),
            onSelected: (filter) => setState(() => _timeFilter = filter),
            itemBuilder: (_) => TransactionTimeFilter.values.map((filter) {
              final isSelected = _timeFilter == filter;
              return PopupMenuItem(
                value: filter,
                child: Row(
                  children: [
                    if (isSelected)
                      Icon(Icons.check, size: 18, color: colorScheme.primary)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 12),
                    Text(filter.label),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: state.isLoading && state.payments.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.payments.isEmpty
              ? _ErrorView(
                  error: state.error!,
                  onRetry: () =>
                      ref.read(paymentHistoryProvider.notifier).load(),
                )
              : filteredPayments.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () => ref
                          .read(paymentHistoryProvider.notifier)
                          .refresh(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: _EmptyView(currencyFilter: _currencyFilter),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref
                          .read(paymentHistoryProvider.notifier)
                          .refresh(),
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredPayments.length +
                            (state.isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == filteredPayments.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final payment = filteredPayments[index];
                          return _TransactionCard(
                            payment: payment,
                            showDate: index == 0 ||
                                !_isSameDay(
                                  payment.createdAt,
                                  filteredPayments[index - 1].createdAt,
                                ),
                          );
                        },
                      ),
                    ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _getTypeLabel(PaymentType type) {
    switch (type) {
      case PaymentType.primaryPurchase:
        return 'Ticket Purchase';
      case PaymentType.resalePurchase:
        return 'Resale Purchase';
      case PaymentType.vendorPos:
        return 'Vendor Purchase';
      case PaymentType.subscription:
        return 'Subscription';
    }
  }

  IconData _getCurrencyIcon(TransactionCurrencyFilter filter) {
    switch (filter) {
      case TransactionCurrencyFilter.all:
        return Icons.all_inclusive;
      case TransactionCurrencyFilter.fiat:
        return Icons.attach_money;
      case TransactionCurrencyFilter.crypto:
        return Icons.currency_bitcoin;
    }
  }
}

/// Single transaction card.
class _TransactionCard extends StatelessWidget {
  final Payment payment;
  final bool showDate;

  const _TransactionCard({
    required this.payment,
    required this.showDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDate) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              _formatDate(payment.createdAt),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => showTransactionDetailSheet(context, payment),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getStatusColor(payment.status, colorScheme)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getTypeIcon(payment.type),
                        color: _getStatusColor(payment.status, colorScheme),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTypeLabel(payment.type),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTime(payment.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Amount and status
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          payment.formattedAmount,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _getAmountColor(payment.type, payment.status, colorScheme),
                          ),
                        ),
                        const SizedBox(height: 2),
                        _StatusChip(status: payment.status),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Chevron hint
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  IconData _getTypeIcon(PaymentType type) {
    switch (type) {
      case PaymentType.primaryPurchase:
        return Icons.confirmation_number;
      case PaymentType.resalePurchase:
        return Icons.swap_horiz;
      case PaymentType.vendorPos:
        return Icons.storefront;
      case PaymentType.subscription:
        return Icons.workspace_premium;
    }
  }

  String _getTypeLabel(PaymentType type) {
    switch (type) {
      case PaymentType.primaryPurchase:
        return 'Ticket Purchase';
      case PaymentType.resalePurchase:
        return 'Resale Purchase';
      case PaymentType.vendorPos:
        return 'Vendor Purchase';
      case PaymentType.subscription:
        return 'Subscription';
    }
  }

  Color _getStatusColor(PaymentStatus status, ColorScheme colorScheme) {
    switch (status) {
      case PaymentStatus.completed:
        return Colors.green;
      case PaymentStatus.pending:
      case PaymentStatus.processing:
        return Colors.orange;
      case PaymentStatus.failed:
        return colorScheme.error;
      case PaymentStatus.refunded:
        return colorScheme.tertiary;
    }
  }

  Color _getAmountColor(
      PaymentType type, PaymentStatus status, ColorScheme colorScheme) {
    if (status == PaymentStatus.refunded) {
      return colorScheme.tertiary;
    }
    return colorScheme.onSurface;
  }
}

/// Status chip widget.
class _StatusChip extends StatelessWidget {
  final PaymentStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = _getStatusInfo(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (Color, String) _getStatusInfo(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.completed:
        return (Colors.green, 'Completed');
      case PaymentStatus.pending:
        return (Colors.orange, 'Pending');
      case PaymentStatus.processing:
        return (Colors.orange, 'Processing');
      case PaymentStatus.failed:
        return (Colors.red, 'Failed');
      case PaymentStatus.refunded:
        return (Colors.blue, 'Refunded');
    }
  }
}

/// Empty state view.
class _EmptyView extends StatelessWidget {
  final TransactionCurrencyFilter currencyFilter;

  const _EmptyView({required this.currencyFilter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, title, subtitle) = _getEmptyContent();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  (IconData, String, String) _getEmptyContent() {
    switch (currencyFilter) {
      case TransactionCurrencyFilter.crypto:
        return (
          Icons.currency_bitcoin,
          'No Crypto Transactions',
          'Crypto payments are coming soon. Stay tuned!',
        );
      case TransactionCurrencyFilter.fiat:
        return (
          Icons.receipt_long,
          'No Fiat Transactions',
          'Your card transactions will appear here.',
        );
      case TransactionCurrencyFilter.all:
        return (
          Icons.receipt_long,
          'No Transactions Yet',
          'Your transaction history will appear here.',
        );
    }
  }
}

/// Error view.
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.error,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
