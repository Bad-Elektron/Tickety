/// Direction of a Cardano transaction relative to our wallet.
enum CardanoTxDirection { sent, received }

/// A Cardano blockchain transaction.
class CardanoTransaction {
  final String txHash;
  final int lovelaceAmount;
  final int feesLovelace;
  final DateTime timestamp;
  final String? counterpartyAddress;
  final CardanoTxDirection direction;
  final int blockHeight;

  const CardanoTransaction({
    required this.txHash,
    required this.lovelaceAmount,
    required this.feesLovelace,
    required this.timestamp,
    this.counterpartyAddress,
    required this.direction,
    required this.blockHeight,
  });

  /// Amount in ADA.
  double get adaAmount => lovelaceAmount / 1000000;

  /// Fee in ADA.
  double get adaFee => feesLovelace / 1000000;

  /// Formatted amount with direction sign (e.g. "+1.50 ADA" or "-2.00 ADA").
  String get formattedAmount {
    final sign = direction == CardanoTxDirection.received ? '+' : '-';
    return '$sign${adaAmount.toStringAsFixed(2)} ADA';
  }

  /// Formatted fee (e.g. "0.17 ADA").
  String get formattedFee => '${adaFee.toStringAsFixed(6)} ADA';

  /// Truncated tx hash for display (e.g. "abc123...def456").
  String get shortTxHash {
    if (txHash.length <= 16) return txHash;
    return '${txHash.substring(0, 8)}...${txHash.substring(txHash.length - 8)}';
  }

  /// Truncated counterparty address for display.
  String get shortCounterparty {
    final addr = counterpartyAddress ?? 'Unknown';
    if (addr.length <= 20) return addr;
    return '${addr.substring(0, 12)}...${addr.substring(addr.length - 8)}';
  }

  /// Build from Blockfrost tx details + utxo info.
  ///
  /// [txDetails] from `/txs/{hash}`
  /// [txUtxos] from `/txs/{hash}/utxos`
  /// [ownAddress] to determine direction and counterparty
  factory CardanoTransaction.fromBlockfrost({
    required Map<String, dynamic> txDetails,
    required Map<String, dynamic> txUtxos,
    required String ownAddress,
  }) {
    final hash = txDetails['hash'] as String;
    final fees = int.tryParse(txDetails['fees'] as String? ?? '0') ?? 0;
    final blockHeight = txDetails['block_height'] as int? ?? 0;
    final blockTime = txDetails['block_time'] as int? ?? 0;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(blockTime * 1000);

    // Determine direction by checking if our address is in inputs
    final inputs = (txUtxos['inputs'] as List<dynamic>?) ?? [];
    final outputs = (txUtxos['outputs'] as List<dynamic>?) ?? [];

    final isFromUs =
        inputs.any((i) => (i['address'] as String?) == ownAddress);

    String? counterparty;
    int lovelaceAmount = 0;

    if (isFromUs) {
      // We sent: find the output(s) NOT to us
      for (final output in outputs) {
        final addr = output['address'] as String?;
        if (addr != null && addr != ownAddress) {
          counterparty = addr;
          final amounts = output['amount'] as List<dynamic>? ?? [];
          for (final a in amounts) {
            if (a['unit'] == 'lovelace') {
              lovelaceAmount += int.tryParse(a['quantity'] as String) ?? 0;
            }
          }
        }
      }
    } else {
      // We received: find the output(s) TO us
      for (final output in outputs) {
        final addr = output['address'] as String?;
        if (addr == ownAddress) {
          final amounts = output['amount'] as List<dynamic>? ?? [];
          for (final a in amounts) {
            if (a['unit'] == 'lovelace') {
              lovelaceAmount += int.tryParse(a['quantity'] as String) ?? 0;
            }
          }
        }
      }
      // Counterparty is the first input address that isn't us
      for (final input in inputs) {
        final addr = input['address'] as String?;
        if (addr != null && addr != ownAddress) {
          counterparty = addr;
          break;
        }
      }
    }

    return CardanoTransaction(
      txHash: hash,
      lovelaceAmount: lovelaceAmount,
      feesLovelace: fees,
      timestamp: timestamp,
      counterpartyAddress: counterparty,
      direction: isFromUs ? CardanoTxDirection.sent : CardanoTxDirection.received,
      blockHeight: blockHeight,
    );
  }
}
