import 'package:flutter_test/flutter_test.dart';

/// Tests for NFC NDEF record parsing logic.
///
/// The NfcTapView widget parses NDEF records to extract ticket IDs.
/// This tests the parsing logic extracted from the widget.
void main() {
  group('NFC URI Prefix Parsing', () {
    test('returns empty string for code 0x00', () {
      expect(_getUriPrefix(0x00), '');
    });

    test('returns http://www. for code 0x01', () {
      expect(_getUriPrefix(0x01), 'http://www.');
    });

    test('returns https://www. for code 0x02', () {
      expect(_getUriPrefix(0x02), 'https://www.');
    });

    test('returns http:// for code 0x03', () {
      expect(_getUriPrefix(0x03), 'http://');
    });

    test('returns https:// for code 0x04', () {
      expect(_getUriPrefix(0x04), 'https://');
    });

    test('returns empty string for unknown code', () {
      expect(_getUriPrefix(0xFF), '');
    });
  });

  group('Ticket ID Extraction from URI', () {
    test('extracts ID from path', () {
      const uri = 'https://tickety.app/ticket/tkt_001';
      expect(_extractTicketIdFromUri(uri), 'tkt_001');
    });

    test('extracts last path segment', () {
      const uri = 'https://tickety.app/events/evt_001/tickets/tkt_002';
      expect(_extractTicketIdFromUri(uri), 'tkt_002');
    });

    test('extracts ID from ticket query param when no path', () {
      // URL with no meaningful path - just root
      const uri = 'https://tickety.app?ticket=tkt_query_001';
      expect(_extractTicketIdFromUri(uri), 'tkt_query_001');
    });

    test('extracts ID from id query param when no path', () {
      const uri = 'https://tickety.app?id=tkt_id_001';
      expect(_extractTicketIdFromUri(uri), 'tkt_id_001');
    });

    test('prefers path over query params', () {
      const uri = 'https://tickety.app/ticket/tkt_path?id=tkt_query';
      expect(_extractTicketIdFromUri(uri), 'tkt_path');
    });

    test('returns original URI for malformed URL', () {
      const uri = 'not-a-valid-uri';
      expect(_extractTicketIdFromUri(uri), uri);
    });

    test('returns URI for URL without path or params', () {
      const uri = 'https://tickety.app';
      // Uri.parse gives empty pathSegments for domain-only
      final result = _extractTicketIdFromUri(uri);
      expect(result, uri);
    });
  });

  group('NDEF Text Record Parsing', () {
    test('extracts text from simple record', () {
      // Text record: [lang code length | lang code | text]
      // "en" language, text "TKT-123-4567"
      final payload = [
        0x02, // Language code length (2 bytes for "en")
        0x65, 0x6E, // "en" in ASCII
        // "TKT-123-4567" in ASCII
        0x54, 0x4B, 0x54, 0x2D, 0x31, 0x32, 0x33, 0x2D, 0x34, 0x35, 0x36, 0x37,
      ];

      final text = _parseTextRecord(payload);
      expect(text, 'TKT-123-4567');
    });

    test('handles empty payload', () {
      final text = _parseTextRecord([]);
      expect(text, isNull);
    });

    test('handles payload with only language code', () {
      // Just language code length and code, no text
      final payload = [0x02, 0x65, 0x6E];
      final text = _parseTextRecord(payload);
      expect(text, '');
    });

    test('handles different language codes', () {
      // "de" language (German), text "TICKET"
      final payload = [
        0x02, // Language code length
        0x64, 0x65, // "de" in ASCII
        0x54, 0x49, 0x43, 0x4B, 0x45, 0x54, // "TICKET"
      ];

      final text = _parseTextRecord(payload);
      expect(text, 'TICKET');
    });

    test('handles UTF-8 bit flag', () {
      // The first byte also contains a UTF-8 flag in the high bit
      // 0x82 = UTF-8 flag (0x80) | language code length 2
      final payload = [
        0x82, // UTF-8 flag + 2 byte lang code
        0x65, 0x6E, // "en"
        0x54, 0x4B, 0x54, // "TKT"
      ];

      // The & 0x3F masks out the flag
      final text = _parseTextRecordWithFlag(payload);
      expect(text, 'TKT');
    });
  });

  group('NDEF URI Record Parsing', () {
    test('parses URI with https:// prefix', () {
      // URI record: [prefix code | URI without prefix]
      final payload = [
        0x04, // https:// prefix
        // "tickety.app/ticket/tkt_001" in ASCII
        ...('tickety.app/ticket/tkt_001'.codeUnits),
      ];

      final uri = _parseUriRecord(payload);
      expect(uri, 'https://tickety.app/ticket/tkt_001');
    });

    test('parses URI with http://www. prefix', () {
      final payload = [
        0x01, // http://www. prefix
        ...('example.com/tkt'.codeUnits),
      ];

      final uri = _parseUriRecord(payload);
      expect(uri, 'http://www.example.com/tkt');
    });

    test('parses URI with no prefix', () {
      final payload = [
        0x00, // No prefix
        ...('custom://app/tkt'.codeUnits),
      ];

      final uri = _parseUriRecord(payload);
      expect(uri, 'custom://app/tkt');
    });

    test('handles empty URI payload', () {
      final uri = _parseUriRecord([]);
      expect(uri, '');
    });

    test('handles single byte payload', () {
      final payload = [0x04]; // Just prefix, no URI
      final uri = _parseUriRecord(payload);
      expect(uri, 'https://');
    });
  });
}

/// Gets URI prefix from NDEF URI record prefix code.
String _getUriPrefix(int code) {
  const prefixes = {
    0x00: '',
    0x01: 'http://www.',
    0x02: 'https://www.',
    0x03: 'http://',
    0x04: 'https://',
  };
  return prefixes[code] ?? '';
}

/// Extracts ticket ID from a URI string.
String? _extractTicketIdFromUri(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return uri;

  // Look for ticket ID in path
  if (parsed.pathSegments.isNotEmpty) {
    return parsed.pathSegments.last;
  }

  // Look for ticket ID in query params
  return parsed.queryParameters['ticket'] ??
      parsed.queryParameters['id'] ??
      uri;
}

/// Parses text from NDEF text record payload.
String? _parseTextRecord(List<int> payload) {
  if (payload.isEmpty) return null;

  // First byte indicates language code length
  final langCodeLength = payload[0] & 0x3F;
  if (payload.length <= langCodeLength + 1) {
    // Not enough bytes for text
    return payload.length > langCodeLength + 1
        ? String.fromCharCodes(payload.sublist(langCodeLength + 1))
        : '';
  }

  // Rest is the text
  return String.fromCharCodes(payload.sublist(langCodeLength + 1));
}

/// Parses text from NDEF text record with UTF-8 flag handling.
String? _parseTextRecordWithFlag(List<int> payload) {
  if (payload.isEmpty) return null;

  // First byte: bit 7 = UTF-8 flag, bits 5-0 = language code length
  final langCodeLength = payload[0] & 0x3F;
  if (payload.length <= langCodeLength + 1) return '';

  return String.fromCharCodes(payload.sublist(langCodeLength + 1));
}

/// Parses URI from NDEF URI record payload.
String _parseUriRecord(List<int> payload) {
  if (payload.isEmpty) return '';

  // First byte is URI prefix identifier
  final uriPrefix = _getUriPrefix(payload[0]);
  if (payload.length == 1) return uriPrefix;

  return uriPrefix + String.fromCharCodes(payload.sublist(1));
}
