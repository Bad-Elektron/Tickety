import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../core/services/services.dart';
import '../../auth/presentation/login_screen.dart';
import '../../events/models/event_model.dart';
import '../models/payment.dart';
import 'checkout_screen.dart';

/// Development-only screen for testing payments.
///
/// Remove this file before production deployment.
class PaymentTestScreen extends ConsumerWidget {
  const PaymentTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paymentState = ref.watch(paymentProcessProvider);

    // Create a mock event for testing
    final testEvent = EventModel(
      id: 'test-event-123',
      title: 'Test Concert',
      subtitle: 'Payment Testing Event',
      description: 'This is a test event for payment testing',
      date: DateTime.now().add(const Duration(days: 30)),
      venue: 'Test Venue',
      city: 'Test City',
      country: 'USA',
      priceInCents: 2999, // $29.99
      currency: 'USD',
      noiseSeed: 12345,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Testing'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Development Only - Remove before production',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Authentication status check
            if (!SupabaseService.instance.isAuthenticated) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.login, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Login Required',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You must be logged in to test payments. Edge Functions require authentication.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Go to Login'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Logged in as: ${SupabaseService.instance.currentUser?.email ?? "Unknown"}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Test event info
            Text(
              'Test Event',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(testEvent.title, style: theme.textTheme.titleLarge),
                    Text(testEvent.subtitle),
                    const SizedBox(height: 8),
                    Text(
                      'Price: ${testEvent.formattedPrice}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Test cards info
            Text(
              'Test Cards',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _TestCardInfo(
              title: 'Success',
              cardNumber: '4242 4242 4242 4242',
              color: Colors.green,
            ),
            _TestCardInfo(
              title: 'Declined',
              cardNumber: '4000 0000 0000 0002',
              color: Colors.red,
            ),
            _TestCardInfo(
              title: '3D Secure',
              cardNumber: '4000 0000 0000 3220',
              color: Colors.blue,
            ),
            const SizedBox(height: 24),

            // State display
            if (paymentState.hasError) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Error: ${paymentState.error}',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (paymentState.isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // Primary Purchase Test
              FilledButton.icon(
                onPressed: !SupabaseService.instance.isAuthenticated
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CheckoutScreen(
                              event: testEvent,
                              amountCents: testEvent.priceInCents!,
                              paymentType: PaymentType.primaryPurchase,
                              quantity: 1,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Test Primary Purchase'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),

              // Multiple tickets test
              OutlinedButton.icon(
                onPressed: !SupabaseService.instance.isAuthenticated
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CheckoutScreen(
                              event: testEvent,
                              amountCents: testEvent.priceInCents! * 3, // 3 tickets
                              paymentType: PaymentType.primaryPurchase,
                              quantity: 3,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.confirmation_number),
                label: const Text('Test 3 Tickets Purchase'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),

              // Resale Purchase Test (mock)
              OutlinedButton.icon(
                onPressed: !SupabaseService.instance.isAuthenticated
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CheckoutScreen(
                              event: testEvent,
                              amountCents: 4500, // $45 resale price
                              paymentType: PaymentType.resalePurchase,
                              quantity: 1,
                              resaleListingId: 'test-listing-123',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Test Resale Purchase (\$45)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // Instructions
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
                    'Testing Instructions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('1. Use any test card number above'),
                  const Text('2. Use any future expiry date (e.g., 12/34)'),
                  const Text('3. Use any 3-digit CVC (e.g., 123)'),
                  const Text('4. Use any billing ZIP (e.g., 12345)'),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Ensure Stripe CLI is forwarding webhooks if testing locally.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestCardInfo extends StatelessWidget {
  const _TestCardInfo({
    required this.title,
    required this.cardNumber,
    required this.color,
  });

  final String title;
  final String cardNumber;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cardNumber,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              // Copy to clipboard
              final cleanNumber = cardNumber.replaceAll(' ', '');
              // Clipboard.setData(ClipboardData(text: cleanNumber));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $cleanNumber')),
              );
            },
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }
}
