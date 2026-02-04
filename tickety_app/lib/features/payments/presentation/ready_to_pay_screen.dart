import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/services.dart';

/// Payload for broadcasting user ID via NFC for tap-to-pay.
class PaymentNfcPayload {
  final String userId;
  final String? displayName;

  const PaymentNfcPayload({
    required this.userId,
    this.displayName,
  });

  /// Convert to string for NFC transmission.
  String toNfcData() => 'TICKETY_PAY:$userId';

  /// Parse from NFC data string.
  static PaymentNfcPayload? fromNfcData(String data) {
    if (!data.startsWith('TICKETY_PAY:')) return null;
    final userId = data.substring('TICKETY_PAY:'.length);
    if (userId.isEmpty) return null;
    return PaymentNfcPayload(userId: userId);
  }
}

/// Screen where customer broadcasts their ID via NFC to receive payment requests.
class ReadyToPayScreen extends ConsumerStatefulWidget {
  const ReadyToPayScreen({super.key});

  @override
  ConsumerState<ReadyToPayScreen> createState() => _ReadyToPayScreenState();
}

class _ReadyToPayScreenState extends ConsumerState<ReadyToPayScreen>
    with SingleTickerProviderStateMixin {
  final _nfcService = NfcService.instance;

  bool _isNfcAvailable = false;
  bool _isBroadcasting = false;
  bool _isCheckingNfc = true;

  // Realtime subscription for incoming payment requests
  RealtimeChannel? _paymentChannel;
  Map<String, dynamic>? _pendingPayment;
  bool _isProcessingPayment = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkNfcAndStart();
    _subscribeToPaymentRequests();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopBroadcasting();
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkNfcAndStart() async {
    final available = await _nfcService.isHceAvailable();
    if (mounted) {
      setState(() {
        _isNfcAvailable = available;
        _isCheckingNfc = false;
      });

      if (available) {
        await _startBroadcasting();
      }
    }
  }

  Future<void> _startBroadcasting() async {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    final payload = PaymentNfcPayload(
      userId: user.id,
      displayName: user.userMetadata?['full_name'] as String?,
    );

    final success = await _nfcService.startBroadcasting(
      TicketNfcPayload(
        ticketId: payload.toNfcData(), // Reuse the NFC service with our payment data
        eventId: 'payment',
        ticketNumber: user.id,
      ),
    );

    if (mounted) {
      setState(() => _isBroadcasting = success);
      if (success) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  Future<void> _stopBroadcasting() async {
    await _nfcService.stopBroadcasting();
    if (mounted) {
      setState(() => _isBroadcasting = false);
    }
  }

  void _subscribeToPaymentRequests() {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    final client = SupabaseService.instance.client;

    _paymentChannel = client
        .channel('pending_payments:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pending_payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('Received payment request: ${payload.newRecord}');
            if (mounted) {
              setState(() {
                _pendingPayment = payload.newRecord;
              });
              HapticFeedback.heavyImpact();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pending_payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('Payment updated: ${payload.newRecord}');
            final status = payload.newRecord['status'] as String?;
            if (status == 'completed' || status == 'failed' || status == 'cancelled' || status == 'expired') {
              if (mounted) {
                setState(() => _pendingPayment = null);
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _processPayment() async {
    if (_pendingPayment == null || _isProcessingPayment) return;

    setState(() => _isProcessingPayment = true);

    try {
      final paymentId = _pendingPayment!['id'] as String;
      final amountCents = _pendingPayment!['amount_cents'] as int;
      final eventId = _pendingPayment!['event_id'] as String;
      final ticketTypeId = _pendingPayment!['ticket_type_id'] as String?;

      // Update status to processing
      await SupabaseService.instance.client
          .from('pending_payments')
          .update({'status': 'processing'})
          .eq('id', paymentId);

      // Create payment intent via edge function
      final response = await SupabaseService.instance.client.functions.invoke(
        'create-tap-to-pay-intent',
        body: {
          'pending_payment_id': paymentId,
          'event_id': eventId,
          'ticket_type_id': ticketTypeId,
          'amount_cents': amountCents,
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to create payment intent');
      }

      final data = response.data as Map<String, dynamic>;
      final clientSecret = data['client_secret'] as String;

      // Present Stripe payment sheet
      // This will be handled by the payment provider
      // For now, we'll use a simplified flow

      if (mounted) {
        final confirmed = await _showPaymentConfirmation(amountCents);
        if (confirmed) {
          // TODO: Integrate with actual Stripe payment sheet
          // For now, simulate success
          await SupabaseService.instance.client
              .from('pending_payments')
              .update({
                'status': 'completed',
                'completed_at': DateTime.now().toUtc().toIso8601String(),
                'stripe_payment_intent_id': clientSecret,
              })
              .eq('id', paymentId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Payment successful! Ticket added to your wallet.'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            Navigator.of(context).pop(true);
          }
        } else {
          // User cancelled
          await SupabaseService.instance.client
              .from('pending_payments')
              .update({'status': 'cancelled'})
              .eq('id', paymentId);
        }
      }
    } catch (e) {
      debugPrint('Payment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _pendingPayment = null;
        });
      }
    }
  }

  Future<bool> _showPaymentConfirmation(int amountCents) async {
    final dollars = amountCents / 100;
    final formattedAmount = '\$${dollars.toStringAsFixed(2)}';

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.payment, size: 48, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              formattedAmount,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _pendingPayment?['ticket_type_name'] ?? 'Ticket',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pay'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _cancelPayment() async {
    if (_pendingPayment == null) return;

    try {
      await SupabaseService.instance.client
          .from('pending_payments')
          .update({'status': 'cancelled'})
          .eq('id', _pendingPayment!['id']);
    } catch (e) {
      debugPrint('Error cancelling payment: $e');
    }

    setState(() => _pendingPayment = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ready to Pay'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Main content
              if (_isCheckingNfc)
                const CircularProgressIndicator()
              else if (!_isNfcAvailable)
                _buildNfcUnavailable(theme, colorScheme)
              else if (_pendingPayment != null)
                _buildPaymentRequest(theme, colorScheme)
              else
                _buildReadyState(theme, colorScheme),

              const Spacer(),

              // Instructions
              if (_isNfcAvailable && _pendingPayment == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Hold your phone near the vendor\'s device to receive a payment request.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNfcUnavailable(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.nfc_outlined,
            size: 56,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'NFC Not Available',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your device doesn\'t support NFC tap-to-pay.\nPlease use QR code or manual payment.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildReadyState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated NFC icon
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 30 * _pulseAnimation.value,
                      spreadRadius: 10 * _pulseAnimation.value,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.contactless,
                  size: 72,
                  color: colorScheme.primary,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        Text(
          _isBroadcasting ? 'Ready to Pay' : 'Starting...',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _isBroadcasting ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isBroadcasting ? 'NFC Active' : 'Initializing NFC...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _isBroadcasting ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentRequest(ThemeData theme, ColorScheme colorScheme) {
    final amountCents = _pendingPayment!['amount_cents'] as int;
    final dollars = amountCents / 100;
    final formattedAmount = '\$${dollars.toStringAsFixed(2)}';
    final ticketTypeName = _pendingPayment!['ticket_type_name'] as String? ?? 'Ticket';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Payment icon
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.payment,
            size: 56,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Payment Request',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          formattedAmount,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          ticketTypeName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessingPayment ? null : _cancelPayment,
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: _isProcessingPayment ? null : _processPayment,
                child: _isProcessingPayment
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pay Now'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
