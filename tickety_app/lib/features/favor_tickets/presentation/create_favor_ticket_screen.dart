import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/errors.dart';
import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../events/models/event_model.dart';
import '../models/ticket_offer.dart';

/// Screen for organizers to create and send a favor/comp ticket.
class CreateFavorTicketScreen extends ConsumerStatefulWidget {
  const CreateFavorTicketScreen({super.key, required this.event});

  final EventModel event;

  @override
  ConsumerState<CreateFavorTicketScreen> createState() =>
      _CreateFavorTicketScreenState();
}

class _CreateFavorTicketScreenState
    extends ConsumerState<CreateFavorTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _priceController = TextEditingController();
  final _messageController = TextEditingController();
  TicketMode _ticketMode = TicketMode.private_;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _priceController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final repository = ref.read(favorTicketRepositoryProvider);

      // Parse price
      final priceText = _priceController.text.replaceAll(RegExp(r'[^\d.]'), '');
      final priceDollars = double.tryParse(priceText) ?? 0;
      final priceCents = (priceDollars * 100).round();

      await repository.createOffer(
        eventId: widget.event.id,
        recipientEmail: _emailController.text.trim(),
        priceCents: priceCents,
        ticketMode: _ticketMode,
        message: _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : null,
      );

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(L.tr('favor_ticket_offer_sent')),
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
      print('>>> FAVOR TICKET ERROR: $e');
      print('>>> FAVOR TICKET STACK: $s');
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('favor_ticket_send_title')),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.card_giftcard,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.event.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              L.tr('favor_ticket_send_subtitle'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Recipient email
                Text(
                  L.tr('favor_ticket_recipient_email'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'recipient@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return L.tr('favor_ticket_enter_email');
                    }
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return L.tr('favor_ticket_valid_email');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  L.tr('favor_ticket_recipient_note'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Price
                Text(
                  L.tr('common_price'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                    hintText: '0.00',
                    helperText: 'Leave at \$0 for a free ticket',
                    border: const OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final price = double.tryParse(value);
                      if (price == null || price < 0) {
                        return L.tr('favor_ticket_valid_price');
                      }
                      if (price > 10000) {
                        return L.tr('favor_ticket_max_price');
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Ticket Mode
                Text(
                  L.tr('favor_ticket_mode'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<TicketMode>(
                  segments: [
                    ButtonSegment(
                      value: TicketMode.private_,
                      label: Text(L.tr('common_private')),
                      icon: const Icon(Icons.lock_outline),
                    ),
                    ButtonSegment(
                      value: TicketMode.public_,
                      label: Text(L.tr('common_public')),
                      icon: const Icon(Icons.public_outlined),
                    ),
                  ],
                  selected: {_ticketMode},
                  onSelectionChanged: (selected) {
                    setState(() => _ticketMode = selected.first);
                  },
                ),
                const SizedBox(height: 12),

                // Mode info callout
                _ModeInfoCard(ticketMode: _ticketMode),
                const SizedBox(height: 24),

                // Optional message
                Text(
                  L.tr('favor_ticket_personal_message'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _messageController,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: L.tr('favor_ticket_message_hint'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit button
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send),
                            const SizedBox(width: 8),
                            Text(
                              L.tr('favor_ticket_send_offer'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeInfoCard extends StatelessWidget {
  const _ModeInfoCard({required this.ticketMode});

  final TicketMode ticketMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isPrivate = ticketMode == TicketMode.private_;
    final icon = isPrivate ? Icons.lock_outline : Icons.public_outlined;
    final color = isPrivate ? Colors.orange : Colors.blue;
    final title = isPrivate ? L.tr('favor_ticket_private_title') : L.tr('favor_ticket_public_title');
    final description = isPrivate
        ? L.tr('favor_ticket_private_description')
        : L.tr('favor_ticket_public_description');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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
