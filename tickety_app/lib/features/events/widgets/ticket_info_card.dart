import 'package:flutter/material.dart';

import '../../staff/models/ticket.dart';

/// Validation status for scanned tickets at check-in.
enum CheckInValidationStatus {
  valid(
    label: 'Valid Ticket',
    icon: Icons.check_circle,
    color: Color(0xFF4CAF50),
  ),
  alreadyUsed(
    label: 'Already Checked In',
    icon: Icons.cancel,
    color: Color(0xFFF44336),
  ),
  cancelled(
    label: 'Ticket Cancelled',
    icon: Icons.block,
    color: Color(0xFFF44336),
  ),
  refunded(
    label: 'Ticket Refunded',
    icon: Icons.undo,
    color: Color(0xFFFF9800),
  ),
  wrongEvent(
    label: 'Wrong Event',
    icon: Icons.event_note,
    color: Color(0xFFFF9800),
  ),
  notFound(
    label: 'Ticket Not Found',
    icon: Icons.error,
    color: Color(0xFFF44336),
  );

  const CheckInValidationStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Creates validation status from a Ticket.
  static CheckInValidationStatus fromTicket(Ticket ticket) {
    return switch (ticket.status) {
      TicketStatus.valid => CheckInValidationStatus.valid,
      TicketStatus.used => CheckInValidationStatus.alreadyUsed,
      TicketStatus.cancelled => CheckInValidationStatus.cancelled,
      TicketStatus.refunded => CheckInValidationStatus.refunded,
    };
  }
}

/// Displays scanned ticket information with validation status.
///
/// Shows a colored status bar (green for valid, red for issues),
/// ticket holder details, and action buttons for check-in.
class TicketInfoCard extends StatelessWidget {
  const TicketInfoCard({
    super.key,
    required this.ticket,
    this.validationStatus,
    this.onDismiss,
    this.onCheckIn,
    this.isLoading = false,
  });

  final Ticket ticket;

  /// Override validation status (useful for wrong event, not found, etc.).
  final CheckInValidationStatus? validationStatus;

  final VoidCallback? onDismiss;
  final VoidCallback? onCheckIn;
  final bool isLoading;

  CheckInValidationStatus get _status =>
      validationStatus ?? CheckInValidationStatus.fromTicket(ticket);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _status.color.withValues(alpha: 0.3),
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
              color: _status.color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _status.icon,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  _status.label,
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
                  value: ticket.ownerName ?? 'Guest',
                ),
                const SizedBox(height: 16),

                if (ticket.ownerEmail != null) ...[
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: ticket.ownerEmail!,
                  ),
                  const SizedBox(height: 16),
                ],

                _InfoRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Ticket Number',
                  value: ticket.ticketNumber,
                  mono: true,
                ),
                const SizedBox(height: 16),

                _InfoRow(
                  icon: Icons.payments_outlined,
                  label: 'Price Paid',
                  value: ticket.formattedPrice,
                ),

                // Check-in timestamp if already used
                if (ticket.isUsed && ticket.checkedInAt != null) ...[
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
                            'Checked in ${_formatDateTime(ticket.checkedInAt!)}',
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
                    onPressed: isLoading ? null : onDismiss,
                    child: const Text('Dismiss'),
                  ),
                ),
                if (_status == CheckInValidationStatus.valid) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: isLoading ? null : onCheckIn,
                      icon: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(isLoading ? 'Checking in...' : 'Check In'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _status.color,
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

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
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
