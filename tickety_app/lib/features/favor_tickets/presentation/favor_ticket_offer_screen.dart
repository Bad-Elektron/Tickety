import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/errors.dart';
import '../../../core/providers/providers.dart';
import '../../events/models/event_model.dart';
import '../../payments/models/payment.dart';
import '../../payments/presentation/checkout_screen.dart';
import '../models/ticket_offer.dart';

/// Screen for recipients to view and accept/decline a ticket offer.
class FavorTicketOfferScreen extends ConsumerStatefulWidget {
  const FavorTicketOfferScreen({super.key, required this.offerId});

  final String offerId;

  @override
  ConsumerState<FavorTicketOfferScreen> createState() =>
      _FavorTicketOfferScreenState();
}

class _FavorTicketOfferScreenState
    extends ConsumerState<FavorTicketOfferScreen> {
  TicketOffer? _offer;
  bool _isLoading = true;
  bool _isActioning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOffer();
  }

  Future<void> _loadOffer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ref.read(favorTicketRepositoryProvider);
      final offer = await repository.getOffer(widget.offerId);

      if (mounted) {
        setState(() {
          _offer = offer;
          _isLoading = false;
          if (offer == null) _error = 'Offer not found';
        });
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = appError.userMessage;
        });
      }
    }
  }

  Future<void> _acceptFreeOffer({bool skipMintingFee = false}) async {
    if (_offer == null) return;

    setState(() => _isActioning = true);

    try {
      final repository = ref.read(favorTicketRepositoryProvider);
      await repository.claimFreeOffer(
        _offer!.id,
        skipMintingFee: skipMintingFee,
      );

      HapticFeedback.mediumImpact();
      ref.read(pendingOffersProvider.notifier).removeOffer(_offer!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Ticket claimed!'),
              ],
            ),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appError.userMessage),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _acceptPaidOffer() async {
    if (_offer == null) return;

    // Fetch event for checkout
    final eventsState = ref.read(eventsProvider);
    final event = eventsState.events
        .where((e) => e.id == _offer!.eventId)
        .firstOrNull;

    if (event == null) {
      // Try refreshing
      await ref.read(eventsProvider.notifier).refresh();
      final refreshedState = ref.read(eventsProvider);
      final refreshedEvent = refreshedState.events
          .where((e) => e.id == _offer!.eventId)
          .firstOrNull;

      if (refreshedEvent == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not load event details'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      _navigateToCheckout(refreshedEvent);
    } else {
      _navigateToCheckout(event);
    }
  }

  void _navigateToCheckout(EventModel event) {
    final fees = ServiceFeeCalculator.calculate(_offer!.priceCents);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          event: event,
          amountCents: fees.totalCents,
          paymentType: PaymentType.favorTicketPurchase,
          baseUnitPriceCents: _offer!.priceCents,
          metadata: {'offer_id': _offer!.id},
        ),
      ),
    );
  }

  Future<void> _declineOffer() async {
    if (_offer == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline offer?'),
        content: const Text(
          'Are you sure you want to decline this ticket offer? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActioning = true);

    try {
      final repository = ref.read(favorTicketRepositoryProvider);
      await repository.declineOffer(_offer!.id);

      ref.read(pendingOffersProvider.notifier).removeOffer(_offer!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offer declined'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appError.userMessage),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket Offer'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(theme, colorScheme)
              : _offer == null
                  ? const Center(child: Text('Offer not found'))
                  : _buildOfferContent(theme, colorScheme),
    );
  }

  Widget _buildErrorState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64,
                color: colorScheme.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              'Failed to load offer',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadOffer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferContent(ThemeData theme, ColorScheme colorScheme) {
    final offer = _offer!;
    final isResolved = offer.status.isResolved;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gift icon header
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.card_giftcard,
                size: 40,
                color: Colors.teal,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Event title
          Center(
            child: Text(
              offer.eventTitle ?? 'Event',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          // From organizer
          Center(
            child: Text(
              'From ${offer.organizerName ?? 'the organizer'}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),

          // Status badge (if resolved)
          if (isResolved)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _statusColor(offer.status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(offer.status),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _statusColor(offer.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          if (isResolved) const SizedBox(height: 24),

          // Offer details card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Ticket',
                  value: offer.ticketMode == TicketMode.private_
                      ? 'Private (non-tradeable)'
                      : 'Public (tradeable)',
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.attach_money,
                  label: 'Price',
                  value: offer.formattedPrice,
                ),
                if (offer.message != null) ...[
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: Icons.message_outlined,
                    label: 'Message',
                    value: offer.message!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons (only for pending offers)
          if (!isResolved) ...[
            // Free private offer
            if (offer.isFree &&
                offer.ticketMode == TicketMode.private_) ...[
              FilledButton(
                onPressed: _isActioning ? null : () => _acceptFreeOffer(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isActioning
                    ? const _LoadingIndicator()
                    : const Text(
                        'Accept',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ],

            // Free public offer - two options
            if (offer.isFree &&
                offer.ticketMode == TicketMode.public_) ...[
              // Info callout about minting fee
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.blue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'A small minting fee makes your ticket tradeable on the marketplace. Skip it to keep the ticket private.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _isActioning ? null : _acceptPaidOffer,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isActioning
                    ? const _LoadingIndicator()
                    : const Text(
                        'Pay \$1 & Accept (Tradeable)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isActioning
                    ? null
                    : () => _acceptFreeOffer(skipMintingFee: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Accept without fee (Non-tradeable)',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],

            // Paid offer (any mode)
            if (offer.isPaid) ...[
              FilledButton(
                onPressed: _isActioning ? null : _acceptPaidOffer,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isActioning
                    ? const _LoadingIndicator()
                    : Text(
                        'Pay ${offer.formattedPrice} & Accept',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ],

            const SizedBox(height: 12),

            // Decline button
            TextButton(
              onPressed: _isActioning ? null : _declineOffer,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                'Decline',
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(TicketOfferStatus status) {
    return switch (status) {
      TicketOfferStatus.accepted => Colors.green,
      TicketOfferStatus.declined => Colors.red,
      TicketOfferStatus.cancelled => Colors.orange,
      TicketOfferStatus.expired => Colors.grey,
      TicketOfferStatus.pending => Colors.blue,
    };
  }

  String _statusLabel(TicketOfferStatus status) {
    return switch (status) {
      TicketOfferStatus.accepted => 'Accepted',
      TicketOfferStatus.declined => 'Declined',
      TicketOfferStatus.cancelled => 'Cancelled by organizer',
      TicketOfferStatus.expired => 'Expired',
      TicketOfferStatus.pending => 'Pending',
    };
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
