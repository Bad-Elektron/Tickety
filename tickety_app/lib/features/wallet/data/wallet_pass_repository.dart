import 'dart:convert';

import '../../../core/errors/errors.dart';
import '../../../core/services/supabase_service.dart';
import '../models/wallet_pass.dart';

/// Repository for wallet pass operations (Apple Wallet & Google Wallet).
class WalletPassRepository {
  final _client = SupabaseService.instance.client;

  /// Safely parse response.data into a Map, handling String/null cases.
  Map<String, dynamic>? _parseResponse(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return null;
  }

  /// Get existing wallet pass for a ticket and type.
  Future<WalletPass?> getPassForTicket(String ticketId, WalletPassType passType) async {
    final response = await _client
        .from('wallet_passes')
        .select()
        .eq('ticket_id', ticketId)
        .eq('pass_type', passType.value)
        .maybeSingle();

    if (response == null) return null;
    return WalletPass.fromJson(response);
  }

  /// Generate a wallet pass for the given ticket and type.
  /// Returns the pass with a URL to add to the native wallet.
  Future<WalletPass> generatePass(String ticketId, WalletPassType passType) async {
    final response = await _client.functions.invoke(
      'generate-wallet-pass',
      body: {
        'ticket_id': ticketId,
        'pass_type': passType.value,
      },
    );

    final data = _parseResponse(response.data);
    if (response.status != 200 || data == null) {
      throw PaymentException(
        data?['error'] as String? ??
            'Failed to generate wallet pass (status=${response.status})',
      );
    }

    final passData = data['pass'] as Map<String, dynamic>?;
    if (passData == null) {
      throw PaymentException('Invalid response: missing pass data');
    }

    return WalletPass.fromJson(passData);
  }
}
