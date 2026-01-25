import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/utils/validators.dart';

void main() {
  group('Validators.password', () {
    test('rejects empty password', () {
      expect(Validators.password(null), 'Password is required');
      expect(Validators.password(''), 'Password is required');
    });

    test('rejects short password', () {
      expect(Validators.password('Pass1'), 'Password must be at least 8 characters');
    });

    test('rejects password without uppercase', () {
      expect(Validators.password('password1'), 'Must contain an uppercase letter');
    });

    test('rejects password without lowercase', () {
      expect(Validators.password('PASSWORD1'), 'Must contain a lowercase letter');
    });

    test('rejects password without number', () {
      expect(Validators.password('Password'), 'Must contain a number');
    });

    test('accepts valid password', () {
      expect(Validators.password('Password1'), isNull);
      expect(Validators.password('MySecurePass123'), isNull);
      expect(Validators.password('Test1234'), isNull);
    });

    test('rejects overly long password', () {
      final longPassword = '${'A' * 100}${'a' * 30}1';
      expect(Validators.password(longPassword), 'Password is too long');
    });
  });

  group('Validators.walletAddress', () {
    test('rejects empty wallet address', () {
      expect(Validators.walletAddress(null), 'Wallet address is required');
      expect(Validators.walletAddress(''), 'Wallet address is required');
    });

    test('rejects short wallet address', () {
      expect(Validators.walletAddress('addr1abc'), 'Invalid Cardano wallet address');
    });

    test('rejects addresses without proper prefix', () {
      // Must start with addr1 (mainnet) or addr_test1 (testnet)
      expect(
        Validators.walletAddress('notavalidaddress'),
        'Invalid Cardano wallet address',
      );
      expect(
        Validators.walletAddress('addr2qwer1234567890'),
        'Invalid Cardano wallet address',
      );
    });

    test('rejects invalid Bech32 characters (b, i, o, uppercase)', () {
      // Bech32 excludes b, i, o and is lowercase only
      expect(
        Validators.walletAddress('addr1QWER1234567890abcdefghijklmnopqrstuvwxyz12345678901234'),
        'Invalid Cardano wallet address',
      );
    });

    test('accepts valid Cardano mainnet addresses', () {
      // Example valid Cardano mainnet address (addr1...)
      expect(
        Validators.walletAddress(
          'addr1qx2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp',
        ),
        isNull,
      );
      expect(
        Validators.walletAddress(
          'addr1q9h7nx6vpt6le3jt2kc5ssjccrcmqe8074mwfpw8g4cjdk04crd2kwyqk8zs33xyxdu4ss44rfgk8prr3g5gcums4w4skcl3p4',
        ),
        isNull,
      );
    });

    test('accepts valid Cardano testnet addresses', () {
      // Example valid Cardano testnet address (addr_test1...)
      expect(
        Validators.walletAddress(
          'addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwqfjkjv7',
        ),
        isNull,
      );
    });
  });

  group('Validators.sanitize', () {
    test('trims whitespace', () {
      expect(Validators.sanitize('  hello  '), 'hello');
    });

    test('normalizes multiple spaces', () {
      expect(Validators.sanitize('hello    world'), 'hello world');
    });

    test('removes control characters', () {
      expect(Validators.sanitize('hello\x00world'), 'helloworld');
      expect(Validators.sanitize('test\x1Fvalue'), 'testvalue');
    });

    test('removes potential XSS content control chars', () {
      // Script tags still remain as text (sanitize removes control chars, not HTML)
      // HTML escaping should happen at render time
      final input = '<script>alert("xss")</script>';
      // sanitize only removes control chars, not HTML
      expect(Validators.sanitize(input), input);
    });

    test('handles empty string', () {
      expect(Validators.sanitize(''), '');
    });

    test('handles whitespace-only string', () {
      expect(Validators.sanitize('   '), '');
    });
  });

  group('Validators.email', () {
    test('validates email format', () {
      expect(Validators.email('test@example.com'), isNull);
      expect(Validators.email('invalid'), isNotNull);
      expect(Validators.email(''), 'Email is required');
    });
  });

  group('Validators.displayName', () {
    test('rejects potentially malicious characters', () {
      expect(Validators.displayName('<script>'), 'Name contains invalid characters');
      expect(Validators.displayName('test"name'), 'Name contains invalid characters');
      expect(Validators.displayName('test\\name'), 'Name contains invalid characters');
    });

    test('accepts valid names', () {
      expect(Validators.displayName('John Doe'), isNull);
      expect(Validators.displayName('María García'), isNull);
    });
  });
}
