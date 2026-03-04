/// Represents the ADA balance of a Cardano wallet.
class CardanoBalance {
  /// Balance in lovelace (1 ADA = 1,000,000 lovelace).
  final int lovelace;

  /// Native assets held at this address.
  final List<CardanoAsset> assets;

  const CardanoBalance({
    required this.lovelace,
    this.assets = const [],
  });

  const CardanoBalance.zero()
      : lovelace = 0,
        assets = const [];

  /// Balance in ADA (decimal).
  double get ada => lovelace / 1000000;

  /// Formatted ADA string (e.g. "125.50 ADA").
  String get formattedAda {
    final value = ada;
    // Show up to 6 decimal places, trimming trailing zeros
    if (value == value.truncateToDouble()) {
      return '${value.toStringAsFixed(0)} ADA';
    }
    // Show 2 decimal places for readability
    return '${value.toStringAsFixed(2)} ADA';
  }

  /// Whether the wallet has any ADA.
  bool get hasFunds => lovelace > 0;

  /// Parse from Blockfrost `/addresses/{address}` response.
  factory CardanoBalance.fromBlockfrost(Map<String, dynamic> json) {
    // Extract lovelace from amount array
    final amounts = json['amount'] as List<dynamic>? ?? [];
    int lovelaceAmount = 0;
    final assetList = <CardanoAsset>[];

    for (final item in amounts) {
      final unit = item['unit'] as String;
      final quantity = int.tryParse(item['quantity'] as String) ?? 0;
      if (unit == 'lovelace') {
        lovelaceAmount = quantity;
      } else {
        // Native asset: unit = policyId + assetNameHex
        final policyId = unit.substring(0, 56);
        final assetNameHex = unit.length > 56 ? unit.substring(56) : '';
        assetList.add(CardanoAsset(
          policyId: policyId,
          assetName: assetNameHex,
          quantity: quantity,
        ));
      }
    }

    return CardanoBalance(
      lovelace: lovelaceAmount,
      assets: assetList,
    );
  }

  @override
  String toString() => 'CardanoBalance($formattedAda)';
}

/// A Cardano native asset (NFT or fungible token).
class CardanoAsset {
  final String policyId;
  final String assetName;
  final int quantity;

  const CardanoAsset({
    required this.policyId,
    required this.assetName,
    required this.quantity,
  });

  /// Human-readable asset name (hex-decoded).
  String get displayName {
    if (assetName.isEmpty) return policyId.substring(0, 8);
    try {
      final bytes = <int>[];
      for (var i = 0; i < assetName.length; i += 2) {
        bytes.add(int.parse(assetName.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return assetName.substring(0, assetName.length.clamp(0, 16));
    }
  }
}
