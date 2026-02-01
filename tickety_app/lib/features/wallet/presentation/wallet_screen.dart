import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/seller_balance_provider.dart';
import '../../payments/models/seller_balance.dart';
import 'transactions_screen.dart';

/// Screen displaying the user's wallet and seller balance.
///
/// Shows the seller's Stripe balance (funds from ticket resales) and
/// allows them to withdraw to their bank account.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  @override
  void initState() {
    super.initState();
    // Load balance on screen open
    Future.microtask(() {
      ref.read(sellerBalanceProvider.notifier).loadBalance();
    });
  }

  Future<void> _handleAddBank() async {
    final notifier = ref.read(sellerBalanceProvider.notifier);
    final result = await notifier.initiateWithdrawal();

    if (result == null) return;
    if (!mounted) return;

    if (result.needsOnboarding && result.onboardingUrl != null) {
      final uri = Uri.parse(result.onboardingUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _handleWithdraw() async {
    final notifier = ref.read(sellerBalanceProvider.notifier);
    final result = await notifier.initiateWithdrawal();

    if (result == null) return;
    if (!mounted) return;

    if (result.needsOnboarding && result.onboardingUrl != null) {
      // User needs to add bank details - open Stripe onboarding
      final uri = Uri.parse(result.onboardingUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (result.success) {
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal of ${result.formattedAmount} initiated! '
            'Funds will arrive in 2-5 business days.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balanceState = ref.watch(sellerBalanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: balanceState.isLoading
                ? null
                : () => ref.read(sellerBalanceProvider.notifier).refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sellerBalanceProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Balance cards
              if (balanceState.isLoading && balanceState.balance == null)
                const _LoadingBalanceCards()
              else if (balanceState.balance != null && balanceState.balance!.hasAccount)
                _BalanceCards(balance: balanceState.balance!)
              else
                _NoAccountCards(
                  onSetup: () async {
                    await ref
                        .read(sellerBalanceProvider.notifier)
                        .ensureSellerAccount();
                  },
                ),

              const SizedBox(height: 24),

              // Action buttons (Add Bank / Withdraw) - only show if user has a seller account
              if (balanceState.balance != null && balanceState.balance!.hasAccount)
                _WalletActions(
                  balance: balanceState.balance!,
                  isLoading: balanceState.isWithdrawing,
                  onAddBank: _handleAddBank,
                  onWithdraw: _handleWithdraw,
                ),

              // Error message
              if (balanceState.error != null) ...[
                const SizedBox(height: 16),
                _ErrorMessage(
                  message: balanceState.error!,
                  onDismiss: () =>
                      ref.read(sellerBalanceProvider.notifier).clearError(),
                ),
              ],

              const SizedBox(height: 32),

              // Info section
              if (balanceState.balance != null) ...[
                Text(
                  'About Your Wallet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _InfoCard(
                  icon: Icons.security,
                  title: 'Secure & Compliant',
                  description:
                      'Your funds are held securely by Stripe, a licensed payment processor.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.access_time,
                  title: 'Fast Withdrawals',
                  description:
                      'Funds typically arrive in your bank account within 2-5 business days.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.percent,
                  title: '95% Earnings',
                  description:
                      'You keep 95% of each sale. Only a 5% platform fee is deducted.',
                ),
                if (!balanceState.balance!.payoutsEnabled) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.account_balance,
                    title: 'Add Bank Details to Withdraw',
                    description:
                        'To withdraw your earnings, you\'ll need to add your bank account details.',
                    isHighlighted: true,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Balance cards showing Stripe and Crypto balances.
class _BalanceCards extends StatelessWidget {
  final SellerBalance balance;

  const _BalanceCards({required this.balance});

  void _navigateToTransactions(
      BuildContext context, TransactionCurrencyFilter filter) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionsScreen(initialCurrencyFilter: filter),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BalanceCard(
            title: 'Available',
            amount: balance.formattedAvailableBalance,
            subtitle: balance.payoutsEnabled ? 'Ready to withdraw' : 'Add bank to withdraw',
            tag: 'Stripe Balance',
            icon: Icons.account_balance_wallet,
            gradientColors: NoisePresets.subtle(42).colors,
            onTap: () => _navigateToTransactions(
                context, TransactionCurrencyFilter.fiat),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BalanceCard(
            title: 'Available',
            amount: '0 ADA',
            subtitle: 'Coming soon',
            tag: 'Crypto Balance',
            icon: Icons.currency_bitcoin,
            gradientColors: NoisePresets.vibrantEvents(108).colors,
            onTap: () => _navigateToTransactions(
                context, TransactionCurrencyFilter.crypto),
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder for balance cards.
class _LoadingBalanceCards extends StatelessWidget {
  const _LoadingBalanceCards();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BalanceCard(
            title: 'Available',
            amount: '...',
            subtitle: 'Loading',
            tag: 'Stripe Balance',
            icon: Icons.account_balance_wallet,
            gradientColors: NoisePresets.subtle(42).colors,
            isLoading: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BalanceCard(
            title: 'Available',
            amount: '...',
            subtitle: 'Loading',
            tag: 'Crypto Balance',
            icon: Icons.currency_bitcoin,
            gradientColors: NoisePresets.vibrantEvents(108).colors,
            isLoading: true,
          ),
        ),
      ],
    );
  }
}

/// Cards shown when user doesn't have a seller account yet.
class _NoAccountCards extends StatelessWidget {
  final VoidCallback onSetup;

  const _NoAccountCards({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: NoisePresets.vibrantEvents(108).colors,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: Colors.white.withValues(alpha: 0.9),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Start Selling Tickets',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set up your seller account to list tickets for resale and track your earnings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: onSetup,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
            ),
            child: const Text('Set Up Seller Account'),
          ),
        ],
      ),
    );
  }
}

/// Card displaying a balance (Stripe or Crypto).
class _BalanceCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final String tag;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isLoading;
  final VoidCallback? onTap;

  const _BalanceCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.tag,
    required this.icon,
    required this.gradientColors,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: isLoading ? null : onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors.first.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            icon,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.chevron_right,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 20,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isLoading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    )
                  else
                    Text(
                      amount,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tag,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Action buttons for wallet (Add Bank Details / Withdraw).
class _WalletActions extends StatelessWidget {
  final SellerBalance balance;
  final bool isLoading;
  final VoidCallback onAddBank;
  final VoidCallback onWithdraw;

  const _WalletActions({
    required this.balance,
    required this.isLoading,
    required this.onAddBank,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final canWithdraw = balance.availableBalanceCents > 0 && balance.payoutsEnabled;
    final needsBankSetup = !balance.payoutsEnabled;

    return Column(
      children: [
        // Add Bank Details button (only if not set up)
        if (needsBankSetup)
          _ActionButton(
            icon: Icons.account_balance,
            label: 'Add Bank Details',
            sublabel: 'Required to withdraw earnings',
            isLoading: isLoading,
            isPrimary: true,
            onTap: onAddBank,
          ),

        if (needsBankSetup && balance.availableBalanceCents > 0)
          const SizedBox(height: 12),

        // Withdraw button
        if (!needsBankSetup || balance.availableBalanceCents > 0)
          _ActionButton(
            icon: canWithdraw ? Icons.arrow_downward : Icons.money_off,
            label: canWithdraw
                ? 'Withdraw ${balance.formattedAvailableBalance}'
                : needsBankSetup
                    ? 'Add bank to withdraw'
                    : 'No funds to withdraw',
            sublabel: canWithdraw ? 'Transfer to your bank account' : null,
            isLoading: false,
            isPrimary: canWithdraw,
            onTap: canWithdraw ? onWithdraw : null,
          ),
      ],
    );
  }
}

/// Single action button widget.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool isLoading;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.isLoading,
    required this.isPrimary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = onTap != null && !isLoading;

    return Material(
      color: isPrimary && isEnabled
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              if (isLoading)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isPrimary && isEnabled
                        ? colorScheme.primary.withValues(alpha: 0.2)
                        : colorScheme.onSurface.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isPrimary && isEnabled
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isPrimary && isEnabled
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sublabel != null)
                      Text(
                        sublabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isPrimary && isEnabled
                              ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isPrimary && isEnabled
                    ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error message display.
class _ErrorMessage extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorMessage({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.error, size: 18),
            onPressed: onDismiss,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// Info card for wallet information.
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isHighlighted;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted
            ? Border.all(color: colorScheme.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? colorScheme.primary.withValues(alpha: 0.2)
                  : colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
