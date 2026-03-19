import 'package:flutter/material.dart';

import '../../../core/localization/localization.dart';
import '../../../core/models/verification_result.dart';

/// Animated card showing 3-tier verification progress.
///
/// Each tier animates from pending → verifying → result with appropriate
/// colors and icons. The bottom bar shows the overall admission decision.
class VerificationCard extends StatelessWidget {
  const VerificationCard({
    super.key,
    required this.result,
    this.onDismiss,
    this.onCheckIn,
    this.isCheckingIn = false,
  });

  final VerificationResult result;
  final VoidCallback? onDismiss;
  final VoidCallback? onCheckIn;
  final bool isCheckingIn;

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
            color: (result.isAdmittable ? Colors.green : Colors.red)
                .withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Text(
              L.tr('VERIFYING TICKET'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Tier rows
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                _TierRow(
                  label: L.tr('Offline Cache'),
                  tier: result.getTier(VerificationTier.offline),
                ),
                const SizedBox(height: 12),
                _TierRow(
                  label: L.tr('Blockchain'),
                  tier: result.getTier(VerificationTier.blockchain),
                ),
                const SizedBox(height: 12),
                _TierRow(
                  label: L.tr('Database'),
                  tier: result.getTier(VerificationTier.database),
                ),
              ],
            ),
          ),

          // Ticket info (if found)
          if (result.ticket != null) ...[
            Divider(
              height: 1,
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  _TicketInfoRow(
                    icon: Icons.person_outline,
                    label: result.ticket!.ownerName ?? L.tr('Guest'),
                  ),
                  if (result.ticket!.ownerEmail != null) ...[
                    const SizedBox(height: 6),
                    _TicketInfoRow(
                      icon: Icons.email_outlined,
                      label: result.ticket!.ownerEmail!,
                    ),
                  ],
                  const SizedBox(height: 6),
                  _TicketInfoRow(
                    icon: Icons.confirmation_number_outlined,
                    label: result.ticket!.ticketNumber,
                    mono: true,
                  ),
                  const SizedBox(height: 6),
                  _TicketInfoRow(
                    icon: result.ticket!.isRedeemable
                        ? Icons.redeem_outlined
                        : Icons.event_seat_outlined,
                    label: result.ticket!.isRedeemable
                        ? L.tr('Redeemable')
                        : L.tr('Entry'),
                  ),
                ],
              ),
            ),
          ],

          // Overall admission bar
          Divider(
            height: 1,
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
          _AdmissionBar(
            isAdmittable: result.isAdmittable,
            isVerifying: _isAnyTierVerifying,
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isCheckingIn ? null : onDismiss,
                    child: Text(L.tr('Dismiss')),
                  ),
                ),
                if (result.isAdmittable) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: isCheckingIn ? null : onCheckIn,
                      icon: isCheckingIn
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check),
                      label:
                          Text(isCheckingIn ? L.tr('Checking in...') : L.tr('Check In')),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
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

  bool get _isAnyTierVerifying {
    return result.tiers.values.any((t) => t.status == TierStatus.verifying);
  }
}

/// Single tier row with animated status indicator.
class _TierRow extends StatelessWidget {
  const _TierRow({required this.label, required this.tier});

  final String label;
  final TierResult tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // Status icon
        SizedBox(
          width: 24,
          height: 24,
          child: _buildIcon(),
        ),
        const SizedBox(width: 12),
        // Label
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (tier.message != null)
                Text(
                  tier.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _statusColor.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ),
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _statusColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIcon() {
    return switch (tier.status) {
      TierStatus.pending => Icon(
          Icons.circle_outlined,
          size: 20,
          color: Colors.grey.shade400,
        ),
      TierStatus.verifying => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.blue.shade400,
          ),
        ),
      TierStatus.verified => const Icon(
          Icons.check_circle,
          size: 20,
          color: Color(0xFF4CAF50),
        ),
      TierStatus.failed => const Icon(
          Icons.cancel,
          size: 20,
          color: Color(0xFFF44336),
        ),
      TierStatus.skipped => Icon(
          Icons.remove_circle_outline,
          size: 20,
          color: Colors.amber.shade700,
        ),
    };
  }

  Color get _statusColor => switch (tier.status) {
        TierStatus.pending => Colors.grey,
        TierStatus.verifying => Colors.blue,
        TierStatus.verified => const Color(0xFF4CAF50),
        TierStatus.failed => const Color(0xFFF44336),
        TierStatus.skipped => Colors.amber.shade700,
      };

  String get _statusLabel => switch (tier.status) {
        TierStatus.pending => L.tr('Waiting'),
        TierStatus.verifying => L.tr('Checking...'),
        TierStatus.verified => L.tr('Verified'),
        TierStatus.failed => L.tr('Failed'),
        TierStatus.skipped => L.tr('Skipped'),
      };
}

/// Bottom bar showing overall admission decision.
class _AdmissionBar extends StatelessWidget {
  const _AdmissionBar({
    required this.isAdmittable,
    required this.isVerifying,
  });

  final bool isAdmittable;
  final bool isVerifying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = isVerifying
        ? Colors.blue
        : isAdmittable
            ? const Color(0xFF4CAF50)
            : const Color(0xFFF44336);
    final label = isVerifying
        ? L.tr('VERIFYING...')
        : isAdmittable
            ? L.tr('ADMIT')
            : L.tr('DENY');
    final icon = isVerifying
        ? Icons.hourglass_top
        : isAdmittable
            ? Icons.check_circle
            : Icons.cancel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple info row for ticket details.
class _TicketInfoRow extends StatelessWidget {
  const _TicketInfoRow({
    required this.icon,
    required this.label,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: mono ? 'monospace' : null,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
