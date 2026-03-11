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
- `OfflineCheckInService` (`core/services/offline_checkin_service.dart`) — SQLite door list + HashMap index. Methods: downloadDoorList, lookupTicket, markCheckedIn, markUndoCheckIn, getSyncQueue, markSynced, getLocalStats
- `CheckInSyncService` (`core/services/checkin_sync_service.dart`) — Background sync engine. Timer-based (7s), batch size 50, conflict resolution, door list refresh every 60s, DB lookup for tickets not in cache
- `BlockchainVerifyService` (`core/services/blockchain_verify_service.dart`) — NFT ownership verification via Blockfrost. Skips non-NFT tickets

**Models:**
- `VerificationResult` (`core/models/verification_result.dart`) — 3-tier result with `VerificationTier`, `TierStatus`, `TierResult`, `DoorListEntry`, `SyncQueueEntry`, `BlockchainVerifyResult`

**Provider:**
- `OfflineCheckInNotifier` (`core/providers/offline_checkin_provider.dart`) — State management with downloadDoorList, verifyTicket (3-tier pipeline), confirmCheckIn, undoCheckIn. Providers: offlineCheckInProvider, offlineCheckInServiceProvider, checkInSyncServiceProvider, blockchainVerifyServiceProvider

**Widgets:**
- `VerificationCard` (`features/events/widgets/verification_card.dart`) — Animated 3-tier verification UI with tier rows, ticket info, admission bar, action buttons
- `ConnectivityIndicator` (`features/events/widgets/connectivity_indicator.dart`) — Status pill (green/amber/red)

**Modified Files:**
- `usher_event_screen.dart` — Integrated offline provider, verification card, connectivity indicator. Auto-downloads door list, uses 3-tier verify pipeline, shows pending sync count and door list freshness
- `staff_dashboard_screen.dart` — "Check Tickets" now navigates to `UsherEventScreen` (was TODO snackbar)
- `i_ticket_repository.dart` + `ticket_repository.dart` — Added `getEventDoorList(eventId)` method
- `services.dart`, `providers.dart`, `models.dart` — Export new files

**Verification Flow:**
1. Tier 1 (Offline, <1ms): HashMap lookup → valid/used/cancelled/notFound
2. Tier 2 (Blockchain, 1-3s, non-blocking): Blockfrost NFT asset check (skipped for non-NFT)
3. Tier 3 (Database, 1-3s, non-blocking): Supabase status confirmation (skipped when offline)
4. Admission: Tier 1 is authoritative. Tiers 2-3 run in parallel for audit only.

**Test Suite:** `test/offline_checkin_test.dart` — 34 tests covering HashMap index, local check-in, undo, sync queue, stats, stress (50K tickets), FIFO ordering, retry exhaustion, edge cases. Uses `sqflite_common_ffi` in-memory databases.

### Priority 2 — Discount & Promo Codes

Table-stakes feature every organizer expects. Percentage or fixed-amount discounts, assignable to specific ticket types, date-limited. Voucher codes that discount total order. Applied at checkout.

### Priority 3 — Waitlists

When tickets sell out, buyers can join a waitlist by email. Organizer can broadcast notifications when tickets become available. Per-ticket-type waitlists.

### Priority 4 — Apple Wallet & Google Wallet

Ticket passes delivered to native wallets. QR code embedded in the pass for check-in scanning. Pass updates pushed for event changes (time, venue).

### Priority 5 — Seating Charts

Drag-and-drop seating chart builder for organizers. Sections, rows, individual seats, tables, standing areas. Seat selection at checkout with visual map. Price zones (VIP section, balcony, floor, etc.). This is the largest feature — consider a phased approach: simple row/seat grid first, then full visual builder.

### Priority 6 — Recurring & Series Events

Repeating events with configurable schedules (daily, weekly, monthly, custom). Shared settings across occurrences (ticket types, venue, description). Per-occurrence capacity and sales tracking. Heat map showing busiest/quietest time slots.

### Priority 7 — Virtual Events

Integrate video conferencing (Zoom, Google Meet, or built-in via WebRTC). Ticket purchase grants access link. Access gated by ticket validation. Hybrid events: both in-person and virtual ticket types.

### Priority 8 — Embeddable Checkout Widget

JavaScript widget organizers drop on their own website. Pop-out checkout flow, no redirect needed. Customizable styling to match organizer's brand.

### Priority 9 — Merch & Products

Sell merchandise, add-ons, and digital downloads alongside or independent of events. Year-round storefront per organizer. Bundling with ticket purchases (e.g. "VIP + T-Shirt"). Inventory tracking per product variant.

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
