import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/env_config.dart';

/// REST client for the Blockfrost Cardano API (Preview testnet).
///
/// Follows the same pattern as [GooglePlacesService]: injectable
/// HTTP client, project_id header on every request.
class BlockfrostService {
  static const _baseUrl = 'https://cardano-preview.blockfrost.io/api/v0';

  final http.Client _client;

  BlockfrostService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'project_id': EnvConfig.blockfrostProjectId,
        'Content-Type': 'application/json',
      };

  /// GET `/addresses/{address}` → lovelace balance + asset list.
  Future<Map<String, dynamic>?> getAddressInfo(String address) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/addresses/$address'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET `/addresses/{address}/utxos` → UTxO list for tx building.
  Future<List<Map<String, dynamic>>> getAddressUtxos(String address) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/addresses/$address/utxos'),
      headers: _headers,
    );
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// GET `/addresses/{address}/transactions` → tx hash list (paginated).
  Future<List<Map<String, dynamic>>> getAddressTransactions(
    String address, {
    int page = 1,
    int count = 20,
    String order = 'desc',
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$_baseUrl/addresses/$address/transactions'
        '?page=$page&count=$count&order=$order',
      ),
      headers: _headers,
    );
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// GET `/txs/{hash}` → full transaction info.
  Future<Map<String, dynamic>> getTransactionDetails(String txHash) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/txs/$txHash'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET `/txs/{hash}/utxos` → inputs/outputs for direction detection.
  Future<Map<String, dynamic>> getTransactionUtxos(String txHash) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/txs/$txHash/utxos'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// POST `/tx/submit` with `application/cbor` body.
  Future<String> submitTransaction(Uint8List cborBytes) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/tx/submit'),
      headers: {
        'project_id': EnvConfig.blockfrostProjectId,
        'Content-Type': 'application/cbor',
      },
      body: cborBytes,
    );
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    // Returns the tx hash as a JSON string
    return jsonDecode(response.body) as String;
  }

  /// GET `/epochs/latest/parameters` → protocol parameters for fee calc.
  Future<Map<String, dynamic>> getProtocolParameters() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/epochs/latest/parameters'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET `/blocks/latest` → latest block info (for TTL calculation).
  Future<Map<String, dynamic>> getLatestBlock() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/blocks/latest'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET `/addresses/{address}/assets` → native assets at this address.
  Future<List<Map<String, dynamic>>> getAddressAssets(String address) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/addresses/$address/assets'),
      headers: _headers,
    );
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// GET `/assets/{asset}` → asset info (policy, name, metadata, mint tx).
  Future<Map<String, dynamic>?> getAssetInfo(String unit) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/assets/$unit'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET `/assets/{asset}/transactions` → transaction list for this asset.
  Future<List<Map<String, dynamic>>> getAssetTransactions(
    String unit, {
    int page = 1,
    int count = 20,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$_baseUrl/assets/$unit/transactions'
        '?page=$page&count=$count&order=desc',
      ),
      headers: _headers,
    );
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw BlockfrostException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  void dispose() {
    _client.close();
  }
}

/// Exception from a Blockfrost API error.
class BlockfrostException implements Exception {
  final int statusCode;
  final String body;

  const BlockfrostException(this.statusCode, this.body);

  @override
  String toString() => 'BlockfrostException($statusCode): $body';
}
