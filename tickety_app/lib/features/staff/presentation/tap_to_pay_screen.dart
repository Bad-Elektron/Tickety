import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/services.dart';
import '../../events/models/event_model.dart';
import '../../events/models/ticket_type.dart';

/// Screen for vendors to accept tap-to-pay from customers.
///
/// Flow:
/// 1. Vendor selects ticket type and opens this screen
/// 2. Screen starts listening for NFC (customer's Tickety app broadcasting their ID)
/// 3. When customer ID is received, creates a pending_payment record
/// 4. Customer's app sees the payment request via Realtime
/// 5. Customer confirms and pays
/// 6. Vendor sees payment success, ticket is created
class TapToPayScreen extends ConsumerStatefulWidget {
  const TapToPayScreen({
    super.key,
    required this.event,
    required this.ticketType,
  });

  final EventModel event;
  final TicketType ticketType;

  @override
  ConsumerState<TapToPayScreen> createState() => _TapToPayScreenState();
}

class _TapToPayScreenState extends ConsumerState<TapToPayScreen>
    with SingleTickerProviderStateMixin {
  bool _isNfcAvailable = false;
  bool _isListening = false;
  bool _isCheckingNfc = true;
  String? _pendingPaymentId;

  // Realtime subscription for payment status
  RealtimeChannel? _paymentChannel;
  String _paymentStatus = 'waiting'; // waiting, pending, processing, completed, failed

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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopListening();
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkNfcAndStart() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      final available = availability == NfcAvailability.enabled;
      if (mounted) {
        setState(() {
          _isNfcAvailable = available;
          _isCheckingNfc = false;
        });

        if (available) {
          await _startListening();
        }
      }
    } catch (e) {
      debugPrint('NFC check error: $e');
      if (mounted) {
        setState(() {
          _isNfcAvailable = false;
          _isCheckingNfc = false;
        });
      }
    }
  }

  Future<void> _startListening() async {
    if (_isListening) return;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          debugPrint('NFC tag discovered: $tag');
          await _handleNfcTag(tag);
        },
      );

      if (mounted) {
        setState(() => _isListening = true);
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('Failed to start NFC session: $e');
    }
  }

  Future<void> _stopListening() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (e) {
      debugPrint('Failed to stop NFC session: $e');
    }
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  Future<void> _handleNfcTag(NfcTag tag) async {
    // Try to read NDEF data from HCE broadcast
    final ndef = Ndef.from(tag);
    if (ndef == null) {
      debugPrint('Tag is not NDEF formatted');
      return;
    }

    try {
      final message = await ndef.read();
      if (message == null || message.records.isEmpty) {
        debugPrint('No NDEF records found');
        return;
      }

      // Parse the payload - look for Tickety payment data
      for (final record in message.records) {
        final payload = _extractPayloadText(record);
        debugPrint('NDEF payload: $payload');

        if (payload != null && payload.contains('TICKETY_PAY:')) {
          final customerId = payload.split('TICKETY_PAY:').last.trim();
          if (customerId.isNotEmpty) {
            await _onCustomerIdReceived(customerId);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading NFC tag: $e');
    }
  }

  /// Extract text from an NDEF record (handles URI and text records).
  String? _extractPayloadText(NdefRecord record) {
    try {
      // Try to decode as UTF-8 directly first
      final text = utf8.decode(record.payload);
      return text;
    } catch (_) {
      // If that fails, try as URI record
      if (record.payload.isNotEmpty) {
        final prefixCode = record.payload[0];
        if (prefixCode < 36 && record.payload.length > 1) {
          // It's a URI record with prefix
          const prefixes = [
            '', 'http://www.', 'https://www.', 'http://', 'https://',
            'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.',
            'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
            'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:',
            'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://', 'btgoep://',
            'tcpobex://', 'irdaobex://', 'file://', 'urn:epc:id:',
            'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
          ];
          final prefix = prefixes[prefixCode];
          final uriData = record.payload.sublist(1);
          return prefix + utf8.decode(uriData);
        }
      }
    }
    return null;
  }

  Future<void> _onCustomerIdReceived(String customerId) async {
    debugPrint('Customer ID received: $customerId');

    if (mounted) {
      setState(() => _paymentStatus = 'pending');
      HapticFeedback.heavyImpact();
    }

    // Stop listening for more NFC tags
    await _stopListening();

    // Create pending payment
    await _createPendingPayment(customerId);
  }

  Future<void> _createPendingPayment(String customerId) async {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    try {
      final response = await SupabaseService.instance.client
          .from('pending_payments')
          .insert({
            'vendor_id': user.id,
            'customer_id': customerId,
            'event_id': widget.event.id,
            'ticket_type_id': widget.ticketType.id,
            'ticket_type_name': widget.ticketType.name,
            'amount_cents': widget.ticketType.priceInCents,
            'status': 'pending',
          })
          .select()
          .single();

      final paymentId = response['id'] as String;

      if (mounted) {
        setState(() => _pendingPaymentId = paymentId);
      }

      // Subscribe to payment status updates
      _subscribeToPaymentStatus(paymentId);

    } catch (e) {
      debugPrint('Failed to create pending payment: $e');
      if (mounted) {
        setState(() => _paymentStatus = 'failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create payment request: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _subscribeToPaymentStatus(String paymentId) {
    final client = SupabaseService.instance.client;

    _paymentChannel = client
        .channel('payment_status:$paymentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pending_payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: paymentId,
          ),
          callback: (payload) {
            debugPrint('Payment status update: ${payload.newRecord}');
            final status = payload.newRecord['status'] as String?;
            if (status != null && mounted) {
              setState(() => _paymentStatus = status);

              if (status == 'completed') {
                HapticFeedback.heavyImpact();
                _onPaymentCompleted();
              } else if (status == 'failed' || status == 'cancelled') {
                HapticFeedback.lightImpact();
              }
            }
          },
        )
        .subscribe();
  }

  void _onPaymentCompleted() {
    // Show success and return
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop(true); // Return success
      }
    });
  }

  void _cancelPayment() async {
    if (_pendingPaymentId == null) {
      Navigator.of(context).pop(false);
      return;
    }

    try {
      await SupabaseService.instance.client
          .from('pending_payments')
          .update({'status': 'cancelled'})
          .eq('id', _pendingPaymentId!);
    } catch (e) {
      debugPrint('Failed to cancel payment: $e');
    }

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  void _retry() {
    setState(() {
      _pendingPaymentId = null;
      _paymentStatus = 'waiting';
    });
    _paymentChannel?.unsubscribe();
    _startListening();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tap to Pay'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelPayment,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Ticket info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.confirmation_number,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.ticketType.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.event.title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      widget.ticketType.formattedPrice,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Main content based on state
              if (_isCheckingNfc)
                const CircularProgressIndicator()
              else if (!_isNfcAvailable)
                _buildNfcUnavailable(theme, colorScheme)
              else
                _buildPaymentState(theme, colorScheme),

              const Spacer(),

              // Bottom action
              if (_paymentStatus == 'failed' || _paymentStatus == 'cancelled')
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
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
          'Your device doesn\'t support NFC.\nUse manual entry instead.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentState(ThemeData theme, ColorScheme colorScheme) {
    switch (_paymentStatus) {
      case 'waiting':
        return _buildWaitingState(theme, colorScheme);
      case 'pending':
      case 'processing':
        return _buildProcessingState(theme, colorScheme);
      case 'completed':
        return _buildCompletedState(theme, colorScheme);
      case 'failed':
      case 'cancelled':
        return _buildFailedState(theme, colorScheme);
      default:
        return _buildWaitingState(theme, colorScheme);
    }
  }

  Widget _buildWaitingState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          'Waiting for Customer',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask customer to open Tickety app\nand tap "Ready to Pay"',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _isListening ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isListening ? 'NFC Active' : 'Initializing...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _isListening ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessingState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Waiting for Payment',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Customer is confirming payment\non their device...',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            size: 72,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Payment Complete!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ticket has been sent to customer',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFailedState(ThemeData theme, ColorScheme colorScheme) {
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
            Icons.error_outline,
            size: 72,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _paymentStatus == 'cancelled' ? 'Payment Cancelled' : 'Payment Failed',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _paymentStatus == 'cancelled'
              ? 'The customer declined the payment'
              : 'Something went wrong. Please try again.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
