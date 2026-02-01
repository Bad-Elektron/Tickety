import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/ticket_provider.dart';
import '../../../core/services/nfc_service.dart';
import '../../../shared/widgets/widgets.dart';
import '../../staff/models/ticket.dart';
import '../models/event_model.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/ticket_info_card.dart';
import 'vendor_event_screen.dart';

/// Screen for ushers to scan and validate tickets at an event.
///
/// NFC-first design with hold-to-scan and optional continuous mode.
class UsherEventScreen extends ConsumerStatefulWidget {
  const UsherEventScreen({
    super.key,
    required this.event,
    this.canSwitchToSelling = false,
  });

  final EventModel event;
  final bool canSwitchToSelling;

  @override
  ConsumerState<UsherEventScreen> createState() => _UsherEventScreenState();
}

class _UsherEventScreenState extends ConsumerState<UsherEventScreen>
    with SingleTickerProviderStateMixin {
  Ticket? _scannedTicket;
  CheckInValidationStatus? _validationStatus;
  bool _isLoading = false;
  bool _isCheckingIn = false;
  int _sessionCheckedIn = 0;

  // NFC state
  bool _isNfcAvailable = false;
  bool _isNfcScanning = false;
  bool _nfcContinuousMode = false;
  bool _isHoldingButton = false;
  final NfcService _nfcService = NfcService.instance;

  // Camera state
  bool _showCamera = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Load real stats for this event
    Future.microtask(() {
      ref.read(ticketProvider.notifier).loadStats(widget.event.id);
    });

    // Check NFC availability
    _checkNfcAvailability();

    // Pulse animation for NFC scanning
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _checkNfcAvailability() async {
    final available = await _nfcService.isNfcAvailable();
    if (mounted) {
      setState(() => _isNfcAvailable = available);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopNfcScanning();
    super.dispose();
  }

  Future<void> _startNfcScanning() async {
    if (!_isNfcAvailable) {
      _showError('NFC is not available on this device');
      return;
    }

    setState(() => _isNfcScanning = true);
    _pulseController.repeat(reverse: true);
    HapticFeedback.mediumImpact();

    await _nfcService.startReading(
      onTagRead: (payload) {
        // Check if the scanned ticket is for this event
        if (payload.eventId == widget.event.id) {
          _lookupTicket(payload.ticketId);
        } else {
          _showError('Ticket is for a different event');
          HapticFeedback.heavyImpact();
        }
      },
      onError: (error) {
        _showError(error);
        HapticFeedback.heavyImpact();
      },
    );
  }

  Future<void> _stopNfcScanning() async {
    await _nfcService.stopReading();
    if (mounted) {
      setState(() => _isNfcScanning = false);
    }
    _pulseController.stop();
    _pulseController.reset();
  }

  void _onHoldStart() {
    if (_nfcContinuousMode) return; // Already scanning continuously
    setState(() => _isHoldingButton = true);
    unawaited(_startNfcScanning());
  }

  void _onHoldEnd() {
    if (_nfcContinuousMode) return; // Keep scanning in continuous mode
    setState(() => _isHoldingButton = false);
    unawaited(_stopNfcScanning());
  }

  void _toggleContinuousMode(bool value) {
    setState(() {
      _nfcContinuousMode = value;
      if (value) {
        unawaited(_startNfcScanning());
      } else if (!_isHoldingButton) {
        unawaited(_stopNfcScanning());
      }
    });
    HapticFeedback.selectionClick();
  }

  void _openCamera() {
    setState(() => _showCamera = true);
  }

  void _closeCamera() {
    setState(() => _showCamera = false);
  }

  /// Look up a ticket by ID or number.
  Future<void> _lookupTicket(String ticketIdOrNumber) async {
    if (ticketIdOrNumber.trim().isEmpty) {
      _showError('Please enter a ticket number');
      return;
    }

    setState(() {
      _isLoading = true;
      _scannedTicket = null;
      _validationStatus = null;
    });

    try {
      final ticket = await ref.read(ticketProvider.notifier).findTicket(
            widget.event.id,
            ticketIdOrNumber.trim(),
          );

      if (!mounted) return;

      if (ticket == null) {
        setState(() {
          _isLoading = false;
          _validationStatus = CheckInValidationStatus.notFound;
        });
        HapticFeedback.heavyImpact();
        _showError('Ticket not found');
        return;
      }

      // Check if ticket is for this event
      if (ticket.eventId != widget.event.id) {
        setState(() {
          _isLoading = false;
          _scannedTicket = ticket;
          _validationStatus = CheckInValidationStatus.wrongEvent;
        });
        HapticFeedback.heavyImpact();
        return;
      }

      setState(() {
        _isLoading = false;
        _scannedTicket = ticket;
        _validationStatus = CheckInValidationStatus.fromTicket(ticket);
      });

      // Haptic feedback based on validity
      if (ticket.isValid) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.heavyImpact();
      }

      // Close camera if open
      if (_showCamera) {
        _closeCamera();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error looking up ticket: $e');
    }
  }

  /// Check in the currently scanned ticket.
  Future<void> _confirmCheckIn() async {
    if (_scannedTicket == null) return;

    setState(() => _isCheckingIn = true);

    try {
      final success = await ref
          .read(ticketProvider.notifier)
          .checkInTicket(_scannedTicket!.id);

      if (!mounted) return;

      if (success) {
        setState(() {
          _sessionCheckedIn++;
          _scannedTicket = null;
          _validationStatus = null;
          _isCheckingIn = false;
        });
        HapticFeedback.heavyImpact();
        _showSuccess('Ticket checked in!');
      } else {
        setState(() => _isCheckingIn = false);
        _showError('Failed to check in ticket');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCheckingIn = false);
      _showError('Error checking in ticket: $e');
    }
  }

  /// Dismiss the current ticket result.
  void _dismissTicket() {
    setState(() {
      _scannedTicket = null;
      _validationStatus = null;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ErrorSnackBar.show(context, message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = widget.event.getNoiseConfig();
    final stats = ref.watch(ticketStatsProvider);

    // Show camera view if open
    if (_showCamera) {
      return _CameraOverlay(
        event: widget.event,
        onScanned: _lookupTicket,
        onClose: _closeCamera,
        onError: _showError,
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.event.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: config.colors,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              // Camera button
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openCamera,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.qr_code_scanner,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              // Role switch button (if user has both roles)
              if (widget.canSwitchToSelling)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => VendorEventScreen(
                              event: widget.event,
                              canSwitchToUsher: true,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.point_of_sale,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Sell',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Usher badge
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Usher',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Stats bar
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    icon: Icons.login,
                    value: '${stats?.checkedIn ?? 0}',
                    label: 'Checked In',
                    color: Colors.green,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  _StatItem(
                    icon: Icons.confirmation_number_outlined,
                    value: '${stats?.totalSold ?? 0}',
                    label: 'Total Sold',
                    color: colorScheme.tertiary,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  _StatItem(
                    icon: Icons.nfc_rounded,
                    value: '$_sessionCheckedIn',
                    label: 'This Session',
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          // Main content
          SliverFillRemaining(
            hasScrollBody: false,
            child: _scannedTicket != null || _validationStatus != null
                ? _buildTicketResult()
                : _buildNfcScanView(),
          ),
        ],
      ),
    );
  }

  Widget _buildNfcScanView() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),

          // NFC Scan Button
          GestureDetector(
            onTapDown: (_) => _onHoldStart(),
            onTapUp: (_) => _onHoldEnd(),
            onTapCancel: _onHoldEnd,
            onLongPressStart: (_) => _onHoldStart(),
            onLongPressEnd: (_) => _onHoldEnd(),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: _isNfcScanning
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 30 * _pulseAnimation.value,
                              spreadRadius: 10 * (_pulseAnimation.value - 1),
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isNfcScanning
                        ? [colorScheme.primary, colorScheme.tertiary]
                        : [
                            colorScheme.surfaceContainerHighest,
                            colorScheme.surfaceContainerHigh,
                          ],
                  ),
                  border: Border.all(
                    color: _isNfcScanning
                        ? colorScheme.primary
                        : colorScheme.outline.withValues(alpha: 0.3),
                    width: 3,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.nfc_rounded,
                      size: 64,
                      color: _isNfcScanning
                          ? Colors.white
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isNfcScanning ? 'Scanning...' : 'Hold to Scan',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _isNfcScanning
                            ? Colors.white
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Instructions
          Text(
            !_isNfcAvailable
                ? 'NFC not available. Use QR scanner instead.'
                : _isNfcScanning
                    ? 'Hold device near attendee\'s phone'
                    : 'Hold the button to activate NFC scanning',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // Continuous mode toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _nfcContinuousMode
                    ? colorScheme.primary
                    : colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.repeat,
                  size: 20,
                  color: _nfcContinuousMode
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  'Continuous Scanning',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _nfcContinuousMode,
                  onChanged: _toggleContinuousMode,
                ),
              ],
            ),
          ),

          const Spacer(),

          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Looking up ticket...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

          // Manual entry hint
          TextButton.icon(
            onPressed: () => _showManualEntryDialog(),
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Enter ticket manually'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Ticket Number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'TKT-XXXXXXX-XXXX',
            prefixIcon: Icon(Icons.confirmation_number_outlined),
          ),
          onSubmitted: (value) {
            Navigator.pop(context);
            _lookupTicket(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _lookupTicket(controller.text);
            },
            child: const Text('Look Up'),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketResult() {
    // Show error state if no ticket but have validation status
    if (_scannedTicket == null && _validationStatus != null) {
      return _ErrorResultView(
        status: _validationStatus!,
        onDismiss: _dismissTicket,
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.only(bottom: 32),
      child: TicketInfoCard(
        ticket: _scannedTicket!,
        validationStatus: _validationStatus,
        onDismiss: _dismissTicket,
        onCheckIn: _confirmCheckIn,
        isLoading: _isCheckingIn,
      ),
    );
  }
}

/// Camera overlay for QR scanning.
class _CameraOverlay extends StatelessWidget {
  const _CameraOverlay({
    required this.event,
    required this.onScanned,
    required this.onClose,
    required this.onError,
  });

  final EventModel event;
  final void Function(String) onScanned;
  final VoidCallback onClose;
  final void Function(String) onError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Camera view
          QrScannerView(
            onScanned: onScanned,
            onError: onError,
          ),

          // Header overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Close button
                      Material(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onClose,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Scan QR Code',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              event.title,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Point camera at the ticket QR code',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error result view for ticket not found.
class _ErrorResultView extends StatelessWidget {
  const _ErrorResultView({
    required this.status,
    required this.onDismiss,
  });

  final CheckInValidationStatus status;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                status.icon,
                size: 48,
                color: status.color,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              status.label,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: status.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getMessage(status),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onDismiss,
                child: const Text('Try Again'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMessage(CheckInValidationStatus status) {
    return switch (status) {
      CheckInValidationStatus.notFound =>
        'This ticket number was not found. Please check and try again.',
      CheckInValidationStatus.wrongEvent =>
        'This ticket is for a different event.',
      CheckInValidationStatus.alreadyUsed =>
        'This ticket has already been checked in.',
      CheckInValidationStatus.cancelled => 'This ticket has been cancelled.',
      CheckInValidationStatus.refunded => 'This ticket has been refunded.',
      CheckInValidationStatus.valid => '',
    };
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
