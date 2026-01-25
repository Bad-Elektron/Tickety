import 'package:mocktail/mocktail.dart';
import 'package:tickety/features/events/data/event_repository.dart';
import 'package:tickety/features/payments/data/i_payment_repository.dart';
import 'package:tickety/features/staff/data/i_staff_repository.dart';
import 'package:tickety/features/staff/data/i_ticket_repository.dart';

/// Mock implementation of EventRepository for testing.
class MockEventRepository extends Mock implements EventRepository {}

/// Mock implementation of IStaffRepository for testing.
class MockStaffRepository extends Mock implements IStaffRepository {}

/// Mock implementation of ITicketRepository for testing.
class MockTicketRepository extends Mock implements ITicketRepository {}

/// Mock implementation of IPaymentRepository for testing.
class MockPaymentRepository extends Mock implements IPaymentRepository {}
