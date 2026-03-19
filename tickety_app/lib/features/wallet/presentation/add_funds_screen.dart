import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/wallet_balance_provider.dart';
import '../../payments/models/payment.dart';
import '../models/linked_bank_account.dart';
import 'link_bank_screen.dart';

/// Screen for adding funds to the Tickety Wallet via ACH bank transfer.
class AddFundsScreen extends ConsumerStatefulWidget {
  const AddFundsScreen({super.key});

  @override
  ConsumerState<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends ConsumerState<AddFundsScreen> {
  final _amountController = TextEditingController();
  int _selectedAmountCents = 0;
  LinkedBankAccount? _selectedBank;
  bool _isCustomAmount = false;

  static const _presetAmounts = [1000, 2500, 5000, 10000]; // $10, $25, $50, $100

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onCustomAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onCustomAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onCustomAmountChanged() {
    if (!_isCustomAmount) return;
    final text = _amountController.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final dollars = double.tryParse(text) ?? 0;
    setState(() {
      _selectedAmountCents = (dollars * 100).round();
    });
  }

  void _selectPresetAmount(int cents) {
    setState(() {
      _selectedAmountCents = cents;
      _isCustomAmount = false;
      _amountController.clear();
    });
  }

  void _selectCustomAmount() {
    setState(() {
      _isCustomAmount = true;
      _selectedAmountCents = 0;
    });
    // Focus the text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  Future<void> _handleAddFunds() async {
    if (_selectedBank == null || _selectedAmountCents <= 0) return;

    if (!ACHFeeCalculator.isValidAmount(_selectedAmountCents)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Amount must be between \$${(ACHFeeCalculator.minTopUpCents / 100).toStringAsFixed(0)} '
            'and \$${(ACHFeeCalculator.maxTopUpCents / 100).toStringAsFixed(0)}',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final notifier = ref.read(walletBalanceProvider.notifier);
    final success = await notifier.topUp(
      amountCents: _selectedAmountCents,
      paymentMethodId: _selectedBank!.stripePaymentMethodId,
    );

    if (success && mounted) {
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    final fees = ACHFeeCalculator.calculate(_selectedAmountCents);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: Text(L.tr('add_funds_topup_processing')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\$${(_selectedAmountCents / 100).toStringAsFixed(2)} is being added to your wallet.',
            ),
            const SizedBox(height: 12),
            Text(
              L.tr('add_funds_ach_settlement_notice'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (fees.achFeeCents > 0) ...[
              const SizedBox(height: 8),
              Text(
                'ACH fee: \$${(fees.achFeeCents / 100).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(true); // Return to wallet
            },
            child: Text(L.tr('got_it')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final walletState = ref.watch(walletBalanceProvider);
    final bankAccounts = walletState.balance?.bankAccounts ?? [];

    // Auto-select first bank if none selected
    if (_selectedBank == null && bankAccounts.isNotEmpty) {
      _selectedBank = bankAccounts.first;
    }

    final isValid = _selectedAmountCents >= ACHFeeCalculator.minTopUpCents &&
        _selectedAmountCents <= ACHFeeCalculator.maxTopUpCents &&
        _selectedBank != null;

    final fees = _selectedAmountCents > 0
        ? ACHFeeCalculator.calculate(_selectedAmountCents)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('add_funds_title')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount section
                    Text(
                      L.tr('add_funds_amount'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Preset amount chips
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ..._presetAmounts.map((cents) => _AmountChip(
                              amount: cents,
                              isSelected: !_isCustomAmount && _selectedAmountCents == cents,
                              onTap: () => _selectPresetAmount(cents),
                            )),
                        _AmountChip(
                          label: L.tr('add_funds_custom'),
                          isSelected: _isCustomAmount,
                          onTap: _selectCustomAmount,
                        ),
                      ],
                    ),

                    // Custom amount input
                    if (_isCustomAmount) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                        decoration: InputDecoration(
                          prefixText: '\$ ',
                          hintText: '0.00',
                          helperText: 'Min \$${(ACHFeeCalculator.minTopUpCents / 100).toStringAsFixed(0)} '
                              '- Max \$${(ACHFeeCalculator.maxTopUpCents / 100).toStringAsFixed(0)}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        autofocus: true,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Bank account section
                    Text(
                      L.tr('add_funds_from_bank'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (bankAccounts.isEmpty)
                      _NoBankCard(
                        onLink: () async {
                          final linked = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(builder: (_) => const LinkBankScreen()),
                          );
                          if (linked == true) {
                            ref.read(walletBalanceProvider.notifier).refresh();
                          }
                        },
                      )
                    else
                      ...bankAccounts.map((bank) => _BankAccountTile(
                            bank: bank,
                            isSelected: _selectedBank?.id == bank.id,
                            onTap: () => setState(() => _selectedBank = bank),
                          )),

                    // Fee breakdown
                    if (fees != null && _selectedAmountCents > 0) ...[
                      const SizedBox(height: 24),
                      Text(
                        L.tr('add_funds_fee_breakdown'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FeeBreakdownCard(fees: fees),
                    ],

                    // Error
                    if (walletState.error != null) ...[
                      const SizedBox(height: 16),
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
                                walletState.error!,
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isValid && !walletState.isTopUpProcessing
                      ? _handleAddFunds
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: walletState.isTopUpProcessing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          fees != null
                              ? L.tr('add_funds_button_with_total', ['\$${(fees.totalChargeCents / 100).toStringAsFixed(2)}'])
                              : L.tr('add_funds_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimary,
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

class _AmountChip extends StatelessWidget {
  final int? amount;
  final String? label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AmountChip({
    this.amount,
    this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayText =
        label ?? '\$${(amount! / 100).toStringAsFixed(0)}';

    return Material(
      color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            displayText,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

class _NoBankCard extends StatelessWidget {
  final VoidCallback onLink;

  const _NoBankCard({required this.onLink});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_outlined,
            size: 40,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            L.tr('add_funds_no_bank'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            L.tr('add_funds_no_bank_desc'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onLink,
            child: Text(L.tr('link_bank_title')),
          ),
        ],
      ),
    );
  }
}

class _BankAccountTile extends StatelessWidget {
  final LinkedBankAccount bank;
  final bool isSelected;
  final VoidCallback onTap;

  const _BankAccountTile({
    required this.bank,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.4)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.2)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.account_balance,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
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
                if (isSelected)
                  Icon(Icons.check_circle, color: colorScheme.primary, size: 22)
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeeBreakdownCard extends StatelessWidget {
  final ACHFeeBreakdown fees;

  const _FeeBreakdownCard({required this.fees});

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
      child: Column(
        children: [
          _FeeRow(
            label: L.tr('add_funds_wallet_credit'),
            amount: '\$${(fees.amountCents / 100).toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _FeeRow(
            label: L.tr('add_funds_ach_fee'),
            amount: '\$${(fees.achFeeCents / 100).toStringAsFixed(2)}',
            isSubtle: true,
          ),
          const SizedBox(height: 12),
          Divider(color: colorScheme.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _FeeRow(
            label: L.tr('add_funds_total_bank_debit'),
            amount: '\$${(fees.totalChargeCents / 100).toStringAsFixed(2)}',
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isSubtle;
  final bool isBold;

  const _FeeRow({
    required this.label,
    required this.amount,
    this.isSubtle = false,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodyMedium?.copyWith(
                  color: isSubtle ? colorScheme.onSurfaceVariant : null,
                ),
        ),
        Text(
          amount,
          style: isBold
              ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodyMedium?.copyWith(
                  color: isSubtle ? colorScheme.onSurfaceVariant : null,
                ),
        ),
      ],
    );
  }
}
