// Run with: dart run scripts/check_stripe_setup.dart
// This script checks if Stripe is properly configured

import 'dart:io';

void main() async {
  print('🔍 Checking Stripe Payment Setup...\n');

  // Check .env file
  final envFile = File('tickety_app/.env');
  if (!envFile.existsSync()) {
    print('❌ .env file not found');
    exit(1);
  }

  final envContent = envFile.readAsStringSync();

  // Check Stripe publishable key
  if (envContent.contains('pk_test_your_publishable_key_here')) {
    print('❌ STRIPE_PUBLISHABLE_KEY is still the placeholder value');
    print('   → Get your test key from https://dashboard.stripe.com/test/apikeys');
  } else if (envContent.contains('pk_test_')) {
    print('✅ STRIPE_PUBLISHABLE_KEY is set (test mode)');
  } else if (envContent.contains('pk_live_')) {
    print('⚠️  STRIPE_PUBLISHABLE_KEY is set to LIVE mode - use test key for development');
  } else {
    print('❌ STRIPE_PUBLISHABLE_KEY not found in .env');
  }

  // Check for required files
  final requiredFiles = [
    'tickety_app/lib/core/services/stripe_service.dart',
    'tickety_app/lib/features/payments/data/payment_repository.dart',
    'tickety_app/lib/features/payments/presentation/checkout_screen.dart',
    'supabase/functions/create-payment-intent/index.ts',
    'supabase/functions/stripe-webhook/index.ts',
  ];

  print('\n📁 Checking required files:');
  for (final path in requiredFiles) {
    if (File(path).existsSync()) {
      print('   ✅ $path');
    } else {
      print('   ❌ $path (missing)');
    }
  }

  // Check migrations
  print('\n📊 Database migrations:');
  final migrationsDir = Directory('supabase/migrations');
  if (migrationsDir.existsSync()) {
    final migrations = migrationsDir.listSync().whereType<File>().toList();
    for (final migration in migrations) {
      final name = migration.path.split(Platform.pathSeparator).last;
      if (name.contains('payment') || name.contains('resale')) {
        print('   ✅ $name');
      }
    }
  } else {
    print('   ⚠️  No migrations directory found');
  }

  // Check Edge Functions
  print('\n⚡ Edge Functions:');
  final functionsDir = Directory('supabase/functions');
  if (functionsDir.existsSync()) {
    final functions = functionsDir.listSync().whereType<Directory>().toList();
    final paymentFunctions = [
      'create-payment-intent',
      'stripe-webhook',
      'process-refund',
      'create-connect-account',
      'connect-webhook',
      'create-resale-intent',
    ];

    for (final fn in paymentFunctions) {
      final exists = functions.any((d) => d.path.endsWith(fn));
      print('   ${exists ? "✅" : "❌"} $fn');
    }
  }

  print('\n📝 Next steps:');
  print('   1. Get Stripe test keys from dashboard.stripe.com');
  print('   2. Update .env with your pk_test_xxx key');
  print('   3. Add sk_test_xxx to Supabase Edge Function secrets');
  print('   4. Run: supabase db push (to apply migrations)');
  print('   5. Run: supabase functions deploy (to deploy edge functions)');
  print('   6. Set up webhook endpoints in Stripe dashboard');
  print('   7. Run: stripe listen --forward-to <your-webhook-url>');

  print('\n✨ Setup check complete!\n');
}
