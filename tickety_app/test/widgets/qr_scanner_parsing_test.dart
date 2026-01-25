import 'package:flutter_test/flutter_test.dart';

/// Tests for QR code content parsing logic.
///
/// The QrScannerView widget parses QR codes to extract ticket IDs.
/// This tests the parsing logic extracted from the widget.
void main() {
  group('QR Content Parsing', () {
    group('plain ticket ID', () {
      test('parses UUID ticket ID', () {
        const content = '550e8400-e29b-41d4-a716-446655440000';
        expect(_parseQrContent(content), content);
      });

      test('parses ticket number format', () {
        const content = 'TKT-123456-7890';
        expect(_parseQrContent(content), content);
      });

      test('trims whitespace from plain content', () {
        const content = '  TKT-123456-7890  ';
        expect(_parseQrContent(content), 'TKT-123456-7890');
      });
    });

    group('URL format', () {
      test('extracts ticket ID from URL path', () {
        const content = 'https://tickety.app/ticket/tkt_001';
        expect(_parseQrContent(content), 'tkt_001');
      });

      test('extracts ticket ID from deep URL path', () {
        const content = 'https://tickety.app/events/evt_001/tickets/tkt_002';
        expect(_parseQrContent(content), 'tkt_002');
      });

      test('handles HTTP URLs', () {
        const content = 'http://tickety.app/ticket/tkt_003';
        expect(_parseQrContent(content), 'tkt_003');
      });

      test('handles URLs with query parameters', () {
        const content = 'https://tickety.app/ticket/tkt_004?ref=qr';
        expect(_parseQrContent(content), 'tkt_004');
      });
    });

    group('JSON format', () {
      test('extracts id from JSON object', () {
        const content = '{"id":"tkt_json_001","event_id":"evt_001"}';
        expect(_parseQrContent(content), 'tkt_json_001');
      });

      test('extracts ticket_number from JSON when no id', () {
        const content = '{"ticket_number":"TKT-JSON-1234","event_id":"evt_001"}';
        expect(_parseQrContent(content), 'TKT-JSON-1234');
      });

      test('prefers id over ticket_number in JSON', () {
        const content = '{"id":"tkt_id","ticket_number":"TKT-NUM"}';
        expect(_parseQrContent(content), 'tkt_id');
      });

      test('handles JSON with extra whitespace', () {
        const content = '{ "id" : "tkt_space_001" }';
        expect(_parseQrContent(content), 'tkt_space_001');
      });
    });

    group('edge cases', () {
      test('returns content as-is for unrecognized format', () {
        const content = 'some-random-string-12345';
        expect(_parseQrContent(content), content);
      });

      test('handles empty path URL by returning full URL', () {
        // URL with no path segments
        const content = 'https://tickety.app';
        // Should return the full URL since no path segment
        final result = _parseQrContent(content);
        expect(result, 'https://tickety.app');
      });

      test('handles JSON without id or ticket_number', () {
        const content = '{"event_id":"evt_001","name":"Test"}';
        // Should return original content
        expect(_parseQrContent(content), content);
      });
    });
  });
}

/// Parses QR code content to extract ticket ID or number.
///
/// This is the same logic used in QrScannerView._parseQrContent
String _parseQrContent(String content) {
  // Check if it's a URL
  if (content.startsWith('http')) {
    final uri = Uri.tryParse(content);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      // Return the last path segment (assumed to be ticket ID)
      return uri.pathSegments.last;
    }
    return content;
  }

  // Check if it's JSON with ticket info
  if (content.startsWith('{')) {
    // Simple extraction - look for id or ticket_number
    final idMatch = RegExp(r'"id"\s*:\s*"([^"]+)"').firstMatch(content);
    if (idMatch != null) return idMatch.group(1)!;

    final numberMatch =
        RegExp(r'"ticket_number"\s*:\s*"([^"]+)"').firstMatch(content);
    if (numberMatch != null) return numberMatch.group(1)!;

    // Return original content if no match
    return content;
  }

  // Return as-is (plain ticket ID or number)
  return content.trim();
}
