import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/cardano_wallet_provider.dart';

/// Screen for sending ADA to another Cardano address.
class CardanoSendScreen extends ConsumerStatefulWidget {
  const CardanoSendScreen({super.key});

  @override
  ConsumerState<CardanoSendScreen> createState() => _CardanoSendScreenState();
}

class _CardanoSendScreenState extends ConsumerState<CardanoSendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _txResult;

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (!_formKey.currentState!.validate()) return;

    final address = _addressController.text.trim();
    final adaAmount = double.tryParse(_amountController.text.trim()) ?? 0;
    final lovelace = (adaAmount * 1000000).round();

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow(label: 'To', value: _truncateAddress(address)),
            const SizedBox(height: 8),
            _ConfirmRow(label: 'Amount', value: '${adaAmount.toStringAsFixed(2)} ADA'),
            const SizedBox(height: 8),
            _ConfirmRow(label: 'Est. Fee', value: '~0.18 ADA'),
            const Divider(height: 24),
            _ConfirmRow(
              label: 'Total',
              value: '~${(adaAmount + 0.18).toStringAsFixed(2)} ADA',
              isBold: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final txHash = await ref
        .read(cardanoWalletProvider.notifier)
        .sendAda(address, lovelace);

    if (!mounted) return;

    if (txHash != null) {
      setState(() => _txResult = txHash);
    }
  }

  Future<void> _scanQR() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QRScanPage()),
    );
    if (result != null && mounted) {
      _addressController.text = result;
    }
  }

  String _truncateAddress(String addr) {
    if (addr.length <= 24) return addr;
    return '${addr.substring(0, 16)}...${addr.substring(addr.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(cardanoWalletProvider);
    final balance = state.balance;

    if (_txResult != null) {
      return _buildSuccess(context, _txResult!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send ADA'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Available balance
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      balance?.formattedAvailableAda ?? '0 ADA',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // To address
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Recipient Address',
                  hintText: 'addr_test1...',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            _addressController.text = data!.text!.trim();
                          }
                        },
                        icon: const Icon(Icons.paste, size: 20),
                        tooltip: 'Paste',
                      ),
                      IconButton(
                        onPressed: _scanQR,
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        tooltip: 'Scan QR',
                      ),
                    ],
                  ),
                ),
                validator: (v) {
                  final addr = v?.trim() ?? '';
                  if (addr.isEmpty) return 'Address is required';
                  if (!addr.startsWith('addr_test1') &&
                      !addr.startsWith('addr1')) {
                    return 'Invalid Cardano address';
                  }
                  if (addr.length < 50) return 'Address is too short';
                  return null;
                },
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // Amount
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount (ADA)',
                  hintText: '0.00',
                  border: const OutlineInputBorder(),
                  suffixText: 'ADA',
                  suffixIcon: TextButton(
                    onPressed: () {
                      if (balance != null && balance.availableAda > 0.2) {
                        _amountController.text =
                            (balance.availableAda - 0.2).toStringAsFixed(2);
                      }
                    },
                    child: const Text('MAX'),
                  ),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) {
                  final amount = double.tryParse(v?.trim() ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter a valid amount';
                  }
                  if (amount < 1.0) {
                    return 'Minimum 1 ADA';
                  }
                  final maxSendable = (balance?.availableAda ?? 0) - 0.2;
                  if (amount > maxSendable) {
                    return 'Insufficient balance (need ~0.2 ADA for fee)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Fee estimate
              Text(
                'Estimated network fee: ~0.17-0.20 ADA',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Error message
              if (state.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    state.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Send button
              FilledButton(
                onPressed: state.isSending ? null : _handleSend,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: state.isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send ADA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, String txHash) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Sent'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Transaction Submitted!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your transaction has been submitted to the Cardano network.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Tx hash
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${txHash.substring(0, 16)}...${txHash.substring(txHash.length - 16)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: txHash));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Transaction hash copied'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                launchUrl(
                  Uri.parse(
                    'https://preview.cardanoscan.io/transaction/$txHash',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('View on CardanoScan'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _ConfirmRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: isBold ? FontWeight.w600 : null,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Simple QR scanner page.
class _QRScanPage extends StatefulWidget {
  const _QRScanPage();

  @override
  State<_QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<_QRScanPage> {
  final _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_scanned) return;
          final barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final value = barcode.rawValue;
            if (value != null &&
                (value.startsWith('addr_test1') ||
                    value.startsWith('addr1'))) {
              _scanned = true;
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
