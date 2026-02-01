import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/errors.dart';
import '../../../core/providers/seller_balance_provider.dart';
import '../data/resale_repository.dart';

/// Provider for resale repository.
final resaleRepositoryProvider = Provider<ResaleRepository>((ref) {
  return ResaleRepository();
});

/// Provider for seller onboarding status (legacy - checks full onboarding).
final sellerOnboardingStatusProvider = FutureProvider<bool>((ref) async {
  final repository = ref.watch(resaleRepositoryProvider);
  return repository.isSellerOnboarded();
});

/// Provider for checking if user has any seller account (new flow).
final hasSellerAccountProvider2 = FutureProvider<bool>((ref) async {
  final repository = ref.watch(resaleRepositoryProvider);
  return repository.hasSellerAccount();
});

/// Screen for Stripe Connect seller onboarding.
///
/// NEW FLOW (Wallet-based):
/// 1. Creates a minimal Stripe Express account (just needs email)
/// 2. User can list tickets immediately
/// 3. Funds from sales go to their Stripe balance ("wallet")
/// 4. When they want to withdraw, they add bank details
///
/// OLD FLOW (Legacy):
/// 1. User must complete full Stripe Connect onboarding first
/// 2. Add bank details upfront
/// 3. Only then can list tickets
///
/// This screen now uses the NEW flow by default.
class SellerOnboardingScreen extends ConsumerStatefulWidget {
  const SellerOnboardingScreen({super.key});

  @override
  ConsumerState<SellerOnboardingScreen> createState() =>
      _SellerOnboardingScreenState();
}

class _SellerOnboardingScreenState
    extends ConsumerState<SellerOnboardingScreen> {
  bool _isLoading = false;
  String? _error;
  bool _accountCreated = false;

  @override
  void initState() {
    super.initState();
    _checkExistingAccount();
  }

  Future<void> _checkExistingAccount() async {
    // Check if user already has a seller account
    final notifier = ref.read(sellerBalanceProvider.notifier);
    await notifier.loadBalance();

    if (mounted) {
      final state = ref.read(sellerBalanceProvider);
      if (state.hasAccount) {
        setState(() => _accountCreated = true);
      }
    }
  }

  Future<void> _createSellerAccount() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Create minimal seller account (no bank details required)
      final notifier = ref.read(sellerBalanceProvider.notifier);
      final success = await notifier.ensureSellerAccount();

      if (success && mounted) {
        setState(() => _accountCreated = true);
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to create seller account',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: 'SellerOnboarding',
      );
      setState(() {
        _error = appError.userMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startBankSetup() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Initiate withdrawal - this will return an onboarding URL if bank not added
      final notifier = ref.read(sellerBalanceProvider.notifier);
      final result = await notifier.initiateWithdrawal();

      if (result?.needsOnboarding == true && result?.onboardingUrl != null) {
        final uri = Uri.parse(result!.onboardingUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to start bank setup',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: 'SellerOnboarding',
      );
      setState(() {
        _error = appError.userMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final balanceState = ref.watch(sellerBalanceProvider);

    // Check if already fully onboarded (has bank details)
    final isFullyOnboarded = balanceState.balance?.payoutsEnabled ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seller Setup'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _accountCreated
              ? (isFullyOnboarded
                  ? _buildFullyOnboardedView(theme, colorScheme)
                  : _buildAccountCreatedView(theme, colorScheme))
              : _buildCreateAccountView(theme, colorScheme),
        ),
      ),
    );
  }

  /// View shown when user has no seller account yet.
  Widget _buildCreateAccountView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.store,
            color: colorScheme.primary,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Start Selling Tickets',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Set up your seller account to list tickets for resale. '
          'You can start listing immediately \u2013 add bank details later when you want to withdraw.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Benefits list
        _BenefitItem(
          icon: Icons.flash_on,
          title: 'List Instantly',
          description: 'No bank details needed to start selling',
        ),
        const SizedBox(height: 12),
        _BenefitItem(
          icon: Icons.account_balance_wallet,
          title: 'Wallet Balance',
          description: 'Funds from sales go to your wallet',
        ),
        const SizedBox(height: 12),
        _BenefitItem(
          icon: Icons.percent,
          title: '95% Earnings',
          description: 'Only 5% platform fee on each sale',
        ),

        // Error message
        if (_error != null) ...[
          const SizedBox(height: 24),
          _ErrorMessage(error: _error!),
        ],

        const Spacer(),

        // Setup button
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _createSellerAccount,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Text('Create Seller Account'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Takes less than a minute',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// View shown when account is created but bank not added.
  Widget _buildAccountCreatedView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 60,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Seller Account Ready!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'You can now list tickets for resale. When your tickets sell, '
          'earnings will appear in your wallet.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Wallet info
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Wallet',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View your balance and withdraw earnings from the Wallet tab.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Optional bank setup
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Bank (Optional)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add bank details now, or later when you\'re ready to withdraw.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 24),
          _ErrorMessage(error: _error!),
        ],

        const Spacer(),

        // Main action - start listing
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Start Listing Tickets'),
          ),
        ),

        const SizedBox(height: 12),

        // Secondary action - add bank now
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isLoading ? null : _startBankSetup,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : const Text('Add Bank Details Now'),
          ),
        ),
      ],
    );
  }

  /// View shown when fully onboarded (has bank details).
  Widget _buildFullyOnboardedView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.verified,
            color: Colors.green,
            size: 60,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'All Set!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Your seller account is fully set up. You can list tickets and '
          'withdraw earnings to your connected bank account.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance,
                  color: Colors.green,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bank Connected',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Withdrawals will be sent to your bank account.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle, color: Colors.green, size: 24),
            ],
          ),
        ),

        const Spacer(),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Start Listing Tickets'),
          ),
        ),
      ],
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
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

class _ErrorMessage extends StatelessWidget {
  final String error;

  const _ErrorMessage({required this.error});

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
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
