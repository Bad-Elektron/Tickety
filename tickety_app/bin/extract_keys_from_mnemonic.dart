// Extract signing key + verify key from mnemonic
// Run: dart run bin/extract_keys_from_mnemonic.dart "word1 word2 word3 ..."

import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:cardano_dart_types/cardano_dart_types.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/extract_keys_from_mnemonic.dart "word1 word2 word3 ..."');
    return;
  }

  final mnemonic = args[0];
  final words = mnemonic.split(' ');
  print('Words: ${words.length}');

  final wallet = await WalletFactory.fromMnemonic(
    NetworkId.testnet,
    words,
  );

  final addrKit = await wallet.getPaymentAddressKit(addressIndex: 0);
  final address = addrKit.address.bech32Encoded;

  final signingKeyHex = addrKit.signingKey.rawKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final verifyKeyHex = addrKit.verifyKey.rawKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  print('');
  print('ADDRESS: $address');
  print('');
  print('SIGNING KEY (hex):');
  print('  $signingKeyHex');
  print('');
  print('VERIFY KEY (hex):');
  print('  $verifyKeyHex');
  print('');
  print('Run this to store the verify key:');
  print('  npx supabase secrets set PLATFORM_CARDANO_VERIFY_KEY=$verifyKeyHex --project-ref hnouslchigcmbiovdbfz');
}
