// 3-tier verification model for offline check-in.

enum VerificationTier { nfcPayload, offline, blockchain, database }

enum TierStatus { pending, verifying, verified, failed, skipped }

/// Result of a single verification tier.
class TierResult {
  final TierStatus status;
  final String? message;

  const TierResult({required this.status, this.message});

  TierResult copyWith({TierStatus? status, String? message}) {
    return TierResult(
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

/// Entry in the local door list cache.
class DoorListEntry {
  final String ticketId;
  final String ticketNumber;
  final String eventId;
  String status; // 'valid', 'used', 'cancelled', 'refunded'
  final String? ownerName;
  final String? ownerEmail;
  final String? nftAssetId;
  final String? nftPolicyId;
  final String? nftTxHash;
  final String? seatLabel;
  final String category;
  final String? itemIcon;
  String? checkedInAt;
  String? checkedInBy;
  final String updatedAt;

  DoorListEntry({
    required this.ticketId,
    required this.ticketNumber,
    required this.eventId,
    required this.status,
    this.ownerName,
    this.ownerEmail,
    this.nftAssetId,
    this.nftPolicyId,
    this.nftTxHash,
    this.seatLabel,
    this.category = 'entry',
    this.itemIcon,
    this.checkedInAt,
    this.checkedInBy,
    required this.updatedAt,
  });

  bool get isValid => status == 'valid';
  bool get isUsed => status == 'used';
  bool get isCancelled => status == 'cancelled';
  bool get isRefunded => status == 'refunded';
  bool get hasNft => nftAssetId != null && nftAssetId!.isNotEmpty;
  bool get isRedeemable => category == 'redeemable';

  Map<String, dynamic> toMap() {
    return {
      'ticket_id': ticketId,
      'ticket_number': ticketNumber,
      'event_id': eventId,
      'status': status,
      'owner_name': ownerName,
      'owner_email': ownerEmail,
      'nft_asset_id': nftAssetId,
      'nft_policy_id': nftPolicyId,
      'nft_tx_hash': nftTxHash,
      'seat_label': seatLabel,
      'category': category,
      'item_icon': itemIcon,
      'checked_in_at': checkedInAt,
      'checked_in_by': checkedInBy,
      'updated_at': updatedAt,
    };
  }

  factory DoorListEntry.fromMap(Map<String, dynamic> map) {
    return DoorListEntry(
      ticketId: map['ticket_id'] as String,
      ticketNumber: map['ticket_number'] as String,
      eventId: map['event_id'] as String,
      status: map['status'] as String? ?? 'valid',
      ownerName: map['owner_name'] as String?,
      ownerEmail: map['owner_email'] as String?,
      nftAssetId: map['nft_asset_id'] as String?,
      nftPolicyId: map['nft_policy_id'] as String?,
      nftTxHash: map['nft_tx_hash'] as String?,
      seatLabel: map['seat_label'] as String?,
      category: map['category'] as String? ?? 'entry',
      itemIcon: map['item_icon'] as String?,
      checkedInAt: map['checked_in_at'] as String?,
      checkedInBy: map['checked_in_by'] as String?,
      updatedAt: map['updated_at'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
    );
  }
}

/// Sync queue entry for pending check-in/undo operations.
class SyncQueueEntry {
  final int? id;
  final String ticketId;
  final String eventId;
  final String action; // 'check_in' or 'undo_check_in'
  final String usherId;
  final String timestamp;
  final bool synced;
  final int retryCount;
  final String? errorMessage;

  const SyncQueueEntry({
    this.id,
    required this.ticketId,
    required this.eventId,
    required this.action,
    required this.usherId,
    required this.timestamp,
    this.synced = false,
    this.retryCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'ticket_id': ticketId,
      'event_id': eventId,
      'action': action,
      'usher_id': usherId,
      'timestamp': timestamp,
      'synced': synced ? 1 : 0,
      'retry_count': retryCount,
      'error_message': errorMessage,
    };
  }

  factory SyncQueueEntry.fromMap(Map<String, dynamic> map) {
    return SyncQueueEntry(
      id: map['id'] as int?,
      ticketId: map['ticket_id'] as String,
      eventId: map['event_id'] as String,
      action: map['action'] as String,
      usherId: map['usher_id'] as String,
      timestamp: map['timestamp'] as String,
      synced: (map['synced'] as int? ?? 0) == 1,
      retryCount: map['retry_count'] as int? ?? 0,
      errorMessage: map['error_message'] as String?,
    );
  }
}

/// Result of blockchain NFT verification.
enum BlockchainVerifyStatus { verified, notFound, ownerMismatch, skipped, error }

class BlockchainVerifyResult {
  final BlockchainVerifyStatus status;
  final String? message;

  const BlockchainVerifyResult({required this.status, this.message});
}

/// Aggregated result of the 3-tier verification pipeline.
class VerificationResult {
  final Map<VerificationTier, TierResult> tiers;
  final DoorListEntry? ticket;
  final bool isAdmittable;

  const VerificationResult({
    required this.tiers,
    this.ticket,
    required this.isAdmittable,
  });

  TierResult getTier(VerificationTier tier) =>
      tiers[tier] ?? const TierResult(status: TierStatus.pending);

  VerificationResult updateTier(VerificationTier tier, TierResult result) {
    return VerificationResult(
      tiers: {...tiers, tier: result},
      ticket: ticket,
      isAdmittable: isAdmittable,
    );
  }

  factory VerificationResult.initial() {
    return const VerificationResult(
      tiers: {
        VerificationTier.nfcPayload: TierResult(status: TierStatus.pending),
        VerificationTier.offline: TierResult(status: TierStatus.pending),
        VerificationTier.blockchain: TierResult(status: TierStatus.pending),
        VerificationTier.database: TierResult(status: TierStatus.pending),
      },
      isAdmittable: false,
    );
  }
}
