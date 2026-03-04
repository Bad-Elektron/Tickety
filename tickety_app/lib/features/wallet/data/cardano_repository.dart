import 'dart:typed_data';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/blockfrost_service.dart';
import '../../../core/services/cardano_wallet_service.dart';
import '../models/cardano_balance.dart';
import '../models/cardano_transaction.dart';

/// Orchestrates [BlockfrostService] + [CardanoWalletService] for
/// all Cardano wallet operations.
class CardanoRepository {
  final BlockfrostService _blockfrost;
  final CardanoWalletService _walletService;

  CardanoRepository({
    BlockfrostService? blockfrost,
    CardanoWalletService? walletService,
  })  : _blockfrost = blockfrost ?? BlockfrostService(),
        _walletService = walletService ?? CardanoWalletService();

  // ---------------------------------------------------------------
  // Wallet lifecycle
  // ---------------------------------------------------------------

  Future<bool> hasWallet() => _walletService.hasWallet();

  /// Ensure a wallet exists (local cache → Supabase → generate new).
  /// Returns the bech32 payment address.
  Future<String> ensureWallet() => _walletService.ensureWallet();

  Future<void> deleteWallet() => _walletService.deleteWallet();

  Future<String> getAddress() => _walletService.getAddress();

  // ---------------------------------------------------------------
  // Balance
  // ---------------------------------------------------------------

  /// Fetch live ADA balance from Blockfrost.
  Future<CardanoBalance> getBalance() async {
    try {
      final address = await _walletService.getAddress();
      final info = await _blockfrost.getAddressInfo(address);
      if (info == null) return const CardanoBalance.zero();
      return CardanoBalance.fromBlockfrost(info);
    } on BlockfrostException catch (e) {
      throw CardanoException.networkError(e.toString());
    }
  }

  // ---------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------

  /// Fetch Cardano transaction history (paginated).
  Future<List<CardanoTransaction>> getTransactions({
    int page = 1,
    int count = 20,
  }) async {
    try {
      final address = await _walletService.getAddress();
      final txRefs = await _blockfrost.getAddressTransactions(
        address,
        page: page,
        count: count,
      );

      final transactions = <CardanoTransaction>[];
      for (final ref in txRefs) {
        final hash = ref['tx_hash'] as String;
        // Fetch details and utxos in parallel for each tx
        final results = await Future.wait([
          _blockfrost.getTransactionDetails(hash),
          _blockfrost.getTransactionUtxos(hash),
        ]);
        transactions.add(CardanoTransaction.fromBlockfrost(
          txDetails: results[0],
          txUtxos: results[1],
          ownAddress: address,
        ));
      }
      return transactions;
    } on BlockfrostException catch (e) {
      if (e.statusCode == 404) return [];
      throw CardanoException.networkError(e.toString());
    }
  }

  // ---------------------------------------------------------------
  // Send ADA
  // ---------------------------------------------------------------

  /// Send ADA to another address. Returns the submitted tx hash.
  ///
  /// [toAddress] must be a valid bech32 `addr_test1...` address.
  /// [lovelaceAmount] must be >= 1,000,000 (1 ADA minimum UTxO).
  Future<String> sendAda(String toAddress, int lovelaceAmount) async {
    if (lovelaceAmount < 1000000) {
      throw CardanoException.insufficientFunds();
    }

    try {
      final address = await _walletService.getAddress();

      // 1. Get UTxOs
      final utxos = await _blockfrost.getAddressUtxos(address);
      if (utxos.isEmpty) {
        throw CardanoException.insufficientFunds();
      }

      // 2. Get protocol parameters + latest block for TTL
      final results = await Future.wait([
        _blockfrost.getProtocolParameters(),
        _blockfrost.getLatestBlock(),
      ]);
      final protocolParams = results[0];
      final latestBlock = results[1];

      // 3. Build the transaction
      final unsignedTxHex = _buildSimpleTransferTx(
        utxos: utxos,
        fromAddress: address,
        toAddress: toAddress,
        lovelaceAmount: lovelaceAmount,
        protocolParams: protocolParams,
        currentSlot: latestBlock['slot'] as int,
      );

      // 4. Sign
      final signedTxHex = await _walletService.signTransaction(unsignedTxHex);

      // 5. Submit
      final txBytes = _hexToBytes(signedTxHex);
      final txHash = await _blockfrost.submitTransaction(txBytes);
      return txHash;
    } on CardanoException {
      rethrow;
    } on BlockfrostException catch (e) {
      throw CardanoException.txSubmissionFailed(e.body);
    } catch (e) {
      throw CardanoException.txSubmissionFailed(e.toString());
    }
  }

  // ---------------------------------------------------------------
  // Transaction builder (simple ADA transfer)
  // ---------------------------------------------------------------

