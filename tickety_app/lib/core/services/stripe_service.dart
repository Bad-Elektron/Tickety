import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';

import '../config/config.dart';
import '../errors/errors.dart';

/// Singleton service providing access to Stripe payment functionality.
///
/// Must call [initialize] before accessing [instance].
/// Note: Stripe Payment Sheet only works on iOS and Android.
/// On other platforms, the service initializes but payment methods are unavailable.
class StripeService {
  static StripeService? _instance;

  /// Whether Stripe is supported on the current platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// The singleton instance. Throws if [initialize] hasn't been called.
  static StripeService get instance {
    if (_instance == null) {
      throw StateError(
        'StripeService not initialized. Call StripeService.initialize() first.',
      );
    }
    return _instance!;
  }

  StripeService._();

  /// Initializes the Stripe SDK with the publishable key from environment.
  ///
  /// Call this once at app startup after [EnvConfig.initialize].
  /// On unsupported platforms (Windows, macOS, Linux, Web), this creates
  /// a stub instance without initializing the Stripe SDK.
  static Future<void> initialize() async {
    if (_instance != null) {
      return;
    }

    // Stripe Payment Sheet only works on iOS and Android
    if (!isSupported) {
      AppLogger.warning(
        'Stripe not supported on this platform. Payment features will be unavailable.',
        tag: 'StripeService',
      );
      _instance = StripeService._();
      return;
    }

    AppLogger.debug('Initializing Stripe SDK', tag: 'StripeService');
    final key = EnvConfig.stripePublishableKey;
    Stripe.publishableKey = key;

    // Enable Apple Pay and Google Pay
    Stripe.merchantIdentifier = 'merchant.com.tickety.app';

    // Apply settings with timeout to prevent hanging
    try {
      await Stripe.instance.applySettings().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.warning(
            'Stripe applySettings timed out - continuing without full initialization',
            tag: 'StripeService',
          );
        },
      );
    } catch (e, stack) {
      AppLogger.error(
        'Failed to apply Stripe settings',
        error: e,
        stackTrace: stack,
        tag: 'StripeService',
      );
      rethrow;
    }

    AppLogger.info('Stripe SDK initialized successfully', tag: 'StripeService');
    _instance = StripeService._();
  }

  /// Initialize the Payment Sheet with customer and payment intent data.
  ///
  /// [paymentIntentClientSecret] - The client secret from the PaymentIntent created server-side.
  /// [customerId] - Optional Stripe customer ID for saved payment methods.
  /// [customerEphemeralKeySecret] - Optional ephemeral key for customer operations.
  /// [merchantDisplayName] - Name shown in the payment sheet.
  ///
  /// Throws [PaymentException] if called on an unsupported platform.
  Future<void> initPaymentSheet({
    required String paymentIntentClientSecret,
    String? customerId,
    String? customerEphemeralKeySecret,
    String merchantDisplayName = 'Tickety',
  }) async {
    if (!isSupported) {
      throw PaymentException.platformNotSupported();
    }

    AppLogger.debug(
      'Initializing payment sheet',
      tag: 'StripeService',
    );

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: paymentIntentClientSecret,
        customerId: customerId,
        customerEphemeralKeySecret: customerEphemeralKeySecret,
        merchantDisplayName: merchantDisplayName,
        style: ThemeMode.system,
        applePay: const PaymentSheetApplePay(
          merchantCountryCode: 'US',
        ),
        googlePay: const PaymentSheetGooglePay(
          merchantCountryCode: 'US',
          testEnv: true, // Set to false for production
        ),
      ),
    );

    AppLogger.debug(
      'Payment sheet initialized successfully',
      tag: 'StripeService',
    );
  }

  /// Present the Payment Sheet to the user.
  ///
  /// Returns true if payment was successful, false if cancelled.
  /// Throws [PaymentException] on payment failure or unsupported platform.
  Future<bool> presentPaymentSheet() async {
    if (!isSupported) {
      throw PaymentException.platformNotSupported();
    }

    AppLogger.info(
      'Presenting payment sheet',
      tag: 'StripeService',
    );

    try {
      await Stripe.instance.presentPaymentSheet();
      AppLogger.info(
        'Payment sheet completed successfully',
        tag: 'StripeService',
      );
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        AppLogger.info(
          'Payment cancelled by user',
          tag: 'StripeService',
        );
        return false;
      }
      AppLogger.error(
        'Payment failed: ${e.error.message}',
        error: e,
        tag: 'StripeService',
      );
      throw PaymentException.fromStripeError(e);
    }
  }

  /// Confirm a payment using a card.
  ///
  /// This is an alternative to Payment Sheet for custom UI scenarios.
  /// Throws [PaymentException] if called on an unsupported platform.
  Future<PaymentIntent> confirmPayment({
    required String paymentIntentClientSecret,
    required PaymentMethodParams paymentMethodData,
  }) async {
    if (!isSupported) {
      throw PaymentException.platformNotSupported();
    }

    AppLogger.info(
      'Confirming payment',
      tag: 'StripeService',
    );

    try {
      final result = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: paymentIntentClientSecret,
        data: paymentMethodData,
      );

      AppLogger.info(
        'Payment confirmed: ${result.status}',
        tag: 'StripeService',
      );

      return result;
    } on StripeException catch (e) {
      AppLogger.error(
        'Payment confirmation failed: ${e.error.message}',
        error: e,
        tag: 'StripeService',
      );
      throw PaymentException.fromStripeError(e);
    }
  }

  /// Check if Apple Pay / Google Pay is available on this device.
  Future<bool> isPlatformPaySupported() async {
    if (!isSupported) return false;
    try {
      return await Stripe.instance.isPlatformPaySupported();
    } catch (_) {
      return false;
    }
  }
}
