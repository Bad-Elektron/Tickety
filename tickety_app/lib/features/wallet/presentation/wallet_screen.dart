import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/cardano_wallet_provider.dart';
import '../../../core/providers/payment_methods_provider.dart';
import '../../../core/providers/seller_balance_provider.dart';
import '../../../core/providers/wallet_balance_provider.dart';
import '../../../core/services/services.dart';
import '../../payments/models/payment_method.dart';
import '../../payments/models/seller_balance.dart';
import '../../payments/presentation/ready_to_pay_screen.dart';
import '../data/wallet_repository.dart';
import '../models/linked_bank_account.dart';
import 'add_funds_screen.dart';
import 'cardano_receive_screen.dart';
import 'cardano_send_screen.dart';
import 'link_bank_screen.dart';
import 'transactions_screen.dart';

/// Screen displaying the user's wallet and seller balance.
///
/// Layout:
/// 1. Tickety Wallet card (prominent, full width) — available + pending balance
/// 2. Crypto Balance card (always visible) with Receive/Send buttons
/// 3. Seller Balance card (only if seller account exists)
/// 4. Linked Bank Accounts section
/// 5. Action buttons & info cards
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(sellerBalanceProvider.notifier).loadBalance();
      ref.read(walletBalanceProvider.notifier).loadBalance();
      ref.read(cardanoWalletProvider.notifier).ensureWallet();
      ref.read(paymentMethodsProvider.notifier).load();
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(sellerBalanceProvider.notifier).refresh(),
      ref.read(walletBalanceProvider.notifier).refresh(),
      ref.read(cardanoWalletProvider.notifier).loadBalance(),
      ref.read(paymentMethodsProvider.notifier).load(),
    ]);
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
      final uri = Uri.parse(result.onboardingUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (result.success) {
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

  Future<void> _handleLinkBank() async {
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LinkBankScreen()),
    );
    if (linked == true) {
      ref.read(walletBalanceProvider.notifier).refresh();
    }
  }

  Future<void> _handleAddFunds() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddFundsScreen()),
    );
    if (added == true) {
      ref.read(walletBalanceProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sellerState = ref.watch(sellerBalanceProvider);
    final walletState = ref.watch(walletBalanceProvider);

    final isAnyLoading = sellerState.isLoading || walletState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isAnyLoading ? null : _refreshAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReadyToPayScreen()),
          );
        },
        icon: const Icon(Icons.contactless),
        label: const Text('Ready to Pay'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ============================
              // 1. TICKETY WALLET CARD (prominent)
              // ============================
              _TicketyWalletCard(
                walletState: walletState,
                onAddFunds: _handleAddFunds,
              ),

              const SizedBox(height: 20),

              // ============================
              // 2. CRYPTO BALANCE CARD (always visible)
              // ============================
              const _CryptoBalanceSection(),

              const SizedBox(height: 16),

              // ============================
              // 3. SELLER BALANCE (only shown if account exists)
              // ============================
              if (sellerState.balance != null && sellerState.balance!.hasAccount) ...[
                _SellerBalanceCard(balance: sellerState.balance!),
                const SizedBox(height: 24),
              ],

              // ============================
              // 3. LINKED BANK ACCOUNTS
              // ============================
              _LinkedBankSection(
                bankAccounts: walletState.balance?.bankAccounts ?? [],
                isLoading: walletState.isLoading,
                onLink: _handleLinkBank,
                onRemove: (bank) async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove Bank Account'),
                      content: Text('Remove ${bank.displayName}?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final repo = ref.read(walletBalanceProvider.notifier);
                    // Remove via repository directly, then refresh
                    try {
                      final walletRepo =
                          ref.read(_walletRepoProvider);
                      await walletRepo.removeBankAccount(
                          bank.stripePaymentMethodId);
                      repo.refresh();
                    } catch (_) {}
                  }
                },
              ),

              const SizedBox(height: 24),

              // ============================
              // 5. SAVED CARDS
              // ============================
              const _SavedCardsSection(),

              const SizedBox(height: 24),

              // ============================
              // 6. SELLER ACTIONS (Add Bank / Withdraw)
              // ============================
              if (sellerState.balance != null && sellerState.balance!.hasAccount)
                _WalletActions(
                  balance: sellerState.balance!,
                  isLoading: sellerState.isWithdrawing,
                  onAddBank: _handleAddBank,
                  onWithdraw: _handleWithdraw,
                ),

              // Error messages
              if (sellerState.error != null) ...[
                const SizedBox(height: 16),
                _ErrorMessage(
                  message: sellerState.error!,
                  onDismiss: () =>
                      ref.read(sellerBalanceProvider.notifier).clearError(),
                ),
              ],
              if (walletState.error != null) ...[
                const SizedBox(height: 16),
                _ErrorMessage(
                  message: walletState.error!,
                  onDismiss: () =>
                      ref.read(walletBalanceProvider.notifier).clearError(),
                ),
              ],

              const SizedBox(height: 32),

              // Info section
              if (sellerState.balance != null) ...[
                Text(
                  'About Your Wallet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _InfoCard(
                  icon: Icons.savings_outlined,
                  title: 'Save on Fees',
                  description:
                      'Fund your wallet via ACH (0.8% fee, max \$5) and buy tickets with just a 5% platform fee — no card processing costs.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.security,
                  title: 'Secure & Compliant',
                  description:
                      'Your funds are held securely by Stripe, a licensed payment processor.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.access_time,
                  title: 'ACH Settlement',
                  description:
                      'Bank transfers take 4-5 business days to settle. Funds show as pending until cleared.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.percent,
                  title: '95% Seller Earnings',
                  description:
                      'You keep 95% of each sale. Only a 5% platform fee is deducted.',
                ),
                if (!sellerState.balance!.payoutsEnabled) ...[
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

              // Space for FAB
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

/// Provider to expose WalletRepository for direct use in wallet screen.
final _walletRepoProvider = Provider((_) {
  return WalletRepository();
});

// ============================================================
// TICKETY WALLET CARD
// ============================================================

class _TicketyWalletCard extends StatelessWidget {
  final WalletBalanceState walletState;
  final VoidCallback onAddFunds;

  const _TicketyWalletCard({
    required this.walletState,
    required this.onAddFunds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = walletState.balance;
    final isLoading = walletState.isLoading && balance == null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
                      Icons.account_balance_wallet,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tickety Wallet',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                FilledButton.tonal(
                  onPressed: onAddFunds,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Add Funds'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              )
            else
              Text(
                balance?.formattedAvailable ?? '\$0.00',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Available Balance',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            if (balance != null && balance.hasPending) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${balance.formattedPending} pending',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CRYPTO BALANCE SECTION (always visible)
// ============================================================

class _CryptoBalanceSection extends ConsumerWidget {
  const _CryptoBalanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardanoState = ref.watch(cardanoWalletProvider);
    final hasCardanoWallet = cardanoState.hasWallet;
    final cardanoBalance = cardanoState.balance;
    final isCardanoLoading = cardanoState.isLoading;

    return Column(
      children: [
        _BalanceCard(
          title: 'Available',
          amount: isCardanoLoading
              ? '...'
              : (cardanoBalance?.formattedAda ?? '0 ADA'),
          subtitle: 'Cardano Preview',
          tag: 'Crypto Balance',
          icon: Icons.currency_bitcoin,
          gradientColors: NoisePresets.vibrantEvents(108).colors,
          isLoading: isCardanoLoading,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TransactionsScreen(
                    initialCurrencyFilter: TransactionCurrencyFilter.crypto),
              ),
            );
          },
        ),
        if (hasCardanoWallet) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CardanoActionButton(
                  icon: Icons.arrow_downward,
                  label: 'Receive',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CardanoReceiveScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CardanoActionButton(
                  icon: Icons.arrow_upward,
                  label: 'Send',
                  onTap: () {
                    Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const CardanoSendScreen(),
                      ),
                    ).then((sent) {
                      if (sent == true) {
                        ref.read(cardanoWalletProvider.notifier).refresh();
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ============================================================
// SELLER BALANCE CARD (single card, not side-by-side)
// ============================================================

class _SellerBalanceCard extends StatelessWidget {
  final SellerBalance balance;

  const _SellerBalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return _BalanceCard(
      title: 'Available',
      amount: balance.formattedAvailableBalance,
      subtitle: balance.payoutsEnabled
          ? 'Ready to withdraw'
          : 'Add bank to withdraw',
      tag: 'Seller Balance',
      icon: Icons.account_balance_wallet,
      gradientColors: NoisePresets.subtle(42).colors,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TransactionsScreen(
                initialCurrencyFilter: TransactionCurrencyFilter.fiat),
          ),
        );
      },
    );
  }
}

// ============================================================
// SAVED CARDS SECTION
// ============================================================

class _SavedCardsSection extends ConsumerWidget {
  const _SavedCardsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(paymentMethodsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Cards',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton.icon(
              onPressed: StripeService.isSupported
                  ? () => ref.read(paymentMethodsProvider.notifier).addCard()
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Card'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.isLoading && state.methods.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (state.methods.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.credit_card_off_outlined,
                  size: 32,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'No cards saved',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add a card to speed up checkout',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          )
        else
          ...state.methods.map((card) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SavedCardTile(
                  card: card,
                  onSetDefault: () {
                    if (!card.isDefault) {
                      ref
                          .read(paymentMethodsProvider.notifier)
                          .setDefault(card.id);
                    }
                  },
                  onDelete: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Remove Card'),
                        content: Text(
                          'Remove ${card.displayBrand} ending in ${card.last4}?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.error,
                            ),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      ref
                          .read(paymentMethodsProvider.notifier)
                          .deleteCard(card.id);
                    }
                  },
                ),
              )),
      ],
    );
  }
}

class _SavedCardTile extends StatelessWidget {
  final PaymentMethodCard card;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const _SavedCardTile({
    required this.card,
    required this.onSetDefault,
    required this.onDelete,
  });

  Color _brandColor(String brand, ColorScheme colorScheme) {
    switch (brand.toLowerCase()) {
      case 'visa':
        return const Color(0xFF1A1F71);
      case 'mastercard':
        return const Color(0xFFEB001B);
      case 'amex':
        return const Color(0xFF2E77BC);
      case 'discover':
        return const Color(0xFFFF6000);
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brandColor = _brandColor(card.brand, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: card.isDefault
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.4),
              )
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 28,
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.credit_card,
              color: brandColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${card.displayBrand} ****${card.last4}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Expires ${card.formattedExpiry}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: card.isExpired
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (card.isDefault)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Default',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
            onSelected: (value) {
              if (value == 'default') onSetDefault();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              if (!card.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Set as Default'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 12),
                    Text('Remove',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardanoActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CardanoActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LINKED BANK ACCOUNTS SECTION
// ============================================================

class _LinkedBankSection extends StatelessWidget {
  final List<LinkedBankAccount> bankAccounts;
  final bool isLoading;
  final VoidCallback onLink;
  final void Function(LinkedBankAccount bank) onRemove;

  const _LinkedBankSection({
    required this.bankAccounts,
    required this.isLoading,
    required this.onLink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Linked Banks',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton.icon(
              onPressed: onLink,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Link Bank'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading && bankAccounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (bankAccounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  size: 32,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'No bank accounts linked',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Link a bank to fund your wallet via ACH',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          )
        else
          ...bankAccounts.map((bank) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.account_balance,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bank.bankName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '****${bank.last4} \u2022 ${bank.accountType}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (bank.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Default',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.more_vert,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () => onRemove(bank),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

// ============================================================
// SHARED WIDGETS (kept from original)
// ============================================================

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
    final canWithdraw =
        balance.availableBalanceCents > 0 && balance.payoutsEnabled;
    final needsBankSetup = !balance.payoutsEnabled;

    return Column(
      children: [
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
                              ? colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.7)
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
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
