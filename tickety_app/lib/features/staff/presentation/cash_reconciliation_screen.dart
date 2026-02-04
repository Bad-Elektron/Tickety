import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/cash_transaction_repository.dart';
import '../models/cash_transaction.dart';

/// Screen for organizers to view and reconcile cash transactions for an event.
class CashReconciliationScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const CashReconciliationScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<CashReconciliationScreen> createState() =>
      _CashReconciliationScreenState();
}

class _CashReconciliationScreenState extends State<CashReconciliationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _repository = CashTransactionRepository();

  bool _isLoading = true;
  CashSummary? _summary;
  List<SellerCashSummary> _sellerSummaries = [];
  List<CashTransaction> _transactions = [];
  CashTransactionStatus? _statusFilter;
  bool _hasMore = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _repository.getEventCashSummary(widget.eventId),
        _repository.getEventCashBySeller(widget.eventId),
        _repository.getEventCashTransactions(
          eventId: widget.eventId,
          status: _statusFilter,
        ),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as CashSummary;
          _sellerSummaries = results[1] as List<SellerCashSummary>;
          final txResult = results[2] as dynamic;
          _transactions = txResult.items as List<CashTransaction>;
          _hasMore = txResult.hasMore as bool;
          _currentPage = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading cash data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (!_hasMore) return;

    try {
      final result = await _repository.getEventCashTransactions(
        eventId: widget.eventId,
        status: _statusFilter,
        page: _currentPage + 1,
      );

      if (mounted) {
        setState(() {
          _transactions.addAll(result.items);
          _hasMore = result.hasMore;
          _currentPage++;
        });
      }
    } catch (e) {
      debugPrint('Error loading more transactions: $e');
    }
  }

  Future<void> _markCollected(CashTransaction tx) async {
    final success = await _repository.markCollected(tx.id);
    if (success) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction marked as collected'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _markDisputed(CashTransaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Disputed?'),
        content: Text(
          'This will flag the transaction for ${tx.formattedAmount} as disputed. '
          'Use this if there\'s an issue with cash collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Mark Disputed'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _repository.markDisputed(tx.id);
      if (success) {
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction marked as disputed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Reconciliation'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Transactions'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(theme, colorScheme),
                _buildTransactionsTab(theme, colorScheme),
              ],
            ),
    );
  }

  Widget _buildSummaryTab(ThemeData theme, ColorScheme colorScheme) {
    final summary = _summary ?? CashSummary.empty();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Event title
          Text(
            widget.eventTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Total cash summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Cash Sales',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary.formattedTotalCash,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatItem(
                        theme,
                        'Transactions',
                        summary.transactionCount.toString(),
                        Icons.receipt_long,
                      ),
                      _buildStatItem(
                        theme,
                        'Collected',
                        summary.collectedCount.toString(),
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                      _buildStatItem(
                        theme,
                        'Pending',
                        summary.pendingCount.toString(),
                        Icons.pending,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Platform fees card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Platform Fees (5%)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Charged',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              summary.formattedFeesCollected,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (summary.feesOutstandingCents > 0)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Outstanding',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                summary.formattedFeesOutstanding,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Per-seller breakdown
          Text(
            'Cash by Seller',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (_sellerSummaries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No cash sales yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._sellerSummaries.map(
              (seller) => _buildSellerCard(theme, colorScheme, seller),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Icon(icon, color: color ?? colorScheme.primary, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerCard(
    ThemeData theme,
    ColorScheme colorScheme,
    SellerCashSummary seller,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    seller.sellerDisplayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${seller.transactionCount} sales',
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
                  seller.formattedTotalCash,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                if (seller.pendingCount > 0)
                  Text(
                    '${seller.pendingCount} pending',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsTab(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // Status filter
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Filter: '),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', null),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                          'Pending', CashTransactionStatus.pending),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                          'Collected', CashTransactionStatus.collected),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                          'Disputed', CashTransactionStatus.disputed),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Transactions list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: _transactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions found',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _transactions.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _transactions.length) {
                        // Load more indicator
                        _loadMoreTransactions();
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return _buildTransactionCard(
                        theme,
                        colorScheme,
                        _transactions[index],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, CashTransactionStatus? status) {
    final isSelected = _statusFilter == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _statusFilter = selected ? status : null;
        });
        _loadData();
      },
    );
  }

  Widget _buildTransactionCard(
    ThemeData theme,
    ColorScheme colorScheme,
    CashTransaction tx,
  ) {
    final dateFormat = DateFormat('MMM d, h:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status icon
                _buildStatusIcon(tx.status),
                const SizedBox(width: 12),
                // Transaction details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.customerDisplayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Ticket #${tx.ticketNumber ?? 'N/A'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Amount
                Text(
                  tx.formattedAmount,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Metadata row
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tx.sellerDisplayName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  dateFormat.format(tx.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // Fee status warning
            if (tx.hasIssues) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'Fee not charged: ${tx.feeChargeError ?? "Unknown error"}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Actions for pending transactions
            if (tx.status == CashTransactionStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _markDisputed(tx),
                    child: const Text('Dispute'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _markCollected(tx),
                    child: const Text('Mark Collected'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(CashTransactionStatus status) {
    switch (status) {
      case CashTransactionStatus.collected:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withValues(alpha: 0.1),
          ),
          child: const Icon(Icons.check_circle, color: Colors.green),
        );
      case CashTransactionStatus.disputed:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.1),
          ),
          child: const Icon(Icons.warning, color: Colors.red),
        );
      case CashTransactionStatus.pending:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.orange.withValues(alpha: 0.1),
          ),
          child: const Icon(Icons.pending, color: Colors.orange),
        );
    }
  }
}