  /// Build an unsigned transaction CBOR hex for a simple ADA transfer.
  ///
  /// This builds a minimal Shelley-era transaction:
  /// - Select UTxOs to cover amount + fee
  /// - Single output to recipient
  /// - Change output back to sender
  /// - Fee based on protocol parameters
  String _buildSimpleTransferTx({
    required List<Map<String, dynamic>> utxos,
    required String fromAddress,
    required String toAddress,
    required int lovelaceAmount,
    required Map<String, dynamic> protocolParams,
    required int currentSlot,
  }) {
    final minFeeA = int.parse(protocolParams['min_fee_a'].toString());
    final minFeeB = int.parse(protocolParams['min_fee_b'].toString());

    // TTL: current slot + 7200 (~2 hours)
    final ttl = currentSlot + 7200;

    // Estimate fee (conservative: ~200 bytes * minFeeA + minFeeB)
    // A simple 1-in/2-out tx is typically 200-300 bytes
    final estimatedFee = (300 * minFeeA) + minFeeB;
    final totalNeeded = lovelaceAmount + estimatedFee;

    // Select UTxOs (simple greedy algorithm)
    final selectedUtxos = <Map<String, dynamic>>[];
    int totalInput = 0;
    for (final utxo in utxos) {
      selectedUtxos.add(utxo);
      final amounts = utxo['amount'] as List<dynamic>;
      for (final a in amounts) {
        if (a['unit'] == 'lovelace') {
          totalInput += int.parse(a['quantity'] as String);
        }
      }
      if (totalInput >= totalNeeded) break;
    }

    if (totalInput < totalNeeded) {
      throw CardanoException.insufficientFunds();
    }

    final change = totalInput - lovelaceAmount - estimatedFee;

    // Build CBOR manually using a simple encoder
    final encoder = _CborEncoder();

    // Transaction body map
    final bodyEntries = <int, List<int>>{};

    // 0: inputs (set of [txhash, index])
    final inputsEncoded = <List<int>>[];
    for (final utxo in selectedUtxos) {
      final txHash = _hexToBytes(utxo['tx_hash'] as String);
      final index = utxo['output_index'] as int;
      inputsEncoded.add(encoder.encodeArray([
        encoder.encodeBytes(txHash),
        encoder.encodeUint(index),
      ]));
    }
    bodyEntries[0] = encoder.encodeArray(inputsEncoded);

    // 1: outputs
    final outputsEncoded = <List<int>>[];

    // Output to recipient
    outputsEncoded.add(encoder.encodeArray([
      encoder.encodeBytes(_bech32AddressToBytes(toAddress)),
      encoder.encodeUint(lovelaceAmount),
    ]));

    // Change output (only if change > min UTxO)
    if (change >= 1000000) {
      outputsEncoded.add(encoder.encodeArray([
        encoder.encodeBytes(_bech32AddressToBytes(fromAddress)),
        encoder.encodeUint(change),
      ]));
    }

    bodyEntries[1] = encoder.encodeArray(outputsEncoded);

    // 2: fee
    bodyEntries[2] = encoder.encodeUint(estimatedFee);

    // 3: ttl
    bodyEntries[3] = encoder.encodeUint(ttl);

    final txBody = encoder.encodeMap(bodyEntries);

    // Full unsigned transaction: [body, {}, true, null]
    final unsignedTx = encoder.encodeArray([
      txBody,
      encoder.encodeMap(<int, List<int>>{}), // empty witness set
      [0xf5], // true (valid)
      [0xf6], // null (no auxiliary data)
    ]);

    return _bytesToHex(Uint8List.fromList(unsignedTx));
  }

  /// Decode a bech32 Cardano address to raw bytes.
  ///
  /// Bech32 format: hrp + "1" + data_part
  /// Uses the Bech32 character set to decode data part to 5-bit groups,
  /// then converts to 8-bit bytes (excluding the checksum).
  static Uint8List _bech32AddressToBytes(String bech32) {
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final sepIndex = bech32.lastIndexOf('1');
    if (sepIndex < 1) throw ArgumentError('Invalid bech32 address');

    final dataPart = bech32.substring(sepIndex + 1);
    // Decode characters to 5-bit values
    final data5bit = <int>[];
    for (final c in dataPart.runes) {
      final idx = charset.indexOf(String.fromCharCode(c));
      if (idx < 0) throw ArgumentError('Invalid bech32 character');
      data5bit.add(idx);
    }

    // Remove 6-character checksum
    final payload5bit = data5bit.sublist(0, data5bit.length - 6);

    // Convert from 5-bit to 8-bit groups
    final bytes = <int>[];
    int acc = 0;
    int bits = 0;
    for (final value in payload5bit) {
      acc = (acc << 5) | value;
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        bytes.add((acc >> bits) & 0xff);
      }
    }

    return Uint8List.fromList(bytes);
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Minimal CBOR encoder for building Cardano transactions.
///
/// Supports only the types needed for a simple ADA transfer:
/// unsigned int, byte string, array, and map with int keys.
class _CborEncoder {
  /// Encode a CBOR header (major type + additional info).
  List<int> _encodeHeader(int majorType, int value) {
    final mt = majorType << 5;
    if (value < 24) return [mt | value];
    if (value < 256) return [mt | 24, value];
    if (value < 65536) return [mt | 25, value >> 8, value & 0xff];
    if (value < 4294967296) {
      return [
        mt | 26,
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];
    }
    return [
      mt | 27,
      (value >> 56) & 0xff,
      (value >> 48) & 0xff,
      (value >> 40) & 0xff,
      (value >> 32) & 0xff,
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  /// Encode an unsigned integer (major type 0).
  List<int> encodeUint(int value) => _encodeHeader(0, value);

  /// Encode a byte string (major type 2).
  List<int> encodeBytes(Uint8List bytes) {
    return [..._encodeHeader(2, bytes.length), ...bytes];
  }

  /// Encode an array (major type 4) from pre-encoded items.
  List<int> encodeArray(List<List<int>> items) {
    return [
      ..._encodeHeader(4, items.length),
      ...items.expand((e) => e),
    ];
  }

  /// Encode a map (major type 5) with integer keys and pre-encoded values.
  List<int> encodeMap(Map<int, List<int>> entries) {
    final buffer = <int>[..._encodeHeader(5, entries.length)];
    // CBOR maps should have keys in canonical order
    final sortedKeys = entries.keys.toList()..sort();
    for (final key in sortedKeys) {
      buffer.addAll(encodeUint(key));
      buffer.addAll(entries[key]!);
    }
    return buffer;
  }
}
