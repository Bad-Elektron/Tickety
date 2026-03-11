// Derive verify key from mnemonic.
// Run from tickety_app/:
//   dart run bin/derive_verify_key.dart "word1 word2 word3 ... word24"

import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:cardano_dart_types/cardano_dart_types.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/derive_verify_key.dart "word1 word2 ... word24"');
    return;
  }

  final words = args[0].split(' ');
  if (words.length != 24) {
    print('Error: expected 24 words, got ${words.length}');
    return;
  }

  final wallet = await WalletFactory.fromMnemonic(
    NetworkId.testnet,
    words,
  );

  final addrKit = await wallet.getPaymentAddressKit(addressIndex: 0);

  final verifyKeyHex = addrKit.verifyKey.rawKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  print('VERIFY KEY: $verifyKeyHex');
}
