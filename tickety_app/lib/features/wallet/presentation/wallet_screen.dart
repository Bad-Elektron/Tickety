import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/cardano_wallet_provider.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/providers/nft_mint_provider.dart';
import '../../../core/providers/payment_methods_provider.dart';
import '../../../core/providers/seller_balance_provider.dart';
import '../../../core/services/services.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../payments/models/payment_method.dart';
import '../../payments/models/seller_balance.dart';
import '../../payments/presentation/ready_to_pay_screen.dart';
import '../data/wallet_repository.dart';
import '../models/linked_bank_account.dart';
import 'cardano_receive_screen.dart';
import 'cardano_send_screen.dart';
import '../models/nft_ticket.dart';
import 'link_bank_screen.dart';
import 'nft_ticket_detail_screen.dart';
import 'transactions_screen.dart';

/// Screen displaying the user's wallets and payment methods.
///
/// Layout:
/// 1. Crypto Balance card (always visible) with Receive/Send buttons
/// 2. NFT Tickets section
/// 3. Seller Balance card (only if seller account exists)
/// 4. Linked Bank Accounts section
/// 5. Saved Cards section
/// 6. Info cards
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  List<LinkedBankAccount> _bankAccounts = [];
  bool _isBankLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(sellerBalanceProvider.notifier).loadBalance();
      ref.read(cardanoWalletProvider.notifier).ensureWallet();
      ref.read(nftMintProvider.notifier).loadNfts();
      ref.read(paymentMethodsProvider.notifier).load();
      _loadBankAccounts();
    });
  }

  Future<void> _loadBankAccounts() async {
    try {
      final repo = WalletRepository();
      final accounts = await repo.getBankAccounts();
      if (mounted) {
        setState(() {
          _bankAccounts = accounts;
          _isBankLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isBankLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(sellerBalanceProvider.notifier).refresh(),
      ref.read(cardanoWalletProvider.notifier).loadBalance(),
      ref.read(nftMintProvider.notifier).loadNfts(),
      ref.read(paymentMethodsProvider.notifier).load(),
    ]);
    _loadBankAccounts();
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
      _loadBankAccounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sellerState = ref.watch(sellerBalanceProvider);

    final isAnyLoading = sellerState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        centerTitle: true,
        actions: [
          _CurrencySelector(),
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
              // 1. CRYPTO BALANCE CARD (always visible)
              // ============================
              const _CryptoBalanceSection(),

              const SizedBox(height: 16),

              // ============================
              // NFT TICKETS (horizontal scroll)
              // ============================
              const _NftTicketsSection(),

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
                bankAccounts: _bankAccounts,
                isLoading: _isBankLoading,
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
                    try {
                      final walletRepo =
                          ref.read(_walletRepoProvider);
                      await walletRepo.removeBankAccount(
                          bank.stripePaymentMethodId);
                      _loadBankAccounts();
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

              const SizedBox(height: 32),

              // Info section
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
                    'Link your bank account and pay via ACH at checkout — just 5% platform fee + 0.8% processing (max \$5). No card fees.',
              ),
              const SizedBox(height: 12),
              _InfoCard(
                icon: Icons.security,
                title: 'Secure & Compliant',
                description:
                    'All payments are processed securely by Stripe.',
              ),
              const SizedBox(height: 12),
              _InfoCard(
                icon: Icons.flash_on,
                title: 'Instant Tickets',
                description:
                    'Get your tickets immediately when paying with your bank. ACH settles in 4-5 business days.',
              ),
              if (sellerState.balance != null) ...[
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
// CRYPTO BALANCE SECTION (always visible)
// ============================================================

// ============================================================
// NFT TICKETS SECTION (horizontal scroll)
// ============================================================

class _NftTicketsSection extends ConsumerWidget {
  const _NftTicketsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nftState = ref.watch(nftMintProvider);
    final nfts = nftState.nfts;

    if (nfts.isEmpty && !nftState.isLoading) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(Icons.token_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'NFT Tickets',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (nftState.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: nfts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final nft = nfts[index];
              return _NftTicketCard(nft: nft);
            },
          ),
        ),
      ],
    );
  }
}

class _NftTicketCard extends StatelessWidget {
  final NftTicket nft;

  const _NftTicketCard({required this.nft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NftTicketDetailScreen(nft: nft),
          ),
        );
      },
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.primaryContainer.withValues(alpha: 0.6),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.token_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'CIP-68',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              nft.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (nft.eventTitle != null)
              Text(
                nft.eventTitle!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _CryptoBalanceSection extends ConsumerWidget {
  const _CryptoBalanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardanoState = ref.watch(cardanoWalletProvider);
    final hasCardanoWallet = cardanoState.hasWallet;
    final cardanoBalance = cardanoState.balance;
    final isCardanoLoading = cardanoState.isLoading;

    final hasLockedAda = cardanoBalance != null && cardanoBalance.lockedLovelace > 0;

    return Column(
      children: [
        _BalanceCard(
          title: 'Available',
          amount: isCardanoLoading
              ? '...'
              : (cardanoBalance?.formattedAvailableAda ?? '0 ADA'),
          subtitle: hasLockedAda
              ? '${cardanoBalance.formattedLockedAda} locked with tickets'
              : 'Cardano Preview',
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

class _SellerBalanceCard extends ConsumerWidget {
  final SellerBalance balance;

  const _SellerBalanceCard({required this.balance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return _BalanceCard(
      title: 'Available',
      amount: CurrencyFormatter.displayAmount(
        balance.availableBalanceCents,
        fromCurrency: balance.currency,
        displayCurrency: currency.code,
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.account_balance_outlined,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No bank accounts linked',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'Link a bank to fund your wallet via ACH',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

class _WalletActions extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
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
                ? 'Withdraw ${CurrencyFormatter.displayAmount(balance.availableBalanceCents, fromCurrency: balance.currency, displayCurrency: currency.code)}'
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

// ============================================================
// CURRENCY SELECTOR (AppBar dropdown)
// ============================================================

class _CurrencySelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currencyProvider);
    final theme = Theme.of(context);

    return PopupMenuButton<AppCurrency>(
      tooltip: 'Change currency',
      offset: const Offset(0, 48),
      onSelected: (currency) {
        ref.read(currencyStateProvider.notifier).setCurrency(currency);
      },
      itemBuilder: (context) => AppCurrency.values.map((c) {
        final isSelected = c == current;
        return PopupMenuItem<AppCurrency>(
          value: c,
          child: Row(
            children: [
              Text(
                c.displayCode,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current.symbol,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                current.displayCode,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
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
