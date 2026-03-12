# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tickety is a Flutter-based event discovery application targeting Android, iOS, Web, Windows, Linux, and macOS. It uses Dart 3.10.7+ with Material Design 3.

## Development Principles

**UX and code quality/architecture are paramount.** The application will have several processes that need to be secure and scalable. When making changes:

- Prioritize user experience in all UI/interaction decisions
- Maintain clean architecture boundaries between layers
- Write secure code—validate inputs, handle sensitive data appropriately
- Design for scalability—avoid tight coupling, use proper state management patterns
- Keep performance in mind, especially for animations and graphics rendering

## Common Gotchas

- **Bottom sheet context after pop:** When a method in a bottom sheet's State calls `Navigator.pop()`, the sheet's `context` and `ref` become invalid. Capture `Navigator.of(context)`, `ScaffoldMessenger.of(context)`, and any `ref.read()` values *before* popping.
- **Immutable widget state after DB writes:** `widget.event` doesn't update after `linkVenue()` or similar writes. Use local state (e.g., `_linkedVenueId`) and a getter like `_effectiveVenueId` to reflect changes immediately.
- **Canvas coordinate spaces:** In `InteractiveViewer`/`Transform`-wrapped canvases, hit-test coordinates must be inverse-transformed (`_screenToCanvas()`) — raw `details.localPosition` is screen space, not canvas space.
- **Edge function variable scoping:** `let` declarations inside `if/else` blocks are block-scoped in TypeScript. Variables referenced later (e.g., `validatedPromoId`) must be hoisted to the outer scope.
- **Android emulator storage:** If the emulator data partition is >85% full, `flutter run` may force-uninstall → reinstall, wiping auth sessions. Increase AVD internal storage in Device Manager and wipe data to apply.
- **Edge function deployment:** After modifying edge functions, they must be deployed with `npx supabase functions deploy <name> --no-verify-jwt`. Code changes are not live until deployed.

## Development Commands

All commands should be run from the `tickety_app/` directory.

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run                    # Default connected device
flutter run -d chrome          # Web (Chrome)
flutter run -d windows         # Windows desktop

# Run tests
flutter test                   # All tests
flutter test test/widget_test.dart  # Single test file

# Static analysis
flutter analyze

# Build
flutter build apk              # Android APK
flutter build ios              # iOS
flutter build web              # Web
flutter build windows          # Windows
```

## Architecture

The app follows a clean architecture pattern with feature-based organization:

```
tickety_app/lib/
├── main.dart              # App entry point, theme config, root widget
├── core/                  # Core utilities shared across features
│   ├── graphics/          # Perlin noise generation & canvas painting
│   └── input/             # Input handling utilities
├── features/              # Feature modules (vertical slices)
│   └── events/            # Events feature
│       ├── models/        # Data models (EventModel)
│       ├── presentation/  # Screens (EventsHomeScreen)
│       └── widgets/       # Feature-specific widgets
└── shared/                # Reusable widgets across features
    └── widgets/           # NoiseBackground, etc.
```

### Key Components

- **NoiseGenerator** (`core/graphics/noise_generator.dart`): Perlin noise implementation with preset configurations (vibrantEvents, sunset, ocean, subtle, darkMood)
- **EventModel** (`features/events/models/event_model.dart`): Immutable event data class with placeholder data for development
- **EventBannerCarousel**: PageView-based carousel with spring physics and dot indicators
- **EventsHomeScreen**: Main screen with "Discover" header, featured carousel, and upcoming events list

### Theme Configuration

- Material 3 enabled
- Color seed: `#6366F1` (Indigo)
- Light theme: white background
- Dark theme: `#121212` background
- System-aware dark/light mode switching

### Library Exports

Each module uses a library file (e.g., `events.dart`, `widgets.dart`) for clean exports. Import the library file rather than individual files.

## TODO

### Pagination Implementation

All repository methods that fetch user-specific lists are now paginated for scalability.

**Completed (using `PaginatedResult<T>` with `.range()`):**
- `getEventPayments()` in `payment_repository.dart` - Returns `PaginatedResult<Payment>`
- `getUpcomingEvents()` in `supabase_event_repository.dart` - Returns `PaginatedResult<EventModel>`
- `getMyPayments()` in `payment_repository.dart` - Returns `PaginatedResult<Payment>` (25 per page)
- `getEventListings()` in `resale_repository.dart` - Returns `PaginatedResult<ResaleListing>` (20 per page)
- `getMyTickets()` in `ticket_repository.dart` - Returns `PaginatedResult<Ticket>` (20 per page)
- `getMyEvents()` in `supabase_event_repository.dart` - Returns `PaginatedResult<EventModel>` (20 per page)
- `getMyStaffEvents()` in `staff_repository.dart` - Returns `PaginatedResult<Map>` (20 per page)
- `getMyListings()` in `resale_repository.dart` - Returns `PaginatedResult<ResaleListing>` (20 per page)
- `EventsProvider` - Supports `loadMore()` with infinite scroll on home screen
- `PaymentHistoryProvider` - Supports `loadMore()` for user payment history
- `MyTicketsNotifier` - Supports `loadMore()` for user's purchased tickets
- `MyEventsNotifier` - Supports `loadMore()` for organizer's events

**Deleted (unused):**
- `getActiveListings()` - Removed, was never used in UI

**Optimized with SQL COUNT:**
- `getResaleListingCount(eventId)` in `resale_repository.dart` - Returns count without fetching records

**Already optimized (using SQL aggregation):**
- `getTicketStats()` - Uses `get_ticket_stats()` RPC function
- `getEventAnalytics()` - Uses `get_event_analytics()` RPC function

**Implementation approach used:**
- Supabase `.range(from, to)` for offset-based pagination
- `page` and `pageSize` parameters on repository methods
- Return `PaginatedResult<T>` from `core/models/paginated_result.dart`
- Fetch `pageSize + 1` items and check length to determine `hasMore`
- Provider state includes `isLoadingMore`, `hasMore`, `currentPage` fields
- `loadMore()` method on notifiers for infinite scroll UI pattern

### Seller Wallet System (Completed)

Sellers can now list tickets for resale without requiring full Stripe onboarding upfront. Funds are held in their Stripe Express account until they add bank details to withdraw.

**Architecture:**
- Stripe holds funds (not Tickety) - avoids Money Transmitter License requirements
- Minimal Stripe Express account created on first listing attempt
- Bank details only required when seller wants to withdraw

**Database:**
- `seller_balances` table caches Stripe balance info (available/pending cents, payouts_enabled)
- Migration: `20260131000002_create_seller_balances.sql`

