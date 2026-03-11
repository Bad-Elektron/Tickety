import '../errors/errors.dart';
import '../models/verification_result.dart';
import 'blockfrost_service.dart';

const _tag = 'BlockchainVerifyService';

/// Verifies NFT ticket ownership on the Cardano blockchain.
///
/// For NFT-enabled tickets, checks that the asset exists on-chain
/// via Blockfrost. Skips gracefully for non-NFT tickets.
class BlockchainVerifyService {
  final BlockfrostService _blockfrost;

  BlockchainVerifyService({BlockfrostService? blockfrost})
      : _blockfrost = blockfrost ?? BlockfrostService();

  /// Verify NFT ownership for a door list entry.
  ///
  /// Returns [BlockchainVerifyResult] with status:
  /// - `verified` if asset exists on-chain
  /// - `notFound` if asset doesn't exist
  /// - `skipped` if ticket has no NFT
  /// - `error` on API failure (non-blocking)
  Future<BlockchainVerifyResult> verifyNftOwnership(DoorListEntry entry) async {
    if (!entry.hasNft) {
      return const BlockchainVerifyResult(
        status: BlockchainVerifyStatus.skipped,
        message: 'Not an NFT ticket',
      );
    }

    try {
      AppLogger.debug(
        'Verifying NFT: ${entry.nftAssetId}',
        tag: _tag,
      );

      final assetInfo = await _blockfrost.getAssetInfo(entry.nftAssetId!);

      if (assetInfo == null) {
        AppLogger.debug(
          'NFT asset not found on chain: ${entry.nftAssetId}',
          tag: _tag,
        );
        return const BlockchainVerifyResult(
          status: BlockchainVerifyStatus.notFound,
          message: 'NFT asset not found on blockchain',
        );
      }

      AppLogger.debug(
        'NFT verified on chain: ${entry.nftAssetId}',
        tag: _tag,
      );
      return const BlockchainVerifyResult(
        status: BlockchainVerifyStatus.verified,
        message: 'NFT ownership confirmed',
      );
    } on BlockfrostException catch (e) {
      AppLogger.error(
        'Blockfrost error during NFT verification',
        error: e,
        tag: _tag,
      );
      return BlockchainVerifyResult(
        status: BlockchainVerifyStatus.error,
        message: 'Blockchain check failed: ${e.statusCode}',
      );
    } catch (e) {
      AppLogger.error(
        'Unexpected error during NFT verification',
        error: e,
        tag: _tag,
      );
      return BlockchainVerifyResult(
        status: BlockchainVerifyStatus.error,
        message: 'Blockchain check unavailable',
      );
    }
  }
}
