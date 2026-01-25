import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/ticket_provider.dart';
import '../../../shared/widgets/widgets.dart';
import '../../staff/models/ticket.dart';
import '../models/event_model.dart';
import '../widgets/nfc_tap_view.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/ticket_info_card.dart';
import 'vendor_event_screen.dart';

/// Check-in method options.
enum CheckInMode {
  qrScan(
    icon: Icons.qr_code_scanner,
    label: 'Scan QR',
    shortLabel: 'QR',
  ),
  nfcTap(
    icon: Icons.nfc_rounded,
    label: 'Tap NFC',
    shortLabel: 'NFC',
  ),
  manual(
    icon: Icons.keyboard_alt_outlined,
    label: 'Manual',
    shortLabel: 'Manual',
  );

  const CheckInMode({
    required this.icon,
    required this.label,
    required this.shortLabel,
  });

  final IconData icon;
  final String label;
  final String shortLabel;
}

/// Screen for ushers to scan and validate tickets at an event.
///
/// Supports three check-in methods:
/// - QR code scanning (camera)
/// - NFC tap (phone-to-phone)
/// - Manual entry (keyboard)
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

class _UsherEventScreenState extends ConsumerState<UsherEventScreen> {
  CheckInMode _currentMode = CheckInMode.qrScan;
  Ticket? _scannedTicket;
  CheckInValidationStatus? _validationStatus;
  bool _isLoading = false;
  bool _isCheckingIn = false;
  int _sessionCheckedIn = 0;

  @override
  void initState() {
    super.initState();
    // Load real stats for this event
    Future.microtask(() {
      ref.read(ticketProvider.notifier).loadStats(widget.event.id);
    });

    // Default to manual on desktop/web where camera/NFC aren't available
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      _currentMode = CheckInMode.manual;
    }
  }

  @override
  void dispose() {
    super.dispose();
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 140,
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
                    icon: Icons.qr_code_scanner,
                    value: '$_sessionCheckedIn',
                    label: 'This Session',
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          // Mode selector
          SliverToBoxAdapter(
            child: _ModeSelector(
              currentMode: _currentMode,
              onModeChanged: (mode) {
                setState(() {
                  _currentMode = mode;
                  _scannedTicket = null;
                  _validationStatus = null;
                });
              },
            ),
          ),

          // Main content
          SliverFillRemaining(
            hasScrollBody: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _scannedTicket != null || _validationStatus != null
                  ? _buildTicketResult()
                  : _buildCheckInView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInView() {
    return Column(
      key: ValueKey('checkin_${_currentMode.name}'),
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: switch (_currentMode) {
                CheckInMode.qrScan => QrScannerView(
                    onScanned: _lookupTicket,
                    onError: _showError,
                  ),
                CheckInMode.nfcTap => NfcTapView(
                    onTicketReceived: _lookupTicket,
                    onError: _showError,
                  ),
                CheckInMode.manual => _ManualEntryView(
                    onLookup: _lookupTicket,
                    isLoading: _isLoading,
                  ),
              },
            ),
          ),
        ),

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
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Looking up ticket...',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
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

/// Mode selector tabs for check-in methods.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.currentMode,
    required this.onModeChanged,
  });

  final CheckInMode currentMode;
  final ValueChanged<CheckInMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter modes based on platform
    final availableModes = CheckInMode.values.where((mode) {
      if (kIsWeb) {
        // Web only supports QR (with HTTPS) and manual
        return mode == CheckInMode.qrScan || mode == CheckInMode.manual;
      }
      if (!(Platform.isIOS || Platform.isAndroid)) {
        // Desktop only supports manual
        return mode == CheckInMode.manual;
      }
      return true; // Mobile supports all
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: availableModes.map((mode) {
          final isSelected = mode == currentMode;
          return Expanded(
            child: GestureDetector(
              onTap: () => onModeChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      mode.icon,
                      size: 18,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mode.shortLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Manual ticket entry view.
class _ManualEntryView extends StatefulWidget {
  const _ManualEntryView({
    required this.onLookup,
    required this.isLoading,
  });

  final void Function(String) onLookup;
  final bool isLoading;

  @override
  State<_ManualEntryView> createState() => _ManualEntryViewState();
}

class _ManualEntryViewState extends State<_ManualEntryView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onLookup(_controller.text);
      _controller.clear();
    }
  }

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
            // Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.keyboard_alt_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Manual Entry',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the ticket number to look up',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Input field
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !widget.isLoading,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'TKT-XXXXXXX-XXXX',
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
                suffixIcon: IconButton(
                  onPressed: widget.isLoading ? null : _submit,
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),

            // Look up button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.isLoading ? null : _submit,
                icon: const Icon(Icons.search),
                label: const Text('Look Up Ticket'),
              ),
            ),
          ],
        ),
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
