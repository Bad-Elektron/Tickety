/// A CIP-68 NFT ticket held in the user's Cardano wallet.
class NftTicket {
  final String policyId;
  final String assetName;
  final String assetId;
  final String? initialMintTxHash;
  final int quantity;

  // CIP-68 metadata (from on-chain datum or Blockfrost)
  final String? name;
  final String? eventTitle;
  final String? eventId;
  final String? ticketNumber;
  final String? ticketId;
  final String? eventDate;
  final String? venue;

  const NftTicket({
    required this.policyId,
    required this.assetName,
    required this.assetId,
    this.initialMintTxHash,
    this.quantity = 1,
    this.name,
    this.eventTitle,
    this.eventId,
    this.ticketNumber,
    this.ticketId,
    this.eventDate,
    this.venue,
  });

  /// Parse from Blockfrost `/assets/{asset}` response.
  factory NftTicket.fromBlockfrost(Map<String, dynamic> json) {
    final policyId = json['policy_id'] as String? ?? '';
    final assetNameHex = json['asset_name'] as String? ?? '';
    final initialMintTxHash = json['initial_mint_tx_hash'] as String?;
    final quantity = int.tryParse(json['quantity']?.toString() ?? '1') ?? 1;

    // Try to parse on-chain metadata
    final onchainMetadata = json['onchain_metadata'] as Map<String, dynamic>?;
    final metadata = json['metadata'] as Map<String, dynamic>?;

    return NftTicket(
      policyId: policyId,
      assetName: assetNameHex,
      assetId: policyId + assetNameHex,
      initialMintTxHash: initialMintTxHash,
      quantity: quantity,
      name: onchainMetadata?['name'] as String? ??
          metadata?['name'] as String?,
      eventTitle: onchainMetadata?['event'] as String?,
      eventId: onchainMetadata?['event_id'] as String?,
      ticketNumber: onchainMetadata?['ticket_number'] as String?,
      ticketId: onchainMetadata?['ticket_id'] as String?,
      eventDate: onchainMetadata?['event_date'] as String?,
      venue: onchainMetadata?['venue'] as String?,
    );
  }

  /// The display name, falling back to a shortened asset name.
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    // Decode hex asset name (skip CIP-68 label prefix)
    final nameWithoutLabel =
        assetName.length > 8 ? assetName.substring(8) : assetName;
    try {
      final bytes = <int>[];
      for (var i = 0; i < nameWithoutLabel.length; i += 2) {
        bytes.add(int.parse(nameWithoutLabel.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return assetId.length > 20
          ? '${assetId.substring(0, 10)}...${assetId.substring(assetId.length - 10)}'
          : assetId;
    }
  }

  /// URL to view this asset on CardanoScan (Preview testnet).
  String get cardanoScanUrl =>
      'https://preview.cardanoscan.io/token/$assetId';

  /// URL to view the mint transaction on CardanoScan.
  String? get mintTxUrl => initialMintTxHash != null
      ? 'https://preview.cardanoscan.io/transaction/$initialMintTxHash'
      : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NftTicket && other.assetId == assetId;

  @override
  int get hashCode => assetId.hashCode;
}
