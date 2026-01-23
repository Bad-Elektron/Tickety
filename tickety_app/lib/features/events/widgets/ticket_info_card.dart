import 'package:flutter/material.dart';

import '../../tickets/models/ticket_model.dart';

/// Displays scanned ticket information with validation status.
///
/// Shows a colored status bar (green for valid, red for issues),
/// ticket holder details, and ticket type information.
class TicketInfoCard extends StatelessWidget {
  const TicketInfoCard({
    super.key,
    required this.ticket,
    this.onDismiss,
    this.onRedeem,
  });

  final TicketModel ticket;
  final VoidCallback? onDismiss;
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = ticket.validationStatus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: status.color.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status.icon,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  status.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Ticket details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Holder info
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Ticket Holder',
                  value: ticket.holderName,
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: ticket.holderEmail,
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Ticket Type',
                  value: ticket.ticketType,
                ),
                if (ticket.seatInfo != null) ...[
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.event_seat_outlined,
                    label: 'Seat / Table',
                    value: ticket.seatInfo!,
                  ),
                ],
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.tag,
                  label: 'Ticket ID',
                  value: ticket.id.toUpperCase(),
                  mono: true,
                ),

                if (ticket.isRedeemed && ticket.redeemedAt != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Redeemed ${_formatDateTime(ticket.redeemedAt!)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
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

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                ),
                if (status == TicketValidationStatus.valid) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onRedeem,
                      icon: const Icon(Icons.check),
                      label: const Text('Redeem Ticket'),
                      style: FilledButton.styleFrom(
                        backgroundColor: status.color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
