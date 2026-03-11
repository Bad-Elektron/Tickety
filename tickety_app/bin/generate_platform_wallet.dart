// One-time script to generate the platform minting wallet.
//
// Run from tickety_app/:
//   dart run bin/generate_platform_wallet.dart
//
// Outputs:
//   1. 24-word mnemonic (store offline, never on a server)
//   2. Signing key hex (store as server secret)
//   3. Address (fund from Cardano Preview Faucet)
//
// Delete this script after use.

import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:cardano_dart_types/cardano_dart_types.dart';

Future<void> main() async {
  print('');
  print('=' * 60);
  print('  Tickety Platform Minting Wallet Generator');
  print('  Network: Cardano Preview Testnet');
  print('=' * 60);
  print('');

  // 1. Generate mnemonic
  final mnemonic = bip39.generateMnemonic(strength: 256); // 24 words
  print('MNEMONIC (24 words) — write down and store OFFLINE:');
  print('');
  final words = mnemonic.split(' ');
  for (var i = 0; i < words.length; i += 6) {
    final end = (i + 6 > words.length) ? words.length : i + 6;
    final line = words
        .sublist(i, end)
        .asMap()
        .entries
        .map((e) =>
            '${(i + e.key + 1).toString().padLeft(2)}. ${e.value.padRight(12)}')
        .join('');
    print('  $line');
  }
  print('');

  // 2. Derive wallet using the same SDK the app uses
  final wallet = await WalletFactory.fromMnemonic(
    NetworkId.testnet,
    words,
  );

  // 3. Get payment address
  final addrKit = await wallet.getPaymentAddressKit(addressIndex: 0);
  final address = addrKit.address.bech32Encoded;

  // 4. Get signing key bytes from the address kit
  final signingKey = addrKit.signingKey;
  final signingKeyHex = signingKey.rawKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final verifyKeyHex = addrKit.verifyKey.rawKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  print('SIGNING KEY (hex) — store as server secret:');
  print('  $signingKeyHex');
  print('');
  print('VERIFY KEY / PUBLIC KEY (hex):');
  print('  $verifyKeyHex');
  print('');
  print('ADDRESS (fund this from the Cardano Preview Faucet):');
  print('  $address');
  print('');

  print('=' * 60);
  print('  NEXT STEPS:');
  print('  1. Store the mnemonic safely offline (paper/password manager)');
  print('  2. Add signing key as your edge function secret:');
  print('     PLATFORM_CARDANO_SIGNING_KEY = $signingKeyHex');
  print('  3. Fund the address from:');
  print('     https://docs.cardano.org/cardano-testnets/tools/faucet/');
  print('  4. Insert address into platform_cardano_config table:');
  print("     INSERT INTO platform_cardano_config (key, value)");
  print("     VALUES ('minting_address', '$address');");
  print('  5. Delete this script!');
  print('=' * 60);
  print('');
}
