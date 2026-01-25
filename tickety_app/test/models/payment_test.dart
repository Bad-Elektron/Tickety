import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/payments/models/payment.dart';

void main() {
  group('PaymentStatus', () {
    test('fromString parses valid statuses', () {
      expect(PaymentStatus.fromString('pending'), PaymentStatus.pending);
      expect(PaymentStatus.fromString('processing'), PaymentStatus.processing);
      expect(PaymentStatus.fromString('completed'), PaymentStatus.completed);
      expect(PaymentStatus.fromString('failed'), PaymentStatus.failed);
      expect(PaymentStatus.fromString('refunded'), PaymentStatus.refunded);
    });

    test('fromString defaults to pending for unknown', () {
      expect(PaymentStatus.fromString('unknown'), PaymentStatus.pending);
      expect(PaymentStatus.fromString(''), PaymentStatus.pending);
    });

    test('isSuccessful returns true only for completed', () {
      expect(PaymentStatus.completed.isSuccessful, isTrue);
      expect(PaymentStatus.pending.isSuccessful, isFalse);
      expect(PaymentStatus.failed.isSuccessful, isFalse);
    });

    test('isFailed returns true only for failed', () {
      expect(PaymentStatus.failed.isFailed, isTrue);
      expect(PaymentStatus.completed.isFailed, isFalse);
    });

    test('isPending returns true for pending and processing', () {
      expect(PaymentStatus.pending.isPending, isTrue);
      expect(PaymentStatus.processing.isPending, isTrue);
      expect(PaymentStatus.completed.isPending, isFalse);
    });

    test('isRefunded returns true only for refunded', () {
      expect(PaymentStatus.refunded.isRefunded, isTrue);
      expect(PaymentStatus.completed.isRefunded, isFalse);
    });
  });

  group('PaymentType', () {
    test('fromString parses valid types', () {
      expect(PaymentType.fromString('primary_purchase'), PaymentType.primaryPurchase);
      expect(PaymentType.fromString('resale_purchase'), PaymentType.resalePurchase);
      expect(PaymentType.fromString('vendor_pos'), PaymentType.vendorPos);
    });

    test('fromString defaults to primaryPurchase for unknown', () {
      expect(PaymentType.fromString('unknown'), PaymentType.primaryPurchase);
    });
  });

  group('Payment', () {
    final now = DateTime.now();

    Payment createPayment({
      String id = 'pay_001',
      int amountCents = 2999,
      int platformFeeCents = 150,
      PaymentStatus status = PaymentStatus.completed,
      PaymentType type = PaymentType.primaryPurchase,
    }) {
      return Payment(
        id: id,
        userId: 'user_001',
        eventId: 'evt_001',
        amountCents: amountCents,
        platformFeeCents: platformFeeCents,
        status: status,
        type: type,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('fromJson creates Payment from valid JSON', () {
      final json = {
        'id': 'pay_001',
        'user_id': 'user_001',
        'ticket_id': 'tkt_001',
        'event_id': 'evt_001',
        'amount_cents': 2999,
        'platform_fee_cents': 150,
        'currency': 'usd',
        'status': 'completed',
        'type': 'primary_purchase',
        'stripe_payment_intent_id': 'pi_xxx',
        'stripe_charge_id': 'ch_xxx',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:05:00Z',
        'metadata': {'quantity': 2},
      };

      final payment = Payment.fromJson(json);

      expect(payment.id, 'pay_001');
      expect(payment.userId, 'user_001');
      expect(payment.ticketId, 'tkt_001');
      expect(payment.eventId, 'evt_001');
      expect(payment.amountCents, 2999);
      expect(payment.platformFeeCents, 150);
      expect(payment.currency, 'usd');
      expect(payment.status, PaymentStatus.completed);
      expect(payment.type, PaymentType.primaryPurchase);
      expect(payment.stripePaymentIntentId, 'pi_xxx');
      expect(payment.stripeChargeId, 'ch_xxx');
      expect(payment.metadata?['quantity'], 2);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'pay_001',
        'user_id': 'user_001',
        'event_id': 'evt_001',
        'amount_cents': 2999,
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:05:00Z',
      };

      final payment = Payment.fromJson(json);

      expect(payment.ticketId, isNull);
      expect(payment.platformFeeCents, 0);
      expect(payment.currency, 'usd');
      expect(payment.status, PaymentStatus.pending);
      expect(payment.type, PaymentType.primaryPurchase);
    });

    test('toJson creates valid JSON', () {
      final payment = createPayment();
      final json = payment.toJson();

      expect(json['id'], 'pay_001');
      expect(json['user_id'], 'user_001');
      expect(json['amount_cents'], 2999);
      expect(json['status'], 'completed');
      expect(json['type'], 'primary_purchase');
    });

    test('formattedAmount formats correctly', () {
      expect(createPayment(amountCents: 2999).formattedAmount, '\$29.99');
      expect(createPayment(amountCents: 100).formattedAmount, '\$1.00');
      expect(createPayment(amountCents: 99).formattedAmount, '\$0.99');
      expect(createPayment(amountCents: 10000).formattedAmount, '\$100.00');
    });

    test('formattedPlatformFee formats correctly', () {
      expect(createPayment(platformFeeCents: 150).formattedPlatformFee, '\$1.50');
      expect(createPayment(platformFeeCents: 0).formattedPlatformFee, '\$0.00');
    });

    test('sellerAmountCents calculates correctly', () {
      final payment = createPayment(amountCents: 10000, platformFeeCents: 500);
      expect(payment.sellerAmountCents, 9500);
    });

    test('formattedSellerAmount formats correctly', () {
      final payment = createPayment(amountCents: 10000, platformFeeCents: 500);
      expect(payment.formattedSellerAmount, '\$95.00');
    });

    test('copyWith creates copy with modified values', () {
      final original = createPayment();
      final modified = original.copyWith(
        status: PaymentStatus.refunded,
        amountCents: 5000,
      );

      expect(modified.id, original.id);
      expect(modified.status, PaymentStatus.refunded);
      expect(modified.amountCents, 5000);
    });

    test('equality compares by id', () {
      final payment1 = createPayment(id: 'pay_001');
      final payment2 = createPayment(id: 'pay_001', amountCents: 9999);
      final payment3 = createPayment(id: 'pay_002');

      expect(payment1, equals(payment2));
      expect(payment1, isNot(equals(payment3)));
    });

    test('hashCode is based on id', () {
      final payment1 = createPayment(id: 'pay_001');
      final payment2 = createPayment(id: 'pay_001');

      expect(payment1.hashCode, equals(payment2.hashCode));
    });

    test('toString includes id, amount, and status', () {
      final payment = createPayment();
      final str = payment.toString();

      expect(str, contains('pay_001'));
      expect(str, contains('\$29.99'));
      expect(str, contains('completed'));
    });
  });

  group('CreatePaymentIntentRequest', () {
    test('toJson creates valid JSON', () {
      final request = CreatePaymentIntentRequest(
        eventId: 'evt_001',
        amountCents: 2999,
        type: PaymentType.primaryPurchase,
      );

      final json = request.toJson();

      expect(json['event_id'], 'evt_001');
      expect(json['amount_cents'], 2999);
      expect(json['currency'], 'usd');
      expect(json['type'], 'primary_purchase');
    });

    test('toJson includes optional fields when present', () {
      final request = CreatePaymentIntentRequest(
        eventId: 'evt_001',
        amountCents: 2999,
        type: PaymentType.resalePurchase,
        ticketId: 'tkt_001',
        resaleListingId: 'listing_001',
        metadata: {'source': 'mobile'},
      );

      final json = request.toJson();

      expect(json['ticket_id'], 'tkt_001');
      expect(json['resale_listing_id'], 'listing_001');
      expect(json['metadata'], {'source': 'mobile'});
    });

    test('toJson omits optional fields when null', () {
      final request = CreatePaymentIntentRequest(
        eventId: 'evt_001',
        amountCents: 2999,
        type: PaymentType.primaryPurchase,
      );

      final json = request.toJson();

      expect(json.containsKey('ticket_id'), isFalse);
      expect(json.containsKey('resale_listing_id'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });
  });

  group('PaymentIntentResponse', () {
    test('fromJson parses complete response', () {
      final json = {
        'payment_intent_id': 'pi_xxx',
        'client_secret': 'pi_xxx_secret_yyy',
        'customer_id': 'cus_xxx',
        'ephemeral_key': 'ek_xxx',
        'payment_id': 'pay_001',
      };

      final response = PaymentIntentResponse.fromJson(json);

      expect(response.paymentIntentId, 'pi_xxx');
      expect(response.clientSecret, 'pi_xxx_secret_yyy');
      expect(response.customerId, 'cus_xxx');
      expect(response.ephemeralKey, 'ek_xxx');
      expect(response.paymentId, 'pay_001');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'payment_intent_id': 'pi_xxx',
        'client_secret': 'pi_xxx_secret_yyy',
      };

      final response = PaymentIntentResponse.fromJson(json);

      expect(response.paymentIntentId, 'pi_xxx');
      expect(response.clientSecret, 'pi_xxx_secret_yyy');
      expect(response.customerId, isNull);
      expect(response.ephemeralKey, isNull);
      expect(response.paymentId, isNull);
    });
  });
}