**Edge Functions (all use `stripe@14.21.0`):**
- `create-seller-account` - Creates minimal Stripe Express account (email only)
- `get-seller-balance` - Fetches balance from Stripe API, caches in DB
- `initiate-withdrawal` - Returns onboarding URL if bank not set up, or creates payout
- `create-resale-intent` - Uses `on_behalf_of` pattern (funds stay in seller's Stripe balance)
- `create-payment-intent` - Primary ticket purchases
- `create-connect-account` - Full Stripe Connect Express setup (legacy)
- `verify-subscription` - Verifies subscription status with Stripe
- `create-subscription-checkout` - Creates subscription checkout sessions
- `stripe-webhook` - Handles payment and subscription events
- `connect-webhook` - Handles Connect account events
- `process-refund` - Processes refunds via Stripe

**RLS Policies:**
- `20260131000003_fix_resale_listing_rls.sql` - Fixes ticket ownership check for resale listings (uses `sold_by` instead of `owner_email`)

**Flutter:**
- `seller_balance_provider.dart` - Manages seller balance state
- `wallet_screen.dart` - Shows Stripe Balance + Crypto Balance (ADA placeholder), separate "Add Bank Details" and "Withdraw" buttons
- `resale_repository.dart` - Wallet methods (hasSellerAccount, createSellerAccount, getSellerBalance, initiateWithdrawal)

**Stripe Test Mode Values:**
- Verification codes: `000000`
- SSN: `000-00-0000`
- Bank routing: `110000000`
- Bank account: `000123456789`

**Important:** Uses `https://esm.sh/stripe@14.21.0` import (not `@13.10.0?target=deno`) for Supabase Edge Runtime compatibility.

### Favor Ticket System (Completed)

Organizers can send comp/gift tickets to anyone by email. Uses a two-phase lifecycle: offer is created (pending), then recipient accepts/pays to claim.

**Ticket Modes:**
- `private` - Off-chain, database only, cannot be resold. Best for personal comps.
- `public` - On-chain NFT (future), tradeable/resaleable on marketplace.
- `standard` - Existing tickets (unchanged, resale allowed).

**Pricing Rules:**
- Private free ($0): Recipient just accepts, no cost.
- Private paid ($X): Recipient must pay $X to claim.
- Public free ($0): Suggest ~$1 minting fee. Recipient can pay (stays public) or skip (downgraded to private).
- Public paid ($X): Recipient pays $X.

**Database:**
- `ticket_offers` table: offers with status lifecycle (pending → accepted/declined/cancelled/expired)
- `ticket_mode` column added to `tickets` table (standard/private/public)
- `offer_id` FK on `tickets` linking back to the offer
- Trigger `block_private_ticket_resale` prevents private tickets from being listed on `resale_listings`
- Trigger `notify_ticket_offer_created` creates notification for registered recipients on offer insert
- Trigger `check_pending_offers_on_signup` links pending offers and notifies when new users register
- Migrations: `20260213000001` through `20260213000006`

**RLS Notes:**
- Recipient policies use `auth.jwt() ->> 'email'` (not `SELECT FROM auth.users`) since the `authenticated` role cannot query `auth.users` directly.
- Trigger functions use `profiles` table for email lookups (same reason). `SECURITY DEFINER` alone is not enough for `auth.users` access in Supabase hosted.

**Edge Functions:**
- `claim-favor-offer` - Claims free offers, handles public→private downgrade when skipping minting fee
- `stripe-webhook` - Extended to handle `favor_ticket_purchase` payment type
- `create-payment-intent` - Extended to accept `favor_ticket_purchase` type

**Flutter:**
- `favor_tickets/models/ticket_offer.dart` - TicketOffer model, TicketOfferStatus enum, TicketMode enum
- `favor_tickets/data/favor_ticket_repository.dart` - CRUD for offers, claim/decline/cancel
- `favor_tickets/presentation/create_favor_ticket_screen.dart` - Organizer form (email, price, mode, message)
- `favor_tickets/presentation/favor_ticket_offer_screen.dart` - Recipient view with accept/pay/decline
- `core/providers/favor_ticket_provider.dart` - PendingOffersNotifier, repository provider
- `ticket.dart` - Added `ticketMode` field and `canBeResold` computed property
- `notification_model.dart` - Added `favorTicketOffer` type with `offerId` getter
- `payment.dart` - Added `favorTicketPurchase` payment type
- `admin_event_screen.dart` - Added "Favor Tickets" action card
- `resale_repository.dart` - Blocks private ticket resale listings
- `ticket_screen.dart` - Uses `canBeResold` for sell button visibility

### Stripe Webhooks Setup (Production)

Set up Stripe webhooks to handle subscription and identity lifecycle events:

1. Go to **Stripe Dashboard → Developers → Webhooks**
2. Add endpoint: `https://hnouslchigcmbiovdbfz.supabase.co/functions/v1/stripe-webhook`
3. Select events:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `identity.verification_session.verified`
   - `identity.verification_session.requires_input`
4. Copy the webhook signing secret
5. Add to Supabase: **Project Settings → Edge Functions → Secrets** as `STRIPE_WEBHOOK_SECRET`

This enables:
- Subscription renewals
- Failed payment retries
- Cancellations from Stripe dashboard
- Plan changes from billing portal
- Identity verification status updates (auto-approve events on verification)

### Organizer Verification & Event Security (Completed)

Organizers must verify their identity via Stripe Identity to create events with 250+ capacity. Unverified large events are auto-held for admin review.

**Database:**
- `profiles` table: `identity_verification_status` (none/pending/verified/failed), `identity_verified_at`, `stripe_identity_session_id`, `payout_delay_days` (14 → 2 on verification)
- `events` table: `status` (active/pending_review/suspended), `status_reason`
- `event_reports` table: user-submitted reports (impersonation/scam/inappropriate/duplicate/other)
- `auto_hold_unverified_large_events` trigger: auto-sets `pending_review` on events with 250+ capacity from unverified organizers
- `find_similar_events()` SQL function: pg_trgm-based similarity detection
- Feature flags: `organizer_verification`, `event_similarity_check`, `event_reporting`
- Migration: `20260228100001_organizer_verification_system.sql`

**Edge Functions:**
- `create-identity-verification` - Creates Stripe Identity VerificationSession (document + selfie)
- `stripe-webhook` - Extended with `identity.verification_session.verified` and `.requires_input` handlers; auto-approves pending events on verification

**Flutter:**
- `EventModel` - Added `organizerName`, `organizerHandle`, `organizerVerified`, `status`, `statusReason`
- `EventMapper` - Parses joined `organizer:profiles` data
- `SupabaseEventRepository` - Queries join organizer profiles; home/featured filter `status = 'active'`; `findSimilarEvents()` and `reportEvent()` methods
- `VerifiedBadge` widget - Indigo checkmark icon, shared across cards and screens
- `EventBannerCard` - Shows "by @handle" with verified badge
- `EventDetailsScreen` - Organizer section with name/handle/verified badge, report event button
- `ReportEventSheet` - Bottom sheet with reason selector and description
- `CreateEventScreen` - Similarity warning banner when similar events found (step 1)
- `AdminEventScreen` - Pending review / suspended status banners
- `VerificationScreen` - Stripe Identity verification flow (profile → get verified)
- `ProfileScreen` - Identity Verification menu item with status indicator

**Admin Panel:**
- Reports page (`/dashboard/reports`) with status management (open → reviewed/resolved/dismissed)
- Event detail page: Approve / Suspend / Reactivate buttons with dialog
- Events table: Status column with color-coded badges
- User detail page: Verification status badge, "Manually Verify" button
- Sidebar: "Reports" nav item added

**Stripe Identity Test Mode:**
- Use test document images from Stripe docs
- Verification completes automatically in test mode

### Google Places Location Integration (Completed)

Events use Google Places Autocomplete for reliable location input with coordinates, replacing the old manual venue/city text fields.

**Approach:** Calls Google Places HTTP API directly (no native SDK) — works on all platforms, no AndroidManifest/iOS changes needed.

**Environment:**
- `GOOGLE_PLACES_API_KEY` in `tickety_app/.env`
- `EnvConfig.googlePlacesApiKey` getter in `core/config/env_config.dart`

**Database:**
- `events` table: `latitude` (DOUBLE PRECISION), `longitude` (DOUBLE PRECISION), `formatted_address` (TEXT) — all nullable for backward compat
- Migration: `20260228200001_add_lat_lng_to_events.sql`

**Service:**
- `GooglePlacesService` (`core/services/google_places_service.dart`) — `getAutocompletePredictions(input)` and `getPlaceDetails(placeId)` via HTTP
- `PlacePrediction` model (placeId, description, mainText, secondaryText)
- `PlaceDetails` model (placeId, formattedAddress, name, lat, lng, city, country)
- Uses `http` package (added to pubspec.yaml)

**Flutter:**
- `PlacesAutocompleteField` (`shared/widgets/places_autocomplete_field.dart`) — Debounced (300ms) search with overlay dropdown
- `EventModel` — Added `latitude`, `longitude`, `formattedAddress` fields + `hasCoordinates` getter + `mapsUrl` getter
- `EventMapper` — Serializes new fields only when non-null (backward compat with DBs without columns); auto-populates legacy `location` from `displayLocation`
- `CreateEventScreen` — Single `PlacesAutocompleteField` replaces venue+city row; stores `PlaceDetails?` in state; passes lat/lng/formattedAddress/venue/city/country to repository
- `EventDetailsScreen` — Location card is tappable when coordinates exist (opens Google Maps via `url_launcher`)
- All screens use `event.displayLocation` (not deprecated `event.location`) — falls back through venue+city → formattedAddress → location

**Important:**
- `displayLocation` fallback chain: venue+city → venue → city → formattedAddress → location
- Legacy `location` column auto-populated from `displayLocation` in `toJson` for backward compat
- Mapper uses `if (value != null)` collection-if for new fields so inserts don't fail on DBs without the columns

### Analytics Consolidation (Completed)

**Completed:**
1. **Unified `get_event_dashboard(event_id)` RPC** — Migration `20260307200001_analytics_consolidation.sql`. Returns tickets + check-ins + engagement in one call. Used by admin event detail API with fallback to legacy `get_event_analytics()`.
2. **Unified cache refresh** — `refresh-analytics` edge function now chains `refresh_engagement_cache()` after main cache refresh. One cron job refreshes everything.
3. **Merged admin Overview + Engagement** — `dashboard/overview/page.tsx` now has Overview | Engagement tabs. Engagement page redirects to overview. Sidebar renamed "Overview" → "Analytics" with `BarChart3` icon.
4. **Flutter analytics engagement** — `PlatformEngagement` model + `getPlatformEngagement()` in analytics repository. Provider loads engagement in parallel with dashboard. Dashboard screen shows Views/Unique/Conversion KPIs, weekly views bar chart, and top events by views.
5. **Dropped `get_ticket_stats()` callers** — `ticket_repository.dart` now calls `get_event_dashboard` RPC and parses the `tickets` section. Legacy `get_ticket_stats` SQL function remains (unused, no harm).

### ACH Direct Bank Payment (Completed)

Users can pay for tickets directly from their linked bank account via ACH at checkout. Tickets are issued immediately; ACH settles in 4-5 business days. If ACH fails, tickets are revoked. Cheaper than card: a $50 ticket costs $52.92 via ACH vs $54.58 via card.

**Replaced the Tickety Wallet system** — no more pre-funding a wallet balance. Users link their bank once, then choose "Bank Transfer" at checkout alongside "Card Payment".

**Database:**
- `linked_bank_accounts` - Cached bank account info (Stripe Financial Connections)
- `wallet_balances`, `wallet_transactions` - Legacy tables (still exist, unused by new flow)
- Migration: `20260301100001_create_wallet_system.sql` (original), `20260308200001_ach_direct_purchase.sql` (adds `ach_purchase` to PaymentType constraint)

**Edge Functions:**
- `create-ach-payment-intent` - Creates ACH PaymentIntent (confirmed server-side), issues tickets immediately. Fees: 5% platform + 0.8% ACH (capped at $5)
- `link-bank-account` - Creates Stripe SetupIntent with Financial Connections for bank linking
- `manage-bank-accounts` - List/save/remove linked bank accounts
- `stripe-webhook` - Extended: ACH purchase settlement on `succeeded` (mark completed), ticket revocation + notification on `failed`
- Legacy: `get-wallet-balance`, `create-wallet-top-up`, `purchase-from-wallet` (still deployed, unused by new UI)

**Flutter Models:**
- `wallet/models/linked_bank_account.dart` - LinkedBankAccount with displayName ("Chase ****1234")
- `payment.dart` - Added `achPurchase` to PaymentType; `ACHPurchaseFeeCalculator` (5% platform + 0.8% ACH capped at $5)

**Flutter Data:**
- `wallet/data/wallet_repository.dart` - `purchaseWithBank()` calls `create-ach-payment-intent`; bank account CRUD methods

**Flutter UI:**
- `wallet_screen.dart` - Crypto Balance + Seller Balance + Linked Banks + Saved Cards (Tickety Wallet card removed)
- `checkout_screen.dart` - Payment method selector (Bank Transfer vs Card) when user has linked bank; shows ACH fee breakdown + savings badge
- `link_bank_screen.dart` - Stripe Financial Connections flow
- `payment_success_screen.dart` - Shows ACH settlement note when `isACH: true`
- `transactions_screen.dart` + `transaction_detail_sheet.dart` - `achPurchase` type with bank icon/label

**ACH Direct Purchase Flow:**
1. User links bank via Stripe Financial Connections (one-time)
2. At checkout, picks "Bank Transfer" → sees lower fee breakdown
3. Edge function creates confirmed ACH PaymentIntent → tickets created immediately → returns success
4. User gets tickets right away, ACH settles in 4-5 business days
5. On settlement success: payment marked completed (tickets already valid)
6. On settlement failure: tickets revoked (status → cancelled), user notified

**No split payments.** ACH covers full amount or user pays full by card.

**Stripe Test Values:** Routing `110000000`, Account `000123456789` (success), `000222222227` (insufficient funds)

### Dev Seed Data (Engagement)

Fake engagement data can be loaded for dashboard development. It is self-contained in two SQL scripts:

**Files:**
- `supabase/seeds/dev_engagement_seed.sql` — Inserts ~1,500-2,500 `event_views` rows using real event/user IDs, refreshes the cache
- `supabase/seeds/cleanup_engagement_seed.sql` — Truncates all engagement tables, removes marker

**How to identify dev data:**
- A marker row in `analytics_cache_meta` with `key = 'dev_seed_marker'` indicates seed data is present
- Query: `SELECT 1 FROM analytics_cache_meta WHERE key = 'dev_seed_marker'`

**How to run:** Paste `dev_engagement_seed.sql` into Supabase SQL Editor and execute. Idempotent — won't double-insert if marker exists.

**How to clean up:** Run `cleanup_engagement_seed.sql` in SQL Editor, or before production: `TRUNCATE event_views, analytics_engagement_daily; DELETE FROM analytics_cache_meta WHERE key = 'dev_seed_marker';`

### Cardano (ADA) Wallet — Phase 1 (Completed)

Auto-created Cardano HD wallet on Preview testnet. Wallet is created transparently on first wallet screen visit — no seed phrase UI. Mnemonic synced to Supabase `user_wallets` table for cross-device restore, cached locally in `flutter_secure_storage`. View ADA balance, receive/send ADA, browse Cardano transaction history. Blockfrost API called directly from Flutter.

**Dependencies:**
- `cardano_flutter_sdk: ^4.0.0` — HD wallet, address derivation, tx signing (pure Dart)
- `cardano_dart_types: ^3.0.0` — Cardano data types and serialization
- `bip39_plus: ^1.1.1` — BIP39 mnemonic generation/validation
- `flutter_secure_storage: ^9.2.4` — Encrypted mnemonic storage (Keychain/Keystore/DPAPI/libsecret)
- `flutter_stripe` upgraded to `^12.3.0` (resolved `freezed_annotation` conflict)

**Environment:**
- `BLOCKFROST_PROJECT_ID` in `tickety_app/.env` (Preview testnet: `previewVA5jY9V686T1apRZItmlqZUf5jOEpNqB`)
- `EnvConfig.blockfrostProjectId` getter in `core/config/env_config.dart`

**Database:**
- `user_wallets` table — Stores mnemonic + cardano_address per user. RLS: users can SELECT/INSERT own row only. Migration: `20260304100001_create_user_wallets.sql`

**Services:**
- `BlockfrostService` (`core/services/blockfrost_service.dart`) — REST client for Cardano Preview testnet API. Methods: getAddressInfo, getAddressUtxos, getAddressTransactions, getTransactionDetails, getTransactionUtxos, submitTransaction, getProtocolParameters, getLatestBlock
- `CardanoWalletService` (`core/services/cardano_wallet_service.dart`) — HD wallet manager with Supabase sync. `ensureWallet()` resolves: local cache → Supabase → generate new. CIP-1852 derivation (m/1852'/1815'/0'/0/0). Keys derived client-side only.

**Models:**
- `wallet/models/cardano_balance.dart` — CardanoBalance (lovelace, assets, ada, formattedAda, hasFunds) + CardanoAsset
- `wallet/models/cardano_transaction.dart` — CardanoTransaction (txHash, lovelaceAmount, fees, timestamp, direction, counterparty) + CardanoTxDirection enum

**Data/Providers:**
- `wallet/data/cardano_repository.dart` — Orchestrates BlockfrostService + CardanoWalletService. Includes minimal CBOR encoder for building simple ADA transfer transactions.
- `core/providers/cardano_wallet_provider.dart` — CardanoWalletNotifier with ensureWallet, loadBalance, loadTransactions, sendAda, refresh, deleteWallet. Convenience providers: cardanoBalanceProvider, cardanoAddressProvider, cardanoHasWalletProvider, cardanoTransactionsProvider

**Errors:**
- `CardanoException` in `core/errors/app_exception.dart` — Factories: walletNotFound, invalidMnemonic, insufficientFunds, txSubmissionFailed, networkError

**UI Screens:**
- `cardano_receive_screen.dart` — QR code + bech32 address + copy/share buttons
- `cardano_send_screen.dart` — Address input (paste + QR scan), amount input with MAX button, fee estimate, confirmation dialog, success screen with CardanoScan link

**Modified Screens:**
- `wallet_screen.dart` — `initState` calls `ensureWallet()` (auto-creates if needed); crypto card always shows balance (loading → ADA amount); Receive/Send buttons visible once wallet ready
- `transactions_screen.dart` — Crypto filter shows Cardano transactions; empty state just says "No Cardano transactions yet"
- `transaction_detail_sheet.dart` — showCardanoTransactionDetailSheet() with direction, amount, fee, addresses, tx hash, CardanoScan link

**Key Design Decisions:**
1. Auto-creation — Wallet created lazily on first wallet screen visit, no user interaction required. No seed phrase backup UI.
2. Supabase sync — Mnemonic stored in `user_wallets` table (RLS-protected). New device login pulls mnemonic from Supabase → caches locally → same address.
3. Local cache — `flutter_secure_storage` used for fast reads. Supabase is fallback, not primary.
4. Non-custodial — Platform holds backup mnemonic but keys are only derived client-side. Blockfrost project_id is a read/submit key.
5. Preview testnet only — All addresses `addr_test1...`. Switch to mainnet = change Blockfrost base URL + project ID.
6. Single address — `m/1852'/1815'/0'/0/0`. Multi-address is a future enhancement.
7. Transaction building — Minimal CBOR encoder builds simple ADA transfers. Complex transactions (native assets, smart contracts) need a full tx builder in Phase 2.

**Blockfrost Test:** Get tADA from [Cardano Preview Faucet](https://docs.cardano.org/cardano-testnets/tools/faucet/)

### Cardano Phase 2A — CIP-68 NFT Ticket Minting (Completed)

When an organizer enables "NFT Tickets" on an event, purchasing a ticket automatically mints a CIP-68 NFT to the buyer's Cardano wallet. Platform-controlled minting via a single minting wallet.

**Architecture:**
- Platform minting wallet (mnemonic as `PLATFORM_CARDANO_MNEMONIC` Supabase secret)
- `NativeScript.PubKey(platformPaymentKeyHash)` minting policy (no Plutus)
- CIP-68 dual-token: Reference NFT (`000643b0` prefix, held at platform address with inline datum) + User Token (`000de140` prefix, sent to buyer)
- Fire-and-forget: stripe-webhook enqueues mint → `mint-ticket-nft` Edge Function builds/signs/submits tx

**Database:**
- `platform_cardano_config` table — stores platform minting address (mnemonic in secrets)
- `nft_mint_queue` table — status queue (queued→minting→minted|failed|skipped), tx hash, policy ID, asset IDs, retry count
- `tickets` table — added `nft_minted`, `nft_asset_id`, `nft_minted_at`, `nft_policy_id`, `nft_tx_hash` columns
- `events` table — added `nft_enabled`, `nft_policy_id` columns
- Migration: `20260305100001_nft_ticket_system.sql`

**Edge Functions:**
- `mint-ticket-nft` — Hand-rolled BIP32-Ed25519 key derivation + CBOR tx building + Blake2b hashing + ed25519 signing. Uses `@noble/curves`, `@noble/hashes`. Derives CIP-1852 keys from mnemonic, builds CIP-68 mint tx, submits to Blockfrost. Auto-retry on failure (max 5 retries, resets to `queued` and self-invokes). `queueEntry` scoped for catch block to prevent stuck `minting` status.
- `stripe-webhook` — Extended: after ticket creation, checks `events.nft_enabled`, looks up buyer's Cardano address from `user_wallets`, inserts into `nft_mint_queue`, fire-and-forget invokes `mint-ticket-nft`.

**Flutter Models:**
- `NftTicket` (`wallet/models/nft_ticket.dart`) — policyId, assetName, assetId, CIP-68 metadata (name, event, ticket, venue), cardanoScanUrl
- `EventModel` — added `nftEnabled`, `nftPolicyId` fields
- `EventMapper` — parses/serializes `nft_enabled`, `nft_policy_id`
- `Ticket` — added `nftPolicyId`, `nftTxHash` fields

**Flutter Services:**
- `BlockfrostService` — added `getAddressAssets()`, `getAssetInfo()`, `getAssetTransactions()`
- `CardanoRepository` — added `getTicketNfts()`, `getNftDetails()`

**Flutter Providers:**
- `NftMintNotifier` (`nft_mint_provider.dart`) — loadNfts, pollMintStatus, getMintStatus
- `nftMintProvider`, `nftTicketsProvider` convenience providers

**Flutter UI:**
- `NftTicketDetailScreen` — NFT badge, event details, on-chain details (policy ID, asset name, tx hash), CardanoScan links
- `WalletScreen` — NFT Tickets horizontal scroll section after crypto card (shows CIP-68 cards)
- `TicketScreen` — NFT status card for `public_` mode tickets (minted badge + CardanoScan link, or pending spinner)
- `CreateEventScreen` — "Enable NFT Tickets" toggle in tickets step

**Mint Flow:**
1. Organizer creates event with `nft_enabled = true`
2. User buys ticket → stripe-webhook creates ticket → checks nft_enabled → looks up buyer wallet → enqueues in `nft_mint_queue`
3. `mint-ticket-nft` picks up queue entry → derives platform keys → builds CIP-68 tx (2 tokens) → signs → submits to Blockfrost
4. On success: updates `nft_mint_queue` (minted), `tickets` (nft_minted, nft_asset_id, nft_tx_hash, nft_policy_id)
5. If buyer has no wallet: status `skipped` (can claim later)

**Platform Wallet Setup:**
1. Generate 24-word mnemonic, derive Preview address
2. Store as `PLATFORM_CARDANO_MNEMONIC` Supabase Edge Function secret
3. Insert address into `platform_cardano_config` table
4. Fund from [Cardano Preview Faucet](https://docs.cardano.org/cardano-testnets/tools/faucet/)

### Cardano Phase 2B — NFT Transfer on Resale (Completed)

When a ticket is resold, the NFT user token is transferred to the new buyer on-chain. Platform mints a new user token to buyer; reference NFT datum updated with new owner.

**Database:**
- Migration: `20260306100001_nft_transfer_support.sql`
- `nft_mint_queue` — Added `action` ('mint'|'transfer'), `seller_address`, `resale_listing_id`, status values 'transferring'/'transferred'
- `tickets` — Added `nft_transfer_tx_hash` column

**Edge Functions:**
- `transfer-ticket-nft` — Builds CIP-68 transfer tx: updates reference NFT datum, mints new user token to buyer, submits via Blockfrost. Auto-retry with exponential backoff (max 5 retries).
- `stripe-webhook` — Extended: on resale payment success, checks `nft_minted`, enqueues transfer via `enqueueNftTransfer()`, fire-and-forget invokes `transfer-ticket-nft`

**Flutter:**
- `Ticket.nftTransferTxHash` field — displays transfer tx hash (falls back to mint tx hash)
- `ticket_screen.dart` — Shows latest on-chain tx (transfer or mint)

### Block Resale of Unminted Tickets (Completed)

Tickets on NFT-enabled events cannot be resold until minting completes. Guards at 3 layers:

**Flutter:**
- `Ticket.isAwaitingMint` — true when event has `nft_enabled` or ticket is `public_` mode and `nftMinted == false`
- `Ticket.canBeResold` — includes `!isAwaitingMint` check; sell button auto-hides
- `resale_repository.dart` — `createListing()` joins events to check `nft_enabled`, throws `PaymentException` if unminted
- `ticket_screen.dart` — Shows "Preparing ticket..." spinner when awaiting mint; polls Supabase every 5s for mint status, auto-updates when complete

**Database:**
- Migration: `20260307300001_block_unminted_resale.sql` — Extends `block_private_ticket_resale()` trigger to also reject unminted public/NFT tickets from `resale_listings`

### Cardano Phase 2C — Admin NFT Controls (Completed)

All events have NFT tickets enabled by default — no organizer toggle needed.

- Admin NFT Wallet dashboard (`/dashboard/nft-wallet`) — Platform wallet info, KPI cards (queued/minting/minted/failed/skipped), mint queue table with retry buttons
- Per-event NFT stats in admin event detail page — Mint queue breakdown, policy ID with CardanoScan link, failed entry retry
- `ManageTicketsScreen` — NFT mint status counts (minted/pending chips)
- Admin sidebar "NFT Wallet" nav item
- `CreateEventScreen` — `_nftEnabled` defaults true, no toggle exposed to organizers

**Legacy dead code:**
- `get_ticket_stats()` SQL function still exists in DB but is unused (callers migrated to `get_event_dashboard`). Can be dropped in a future migration.

### Cardano Phase 2D — Automatic NFT Burn & ADA Reclaim (Completed)

After an event ends + 60-day grace period, ticket NFTs are automatically burned on-chain and the locked ADA (~1.5 per NFT) is reclaimed to the platform wallet. Fully automatic — no user interaction needed because the platform holds user mnemonics in `user_wallets`.

**Database:**
- Migration: `20260308100001_nft_burn_reclaim.sql`
- `nft_mint_queue` — Extended: action `'burn'`, statuses `'burning'`/`'burned'`
- `tickets` — Added `nft_burned` (bool), `nft_burned_at`, `nft_burn_tx_hash`
- `get_burn_eligible_tickets(grace_days)` SQL function — Finds tickets with minted NFTs on events ended 60+ days ago
- `enqueue_expired_nft_burns(grace_days)` SQL function — Enqueues burn jobs for eligible tickets
- pg_cron job `enqueue-expired-nft-burns` — Runs daily at 1am UTC

**Edge Functions:**
- `burn-expired-nfts` — Batch processor (up to 10 per invocation). For each ticket:
  1. Derives buyer's payment key from mnemonic (CIP-1852 BIP32-Ed25519)
  2. Finds reference NFT UTxO at platform address + user token UTxO at buyer address
  3. Builds burn tx: spends both UTxOs, burns both CIP-68 tokens (-1 each), sends all ADA to platform
  4. Signs with dual witnesses (platform key + buyer key)
  5. Submits to Blockfrost, updates `nft_mint_queue` and `tickets`
  - Handles edge cases: user token not at expected address (burns ref only), no user wallet (marks burned)
  - Supports `{ "enqueue": true }` to also run the enqueue SQL function
  - Self-invokes for next batch if more entries remain
  - Max 5 retries per entry
- `refresh-analytics` — Extended: fire-and-forget triggers `burn-expired-nfts` with enqueue=true after analytics refresh

**Key Derivation (server-side, Deno):**
- BIP39 mnemonic → PBKDF2-HMAC-SHA512 → Icarus V2 master key (96 bytes: kL+kR+chainCode)
- CIP-1852 path: m/1852'/1815'/0'/0/0 (3 hardened + 2 normal derivations)
- BIP32-Ed25519 child key derivation using HMAC-SHA512
- Derives fresh each time (milliseconds) — no stored private keys

**Burn Transaction Structure:**
- Inputs: reference NFT UTxO (platform) + user token UTxO (buyer) + optional ADA-only UTxOs for fees
- Outputs: single change output to platform address (reclaimed ADA)
- Mint field: -1 reference NFT + -1 user token (CBOR negative integers)
- Witnesses: platform vkey + buyer vkey + native script (policy)

**Flutter:**
- `Ticket` model — Added `nftBurned`, `nftBurnedAt`, `nftBurnTxHash` fields
- `ticket_screen.dart` — Shows "Expired" pill (with timer_off icon) when `nftBurned == true`, tappable → CardanoScan burn tx

**Admin Panel:**
- NFT Wallet dashboard — "Burned" KPI card, burn statuses in queue table (burning/burned badges)
- API route — Returns burn counts, handles burn action retries

## Future: Cardano Phase 3

- Multi-address derivation for privacy
- Mainnet deployment (switch Blockfrost base URL + project ID)
- Organizer NFT customization (custom metadata fields, artwork)

## Roadmap: Competitive Parity with Ticket Tailor

Ticket Tailor is our closest competitor (~73K organizers, $6.6M ARR, flat $0.26/ticket). They excel at organizer tooling; we excel at buyer experience (discovery, native app, NFT tickets, built-in resale, crypto wallet). These features close the organizer-side gap.

### ~~Priority 1 — Offline Check-in~~ (Completed)

Ushers can check in attendees even with no connectivity. Door list auto-downloads on screen open. 3-tier verification (Offline Cache → Blockchain → Database) with real-time animated UI.

**Architecture:**
- SQLite local database (`checkin_cache.db`) with `door_list` and `sync_queue` tables
- O(1) HashMap index: 2 keys per ticket (ticket_id + ticket_number)
- Background sync every 7 seconds when online (via `connectivity_plus`)
- Conflict resolution: local check-in timestamp wins for "already used"; server "cancelled" status propagated

**Dependencies added:**
- `sqflite: ^2.3.0` / `sqflite_common_ffi: ^2.3.0+2` — SQLite
- `connectivity_plus: ^6.0.0` — Network state detection
- `path: ^1.9.0` — Database path resolution

**Core Services:**
- `OfflineCheckInService` (`core/services/offline_checkin_service.dart`) — SQLite door list + HashMap index. Methods: downloadDoorList, lookupTicket, markCheckedIn, markUndoCheckIn, getSyncQueue, markSynced, getLocalStats, getDoorListInfo. SQLite v2 schema with `door_list_meta` table tracking which events have been downloaded (including 0-ticket events).
- `CheckInSyncService` (`core/services/checkin_sync_service.dart`) — Background sync engine. Timer-based (7s), batch size 50, conflict resolution, door list refresh every 60s (picks up new ticket purchases), DB lookup for tickets not in cache. Emits `statsChangedStream` after sync/refresh so UI updates live.
- `BlockchainVerifyService` (`core/services/blockchain_verify_service.dart`) — NFT ownership verification via Blockfrost. Skips non-NFT tickets

**Models:**
- `VerificationResult` (`core/models/verification_result.dart`) — 3-tier result with `VerificationTier`, `TierStatus`, `TierResult`, `DoorListEntry`, `SyncQueueEntry`, `BlockchainVerifyResult`

**Provider:**
- `OfflineCheckInNotifier` (`core/providers/offline_checkin_provider.dart`) — State management with downloadDoorList, verifyTicket (3-tier pipeline), confirmCheckIn, undoCheckIn. Providers: offlineCheckInProvider, offlineCheckInServiceProvider, checkInSyncServiceProvider, blockchainVerifyServiceProvider

**Widgets:**
- `VerificationCard` (`features/events/widgets/verification_card.dart`) — Animated 3-tier verification UI with tier rows, ticket info, admission bar, action buttons
- `ConnectivityIndicator` (`features/events/widgets/connectivity_indicator.dart`) — Status banner (green/amber/red) with `expanded` mode for full-width display. Shows "Online — Door list cached" / "Syncing X" / "Offline (X pending)"
- `_DoorListChip` in `my_events_screen.dart` — Shows cache status on ushering tab event cards: "Offline · 45.2 KB" (green), "Offline · No guests" (green, 0 tickets), or "Tap to Download" (grey). Uses `doorListCachedProvider` with auto-dispose.

**Modified Files:**
- `usher_event_screen.dart` — Integrated offline provider, verification card, expanded connectivity banner below app bar. Auto-downloads door list, invalidates `doorListCachedProvider` after download so My Events chips update on back navigation.
- `my_events_screen.dart` — Ushering tab cards show `_DoorListChip` with offline cache status and data size
- `staff_dashboard_screen.dart` — "Check Tickets" now navigates to `UsherEventScreen` (was TODO snackbar)
- `i_ticket_repository.dart` + `ticket_repository.dart` — Added `getEventDoorList(eventId)` method
- `services.dart`, `providers.dart`, `models.dart` — Export new files

**Verification Flow:**
1. Tier 1 (Offline, <1ms): HashMap lookup → valid/used/cancelled/notFound
2. Tier 2 (Blockchain, 1-3s, non-blocking): Blockfrost NFT asset check (skipped for non-NFT)
3. Tier 3 (Database, 1-3s, non-blocking): Supabase status confirmation (skipped when offline)
4. Admission: Tier 1 is authoritative. Tiers 2-3 run in parallel for audit only.

**Test Suite:** `test/offline_checkin_test.dart` — 34 tests covering HashMap index, local check-in, undo, sync queue, stats, stress (50K tickets), FIFO ordering, retry exhaustion, edge cases. Uses `sqflite_common_ffi` in-memory databases.

### ~~Priority 2 — Discount & Promo Codes~~ (Completed)

Organizers create promo codes (e.g., `EARLY20`, `VIP50OFF`) for their events. Buyers enter codes at checkout to get a discount. Discount applied to BASE ticket price before fees.

**Database:**
- `promo_codes` table — code, discount_type (percentage/fixed), discount_value, max_uses, valid_from/until, ticket_type_id, is_active
- `promo_code_uses` table — tracks per-user usage (UNIQUE on promo_code_id + user_id)
- `payments.promo_code_id` FK — links payment to the promo code used
- `validate_promo_code()` SQL function — checks active, dates, max uses, per-user use, ticket type, calculates discount
- `redeem_promo_code()` SQL function — inserts use record, increments counter
- RLS: organizers manage own event codes, buyers can read active codes
- Migration: `20260312100001_promo_code_system.sql`

**Edge Functions:**
- `validate-promo-code` — Calls `validate_promo_code` RPC, returns validation result (read-only)
- `create-payment-intent` — Extended: accepts `promo_code_id`, re-validates server-side, calculates fees on discounted base, redeems after payment creation
- `create-ach-payment-intent` — Extended: same promo support as card flow

**Flutter Models:**
- `PromoDiscountType` enum (percentage, fixed)
- `PromoCode` — full model with fromJson, formattedDiscount, formattedUsage
- `PromoValidationResult` — {valid, error?, promoCodeId?, discountCents?, discountedPriceCents?}
- `CreatePaymentIntentRequest.promoCodeId` — passed to edge function

**Flutter Data:**
- `promo_code_repository.dart` — validateCode (via edge function), getEventPromoCodes, createPromoCode, deactivatePromoCode, activatePromoCode

**Flutter Providers:**
- `PromoValidationNotifier` (buyer checkout) — validateCode, clearCode; state: isValidating, result, appliedCode, error
- `PromoCodeManagementNotifier` (organizer, family by eventId) — loadCodes, createCode, deactivateCode, activateCode
- `promoValidationProvider`, `promoCodeManagementProvider(eventId)`

**Flutter UI:**
- `checkout_screen.dart` — "Have a promo code?" collapsible → text input + Apply → green chip with discount amount and X to remove. Fee recalculation on discounted base. Discount row in order summary. Re-initializes Stripe payment sheet when code applied/removed. Works with both card and ACH.
- `promo_codes_screen.dart` — Organizer management: list of code cards (monospace code, discount, usage stats, active toggle), FAB to create. Create bottom sheet with auto-generated code, percentage/fixed toggle, slider, preview, max uses.
- `admin_event_screen.dart` — "Promo Codes" action card (orange, Icons.discount_outlined)
- `manage_tickets_screen.dart` — "Promo Codes" nav button in summary bar

**Discount Logic:**
- Discount applied to `base_price * quantity` before fees
- Fees (platform 5%, Stripe 2.9%+$0.30, mint $0.25 for card; 5% + 0.8% ACH for bank) calculated on discounted base
- Client and server compute identically — server re-validates and rejects mismatches
- One use per user per code (enforced by UNIQUE constraint + SQL function)

### ~~Priority 3 — Waitlists~~ (Completed)

Two-mode waitlist system: "Notify Me" (get alerted when tickets available) and "Auto-Buy" (automatically purchase when a ticket appears under a max price). FIFO queue processing triggered by resale listings.

**Database:**
- `waitlist_entries` table — mode (notify/auto_buy), max_price_cents, payment_method_id, stripe_customer_id, status lifecycle (active/notified/purchased/cancelled/expired/failed)
- Partial unique index: one active entry per user per event
- SQL functions: `get_waitlist_queue()`, `get_waitlist_count()`, `expire_past_event_waitlists()`
- pg_cron job: expires waitlists for past events daily at 2am UTC
- Added `waitlist_auto_purchase` to payments type constraint
- Migration: `20260312200001_waitlist_system.sql`

**Edge Functions:**
- `process-waitlist` — FIFO queue processor. Notifies "notify" users, attempts off-session Stripe payment for "auto_buy" users. Triggered by resale listings and capacity changes. Fee calculation matches primary purchase (5% platform + 2.9%+$0.30 Stripe + $0.25 mint).

**Flutter Models:**
- `waitlist/models/waitlist_entry.dart` — WaitlistEntry, WaitlistMode enum (notify/autoBuy), WaitlistStatus enum, WaitlistCount

**Flutter Data:**
- `waitlist/data/waitlist_repository.dart` — getMyEntry, joinNotify, joinAutoBuy, cancel, getWaitlistCount, getPosition, triggerProcessing (fire-and-forget)

**Flutter Provider:**
- `core/providers/waitlist_provider.dart` — WaitlistNotifier (family by eventId) with load, joinNotify, joinAutoBuy, leave. Providers: waitlistProvider, waitlistCountProvider, waitlistRepositoryProvider

**Flutter UI:**
- `waitlist/presentation/waitlist_sheet.dart` — Bottom sheet with mode selector (Notify Me / Auto-Buy), max price input, payment method selection, active waitlist status card with position and leave button
- `event_details_screen.dart` — Waitlist section in buy sheet appears when official tickets are sold out. "Join Waitlist" card navigates to waitlist sheet.

**Modified Files:**
- `notification_model.dart` — Added `waitlistAvailable`, `waitlistAutoPurchased` types
- `notifications_screen.dart` — Handle new notification types (icons, colors, navigation)
- `payment.dart` — Added `waitlistAutoPurchase` to PaymentType enum
- `checkout_screen.dart` — Handle new payment type in switch
- `transaction_detail_sheet.dart` — Labels/icons for waitlist auto-purchase
- `transactions_screen.dart` — Labels/icons for waitlist auto-purchase
- `resale_repository.dart` — Fire-and-forget `process-waitlist` trigger after listing creation
- `stripe-webhook/index.ts` — `waitlist_auto_purchase` creates tickets like primary_purchase
- `providers.dart` — Export waitlist_provider.dart

**Waitlist Flow:**
1. Tickets sell out → "Join Waitlist" appears in buy sheet
2. User picks "Notify Me" or "Auto-Buy" (with max price + saved card)
3. When someone lists a resale ticket: `process-waitlist` fires
4. Notify users get a notification; auto-buy users get off-session purchase attempted
5. On auto-buy success: ticket created, user notified of purchase
6. On auto-buy failure: user notified to check event page manually

### ~~Priority 4 — Apple Wallet & Google Wallet~~ (Completed — secrets pending)

Ticket passes delivered to native wallets. QR code embedded in the pass for check-in scanning. Pass updates pushed for event changes (time, venue). **Secrets not yet configured** — infrastructure is built, passes will generate once Apple/Google credentials are added.

**Database:**
- `wallet_passes` table — ticket_id FK, pass_type (apple/google), pass_url, apple_serial, apple_auth_token, apple_push_token, google_object_id, status lifecycle (created/delivered/updated/expired/revoked)
- `wallet_pass_registrations` table — Apple device registrations (serial_number, device_id, push_token)
- RLS: users SELECT own passes via ticket join, service role INSERT/UPDATE
- Migration: `20260313400001_wallet_passes.sql`

**Edge Functions:**
- `generate-wallet-pass` — Builds Apple PKPass (ZIP with pass.json + manifest + QR barcode) and Google Wallet JWT save URL. QR uses existing check-in JSON format. Supports location-aware lock screen notifications when event has coordinates. Falls back gracefully when signing certs not configured.
- `wallet-pass-callback` — Apple webServiceURL handler per spec: POST register device, DELETE unregister, GET latest pass (with If-Modified-Since), GET updated serials, POST error log
- `update-wallet-passes` — Propagates event changes. Apple: marks updated + APNs push → device fetches new pass. Google: PATCH EventTicketObject via REST API
- `stripe-webhook` — Extended: fire-and-forget `generate-wallet-pass` for both pass types after ticket creation

**Flutter:**
- `wallet/models/wallet_pass.dart` — WalletPass model, WalletPassType enum (apple/google)
- `wallet/data/wallet_pass_repository.dart` — getPassForTicket(), generatePass() via edge function
- `core/providers/wallet_pass_provider.dart` — WalletPassNotifier (family by ticketId), generateAndOpen(), platform detection
- `ticket_screen.dart` — "Add to Apple Wallet" / "Add to Google Wallet" buttons below wallet status card. Platform-aware: iOS shows Apple, Android/web shows Google. Loading state, error handling, "View in..." when already generated

**Secrets needed (not yet configured):**
- `APPLE_PASS_CERT` (PEM), `APPLE_PASS_KEY` (PEM), `APPLE_PASS_PHRASE`, `APPLE_TEAM_ID`, `APPLE_PASS_TYPE_ID`
- `GOOGLE_WALLET_ISSUER_ID`, `GOOGLE_WALLET_SERVICE_ACCOUNT_KEY` (JSON)

### ~~Priority 5 — Seating Charts~~ (Phase 1 Completed: Builder; Phase 2 Completed: Seat Selection at Checkout)

**Phase 1** (completed previously): Drag-and-drop seating chart builder — sections (seated/standing/table), elements (stage/bar/entrance), canvas painting, hit testing, seat generation, VenueMiniMap.

**Phase 2 — Seat Selection at Checkout** (Completed):

When an event has a venue with seated sections that have generated seats, buyers pick their exact seats before checkout.

**Database:**
- `tickets` table: added `venue_section_id`, `seat_id`, `seat_label` columns
- `payments` table: added `seat_selections` JSONB column (stores full seat selection array — avoids Stripe metadata limits)
- `seat_holds` table: temporary locks during checkout (event_id, venue_section_id, seat_id, user_id, expires_at) with UNIQUE constraint
- Index: `idx_tickets_event_section_seat` for fast sold-seat lookup
- pg_cron: `expire-seat-holds` every minute deletes expired holds
- Migration: `20260315100001_seat_selection.sql`

**Flutter Models:**
- `SeatSelection` (`venues/models/seat_selection.dart`) — sectionId, seatId, seatLabel, sectionName, rowLabel, seatNumber

**Flutter Data:**
- `VenueRepository` — `getUnavailableSeats(eventId, sectionId)` returns UNION of sold tickets + active holds as `Set<String>`, `holdSeats(eventId, seats)` creates 10-min TTL holds, `releaseHolds(holdIds)` deletes by ID

**Flutter UI:**
- `SeatPickerScreen` (`venues/presentation/seat_picker_screen.dart`) — Full-screen seat picker:
  - Auto-selects section when only one seated section needs seats (skips map phase)
  - Accepts `initialSectionId` parameter to skip Phase A
  - Phase A: VenueMiniMap with highlighted seated sections, tap to drill in
  - Phase B: Normalized seat grid — raw seat positions quantized into rows/columns, scaled to fit screen via `LayoutBuilder`. Seats are 40px with 6px gaps, row labels on left (28px label area), symmetrical padding. Seat numbers rendered inside each seat, checkmark on selected seats.
  - Replace-selection: when at max capacity, tapping a new seat replaces the oldest selected (no need to deselect first)
  - Bottom bar: selected seat chips with delete + "Confirm Seats" button
- `EventDetailsScreen._checkout()` — If event has seated venue sections with generated seats, pushes SeatPickerScreen first, holds seats, then navigates to CheckoutScreen with seat_selections in metadata. **Important:** navigator, scaffoldMessenger, venueRepo must be captured via `ref.read()` / `Navigator.of()` *before* popping the bottom sheet — the sheet's context and ref become invalid after pop.
- `EventDetailsScreen` buy sheet — "Full Screen" button below VenueMiniMap for optional full-screen venue browsing
- `TicketScreen` — Shows `_InfoCard` with `event_seat` icon and seat label when `seatLabel != null`
- `OfflineCheckInService` — Added `seat_label` to door_list SQLite schema (v3), downloaded from Supabase, available in `DoorListEntry.seatLabel`
- `ManageTicketsScreen` — Shows VenueMiniMap when venue is linked; venue link card uses `_effectiveVenueId` (local state) so UI updates immediately after linking. Section assignments are tracked locally with "Push Changes" button in app bar — changes only saved to DB on push, discarded on back.
- `AdminEventScreen` — Same `_effectiveVenueId` pattern for immediate venue link UI updates

**Edge Functions:**
- `create-payment-intent` — Accepts `seat_selections` array, stores in `payments.seat_selections` JSONB
- `create-ach-payment-intent` — Same seat_selections support; assigns seat data to tickets on immediate creation; cleans up seat_holds after
- `stripe-webhook` — Reads `seat_selections` from payment record, assigns `venue_section_id`/`seat_id`/`seat_label` to each ticket; cleans up seat_holds after

**Ticket Model:**
- `Ticket` — Added `venueSectionId`, `seatId`, `seatLabel` fields in fromJson/toJson/copyWith
- `DoorListEntry` — Added `seatLabel` field

**Flow:**
1. Buyer selects ticket types with quantities in buy sheet
2. If any selected ticket type maps to a seated section with generated seats → SeatPickerScreen (auto-selects section if only one)
3. Buyer sees normalized seat grid → taps to select seats (replace-selection when at max)
4. "Confirm Seats" → holdSeats (10-min TTL) → CheckoutScreen with seat_selections metadata
5. Card: create-payment-intent stores seat_selections in payments.seat_selections; webhook reads them and assigns to tickets
6. ACH: create-ach-payment-intent stores seat_selections and assigns directly to tickets
7. After ticket creation, seat_holds are cleaned up; expired holds auto-deleted every minute by pg_cron

**Venue Builder Fix (Phase 1):**
- Hit-test coordinates must use `_screenToCanvas()` (inverse transform) — raw `details.localPosition` is in screen space, not canvas space. Fixed in `_onTapDown`, `_onScaleStart`, rotation drag, and scale handle drag.

**Admin Screen Venue Display:**
- `widget.event` is immutable — after `linkVenue()`, the event's `venueId` stays `null`. Both `ManageTicketsScreen` and `AdminEventScreen` use `_linkedVenueId` local state + `_effectiveVenueId` getter to track venue linkage immediately.

### ~~Priority 6 — Recurring & Series Events~~ (Completed)

Organizers can create recurring events (daily, weekly, biweekly, monthly). Each occurrence is a real `events` row — materialized occurrences, not virtual. Template snapshot pattern stores event config as JSONB for generating new occurrences. Cron job ensures 4+ future occurrences exist.

**Database:**
- `event_series` table — recurrence_type (daily/weekly/biweekly/monthly), recurrence_day, recurrence_time, starts_at, ends_at, max_occurrences, template_snapshot JSONB, ticket_types_snapshot JSONB, is_active
- `events` table — Added `series_id` FK, `occurrence_index` INT, `series_edited` BOOLEAN, `recurrence_type` TEXT (denormalized for display)
- `generate_series_occurrences(p_series_id, p_min_future)` — SQL function that generates future occurrences from template, clones ticket types
- `generate_all_series_occurrences()` — iterates all active series
- `get_series_occurrences(p_series_id)` — returns all occurrences ordered by date
- pg_cron job at 3am UTC daily ensures rolling window of future occurrences
- RLS: organizers manage own series
- Migration: `20260313100001_recurring_events.sql`

**Flutter Models:**
- `event_series.dart` — `RecurrenceType` enum (daily/weekly/biweekly/monthly) with label/shortLabel, `EventSeries` model with fromJson, `SeriesOccurrence` lightweight model
- `EventModel` — Added `seriesId`, `occurrenceIndex`, `seriesEdited`, `recurrenceType` fields + `isPartOfSeries` getter
- `EventMapper` — Parses series fields from JSON

**Flutter Data:**
- `supabase_event_repository.dart` — Added `createEventSeries()` (inserts series + generates occurrences via RPC), `getEventSeries()`, `getSeriesOccurrences()`, `updateSeriesTemplate()` (scope: this_only/this_and_future/all), `cancelSeries()` (deactivates + soft-deletes future occurrences)

**Flutter Providers:**
- `series_provider.dart` — `seriesOccurrencesProvider` and `seriesDetailProvider` (autoDispose family FutureProviders)

**Flutter UI:**
- `create_event_screen.dart` — Recurrence card with toggle, SegmentedButton for frequency (Daily/Weekly/Biweekly/Monthly), info text showing schedule, end date picker. Creates series via `createEventSeries()` instead of single event.
- `event_details_screen.dart` — Recurring event chip (purple, shows frequency + "See all dates"), `_AllDatesSheet` showing all occurrences with date formatting and navigation
- `admin_event_screen.dart` — Series info banner (purple) showing recurrence type and occurrence number, "Cancel Series" action card with confirmation dialog
- `my_events_screen.dart` — Recurring badge (_StatChip with repeat icon) on event cards
- `event_banner_card.dart` — Recurring badge (purple chip) in tag row

**Key Design Decisions:**
1. Materialized occurrences — each is a real `events` row (not computed). Allows per-occurrence edits, independent ticket sales, analytics.
2. Template snapshot — JSONB stores the event config. New occurrences inherit from template, not from latest occurrence.
3. Denormalized `recurrence_type` on events — avoids joining `event_series` for display in cards/lists.
4. Dart weekday → PostgreSQL DOW: `date.weekday % 7` (Dart: 1=Mon..7=Sun → PG: 0=Sun..6=Sat)
5. Rolling window — cron job generates occurrences 4+ into the future. Immediate generation on series creation via RPC.

### Priority 7 — Virtual Events

External-hosted virtual events (Zoom, Google Meet, Discord, etc.). Tickety doesn't host video — organizers use whatever platform they want. Hybrid events support both in-person and virtual ticket types.

**Access gating: Timed lockdown + reveal**
- Organizer enters meeting link + optional password when creating event (stored hidden, never shown to buyers until lockdown)
- Tickets can be resold normally on the marketplace until 1 hour before event start
- At T-1h, automated lockdown triggers:
  1. All tickets for the event become locked (resale blocked)
  2. Any active resale listings are delisted (status reverted to `none`)
  3. Meeting link + password revealed to all valid ticket holders
  4. Push notification sent: "Your virtual event link is now available"
- On ticket screen, "Join Event" button appears linking to the external platform
- Timezone-safe: events use `TIMESTAMPTZ` (UTC storage), lockdown computed against `NOW()`

**Database changes needed:**
- `events` table: `event_format` (in_person/virtual/hybrid), `virtual_event_url` (TEXT, encrypted/hidden until lockdown), `virtual_event_password` (TEXT, optional), `virtual_lockdown_at` (TIMESTAMPTZ, computed as `date - interval '1 hour'`)
- `events` table: `virtual_locked` (BOOLEAN, default false) — set true at lockdown
- Scheduled job (pg_cron or edge function): runs every 5 min, finds events where `NOW() >= virtual_lockdown_at AND NOT virtual_locked`, executes lockdown
- Lockdown procedure: UPDATE tickets SET resale blocked, UPDATE resale_listings SET status='cancelled' WHERE event_id AND status='listed', UPDATE events SET virtual_locked=true, INSERT notifications for all valid ticket holders

**Flutter changes needed:**
- `EventModel` — `eventFormat`, `virtualEventUrl`, `virtualEventPassword`, `virtualLocked` fields
- `CreateEventScreen` — Event format selector (In-Person/Virtual/Hybrid), meeting link + password fields for virtual/hybrid
- `EventDetailsScreen` — Virtual event badge, "Online Event" indicator
- `TicketScreen` — "Join Event" button (only after lockdown), shows meeting link + password
- `ResaleRepository` / `Ticket.canBeResold` — block resale when `virtualLocked == true`
- Notification types: `virtualEventLinkRevealed`

### Priority 8 — Embeddable Checkout Widget

JavaScript widget organizers drop on their own website. Pop-out checkout flow, no redirect needed. Customizable styling to match organizer's brand.

### Priority 9 — Merch & Products (Architecture Planned)

Sell merchandise, add-ons, and digital downloads alongside or independent of events. Year-round storefront per organizer. Bundling with ticket purchases (e.g. "VIP + T-Shirt"). Inventory tracking per product variant.

**Planned Architecture:**

**Database:**
- `organizer_merch_config` — organizer_id, provider (shopify/stripe/none), shopify_domain, shopify_access_token, stripe_products_enabled
- `merch_products` — organizer_id, source (shopify/stripe), external_id, title, description, image_urls JSONB, variants JSONB [{id, name, price_cents, inventory, sku}], is_active, event_id (nullable)
- `merch_orders` — user_id, organizer_id, product_id, variant_id, quantity, amount_cents, status lifecycle (pending/paid/processing/shipped/delivered/cancelled/refunded), shipping_address JSONB, tracking_info JSONB, stripe_payment_intent_id, shopify_order_id
- Add `merch_purchase` to payments type constraint

**Edge Functions:**
- `sync-shopify-products` — Pull Shopify catalog via Admin API, upsert into merch_products
- `create-merch-checkout` — Stripe source: create PaymentIntent + merch_order; Shopify source: create draft order, return checkout URL
- Extend `stripe-webhook` with `merch_purchase` handler → update merch_orders to paid, notify organizer
- `merch-webhook` — Shopify fulfillment/cancellation webhooks → update merch_orders status + tracking

**Flutter Feature:** `features/merch/`
- models: MerchProduct, MerchVariant, MerchOrder, MerchOrderStatus, OrganizerMerchConfig, MerchProvider enum
- data: MerchRepository (CRUD, sync, checkout routing)
- presentation: MerchStoreScreen, ProductDetailScreen, MerchCheckoutScreen, MerchOrdersScreen, OrganizerProductsScreen, OrganizerOrdersScreen, ConnectShopifyScreen
- providers: eventMerchProvider(eventId), organizerProductsProvider, myMerchOrdersProvider, merchConfigProvider

**Integration Points:**
- EventDetailsScreen: "Merch" section below tickets when event has products
- AdminEventScreen: "Merch" action card
- PaymentType enum: add `merchPurchase`
- Seller balance reuse: `on_behalf_of` pattern for organizer payouts
- One provider per organizer (Shopify OR Stripe, not both simultaneously)
- No cart initially — single product checkout. Cart batching is a future enhancement.

### Priority 10 — Localization (i18n)

Multi-language checkout and app UI. Start with Spanish, French, German, Portuguese. Currency formatting per locale. RTL support for Arabic/Hebrew (later phase).

### Priority 11 — White-Labeling & Custom Domains

Organizers hide Tickety branding, use their own logo/colors. Custom domain for ticket pages (tickets.yourbrand.com). Branded email notifications.

### Priority 12 — Public API

REST API for organizers to integrate with their own systems. Endpoints: events, tickets, orders, check-ins, discount codes. API key auth, rate limiting, webhook subscriptions. Developer documentation site.

### Priority 13 — Affiliate & Referral Tracking

Unique referral links per sales channel. Performance dashboard showing which channels drive sales. Commission tracking for affiliates.

### Not Prioritized (Tickety already ahead)

- NFT tickets (CIP-68 on Cardano) — Ticket Tailor has nothing
- Crypto wallet (ADA send/receive) — Ticket Tailor has nothing
- Built-in resale marketplace — Ticket Tailor uses third-party Tixel
- ACH bank payments — Ticket Tailor doesn't offer
- Native buyer app — Ticket Tailor is web-only for buyers
- Event discovery — Ticket Tailor has no marketplace
- Tap-to-pay (phone-to-phone NFC) — More flexible than Ticket Tailor's Stripe Terminal approach
- Comp/favor tickets — Not documented in Ticket Tailor
- Organizer verification — Ticket Tailor has nothing comparable
