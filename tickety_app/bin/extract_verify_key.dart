// Extract verify key from the signing key stored in PLATFORM_CARDANO_SIGNING_KEY
// Run: dart run bin/extract_verify_key.dart <signing_key_hex>

import 'dart:typed_data';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/extract_verify_key.dart <signing_key_hex>');
    return;
  }

  final signingKeyHex = args[0];
  final signingKeyBytes = Uint8List.fromList([
    for (var i = 0; i < signingKeyHex.length; i += 2)
      int.parse(signingKeyHex.substring(i, i + 2), radix: 16),
  ]);

  print('Signing key length: ${signingKeyBytes.length} bytes');

  // Create signing key from raw bytes
  final signingKey = Bip32SigningKey(signingKeyBytes);
  final verifyKey = signingKey.verifyKey;

  final verifyKeyHex = verifyKey.rawKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  print('VERIFY KEY (hex):');
  print('  $verifyKeyHex');
  print('');
  print('Store as Supabase secret:');
  print('  npx supabase secrets set PLATFORM_CARDANO_VERIFY_KEY=$verifyKeyHex --project-ref hnouslchigcmbiovdbfz');
}
