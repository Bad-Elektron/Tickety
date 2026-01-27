import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/providers/subscription_provider.dart';
import 'package:tickety/core/state/app_state.dart';
import 'package:tickety/features/subscriptions/models/subscription.dart';

void main() {
  group('SubscriptionState', () {
    test('initial state has correct defaults', () {
      const state = SubscriptionState();

      expect(state.subscription, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('effectiveTier returns base when no subscription', () {
      const state = SubscriptionState();
      expect(state.effectiveTier, AccountTier.base);
    });

    test('effectiveTier returns subscription tier when present', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.pro),
      );
      expect(state.effectiveTier, AccountTier.pro);
    });

    test('isActive returns false when no subscription', () {
      const state = SubscriptionState();
      expect(state.isActive, isFalse);
    });

    test('isActive returns true for active subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(status: SubscriptionStatus.active),
      );
      expect(state.isActive, isTrue);
    });

    test('isActive returns false for canceled subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(status: SubscriptionStatus.canceled),
      );
      expect(state.isActive, isFalse);
    });

    test('willRenew returns false when no subscription', () {
      const state = SubscriptionState();
      expect(state.willRenew, isFalse);
    });

    test('willRenew returns true for active subscription not canceling', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(
          status: SubscriptionStatus.active,
          cancelAtPeriodEnd: false,
        ),
      );
      expect(state.willRenew, isTrue);
    });

    test('willRenew returns false when cancelAtPeriodEnd is true', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(
          status: SubscriptionStatus.active,
          cancelAtPeriodEnd: true,
        ),
      );
      expect(state.willRenew, isFalse);
    });

    test('isPaid returns false when no subscription', () {
      const state = SubscriptionState();
      expect(state.isPaid, isFalse);
    });

    test('isPaid returns false for base tier', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.base),
      );
      expect(state.isPaid, isFalse);
    });

    test('isPaid returns true for pro tier', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.pro),
      );
      expect(state.isPaid, isTrue);
    });

    test('daysRemaining returns null when no subscription', () {
      const state = SubscriptionState();
      expect(state.daysRemaining, isNull);
    });

    test('isCanceling returns false when no subscription', () {
      const state = SubscriptionState();
      expect(state.isCanceling, isFalse);
    });

    test('isCanceling returns true when cancelAtPeriodEnd is true', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(cancelAtPeriodEnd: true),
      );
      expect(state.isCanceling, isTrue);
    });

    test('copyWith creates copy with modified values', () {
      const original = SubscriptionState();
      final modified = original.copyWith(
        isLoading: true,
        error: 'Test error',
      );

      expect(modified.isLoading, isTrue);
      expect(modified.error, 'Test error');
      expect(modified.subscription, isNull);
    });

    test('copyWith with clearSubscription removes subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(),
      );
      final cleared = state.copyWith(clearSubscription: true);

      expect(cleared.subscription, isNull);
    });

    test('copyWith with clearError removes error', () {
      final state = const SubscriptionState().copyWith(error: 'Test error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith preserves existing values when not specified', () {
      final subscription = _createMockSubscription();
      final original = SubscriptionState(
        subscription: subscription,
        isLoading: true,
        error: 'Test error',
      );

      final modified = original.copyWith(isLoading: false);

      expect(modified.subscription, subscription);
      expect(modified.isLoading, isFalse);
      expect(modified.error, 'Test error');
    });

    test('effectiveTier returns enterprise for enterprise subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.enterprise),
      );
      expect(state.effectiveTier, AccountTier.enterprise);
    });

    test('isActive returns true for trialing subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(status: SubscriptionStatus.trialing),
      );
      expect(state.isActive, isTrue);
    });

    test('isActive returns false for pastDue subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(status: SubscriptionStatus.pastDue),
      );
      expect(state.isActive, isFalse);
    });

    test('isActive returns false for paused subscription', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(status: SubscriptionStatus.paused),
      );
      expect(state.isActive, isFalse);
    });
  });

  group('SubscriptionState tier comparisons', () {
    test('base tier isPaid returns false', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.base),
      );
      expect(state.isPaid, isFalse);
    });

    test('pro tier isPaid returns true', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.pro),
      );
      expect(state.isPaid, isTrue);
    });

    test('enterprise tier isPaid returns true', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(tier: AccountTier.enterprise),
      );
      expect(state.isPaid, isTrue);
    });
  });

  group('SubscriptionState daysRemaining', () {
    test('returns remaining days when period end is in future', () {
      final futureDate = DateTime.now().add(const Duration(days: 15));
      final state = SubscriptionState(
        subscription: _createMockSubscription(currentPeriodEnd: futureDate),
      );
      final days = state.daysRemaining;
      expect(days, isNotNull);
      expect(days, greaterThanOrEqualTo(14));
      expect(days, lessThanOrEqualTo(16));
    });

    test('returns null when subscription has no period end', () {
      final state = SubscriptionState(
        subscription: _createMockSubscription(),
      );
      expect(state.daysRemaining, isNull);
    });
  });
}

Subscription _createMockSubscription({
  String id = 'sub_001',
  String userId = 'user_001',
  AccountTier tier = AccountTier.pro,
  SubscriptionStatus status = SubscriptionStatus.active,
  bool cancelAtPeriodEnd = false,
  DateTime? currentPeriodEnd,
}) {
  final now = DateTime.now();
  return Subscription(
    id: id,
    userId: userId,
    tier: tier,
    status: status,
    cancelAtPeriodEnd: cancelAtPeriodEnd,
    currentPeriodEnd: currentPeriodEnd,
    createdAt: now,
    updatedAt: now,
  );
}
