import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/services/nfc_service.dart';
import '../../events/data/event_mapper.dart';
import '../../events/models/event_model.dart';
import '../../events/presentation/event_details_screen.dart';
import '../../staff/models/ticket.dart';
import 'resale_listing_screen.dart';

/// Screen displaying details of a single ticket.
///
/// Supports NFC broadcasting for tap-to-check-in on mobile devices.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticket});

  final Ticket ticket;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  bool _nfcAvailable = false;
  bool _hceAvailable = false;
  bool _nfcBroadcasting = false;
  final NfcService _nfcService = NfcService.instance;

  // Helper getters to extract event data
  String get _eventTitle =>
      widget.ticket.eventData?['title'] as String? ?? 'Unknown Event';

  String? get _eventSubtitle =>
      widget.ticket.eventData?['subtitle'] as String?;

  String? get _venue => widget.ticket.eventData?['venue'] as String?;

  String? get _city => widget.ticket.eventData?['city'] as String?;

  String? get _country => widget.ticket.eventData?['country'] as String?;

  DateTime? get _eventDate {
    final dateStr = widget.ticket.eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  int get _noiseSeed =>
      widget.ticket.eventData?['noise_seed'] as int? ??
      widget.ticket.ticketNumber.hashCode;

  String? get _fullAddress {
    final parts = <String>[];
    if (_venue != null) parts.add(_venue!);
    if (_city != null) parts.add(_city!);
    if (_country != null) parts.add(_country!);
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  /// Get the EventModel from ticket's event data.
  EventModel? get _eventModel {
    final eventData = widget.ticket.eventData;
    if (eventData == null) return null;
    try {
      return EventMapper.fromJson(eventData);
    } catch (_) {
      return null;
    }
  }

  void _navigateToEvent() {
    final event = _eventModel;
    if (event == null) {
      _showMessage('Event details not available');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailsScreen(event: event),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkNfcAvailability();
  }

  @override
  void dispose() {
    // Stop broadcasting when screen is disposed
    if (_nfcBroadcasting) {
      _nfcService.stopBroadcasting();
    }
    super.dispose();
  }

  Future<void> _checkNfcAvailability() async {
    // Only check on mobile platforms
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final nfcAvailable = await _nfcService.isNfcAvailable();
    final hceAvailable = await _nfcService.isHceAvailable();

    if (mounted) {
      setState(() {
        _nfcAvailable = nfcAvailable;
        _hceAvailable = hceAvailable;
      });
    }
  }

  Future<void> _toggleNfcBroadcast() async {
    if (!_hceAvailable) {
      if (Platform.isIOS) {
        _showMessage('NFC broadcasting is not available on iOS. Please use QR code.');
      } else {
        _showMessage('NFC is not available on this device. Please use QR code.');
      }
      return;
    }

    if (_nfcBroadcasting) {
      await _nfcService.stopBroadcasting();
      if (mounted) {
        setState(() => _nfcBroadcasting = false);
        HapticFeedback.lightImpact();
      }
    } else {
      final payload = TicketNfcPayload(
        ticketId: widget.ticket.id,
        ticketNumber: widget.ticket.ticketNumber,
        eventId: widget.ticket.eventId,
      );

      final success = await _nfcService.startBroadcasting(payload);
      if (mounted) {
        if (success) {
          setState(() => _nfcBroadcasting = true);
          HapticFeedback.mediumImpact();
          _showMessage('NFC ready. Hold phone near usher device.');
        } else {
          _showMessage('Failed to start NFC. Please use QR code.');
        }
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Present ticket for check-in: shows QR overlay and starts NFC broadcasting.
  Future<void> _presentTicket() async {
    HapticFeedback.mediumImpact();

    // Start NFC broadcasting if available and ticket is valid
    if (_hceAvailable && widget.ticket.isValid && !_nfcBroadcasting) {
      final payload = TicketNfcPayload(
        ticketId: widget.ticket.id,
        ticketNumber: widget.ticket.ticketNumber,
        eventId: widget.ticket.eventId,
      );
      final success = await _nfcService.startBroadcasting(payload);
      if (mounted && success) {
        setState(() => _nfcBroadcasting = true);
      }
    }

    if (!mounted) return;

    // Generate QR data
    final qrData = jsonEncode({
      'type': 'tickety_ticket',
      'version': 1,
      'ticket_id': widget.ticket.id,
      'ticket_number': widget.ticket.ticketNumber,
      'event_id': widget.ticket.eventId,
    });

    // Show the QR overlay
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => _QrCodeOverlay(
        qrData: qrData,
        ticketNumber: widget.ticket.ticketNumber,
        eventTitle: _eventTitle,
        isNfcActive: _nfcBroadcasting,
        isNfcSupported: _hceAvailable,
      ),
    );

    // Stop NFC broadcasting when overlay is closed
    if (_nfcBroadcasting && mounted) {
      await _nfcService.stopBroadcasting();
      setState(() => _nfcBroadcasting = false);
    }
  }

  void _openNavigation(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.navigation, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Navigate to ${_fullAddress ?? _venue ?? "venue"}'),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  void _showSellConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sell This Ticket?'),
        content: const Text(
          'By confirming, your ticket will be listed on the marketplace. '
          'Other users will be able to purchase it. You can cancel the listing at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToSellScreen();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToSellScreen() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResaleListingScreen(ticket: widget.ticket),
      ),
    );

    if (result == true && mounted) {
      HapticFeedback.mediumImpact();
      _showMessage('Ticket listed for sale!');
      // Pop back to refresh the tickets list
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient background
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _TicketHeader(
                noiseSeed: _noiseSeed,
                ticketId: widget.ticket.id,
                ticketNumber: widget.ticket.ticketNumber,
                eventId: widget.ticket.eventId,
                eventTitle: _eventTitle,
                nfcBroadcasting: _nfcBroadcasting,
                onPresent: _presentTicket,
              ),
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event title and subtitle - tappable to view event
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _navigateToEvent,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _eventTitle,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_eventSubtitle != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _eventSubtitle!,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Ticket number
                  _InfoCard(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Ticket Number',
                    value: widget.ticket.ticketNumber,
                    trailing: _StatusBadge(ticket: widget.ticket),
                  ),
                  const SizedBox(height: 12),

                  // Date and time
                  _InfoCard(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: _eventDate != null
                        ? _formatDate(_eventDate!)
                        : 'To be announced',
                  ),
                  const SizedBox(height: 12),

                  // Location with navigation
                  _InfoCard(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    value: _venue ?? 'TBA',
                    subtitle: _city != null
                        ? '$_city${_country != null ? ", $_country" : ""}'
                        : null,
                    trailing: IconButton(
                      onPressed: () => _openNavigation(context),
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.primary,
                      ),
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      tooltip: 'Get directions',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Wallet Status Card
                  _WalletStatusCard(
                    ticket: widget.ticket,
                    onSellPressed: widget.ticket.isValid && !widget.ticket.isListedForSale
                        ? _showSellConfirmation
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Purchase info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Purchase Details',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DetailRow(
                          label: 'Price Paid',
                          value: widget.ticket.formattedPrice,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Purchased',
                          value: _formatDate(widget.ticket.soldAt),
                        ),
                        if (widget.ticket.ownerName != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Holder',
                            value: widget.ticket.ownerName!,
                          ),
                        ],
                        if (widget.ticket.ownerEmail != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Email',
                            value: widget.ticket.ownerEmail!,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Check-in info if used
                  if (widget.ticket.isUsed && widget.ticket.checkedInAt != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Checked In',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                                Text(
                                  _formatDateTime(widget.ticket.checkedInAt!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Discover more events button
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        // Pop back to home screen
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('Discover More Events'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${_formatDate(date)} at $hour:$minute $period';
  }
}

/// NFC tap-to-check-in card.
class _NfcCheckInCard extends StatelessWidget {
  const _NfcCheckInCard({
    required this.isActive,
    required this.onToggle,
  });

  final bool isActive;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withValues(alpha: 0.8),
                ],
              )
            : null,
        color: isActive ? null : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? null
            : Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // NFC icon with animation
          _AnimatedNfcIcon(isActive: isActive),
          const SizedBox(width: 16),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Ready to Tap' : 'Tap to Check In',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? 'Hold phone near usher device'
                      : 'Enable NFC for instant check-in',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.9)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Toggle button
          Switch(
            value: isActive,
            onChanged: (_) => onToggle(),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return null;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white.withValues(alpha: 0.3);
              }
              return null;
            }),
          ),
        ],
      ),
    );
  }
}

