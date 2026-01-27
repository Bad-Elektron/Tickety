import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/state/app_state.dart';
import 'package:tickety/features/subscriptions/models/subscription.dart';

void main() {
  group('SubscriptionStatus', () {
    test('fromString parses valid statuses', () {
      expect(SubscriptionStatus.fromString('active'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromString('canceled'), SubscriptionStatus.canceled);
      expect(SubscriptionStatus.fromString('past_due'), SubscriptionStatus.pastDue);
      expect(SubscriptionStatus.fromString('trialing'), SubscriptionStatus.trialing);
      expect(SubscriptionStatus.fromString('paused'), SubscriptionStatus.paused);
    });

    test('fromString is case insensitive', () {
      expect(SubscriptionStatus.fromString('ACTIVE'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromString('Active'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromString('PAST_DUE'), SubscriptionStatus.pastDue);
    });

    test('fromString defaults to active for unknown values', () {
      expect(SubscriptionStatus.fromString('unknown'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromString(''), SubscriptionStatus.active);
    });

    test('toDbString returns correct database values', () {
      expect(SubscriptionStatus.active.toDbString(), 'active');
      expect(SubscriptionStatus.canceled.toDbString(), 'canceled');
      expect(SubscriptionStatus.pastDue.toDbString(), 'past_due');
      expect(SubscriptionStatus.trialing.toDbString(), 'trialing');
      expect(SubscriptionStatus.paused.toDbString(), 'paused');
    });

    test('grantsAccess returns true for active and trialing', () {
      expect(SubscriptionStatus.active.grantsAccess, isTrue);
      expect(SubscriptionStatus.trialing.grantsAccess, isTrue);
      expect(SubscriptionStatus.canceled.grantsAccess, isFalse);
      expect(SubscriptionStatus.pastDue.grantsAccess, isFalse);
      expect(SubscriptionStatus.paused.grantsAccess, isFalse);
    });

    test('label returns human-readable names', () {
      expect(SubscriptionStatus.active.label, 'Active');
      expect(SubscriptionStatus.canceled.label, 'Canceled');
      expect(SubscriptionStatus.pastDue.label, 'Past Due');
      expect(SubscriptionStatus.trialing.label, 'Trial');
      expect(SubscriptionStatus.paused.label, 'Paused');
    });
  });

  group('Subscription', () {
    final now = DateTime.now();
    final futureDate = now.add(const Duration(days: 30));
    final pastDate = now.subtract(const Duration(days: 5));

    Subscription createSubscription({
      String id = 'sub_001',
      String userId = 'user_001',
      AccountTier tier = AccountTier.pro,
      SubscriptionStatus status = SubscriptionStatus.active,
      String? stripeSubscriptionId,
      DateTime? currentPeriodEnd,
      bool cancelAtPeriodEnd = false,
    }) {
      return Subscription(
        id: id,
        userId: userId,
        tier: tier,
        status: status,
        stripeSubscriptionId: stripeSubscriptionId,
        currentPeriodEnd: currentPeriodEnd,
        cancelAtPeriodEnd: cancelAtPeriodEnd,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('fromJson creates Subscription from valid JSON', () {
      final json = {
        'id': 'sub_001',
        'user_id': 'user_001',
        'tier': 'pro',
        'status': 'active',
        'stripe_subscription_id': 'stripe_sub_xxx',
        'stripe_price_id': 'price_xxx',
        'current_period_start': '2025-01-01T00:00:00Z',
        'current_period_end': '2025-02-01T00:00:00Z',
        'cancel_at_period_end': false,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final subscription = Subscription.fromJson(json);

      expect(subscription.id, 'sub_001');
      expect(subscription.userId, 'user_001');
      expect(subscription.tier, AccountTier.pro);
      expect(subscription.status, SubscriptionStatus.active);
      expect(subscription.stripeSubscriptionId, 'stripe_sub_xxx');
      expect(subscription.stripePriceId, 'price_xxx');
      expect(subscription.cancelAtPeriodEnd, isFalse);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'sub_001',
        'user_id': 'user_001',
        'tier': 'base',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final subscription = Subscription.fromJson(json);

      expect(subscription.stripeSubscriptionId, isNull);
      expect(subscription.stripePriceId, isNull);
      expect(subscription.currentPeriodStart, isNull);
      expect(subscription.currentPeriodEnd, isNull);
      expect(subscription.status, SubscriptionStatus.active);
      expect(subscription.cancelAtPeriodEnd, isFalse);
    });

    test('fromJson parses tier correctly', () {
      expect(
        Subscription.fromJson({
          'id': '1',
          'user_id': 'u1',
          'tier': 'base',
          'created_at': '2025-01-01T00:00:00Z',
          'updated_at': '2025-01-01T00:00:00Z',
        }).tier,
        AccountTier.base,
      );
      expect(
        Subscription.fromJson({
          'id': '2',
          'user_id': 'u2',
          'tier': 'pro',
          'created_at': '2025-01-01T00:00:00Z',
          'updated_at': '2025-01-01T00:00:00Z',
        }).tier,
        AccountTier.pro,
      );
      expect(
        Subscription.fromJson({
          'id': '3',
          'user_id': 'u3',
          'tier': 'enterprise',
          'created_at': '2025-01-01T00:00:00Z',
          'updated_at': '2025-01-01T00:00:00Z',
        }).tier,
        AccountTier.enterprise,
      );
    });

    test('fromJson defaults to base for unknown tier', () {
      final subscription = Subscription.fromJson({
        'id': '1',
        'user_id': 'u1',
        'tier': 'unknown',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(subscription.tier, AccountTier.base);
    });

    test('toJson creates valid JSON', () {
      final subscription = createSubscription(
        stripeSubscriptionId: 'stripe_sub_xxx',
        currentPeriodEnd: futureDate,
      );
      final json = subscription.toJson();

      expect(json['id'], 'sub_001');
      expect(json['user_id'], 'user_001');
      expect(json['tier'], 'pro');
      expect(json['status'], 'active');
      expect(json['stripe_subscription_id'], 'stripe_sub_xxx');
    });

    test('hasAccess returns correct values for tier comparison', () {
      final baseSubscription = createSubscription(tier: AccountTier.base);
      final proSubscription = createSubscription(tier: AccountTier.pro);
      final enterpriseSubscription = createSubscription(tier: AccountTier.enterprise);

      // Base tier
      expect(baseSubscription.hasAccess(AccountTier.base), isTrue);
      expect(baseSubscription.hasAccess(AccountTier.pro), isFalse);
      expect(baseSubscription.hasAccess(AccountTier.enterprise), isFalse);

      // Pro tier
      expect(proSubscription.hasAccess(AccountTier.base), isTrue);
      expect(proSubscription.hasAccess(AccountTier.pro), isTrue);
      expect(proSubscription.hasAccess(AccountTier.enterprise), isFalse);

      // Enterprise tier
      expect(enterpriseSubscription.hasAccess(AccountTier.base), isTrue);
      expect(enterpriseSubscription.hasAccess(AccountTier.pro), isTrue);
      expect(enterpriseSubscription.hasAccess(AccountTier.enterprise), isTrue);
    });

    test('hasAccess returns false when status does not grant access', () {
      final canceledSubscription = createSubscription(
        tier: AccountTier.enterprise,
        status: SubscriptionStatus.canceled,
      );

      expect(canceledSubscription.hasAccess(AccountTier.base), isFalse);
      expect(canceledSubscription.hasAccess(AccountTier.pro), isFalse);
      expect(canceledSubscription.hasAccess(AccountTier.enterprise), isFalse);
    });

    test('daysRemaining calculates correctly', () {
      final subscription = createSubscription(currentPeriodEnd: futureDate);
      final days = subscription.daysRemaining;

      expect(days, isNotNull);
      expect(days, greaterThanOrEqualTo(29)); // Allow for time zone differences
      expect(days, lessThanOrEqualTo(31));
    });

    test('daysRemaining returns null when no period end', () {
      final subscription = createSubscription();
      expect(subscription.daysRemaining, isNull);
    });

    test('daysRemaining returns 0 when period has ended', () {
      final subscription = createSubscription(currentPeriodEnd: pastDate);
      expect(subscription.daysRemaining, 0);
    });

    test('isPaid returns true for pro and enterprise', () {
      expect(createSubscription(tier: AccountTier.base).isPaid, isFalse);
      expect(createSubscription(tier: AccountTier.pro).isPaid, isTrue);
      expect(createSubscription(tier: AccountTier.enterprise).isPaid, isTrue);
    });

    test('isActive returns true when status grants access', () {
      expect(createSubscription(status: SubscriptionStatus.active).isActive, isTrue);
      expect(createSubscription(status: SubscriptionStatus.trialing).isActive, isTrue);
      expect(createSubscription(status: SubscriptionStatus.canceled).isActive, isFalse);
      expect(createSubscription(status: SubscriptionStatus.pastDue).isActive, isFalse);
    });

    test('willRenew returns correct values', () {
      expect(
        createSubscription(status: SubscriptionStatus.active, cancelAtPeriodEnd: false).willRenew,
        isTrue,
      );
      expect(
        createSubscription(status: SubscriptionStatus.active, cancelAtPeriodEnd: true).willRenew,
        isFalse,
      );
      expect(
        createSubscription(status: SubscriptionStatus.canceled, cancelAtPeriodEnd: false).willRenew,
        isFalse,
      );
    });

    test('copyWith creates copy with modified values', () {
      final original = createSubscription();
      final modified = original.copyWith(
        tier: AccountTier.enterprise,
        status: SubscriptionStatus.trialing,
      );

      expect(modified.id, original.id);
      expect(modified.userId, original.userId);
      expect(modified.tier, AccountTier.enterprise);
      expect(modified.status, SubscriptionStatus.trialing);
    });

    test('equality compares by id, tier, and status', () {
      final sub1 = createSubscription(id: 'sub_001');
      final sub2 = createSubscription(id: 'sub_001');
      final sub3 = createSubscription(id: 'sub_002');
      final sub4 = createSubscription(id: 'sub_001', tier: AccountTier.enterprise);

      expect(sub1, equals(sub2));
      expect(sub1, isNot(equals(sub3)));
      expect(sub1, isNot(equals(sub4)));
    });

    test('hashCode is based on id, tier, and status', () {
      final sub1 = createSubscription(id: 'sub_001');
      final sub2 = createSubscription(id: 'sub_001');

      expect(sub1.hashCode, equals(sub2.hashCode));
    });

    test('toString includes tier and status', () {
      final subscription = createSubscription();
      final str = subscription.toString();

      expect(str, contains('pro'));
      expect(str, contains('active'));
    });
  });

  group('SubscriptionCheckoutResponse', () {
    test('fromJson parses complete response', () {
      final json = {
        'client_secret': 'pi_xxx_secret_yyy',
        'customer_id': 'cus_xxx',
        'ephemeral_key': 'ek_xxx',
        'subscription_id': 'sub_xxx',
      };

      final response = SubscriptionCheckoutResponse.fromJson(json);

      expect(response.clientSecret, 'pi_xxx_secret_yyy');
      expect(response.customerId, 'cus_xxx');
      expect(response.ephemeralKey, 'ek_xxx');
      expect(response.subscriptionId, 'sub_xxx');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'client_secret': 'pi_xxx_secret_yyy',
        'customer_id': 'cus_xxx',
        'ephemeral_key': 'ek_xxx',
      };

      final response = SubscriptionCheckoutResponse.fromJson(json);

      expect(response.subscriptionId, isNull);
    });
  });

  group('CustomerPortalResponse', () {
    test('fromJson parses URL', () {
      final json = {
        'url': 'https://billing.stripe.com/session/xxx',
      };

      final response = CustomerPortalResponse.fromJson(json);

      expect(response.url, 'https://billing.stripe.com/session/xxx');
    });
  });
}
