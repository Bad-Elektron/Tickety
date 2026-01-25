import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/staff/data/i_ticket_repository.dart';

void main() {
  group('TicketStats', () {
    test('creates with required values', () {
      const stats = TicketStats(
        totalSold: 100,
        checkedIn: 50,
        totalRevenueCents: 500000,
      );

      expect(stats.totalSold, 100);
      expect(stats.checkedIn, 50);
      expect(stats.totalRevenueCents, 500000);
    });

    group('remaining', () {
      test('calculates correctly', () {
        const stats = TicketStats(
          totalSold: 100,
          checkedIn: 40,
          totalRevenueCents: 0,
        );

        expect(stats.remaining, 60);
      });

      test('returns zero when all checked in', () {
        const stats = TicketStats(
          totalSold: 50,
          checkedIn: 50,
          totalRevenueCents: 0,
        );

        expect(stats.remaining, 0);
      });

      test('returns total when none checked in', () {
        const stats = TicketStats(
          totalSold: 100,
          checkedIn: 0,
          totalRevenueCents: 0,
        );

        expect(stats.remaining, 100);
      });
    });

    group('formattedRevenue', () {
      test('formats whole dollars correctly', () {
        const stats = TicketStats(
          totalSold: 10,
          checkedIn: 0,
          totalRevenueCents: 10000, // $100.00
        );

        expect(stats.formattedRevenue, '\$100.00');
      });

      test('formats with cents correctly', () {
        const stats = TicketStats(
          totalSold: 10,
          checkedIn: 0,
          totalRevenueCents: 12345, // $123.45
        );

        expect(stats.formattedRevenue, '\$123.45');
      });

      test('formats zero revenue', () {
        const stats = TicketStats(
          totalSold: 0,
          checkedIn: 0,
          totalRevenueCents: 0,
        );

        expect(stats.formattedRevenue, '\$0.00');
      });

      test('formats large revenue', () {
        const stats = TicketStats(
          totalSold: 1000,
          checkedIn: 0,
          totalRevenueCents: 1000000, // $10,000.00
        );

        expect(stats.formattedRevenue, '\$10000.00');
      });
    });

    group('checkInRate', () {
      test('calculates percentage correctly', () {
        const stats = TicketStats(
          totalSold: 100,
          checkedIn: 25,
          totalRevenueCents: 0,
        );

        expect(stats.checkInRate, 0.25);
      });

      test('returns 0 when no tickets sold', () {
        const stats = TicketStats(
          totalSold: 0,
          checkedIn: 0,
          totalRevenueCents: 0,
        );

        expect(stats.checkInRate, 0);
      });

      test('returns 1.0 when all checked in', () {
        const stats = TicketStats(
          totalSold: 50,
          checkedIn: 50,
          totalRevenueCents: 0,
        );

        expect(stats.checkInRate, 1.0);
      });

      test('handles fractional rates', () {
        const stats = TicketStats(
          totalSold: 3,
          checkedIn: 1,
          totalRevenueCents: 0,
        );

        expect(stats.checkInRate, closeTo(0.333, 0.01));
      });
    });

    group('checkInPercentage', () {
      test('formats whole percentages', () {
        const stats = TicketStats(
          totalSold: 100,
          checkedIn: 75,
          totalRevenueCents: 0,
        );

        expect(stats.checkInPercentage, '75%');
      });

      test('formats 0%', () {
        const stats = TicketStats(
          totalSold: 100,
          checkedIn: 0,
          totalRevenueCents: 0,
        );

        expect(stats.checkInPercentage, '0%');
      });

      test('formats 100%', () {
        const stats = TicketStats(
          totalSold: 100,
          checkedIn: 100,
          totalRevenueCents: 0,
        );

        expect(stats.checkInPercentage, '100%');
      });

      test('rounds fractional percentages', () {
        const stats = TicketStats(
          totalSold: 3,
          checkedIn: 1,
          totalRevenueCents: 0,
        );

        // 33.33...% rounds to 33%
        expect(stats.checkInPercentage, '33%');
      });

      test('handles zero total sold', () {
        const stats = TicketStats(
          totalSold: 0,
          checkedIn: 0,
          totalRevenueCents: 0,
        );

        expect(stats.checkInPercentage, '0%');
      });
    });

    group('edge cases', () {
      test('handles very large numbers', () {
        const stats = TicketStats(
          totalSold: 1000000,
          checkedIn: 500000,
          totalRevenueCents: 99999999,
        );

        expect(stats.remaining, 500000);
        expect(stats.checkInRate, 0.5);
        expect(stats.formattedRevenue, '\$999999.99');
      });

      test('handles typical event stats', () {
        const stats = TicketStats(
          totalSold: 250,
          checkedIn: 187,
          totalRevenueCents: 1875000, // $18,750.00
        );

        expect(stats.remaining, 63);
        expect(stats.checkInRate, closeTo(0.748, 0.01));
        expect(stats.checkInPercentage, '75%');
        expect(stats.formattedRevenue, '\$18750.00');
      });
    });
  });
}
