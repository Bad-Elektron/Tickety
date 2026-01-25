import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/events/presentation/usher_event_screen.dart';

void main() {
  group('CheckInMode', () {
    test('has correct properties for qrScan', () {
      expect(CheckInMode.qrScan.icon, Icons.qr_code_scanner);
      expect(CheckInMode.qrScan.label, 'Scan QR');
      expect(CheckInMode.qrScan.shortLabel, 'QR');
    });

    test('has correct properties for nfcTap', () {
      expect(CheckInMode.nfcTap.icon, Icons.nfc_rounded);
      expect(CheckInMode.nfcTap.label, 'Tap NFC');
      expect(CheckInMode.nfcTap.shortLabel, 'NFC');
    });

    test('has correct properties for manual', () {
      expect(CheckInMode.manual.icon, Icons.keyboard_alt_outlined);
      expect(CheckInMode.manual.label, 'Manual');
      expect(CheckInMode.manual.shortLabel, 'Manual');
    });

    test('has all three modes', () {
      expect(CheckInMode.values, hasLength(3));
      expect(CheckInMode.values, contains(CheckInMode.qrScan));
      expect(CheckInMode.values, contains(CheckInMode.nfcTap));
      expect(CheckInMode.values, contains(CheckInMode.manual));
    });
  });

  group('CheckInMode enum values', () {
    test('qrScan has index 0', () {
      expect(CheckInMode.qrScan.index, 0);
    });

    test('nfcTap has index 1', () {
      expect(CheckInMode.nfcTap.index, 1);
    });

    test('manual has index 2', () {
      expect(CheckInMode.manual.index, 2);
    });
  });
}