/// Animated NFC icon with pulse effect when active.
class _AnimatedNfcIcon extends StatefulWidget {
  const _AnimatedNfcIcon({required this.isActive});

  final bool isActive;

  @override
  State<_AnimatedNfcIcon> createState() => _AnimatedNfcIconState();
}

class _AnimatedNfcIconState extends State<_AnimatedNfcIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_AnimatedNfcIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse rings when active
          if (widget.isActive)
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Container(
                  width: 48 + (16 * _animation.value),
                  height: 48 + (16 * _animation.value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 1.0 - _animation.value),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          // Icon background
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? Colors.white.withValues(alpha: 0.2)
                  : colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.nfc_rounded,
              size: 24,
              color: widget.isActive ? Colors.white : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color textColor;
    String label;
    IconData icon;

    switch (ticket.status) {
      case TicketStatus.valid:
        backgroundColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green;
        label = 'Valid';
        icon = Icons.check_circle;
      case TicketStatus.used:
        backgroundColor = Colors.blue.withValues(alpha: 0.1);
        textColor = Colors.blue;
        label = 'Used';
        icon = Icons.verified;
      case TicketStatus.cancelled:
        backgroundColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red;
        label = 'Cancelled';
        icon = Icons.cancel;
      case TicketStatus.refunded:
        backgroundColor = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange;
        label = 'Refunded';
        icon = Icons.undo;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketHeader extends StatelessWidget {
  const _TicketHeader({
    required this.noiseSeed,
    required this.ticketId,
    required this.ticketNumber,
    required this.eventId,
    required this.eventTitle,
    required this.nfcBroadcasting,
    required this.onPresent,
  });

  final int noiseSeed;
  final String ticketId;
  final String ticketNumber;
  final String eventId;
  final String eventTitle;
  final bool nfcBroadcasting;
  final VoidCallback onPresent;

  /// Generate QR code data as JSON string.
  String get _qrData {
    final data = {
      'type': 'tickety_ticket',
      'version': 1,
      'ticket_id': ticketId,
      'ticket_number': ticketNumber,
      'event_id': eventId,
    };
    return jsonEncode(data);
  }

  @override
  Widget build(BuildContext context) {
    final config = _getNoiseConfig();

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: config.colors,
            ),
          ),
        ),
        // QR Code - tappable
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onPresent,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 130,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Tap hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tap to present',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // NFC indicator when broadcasting
              if (nfcBroadcasting) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'NFC Ready',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  NoiseConfig _getNoiseConfig() {
    final presetIndex = noiseSeed % 5;
    return switch (presetIndex) {
      0 => NoisePresets.vibrantEvents(noiseSeed),
      1 => NoisePresets.sunset(noiseSeed),
      2 => NoisePresets.ocean(noiseSeed),
      3 => NoisePresets.subtle(noiseSeed),
      _ => NoisePresets.darkMood(noiseSeed),
    };
  }
}

