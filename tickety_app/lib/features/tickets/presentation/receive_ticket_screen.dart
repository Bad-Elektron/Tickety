import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Screen for customers to receive a ticket via NFC transfer.
///
/// Shows a "Ready to receive" animation while waiting for the vendor
/// to broadcast the ticket. Once received, shows success with ticket details.
class ReceiveTicketScreen extends StatefulWidget {
  const ReceiveTicketScreen({super.key});

  @override
  State<ReceiveTicketScreen> createState() => _ReceiveTicketScreenState();
}

class _ReceiveTicketScreenState extends State<ReceiveTicketScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isReceiving = false;
  bool _isSuccess = false;
  String? _error;
  Map<String, dynamic>? _receivedTicket;

  @override
  void initState() {
    super.initState();

    // Setup pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // TODO: In production, implement actual NFC reading
    // For now, this is a placeholder UI that can be triggered manually
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Called when a transfer token is received via NFC.
  Future<void> _claimTicket(String transferToken) async {
    if (_isReceiving) return;

    setState(() {
      _isReceiving = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'claim-ticket-transfer',
        body: {'transfer_token': transferToken},
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Failed to claim ticket';
        throw Exception(error);
      }

      final data = response.data as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _isReceiving = false;
          _isSuccess = true;
          _receivedTicket = data['ticket'] as Map<String, dynamic>;
        });
        _pulseController.stop();
        HapticFeedback.mediumImpact();

        // Auto-close after showing success
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReceiving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  /// Simulates receiving a ticket for testing.
  void _showTestDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test: Enter Transfer Token'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Paste transfer token here',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (controller.text.isNotEmpty) {
                _claimTicket(controller.text.trim());
              }
            },
            child: const Text('Claim'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Ticket'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Main content area
              if (_isSuccess && _receivedTicket != null)
                _buildSuccessState(theme, colorScheme)
              else if (_error != null)
                _buildErrorState(theme, colorScheme)
              else
                _buildReadyState(theme, colorScheme),

              const Spacer(),

              // Action buttons
              if (_isSuccess)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('View My Tickets'),
                )
              else if (_error != null)
                Column(
                  children: [
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                        });
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Try Again'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    if (_isReceiving)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: CircularProgressIndicator(),
                      ),
                    OutlinedButton(
                      onPressed: _isReceiving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(height: 12),
                    // Test button for development
                    TextButton.icon(
                      onPressed: _isReceiving ? null : _showTestDialog,
                      icon: const Icon(Icons.bug_report, size: 18),
                      label: const Text('Test: Manual Token Entry'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadyState(ThemeData theme, ColorScheme colorScheme) {
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
          'Ready to Receive',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Hold your phone near the vendor\'s device\nto receive your ticket',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Make sure NFC is enabled on your device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme, ColorScheme colorScheme) {
    final ticket = _receivedTicket!;
    final eventTitle = ticket['event_title'] as String? ?? 'Unknown Event';
    final ticketNumber = ticket['ticket_number'] as String? ?? '';
    final eventVenue = ticket['event_venue'] as String?;
    final eventCity = ticket['event_city'] as String?;

    String? locationText;
    if (eventVenue != null && eventCity != null) {
      locationText = '$eventVenue, $eventCity';
    } else if (eventVenue != null) {
      locationText = eventVenue;
    } else if (eventCity != null) {
      locationText = eventCity;
    }

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
          'Ticket Received!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 24),
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
                      'Event',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        eventTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.end,
                        maxLines: 2,
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
                      'Ticket #',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      ticketNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                if (locationText != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Location',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          locationText,
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your ticket is now in My Tickets',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.errorContainer,
          ),
          child: Icon(
            Icons.error_outline,
            size: 80,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Transfer Failed',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An unknown error occurred',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
