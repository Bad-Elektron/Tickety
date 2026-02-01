import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tickety/core/models/paginated_result.dart';
import 'package:tickety/core/providers/payment_provider.dart';
import 'package:tickety/features/payments/models/payment.dart';

import '../mocks/mock_repositories.dart';

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    registerFallbackValue(
      const CreatePaymentIntentRequest(
        eventId: 'evt_001',
        amountCents: 2999,
        type: PaymentType.primaryPurchase,
      ),
    );
  });

  group('PaymentProcessState', () {
    test('initial state has correct defaults', () {
      const state = PaymentProcessState();

      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.paymentIntent, isNull);
      expect(state.isPaymentSheetReady, isFalse);
      expect(state.completedPayment, isNull);
    });

    test('hasError returns true when error exists', () {
      final state = const PaymentProcessState().copyWith(error: 'Test error');

      expect(state.hasError, isTrue);
    });

    test('hasError returns false when no error', () {
      const state = PaymentProcessState();

      expect(state.hasError, isFalse);
    });

    test('isReady returns true when payment intent exists and sheet is ready', () {
      final state = const PaymentProcessState().copyWith(
        paymentIntent: _createMockPaymentIntentResponse(),
        isPaymentSheetReady: true,
        isLoading: false,
      );

      expect(state.isReady, isTrue);
    });

    test('isReady returns false when loading', () {
      final state = const PaymentProcessState().copyWith(
        paymentIntent: _createMockPaymentIntentResponse(),
        isPaymentSheetReady: true,
        isLoading: true,
      );

      expect(state.isReady, isFalse);
    });

    test('isReady returns false when payment sheet not ready', () {
      final state = const PaymentProcessState().copyWith(
        paymentIntent: _createMockPaymentIntentResponse(),
        isPaymentSheetReady: false,
      );

      expect(state.isReady, isFalse);
    });

    test('copyWith creates copy with modified values', () {
      const original = PaymentProcessState();
      final modified = original.copyWith(
        isLoading: true,
        error: 'Test error',
        isPaymentSheetReady: true,
      );

      expect(modified.isLoading, isTrue);
      expect(modified.error, 'Test error');
      expect(modified.isPaymentSheetReady, isTrue);
    });

    test('copyWith with clearError removes error', () {
      final state = const PaymentProcessState().copyWith(error: 'Test error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith with clearPaymentIntent removes payment intent', () {
      final state = const PaymentProcessState().copyWith(
        paymentIntent: _createMockPaymentIntentResponse(),
      );
      final cleared = state.copyWith(clearPaymentIntent: true);

      expect(cleared.paymentIntent, isNull);
    });

    test('copyWith with clearCompletedPayment removes completed payment', () {
      final state = const PaymentProcessState().copyWith(
        completedPayment: _createMockPayment(),
      );
      final cleared = state.copyWith(clearCompletedPayment: true);

      expect(cleared.completedPayment, isNull);
    });
  });

  group('PaymentProcessNotifier', () {
    late MockPaymentRepository mockRepository;
    late PaymentProcessNotifier notifier;

    setUp(() {
      mockRepository = MockPaymentRepository();
      notifier = PaymentProcessNotifier(mockRepository);
    });

    test('initial state is empty', () {
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.paymentIntent, isNull);
      expect(notifier.state.isPaymentSheetReady, isFalse);
    });

    test('initializePrimaryPurchase returns false when already loading', () async {
      // Start loading
      when(() => mockRepository.createPaymentIntent(any()))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 10));
        return _createMockPaymentIntentResponse();
      });

      // Start first initialization (don't await)
      final future1 = notifier.initializePrimaryPurchase(
        eventId: 'evt_001',
        amountCents: 2999,
      );

      // Try to start second while first is running
      final result = await notifier.initializePrimaryPurchase(
        eventId: 'evt_002',
        amountCents: 3999,
      );

      expect(result, isFalse);

      // Clean up
      future1.ignore();
    });

    test('initializePrimaryPurchase handles repository errors', () async {
      when(() => mockRepository.createPaymentIntent(any()))
          .thenThrow(Exception('Network error'));

      final result = await notifier.initializePrimaryPurchase(
        eventId: 'evt_001',
        amountCents: 2999,
      );

      expect(result, isFalse);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNotNull);
    });

    test('clear resets state', () async {
      // Set up some state
      when(() => mockRepository.createPaymentIntent(any()))
          .thenThrow(Exception('Error'));
      await notifier.initializePrimaryPurchase(
        eventId: 'evt_001',
        amountCents: 2999,
      );

      notifier.clear();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNull);
      expect(notifier.state.paymentIntent, isNull);
      expect(notifier.state.isPaymentSheetReady, isFalse);
    });

    test('clearError removes only error', () async {
      when(() => mockRepository.createPaymentIntent(any()))
          .thenThrow(Exception('Error'));
      await notifier.initializePrimaryPurchase(
        eventId: 'evt_001',
        amountCents: 2999,
      );

      expect(notifier.state.error, isNotNull);

      notifier.clearError();

      expect(notifier.state.error, isNull);
    });
  });

  group('PaymentHistoryState', () {
    test('initial state has correct defaults', () {
      const state = PaymentHistoryState();

      expect(state.payments, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, 0);
      expect(state.hasMore, isTrue);
      expect(state.pageSize, kPaymentHistoryPageSize);
    });

    test('canLoadMore returns true when conditions are met', () {
      const state = PaymentHistoryState(
        hasMore: true,
        isLoading: false,
        isLoadingMore: false,
      );
      expect(state.canLoadMore, isTrue);
    });

    test('canLoadMore returns false when loading', () {
      const loading = PaymentHistoryState(
        hasMore: true,
        isLoading: true,
        isLoadingMore: false,
      );
      const loadingMore = PaymentHistoryState(
        hasMore: true,
        isLoading: false,
        isLoadingMore: true,
      );
      const noMore = PaymentHistoryState(
        hasMore: false,
        isLoading: false,
        isLoadingMore: false,
      );

      expect(loading.canLoadMore, isFalse);
      expect(loadingMore.canLoadMore, isFalse);
      expect(noMore.canLoadMore, isFalse);
    });

    test('completedPayments filters correctly', () {
      final payments = [
        _createMockPayment(id: '1', status: PaymentStatus.completed),
        _createMockPayment(id: '2', status: PaymentStatus.pending),
        _createMockPayment(id: '3', status: PaymentStatus.completed),
        _createMockPayment(id: '4', status: PaymentStatus.failed),
      ];
      final state = const PaymentHistoryState().copyWith(payments: payments);

      expect(state.completedPayments.length, 2);
    });

    test('pendingPayments filters correctly', () {
      final payments = [
        _createMockPayment(id: '1', status: PaymentStatus.pending),
        _createMockPayment(id: '2', status: PaymentStatus.processing),
        _createMockPayment(id: '3', status: PaymentStatus.completed),
      ];
      final state = const PaymentHistoryState().copyWith(payments: payments);

      expect(state.pendingPayments.length, 2);
    });

    test('refundedPayments filters correctly', () {
      final payments = [
        _createMockPayment(id: '1', status: PaymentStatus.refunded),
        _createMockPayment(id: '2', status: PaymentStatus.completed),
        _createMockPayment(id: '3', status: PaymentStatus.refunded),
      ];
      final state = const PaymentHistoryState().copyWith(payments: payments);

      expect(state.refundedPayments.length, 2);
    });

    test('totalSpentCents sums completed payments', () {
      final payments = [
        _createMockPayment(id: '1', status: PaymentStatus.completed, amountCents: 1000),
        _createMockPayment(id: '2', status: PaymentStatus.completed, amountCents: 2000),
        _createMockPayment(id: '3', status: PaymentStatus.pending, amountCents: 500),
        _createMockPayment(id: '4', status: PaymentStatus.refunded, amountCents: 300),
      ];
      final state = const PaymentHistoryState().copyWith(payments: payments);

      expect(state.totalSpentCents, 3000); // Only completed: 1000 + 2000
    });

    test('copyWith with clearError removes error', () {
      final state = const PaymentHistoryState().copyWith(error: 'Test error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });
  });

  group('PaymentHistoryNotifier', () {
    late MockPaymentRepository mockRepository;
    late PaymentHistoryNotifier notifier;

    PaginatedResult<Payment> _paginatedPayments(
      List<Payment> items, {
      int page = 0,
      bool hasMore = false,
    }) {
      return PaginatedResult(
        items: items,
        page: page,
        pageSize: kPaymentHistoryPageSize,
        hasMore: hasMore,
      );
    }

    setUp(() {
      mockRepository = MockPaymentRepository();
      notifier = PaymentHistoryNotifier(mockRepository);
    });

    test('initial state is empty', () {
      expect(notifier.state.payments, isEmpty);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.isLoadingMore, isFalse);
    });

    test('load fetches payments', () async {
      final payments = [
        _createMockPayment(id: '1'),
        _createMockPayment(id: '2'),
      ];

      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedPayments(payments, hasMore: true));

      await notifier.load();

      expect(notifier.state.payments, payments);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.hasMore, isTrue);
    });

    test('load handles errors', () async {
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenThrow(Exception('Network error'));

      await notifier.load();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.hasMore, isFalse);
    });

    test('load does not reload when already loading', () async {
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 10));
        return _paginatedPayments([]);
      });

      // Start first load (don't await)
      final future1 = notifier.load();

      // Try to load again
      await notifier.load();

      // Should only call repository once
      verify(() => mockRepository.getMyPayments(
            page: 0,
            pageSize: any(named: 'pageSize'),
          )).called(1);

      future1.ignore();
    });

    test('refresh resets isLoading and loads', () async {
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedPayments([]));

      await notifier.refresh();

      verify(() => mockRepository.getMyPayments(
            page: 0,
            pageSize: any(named: 'pageSize'),
          )).called(1);
    });

    test('loadMore appends items and increments page', () async {
      final page1 = [_createMockPayment(id: '1'), _createMockPayment(id: '2')];
      final page2 = [_createMockPayment(id: '3'), _createMockPayment(id: '4')];

      when(() => mockRepository.getMyPayments(page: 0, pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => _paginatedPayments(page1, hasMore: true));
      when(() => mockRepository.getMyPayments(page: 1, pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => _paginatedPayments(page2, page: 1, hasMore: false));

      await notifier.load();
      expect(notifier.state.payments.length, 2);
      expect(notifier.state.currentPage, 0);

      await notifier.loadMore();
      expect(notifier.state.payments.length, 4);
      expect(notifier.state.currentPage, 1);
      expect(notifier.state.hasMore, isFalse);
    });

    test('loadMore does nothing when hasMore is false', () async {
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedPayments([], hasMore: false));

      await notifier.load();
      expect(notifier.state.hasMore, isFalse);

      // Reset mock to track further calls
      reset(mockRepository);
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedPayments([]));

      await notifier.loadMore();

      // Should not call repository again
      verifyNever(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ));
    });

    test('loadMore preserves existing data on error', () async {
      final payments = [_createMockPayment(id: '1')];

      when(() => mockRepository.getMyPayments(page: 0, pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => _paginatedPayments(payments, hasMore: true));
      when(() => mockRepository.getMyPayments(page: 1, pageSize: any(named: 'pageSize')))
          .thenThrow(Exception('Network error'));

      await notifier.load();
      await notifier.loadMore();

      expect(notifier.state.payments, payments);
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.isLoadingMore, isFalse);
    });

    test('requestRefund updates payment in list', () async {
      final originalPayment = _createMockPayment(
        id: 'pay_001',
        status: PaymentStatus.completed,
      );
      final refundedPayment = _createMockPayment(
        id: 'pay_001',
        status: PaymentStatus.refunded,
      );

      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedPayments([originalPayment]));
      when(() => mockRepository.requestRefund('pay_001'))
          .thenAnswer((_) async => refundedPayment);

      await notifier.load();
      final result = await notifier.requestRefund('pay_001');

      expect(result, isTrue);
      expect(notifier.state.payments.first.status, PaymentStatus.refunded);
    });

    test('requestRefund handles errors', () async {
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedPayments([]));
      when(() => mockRepository.requestRefund('pay_001'))
          .thenThrow(Exception('Refund failed'));

      await notifier.load();
      final result = await notifier.requestRefund('pay_001');

      expect(result, isFalse);
      expect(notifier.state.error, isNotNull);
    });

    test('clearError removes error', () async {
      when(() => mockRepository.getMyPayments(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenThrow(Exception('Error'));
      await notifier.load();

      expect(notifier.state.error, isNotNull);

      notifier.clearError();

      expect(notifier.state.error, isNull);
    });
  });
}

PaymentIntentResponse _createMockPaymentIntentResponse() {
  return const PaymentIntentResponse(
    paymentIntentId: 'pi_test_xxx',
    clientSecret: 'pi_test_xxx_secret_yyy',
    customerId: 'cus_xxx',
    ephemeralKey: 'ek_xxx',
    paymentId: 'pay_001',
  );
}

Payment _createMockPayment({
  String id = 'pay_001',
  PaymentStatus status = PaymentStatus.completed,
  int amountCents = 2999,
}) {
  final now = DateTime.now();
  return Payment(
    id: id,
    userId: 'user_001',
    eventId: 'evt_001',
    amountCents: amountCents,
    status: status,
    type: PaymentType.primaryPurchase,
    createdAt: now,
    updatedAt: now,
  );
}
