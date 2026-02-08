import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../payments/models/payment.dart';

/// Shows the transaction detail bottom sheet for a given [payment].
void showTransactionDetailSheet(BuildContext context, Payment payment) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => TransactionDetailSheet(payment: payment),
  );
}

/// Bottom sheet displaying detailed information about a payment transaction.
class TransactionDetailSheet extends StatelessWidget {
  final Payment payment;

  const TransactionDetailSheet({super.key, required this.payment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _getStatusColor(payment.status, colorScheme)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _getTypeIcon(payment.type),
                        color: _getStatusColor(payment.status, colorScheme),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      payment.formattedAmount,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(status: payment.status),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Event name (from metadata)
              if (payment.metadata?['event_title'] != null) ...[
                _DetailRow(
                  label: 'Event',
                  value: payment.metadata!['event_title'] as String,
                ),
                const SizedBox(height: 12),
              ],

              // Payment type
              _DetailRow(
                label: 'Type',
                value: _getTypeLabel(payment.type),
              ),
              const SizedBox(height: 12),

              // Date & time
              _DetailRow(
                label: 'Date',
                value: _formatDateTime(payment.createdAt),
              ),
              const SizedBox(height: 12),

              // Amount breakdown
              const Divider(height: 24),
              _DetailRow(
                label: 'Subtotal',
                value: payment.formattedSellerAmount,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Platform fee',
                value: payment.formattedPlatformFee,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Total',
                value: payment.formattedAmount,
                isBold: true,
              ),
              const Divider(height: 24),

              // Reference ID
              if (payment.stripePaymentIntentId != null) ...[
                _ReferenceRow(
                  paymentIntentId: payment.stripePaymentIntentId!,
                ),
                const SizedBox(height: 20),
              ],

              // View Receipt button
              if (payment.status == PaymentStatus.completed &&
                  payment.receiptUrl != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openReceipt(context),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('View Receipt'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReceipt(BuildContext context) async {
    final uri = Uri.parse(payment.receiptUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open receipt'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    }
  }

  IconData _getTypeIcon(PaymentType type) {
    switch (type) {
      case PaymentType.primaryPurchase:
        return Icons.confirmation_number;
      case PaymentType.resalePurchase:
        return Icons.swap_horiz;
      case PaymentType.vendorPos:
        return Icons.storefront;
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

  String _formatDateTime(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day}, ${date.year} at $hour:$minute $period';
  }
}

/// A row displaying a label-value pair.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
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
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
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

/// Row displaying a truncated reference ID with tap-to-copy.
class _ReferenceRow extends StatelessWidget {
  final String paymentIntentId;

  const _ReferenceRow({required this.paymentIntentId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show truncated ID like "pi_3Abc...Xyz"
    final truncated = paymentIntentId.length > 16
        ? '${paymentIntentId.substring(0, 10)}...${paymentIntentId.substring(paymentIntentId.length - 4)}'
        : paymentIntentId;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Reference',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: paymentIntentId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Reference ID copied'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  truncated,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.copy,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Status badge with colored background.
class _StatusBadge extends StatelessWidget {
  final PaymentStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = _getStatusInfo(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
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
