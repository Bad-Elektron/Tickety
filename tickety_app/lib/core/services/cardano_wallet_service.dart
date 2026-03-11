import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local Cardano HD wallet manager with Supabase sync.
///
/// Uses [cardano_flutter_sdk] for BIP32-ED25519 key derivation,
/// [flutter_secure_storage] as local cache, and [Supabase] `user_wallets`
/// table for cross-device sync. Private keys are derived client-side only.
class CardanoWalletService {
  // Storage keys are scoped by user ID to prevent cross-user wallet leaks
  static const _mnemonicKeyPrefix = 'cardano_mnemonic_';
  static const _addressCacheKeyPrefix = 'cardano_address_cache_';
  // Legacy keys (pre-fix) — checked once for migration, then deleted
  static const _legacyMnemonicKey = 'cardano_mnemonic';
  static const _legacyAddressCacheKey = 'cardano_address_cache';

  final FlutterSecureStorage _storage;
  String? _cachedAddress;

  CardanoWalletService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  String get _userId {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) throw StateError('No authenticated user');
    return id;
  }

  String get _mnemonicKey => '$_mnemonicKeyPrefix$_userId';
  String get _addressCacheKey => '$_addressCacheKeyPrefix$_userId';

  /// Ensure a wallet exists. Creates one if needed.
  ///
  /// Resolution order:
  /// 1. Local secure storage (scoped by user ID)
  /// 2. Migrate from legacy unscoped key (one-time)
  /// 3. Supabase `user_wallets` table (cross-device restore)
  /// 4. Generate new wallet (first time)
  ///
  /// Returns the bech32 payment address.
  Future<String> ensureWallet() async {
    // 1. Check user-scoped local cache
    final localMnemonic = await _storage.read(key: _mnemonicKey);
    if (localMnemonic != null && localMnemonic.isNotEmpty) {
      return getAddress();
    }

    // 2. Check Supabase (authoritative per-user data)
    final remote = await _fetchFromSupabase();
    if (remote != null) {
      // Cache locally under user-scoped key
      await _storage.write(key: _mnemonicKey, value: remote.mnemonic);
      await _storage.write(key: _addressCacheKey, value: remote.address);
      _cachedAddress = remote.address;
      // Clean up legacy keys if they exist
      await _cleanupLegacyKeys();
      return remote.address;
    }

    // 3. Generate new wallet
    final mnemonic = bip39.generateMnemonic(strength: 256);
    final address = await _deriveAddress(mnemonic.split(' '));

    // Store locally under user-scoped key
    await _storage.write(key: _mnemonicKey, value: mnemonic);
    await _storage.write(key: _addressCacheKey, value: address);
    _cachedAddress = address;

    // Sync to Supabase
    await _syncToSupabase(mnemonic, address);

    // Clean up legacy keys
    await _cleanupLegacyKeys();

    return address;
  }

  /// Whether a wallet exists locally for the current user.
  Future<bool> hasWallet() async {
    final mnemonic = await _storage.read(key: _mnemonicKey);
    return mnemonic != null && mnemonic.isNotEmpty;
  }

  /// Get the wallet's bech32 payment address.
  Future<String> getAddress() async {
    // Return cached
    if (_cachedAddress != null) return _cachedAddress!;

    // Try reading from cache
    final cached = await _storage.read(key: _addressCacheKey);
    if (cached != null && cached.isNotEmpty) {
      _cachedAddress = cached;
      return cached;
    }

    // Derive from mnemonic
    final mnemonic = await _storage.read(key: _mnemonicKey);
    if (mnemonic == null || mnemonic.isEmpty) {
      throw StateError('No wallet found');
    }

    final address = await _deriveAddress(mnemonic.split(' '));
    await _storage.write(key: _addressCacheKey, value: address);
    _cachedAddress = address;
    return address;
  }

  /// Sign a transaction and return the signed CBOR hex string.
  ///
  /// [unsignedTxHex] is the CBOR-encoded unsigned transaction as hex.
  Future<String> signTransaction(String unsignedTxHex) async {
    final mnemonic = await _storage.read(key: _mnemonicKey);
    if (mnemonic == null || mnemonic.isEmpty) {
      throw StateError('No wallet found');
    }

    final wallet = await WalletFactory.fromMnemonic(
      NetworkId.testnet,
      mnemonic.split(' '),
    );

    final tx = CardanoTransaction.deserializeFromHex(unsignedTxHex);
    final address = await getAddress();

    final witnessSet = await wallet.signTransaction(
      tx: tx,
      witnessBech32Addresses: {address},
    );

    final signedTx = tx.copyWithAdditionalSignatures(witnessSet);
    return signedTx.serializeHexString();
  }

  /// Delete the wallet from secure storage for the current user.
  Future<void> deleteWallet() async {
    await _storage.delete(key: _mnemonicKey);
    await _storage.delete(key: _addressCacheKey);
    _cachedAddress = null;
  }

  /// Clear in-memory cache (call on logout so next user gets fresh state).
  void clearCache() {
    _cachedAddress = null;
  }

  /// Remove legacy unscoped storage keys from before the per-user fix.
  Future<void> _cleanupLegacyKeys() async {
    try {
      await _storage.delete(key: _legacyMnemonicKey);
      await _storage.delete(key: _legacyAddressCacheKey);
    } catch (_) {}
  }

  // ---------------------------------------------------------------
  // Supabase sync
  // ---------------------------------------------------------------

  /// Upsert wallet data to Supabase `user_wallets` table.
  Future<void> _syncToSupabase(String mnemonic, String address) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('user_wallets').upsert({
        'user_id': userId,
        'mnemonic': mnemonic,
        'cardano_address': address,
        'network': 'preview',
      }, onConflict: 'user_id');
    } catch (_) {
      // Non-fatal: wallet still works locally even if sync fails
    }
  }

  /// Fetch wallet data from Supabase `user_wallets` table.
  Future<({String mnemonic, String address})?> _fetchFromSupabase() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await Supabase.instance.client
          .from('user_wallets')
          .select('mnemonic, cardano_address')
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      return (
        mnemonic: response['mnemonic'] as String,
        address: response['cardano_address'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------

  /// Derive the first payment address from a mnemonic word list.
  /// Uses CIP-1852 derivation path: m/1852'/1815'/0'/0/0
  Future<String> _deriveAddress(List<String> words) async {
    final wallet = await WalletFactory.fromMnemonic(
      NetworkId.testnet,
      words,
    );
    final addrKit = await wallet.getPaymentAddressKit(addressIndex: 0);
    return addrKit.address.bech32Encoded;
  }
}
