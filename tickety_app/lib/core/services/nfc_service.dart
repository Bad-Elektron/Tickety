import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_hce/flutter_nfc_hce.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

/// NDEF data format for ticket information.
/// Encodes as URI: `https://tickety.app/scan#{"t":"ticketId","n":"ticketNumber","e":"eventId"}`
class TicketNfcPayload {
  const TicketNfcPayload({
    required this.ticketId,
    required this.ticketNumber,
    required this.eventId,
  });

  final String ticketId;
  final String ticketNumber;
  final String eventId;

  /// Parse from NDEF URI record fragment.
  static TicketNfcPayload? fromUri(String uri) {
    try {
      final hashIndex = uri.indexOf('#');
      if (hashIndex == -1) return null;

      final fragment = uri.substring(hashIndex + 1);
      final json = jsonDecode(fragment) as Map<String, dynamic>;

      return TicketNfcPayload(
        ticketId: json['t'] as String,
        ticketNumber: json['n'] as String,
        eventId: json['e'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// Encode to NDEF URI format.
  String toUri() {
    final json = jsonEncode({'t': ticketId, 'n': ticketNumber, 'e': eventId});
    return 'https://tickety.app/scan#$json';
  }
}

/// Service for NFC operations (reading tickets as usher, broadcasting as attendee).
///
/// Platform behavior:
/// - Android: Full support for reading and broadcasting (HCE)
/// - iOS: Reading only (Apple restricts HCE)
/// - Web/Desktop: NFC not available
class NfcService {
  NfcService._();

  static final NfcService instance = NfcService._();

  bool _isReading = false;
  bool _isBroadcasting = false;
  final FlutterNfcHce _hce = FlutterNfcHce();

  /// Check if NFC is available on this device.
  Future<bool> isNfcAvailable() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return false;
    }
    try {
      final availability = await NfcManager.instance.checkAvailability();
      return availability == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  /// Check if HCE (Host Card Emulation) is available for broadcasting.
  /// Only available on Android.
  Future<bool> isHceAvailable() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    // HCE is available on Android 4.4+ (API 19+), which Flutter requires anyway
    // Check if NFC is available first
    return await isNfcAvailable();
  }

  /// Whether reading is currently active.
  bool get isReading => _isReading;

  /// Whether broadcasting is currently active.
  bool get isBroadcasting => _isBroadcasting;

  /// Start reading NFC tags.
  ///
  /// [onTagRead] is called with the parsed ticket payload when a valid ticket tag is scanned.
  /// [onError] is called if scanning fails or an invalid tag is detected.
  Future<void> startReading({
    required void Function(TicketNfcPayload payload) onTagRead,
    void Function(String error)? onError,
  }) async {
    if (_isReading) return;

    if (!await isNfcAvailable()) {
      onError?.call('NFC is not available on this device');
      return;
    }

    _isReading = true;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            onError?.call('Tag does not contain NDEF data');
            return;
          }

          try {
            final cachedMessage = ndef.cachedMessage;
            if (cachedMessage == null) {
              onError?.call('No NDEF message found');
              return;
            }

            final payload = _parseNdefMessage(cachedMessage);

            if (payload != null) {
              onTagRead(payload);
            } else {
              onError?.call('Invalid ticket data');
            }
          } catch (e) {
            onError?.call('Error reading tag: $e');
          }
        },
      );
    } catch (e) {
      _isReading = false;
      onError?.call('Failed to start NFC scanning: $e');
    }
  }

  /// Stop reading NFC tags.
  Future<void> stopReading() async {
    if (!_isReading) return;

    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // Ignore errors when stopping
    } finally {
      _isReading = false;
    }
  }

  /// Start broadcasting ticket data via NFC HCE (Android only).
  ///
  /// Returns true if broadcasting started successfully.
  Future<bool> startBroadcasting(TicketNfcPayload payload) async {
    if (_isBroadcasting) return true;

    if (!await isHceAvailable()) {
      return false;
    }

    try {
      await _hce.startNfcHce(payload.toUri());
      _isBroadcasting = true;
      return true;
    } catch (e) {
      debugPrint('Failed to start NFC broadcasting: $e');
      return false;
    }
  }

  /// Stop broadcasting NFC data.
  Future<void> stopBroadcasting() async {
    if (!_isBroadcasting) return;

    try {
      await _hce.stopNfcHce();
    } catch (_) {
      // Ignore errors when stopping
    } finally {
      _isBroadcasting = false;
    }
  }

  /// Parse NDEF message to extract ticket payload.
  TicketNfcPayload? _parseNdefMessage(NdefMessage message) {
    for (final record in message.records) {
      // Try to extract URI from the record
      final uri = _extractUriFromRecord(record);
      if (uri != null && uri.contains('tickety.app/scan')) {
        return TicketNfcPayload.fromUri(uri);
      }
    }
    return null;
  }

  /// Extract URI from an NDEF record.
  String? _extractUriFromRecord(NdefRecord record) {
    // Check for URI record type (TNF = well-known, type = 'U')
    if (record.typeNameFormat == TypeNameFormat.wellKnown) {
      final typeStr = utf8.decode(record.type);

      if (typeStr == 'U') {
        // URI record
        return _decodeUriRecord(record);
      } else if (typeStr == 'T') {
        // Text record - might contain URI
        return _decodeTextRecord(record);
      }
    }

    // Try to decode payload as UTF-8 text as fallback
    try {
      final text = utf8.decode(record.payload);
      if (text.contains('tickety.app/scan')) {
        return text;
      }
    } catch (_) {
      // Not valid UTF-8
    }

    return null;
  }

  /// Decode URI record payload.
  String? _decodeUriRecord(NdefRecord record) {
    if (record.payload.isEmpty) return null;

    final prefixCode = record.payload[0];
    final uriData = record.payload.sublist(1);

    const prefixes = [
      '',
      'http://www.',
      'https://www.',
      'http://',
      'https://',
      'tel:',
      'mailto:',
      'ftp://anonymous:anonymous@',
      'ftp://ftp.',
      'ftps://',
      'sftp://',
      'smb://',
      'nfs://',
      'ftp://',
      'dav://',
      'news:',
      'telnet://',
      'imap:',
      'rtsp://',
      'urn:',
      'pop:',
      'sip:',
      'sips:',
      'tftp:',
      'btspp://',
      'btl2cap://',
      'btgoep://',
      'tcpobex://',
      'irdaobex://',
      'file://',
      'urn:epc:id:',
      'urn:epc:tag:',
      'urn:epc:pat:',
      'urn:epc:raw:',
      'urn:epc:',
      'urn:nfc:',
    ];

    final prefix = prefixCode < prefixes.length ? prefixes[prefixCode] : '';
    return prefix + utf8.decode(uriData);
  }

  /// Decode text record payload.
  String? _decodeTextRecord(NdefRecord record) {
    if (record.payload.isEmpty) return null;

    final languageCodeLength = record.payload[0] & 0x3F;
    if (record.payload.length <= languageCodeLength + 1) return null;

    return utf8.decode(record.payload.sublist(languageCodeLength + 1));
  }
}
