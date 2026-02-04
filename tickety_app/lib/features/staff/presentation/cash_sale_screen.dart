import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/nfc_service.dart';
import '../../events/models/event_model.dart';
import '../../events/models/ticket_type.dart';
import '../data/cash_transaction_repository.dart';
import '../models/cash_transaction.dart';

/// Result of a cash sale.
class CashSaleScreenResult {
  const CashSaleScreenResult({
    required this.success,
    this.ticketNumber,
  });

  final bool success;
  final String? ticketNumber;
}

/// Screen for processing a cash sale via NFC.
///
/// Flow:
/// 1. Staff opens this screen with ticket type selected
/// 2. Waits for customer to tap their phone (NFC read mode)
/// 3. Reads customer identity from NFC
/// 4. Shows confirmation dialog with customer name
/// 5. On confirm, creates ticket with customer as owner
class CashSaleScreen extends StatefulWidget {
  const CashSaleScreen({
    super.key,
    required this.event,
    required this.ticketType,
  });

  final EventModel event;
  final TicketType ticketType;

  @override
  State<CashSaleScreen> createState() => _CashSaleScreenState();
}

class _CashSaleScreenState extends State<CashSaleScreen>
    with SingleTickerProviderStateMixin {
  final _nfcService = NfcService.instance;
  final _cashRepo = CashTransactionRepository();
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isReading = false;
  bool _isProcessing = false;
  bool _isSuccess = false;
  bool _isLookingUpEmail = false;
  bool _showEmailInput = false;
  String? _error;
  CustomerNfcPayload? _pendingCustomer;
  String? _soldTicketNumber;

  String get _formattedPrice {
    if (widget.ticketType.priceInCents == 0) return 'Free';
    final dollars = widget.ticketType.priceInCents / 100;
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

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start NFC reading
    _startNfcReading();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _emailController.dispose();
    _emailFocusNode.dispose();
    _nfcService.stopReading();
    super.dispose();
  }

  Future<void> _startNfcReading() async {
    setState(() {
      _isReading = true;
      _error = null;
    });

    // Check if NFC is available first
    final nfcAvailable = await _nfcService.isNfcAvailable();
    if (!nfcAvailable) {
      // NFC not available - still show NFC UI but it won't actually read
      // User can tap "Enter email instead" to manually enter customer info
      if (mounted) {
        setState(() {
          _isReading = false;
        });
      }
      return;
    }

    await _nfcService.startReadingCustomer(
      onCustomerRead: _onCustomerRead,
      onError: (error) {
        if (mounted) {
          // Don't show error for NFC issues - just stop reading
          setState(() {
            _isReading = false;
          });
        }
      },
    );
  }

  void _onCustomerRead(CustomerNfcPayload customer) {
    if (!mounted) return;

    // Stop reading and show confirmation
    _nfcService.stopReading();

    setState(() {
      _isReading = false;
      _pendingCustomer = customer;
    });

    HapticFeedback.mediumImpact();

    // Show confirmation dialog
    _showConfirmationDialog(customer);
  }

  Future<void> _showConfirmationDialog(
    CustomerNfcPayload customer, {
    bool isNewCustomer = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer ticket to:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    customer.name.isNotEmpty
                        ? customer.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        customer.email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      if (isNewCustomer) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'No account - ticket sent via email',
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Colors.orange.shade700,
                                    ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ticket Type',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  widget.ticketType.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  _formattedPrice,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
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
            child: const Text('Confirm Sale'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _processSale(customer);
    } else {
      // Go back to appropriate state
      setState(() {
        _pendingCustomer = null;
      });
      if (_showEmailInput) {
        // Stay in email input mode
      } else {
        _startNfcReading();
      }
    }
  }

  Future<void> _processSale(CustomerNfcPayload customer) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final result = await _cashRepo.createCashSale(
        eventId: widget.event.id,
        amountCents: widget.ticketType.priceInCents,
        deliveryMethod: CashDeliveryMethod.nfc,
        ticketTypeId: widget.ticketType.id,
        customerName: customer.name,
        customerEmail: customer.email,
      );

      if (result.success && result.ticketNumber != null) {
        setState(() {
          _isProcessing = false;
          _isSuccess = true;
          _soldTicketNumber = result.ticketNumber;
        });

        HapticFeedback.mediumImpact();
        _pulseController.stop();

        // Auto-close after showing success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop(
              CashSaleScreenResult(
                success: true,
                ticketNumber: result.ticketNumber,
              ),
            );
          }
        });
      } else {
        setState(() {
          _isProcessing = false;
          _error = result.error ?? 'Failed to create ticket';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error: $e';
      });
    }
  }

  /// Simulate a customer tap for testing on emulator.
  void _simulateCustomerTap() {
    final simulatedCustomer = CustomerNfcPayload(
      userId: 'test-user-123',
      name: 'Test Customer',
      email: 'test@example.com',
    );
    _onCustomerRead(simulatedCustomer);
  }

  /// Toggle email input mode.
  void _toggleEmailInput() {
    setState(() {
      _showEmailInput = !_showEmailInput;
      if (_showEmailInput) {
        _nfcService.stopReading();
        _isReading = false;
        // Focus the email field after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _emailFocusNode.requestFocus();
        });
      } else {
        _emailController.clear();
        _startNfcReading();
      }
    });
  }

  /// Look up customer by email and proceed with sale.
  Future<void> _lookupByEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter an email address');
      return;
    }

    // Basic email validation
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLookingUpEmail = true;
      _error = null;
    });

    try {
      // Look up user by email via repository
      final userInfo = await _cashRepo.lookupUserByEmail(email);

      if (userInfo != null) {
        // User found - create customer payload and show confirmation
        final customer = CustomerNfcPayload(
          userId: userInfo['id'] as String,
          name: userInfo['name'] as String? ?? email.split('@').first,
          email: email,
        );

        setState(() {
          _isLookingUpEmail = false;
          _pendingCustomer = customer;
        });

        _showConfirmationDialog(customer);
      } else {
        // User not found - create sale with just email (no account)
        final customer = CustomerNfcPayload(
          userId: '', // No user ID - will use email only
          name: email.split('@').first, // Use email prefix as name
          email: email,
        );

        setState(() {
          _isLookingUpEmail = false;
          _pendingCustomer = customer;
        });

        _showConfirmationDialog(customer, isNewCustomer: true);
      }
    } catch (e) {
      setState(() {
        _isLookingUpEmail = false;
        _error = 'Failed to look up email: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Sale'),
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
                            'Event',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.event.title,
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
                            'Ticket',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            widget.ticketType.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
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

              // Main content area
              if (_isSuccess)
                _buildSuccessState(theme, colorScheme)
              else if (_isProcessing)
                _buildProcessingState(theme, colorScheme)
              else if (_error != null)
                _buildErrorState(theme, colorScheme)
              else
                _buildReadingState(theme, colorScheme),

              const Spacer(),

              // Action buttons
              if (_isSuccess) ...[
                // Success auto-closes, no button needed
              ] else if (_isProcessing) ...[
                // Processing, no button needed
              ] else if (_error != null) ...[
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _error = null);
                    _startNfcReading();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(
                    const CashSaleScreenResult(success: false),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Cancel'),
                ),
              ] else if (_showEmailInput) ...[
                // Email input mode - just show cancel
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(
                    const CashSaleScreenResult(success: false),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Cancel'),
                ),
              ] else ...[
                // NFC mode - show email option and cancel
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _toggleEmailInput,
                        icon: const Icon(Icons.email_outlined, size: 18),
                        label: const Text('Email'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _simulateCustomerTap,
                        icon: const Icon(Icons.bug_report, size: 18),
                        label: const Text('Test'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(
                    const CashSaleScreenResult(success: false),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadingState(ThemeData theme, ColorScheme colorScheme) {
    if (_showEmailInput) {
      return _buildEmailInputState(theme, colorScheme);
    }

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
          'Waiting for Customer',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask the customer to open the Tickety app\nand tap their phone to receive the ticket',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEmailInputState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // Compact email input card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter Customer Email',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _toggleEmailInput,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  focusNode: _emailFocusNode,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _lookupByEmail(),
                  decoration: InputDecoration(
                    hintText: 'customer@example.com',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    suffixIcon: _isLookingUpEmail
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _lookupByEmail,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLookingUpEmail ? null : _lookupByEmail,
                    child: Text(
                        _isLookingUpEmail ? 'Looking up...' : 'Look Up'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: const Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 6),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Processing Sale...',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Creating ticket and charging platform fee',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
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
          'Sale Complete!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ticket #$_soldTicketNumber\nhas been transferred to the customer',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
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
            color: Colors.red.withValues(alpha: 0.2),
          ),
          child: const Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Error',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red,
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