/// Full-screen QR code overlay for easy scanning.
class _QrCodeOverlay extends StatefulWidget {
  const _QrCodeOverlay({
    required this.qrData,
    required this.ticketNumber,
    required this.eventTitle,
    this.isNfcActive = false,
    this.isNfcSupported = false,
  });

  final String qrData;
  final String ticketNumber;
  final String eventTitle;
  final bool isNfcActive;
  final bool isNfcSupported;

  @override
  State<_QrCodeOverlay> createState() => _QrCodeOverlayState();
}

class _QrCodeOverlayState extends State<_QrCodeOverlay> {
  double _previousBrightness = 0.5;

  @override
  void initState() {
    super.initState();
    _boostBrightness();
  }

  @override
  void dispose() {
    _restoreBrightness();
    super.dispose();
  }

  Future<void> _boostBrightness() async {
    // Note: In a real app, you'd use a package like screen_brightness
    // to actually change the screen brightness. For now, we'll just
    // set a flag that this should happen.
    // This is a placeholder for:
    // _previousBrightness = await ScreenBrightness().current;
    // await ScreenBrightness().setScreenBrightness(1.0);
  }

  Future<void> _restoreBrightness() async {
    // Placeholder for:
    // await ScreenBrightness().setScreenBrightness(_previousBrightness);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = screenWidth * 0.75;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Event title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.eventTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.ticketNumber,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 32),
                // Large QR code
                Container(
                  width: qrSize + 32,
                  height: qrSize + 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: widget.qrData,
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                const SizedBox(height: 32),
                // Instructions - QR code
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Show QR code to usher',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                // NFC indicator - show when supported or active
                if (widget.isNfcActive || widget.isNfcSupported) ...[
                  const SizedBox(height: 16),
                  _NfcActiveIndicator(isActive: widget.isNfcActive),
                ] else ...[
                  // Always show NFC info on Android as a feature hint
                  if (!kIsWeb && Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    _NfcActiveIndicator(isActive: false),
                  ],
                ],
                const SizedBox(height: 48),
                // Close hint
                Text(
                  'Tap anywhere to close',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Card showing ticket wallet status and sell option.
class _WalletStatusCard extends StatelessWidget {
  const _WalletStatusCard({
    required this.ticket,
    this.onSellPressed,
  });

  final Ticket ticket;
  final VoidCallback? onSellPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnSale = ticket.isListedForSale;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isOnSale
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.shade600,
                  Colors.orange.shade400,
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.green.shade600,
                  Colors.green.shade400,
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isOnSale ? Colors.orange : Colors.green).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Status icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOnSale ? Icons.storefront_rounded : Icons.lock_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              // Status text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnSale ? 'Listed for Sale' : 'Secure in Wallet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOnSale
                          ? 'Visible on marketplace \u2022 ${ticket.formattedListingPrice ?? "Price TBD"}'
                          : 'Only you can access this ticket',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOnSale ? Icons.visibility : Icons.shield,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnSale ? 'Public' : 'Private',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Sell button (only if not already listed and ticket is valid)
          if (onSellPressed != null && !isOnSale) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSellPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.sell_outlined, size: 20),
                label: const Text(
                  'Sell This Ticket',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          // Cancel listing hint (if on sale)
          if (isOnSale) ...[
            const SizedBox(height: 12),
            Text(
              'Tap to manage or cancel listing',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Animated NFC active indicator shown in the present overlay.
class _NfcActiveIndicator extends StatefulWidget {
  const _NfcActiveIndicator({this.isActive = true});

  final bool isActive;

  @override
  State<_NfcActiveIndicator> createState() => _NfcActiveIndicatorState();
}

class _NfcActiveIndicatorState extends State<_NfcActiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _iconAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _iconAnimation = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;

    // When not active, show a static version
    if (!isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.smartphone,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.nfc_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'NFC tap check-in',
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Available on supported devices',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    // Active state with animation
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.4 * _pulseAnimation.value),
                theme.colorScheme.tertiary.withValues(alpha: 0.3 * _pulseAnimation.value),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3 * _pulseAnimation.value),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.3 * _pulseAnimation.value),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated phone icon moving towards NFC
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: Offset(_iconAnimation.value, 0),
                    child: Icon(
                      Icons.smartphone,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Signal waves
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) {
                      final delay = index * 0.2;
                      final animValue = ((_controller.value + delay) % 1.0);
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.wifi_rounded,
                          color: Colors.white.withValues(alpha: 0.3 + (animValue * 0.7)),
                          size: 16 + (index * 2),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.nfc_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Main text
              Text(
                'Move phone to usher',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'NFC is ready for tap check-in',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Notice shown on iOS explaining QR-only check-in.
class _IosQrNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_2,
              size: 24,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QR Code Check-in',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Show the QR code above to the usher for check-in',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
