import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../data/wallet_repository.dart';

/// Screen for linking a bank account via Stripe Financial Connections.
class LinkBankScreen extends ConsumerStatefulWidget {
  const LinkBankScreen({super.key});

  @override
  ConsumerState<LinkBankScreen> createState() => _LinkBankScreenState();
}

class _LinkBankScreenState extends ConsumerState<LinkBankScreen> {
  bool _isLinking = false;
  String? _error;

  Future<void> _handleLinkBank() async {
    setState(() {
      _isLinking = true;
      _error = null;
    });

    try {
      final repository = WalletRepository();

      // 1. Get SetupIntent from edge function
      // ignore: avoid_print
      print('[LinkBank] Step 1: Calling linkBankAccount...');
      final setupData = await repository.linkBankAccount();
      // ignore: avoid_print
      print('[LinkBank] Step 1 OK: keys=${setupData.keys.toList()}, '
          'setup_intent_id=${setupData['setup_intent_id']}');
      final clientSecret = setupData['client_secret'] as String;
      final setupIntentId = setupData['setup_intent_id'] as String;

      // 2. Collect bank account via Financial Connections
      // ignore: avoid_print
      print('[LinkBank] Step 2: collectBankAccount...');
      String? paymentMethodId;
      try {
        final result = await Stripe.instance.collectBankAccount(
          isPaymentIntent: false,
          clientSecret: clientSecret,
          params: CollectBankAccountParams(
            paymentMethodData: CollectBankAccountPaymentMethodData(
              billingDetails: BillingDetails(
                name: setupData['customer_name'] as String? ?? 'Account Holder',
                email: setupData['customer_email'] as String?,
              ),
            ),
          ),
        );
        paymentMethodId = result.paymentMethodId;
        // ignore: avoid_print
        print('[LinkBank] Step 2 OK: paymentMethodId=$paymentMethodId');
      } on TypeError catch (te) {
        // Known flutter_stripe bug: when collectBankAccount with
        // isPaymentIntent=false completes, the SDK tries to parse
        // the result as a StripeException and crashes on
        // `json['error'] as Map<String, dynamic>` when error is null.
        // This means the flow actually succeeded — proceed with
        // server-side payment method resolution via setup_intent_id.
        // ignore: avoid_print
        print('[LinkBank] Step 2: TypeError workaround (SDK bug): $te');
      }

      // 3. Save bank account via edge function
      // Server resolves payment method from SetupIntent if paymentMethodId is null
      // ignore: avoid_print
      print('[LinkBank] Step 3: saveBankAccount(pmId=$paymentMethodId, '
          'siId=$setupIntentId)...');
      await repository.saveBankAccount(
        paymentMethodId: paymentMethodId,
        setupIntentId: setupIntentId,
      );
      // ignore: avoid_print
      print('[LinkBank] Step 3 OK');

      // 4. Bank linked successfully
      // ignore: avoid_print
      print('[LinkBank] Step 4: Done');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bank account linked successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      // ignore: avoid_print
      print('[LinkBank] FAILED at: ${e.runtimeType}: $e');
      // ignore: avoid_print
      print('[LinkBank] Stack: $s');

      if (mounted) {
        setState(() {
          _isLinking = false;
          _error = '${e.runtimeType}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Bank Account'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero icon
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.account_balance,
                        size: 48,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Connect Your Bank',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Link your bank account to pay for tickets directly via ACH. Lower fees than card payments.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Benefits
                    _BenefitItem(
                      icon: Icons.savings_outlined,
                      title: 'Lower Fees',
                      description: 'ACH costs only 0.8% (max \$5) vs 2.9% + \$0.30 for cards.',
                    ),
                    const SizedBox(height: 16),
                    _BenefitItem(
                      icon: Icons.bolt_outlined,
                      title: 'Instant Tickets',
                      description: 'Get your tickets immediately. Bank payment settles in 4-5 days.',
                    ),
                    const SizedBox(height: 16),
                    _BenefitItem(
                      icon: Icons.security_outlined,
                      title: 'Bank-Level Security',
                      description: 'Powered by Stripe Financial Connections. Your credentials are never stored.',
                    ),

                    // Error message
                    if (_error != null) ...[
                      const SizedBox(height: 24),
                      Container(
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
                                _error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLinking ? null : _handleLinkBank,
                  icon: _isLinking
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.account_balance),
                  label: Text(
                    _isLinking ? 'Connecting...' : 'Connect Bank Account',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _isLinking ? null : colorScheme.onPrimary,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _BenefitItem({
    required this.icon,
    required this.title,
    required this.description,
  });

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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 22),
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
