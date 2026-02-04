import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Screen for vendor to broadcast ticket via NFC for customer to receive.
///
/// Shows a "broadcasting" animation while waiting for customer to tap
/// their device to receive the ticket.
class NfcTicketTransferScreen extends StatefulWidget {
  final String ticketId;
  final String ticketNumber;
  final String transferToken;
  final DateTime transferTokenExpiresAt;
  final String eventTitle;
  final int amountCents;

  const NfcTicketTransferScreen({
    super.key,
    required this.ticketId,
    required this.ticketNumber,
    required this.transferToken,
    required this.transferTokenExpiresAt,
    required this.eventTitle,
    required this.amountCents,
  });

  @override
  State<NfcTicketTransferScreen> createState() => _NfcTicketTransferScreenState();
}

class _NfcTicketTransferScreenState extends State<NfcTicketTransferScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _expiryTimer;
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;
  bool _isTransferred = false;
  bool _isExpired = false;

  String get _formattedPrice {
    if (widget.amountCents == 0) return 'Free';
    final dollars = widget.amountCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  void initState() {
    super.initState();

    // Setup pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Calculate time remaining
    _updateTimeRemaining();

    // Set up countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeRemaining();
    });

    // Set up expiry timer
    final expiresIn = widget.transferTokenExpiresAt.difference(DateTime.now());
    if (expiresIn.isNegative) {
      _isExpired = true;
    } else {
      _expiryTimer = Timer(expiresIn, _onExpired);
    }

    // TODO: In production, implement actual NFC broadcasting
    // For now, this is a placeholder UI
  }

  void _updateTimeRemaining() {
    final remaining = widget.transferTokenExpiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      _onExpired();
    } else {
      setState(() {
        _timeRemaining = remaining;
      });
    }
  }

  void _onExpired() {
    if (!mounted) return;
    setState(() {
      _isExpired = true;
    });
    _countdownTimer?.cancel();
    _pulseController.stop();
    HapticFeedback.heavyImpact();
  }

  void _onTransferred() {
    if (!mounted) return;
    setState(() {
      _isTransferred = true;
    });
    _countdownTimer?.cancel();
    _expiryTimer?.cancel();
    _pulseController.stop();
    HapticFeedback.mediumImpact();

    // Auto-close after showing success
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _expiryTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Ticket'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Ticket info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ticket #',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            widget.ticketNumber,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Event',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.eventTitle,
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Price',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            _formattedPrice,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // NFC broadcasting animation
              if (_isTransferred)
                _buildSuccessState(theme, colorScheme)
              else if (_isExpired)
                _buildExpiredState(theme, colorScheme)
              else
                _buildBroadcastingState(theme, colorScheme),

              const Spacer(),

              // Time remaining (only show when broadcasting)
              if (!_isTransferred && !_isExpired) ...[
                Text(
                  'Time remaining',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(_timeRemaining),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _timeRemaining.inSeconds < 30
                        ? Colors.orange
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Action buttons
              if (_isExpired)
                Column(
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The ticket was created but transfer timed out.\nYou can try in-person or email delivery instead.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              else if (!_isTransferred)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Cancel Transfer'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBroadcastingState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primaryContainer,
            ),
            child: Icon(
              Icons.nfc,
              size: 80,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Broadcasting...',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask the customer to tap their phone\nto receive the ticket',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),

        // For testing - simulate transfer button
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: _onTransferred,
          icon: const Icon(Icons.check),
          label: const Text('Simulate Transfer (Testing)'),
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withValues(alpha: 0.2),
          ),
          child: const Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Transfer Complete!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The ticket has been transferred\nto the customer\'s device',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildExpiredState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.orange.withValues(alpha: 0.2),
          ),
          child: const Icon(
            Icons.timer_off,
            size: 80,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Transfer Expired',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The transfer window has closed.\nThe ticket was created but not transferred.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
