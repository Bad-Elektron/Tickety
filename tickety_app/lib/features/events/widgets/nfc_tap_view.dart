import 'package:flutter/material.dart';

/// NFC receiver for tap-to-check-in functionality.
///
/// Note: NFC is temporarily disabled while resolving Android build issues.
/// Use QR scanning instead.
class NfcTapView extends StatelessWidget {
  const NfcTapView({
    super.key,
    required this.onTicketReceived,
    this.onError,
  });

  /// Called when a ticket ID is received via NFC.
  final void Function(String ticketIdOrNumber) onTicketReceived;

  /// Called when an error occurs.
  final void Function(String error)? onError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.nfc_rounded,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'NFC Temporarily Unavailable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'NFC check-in is being updated. Please use QR scanning or manual entry instead.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
