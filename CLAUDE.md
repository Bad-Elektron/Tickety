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

### Analytics Consolidation (TODO)

The analytics system is scattered across multiple surfaces with inconsistent patterns. Needs a consolidation pass to unify into a coherent architecture.

**Current state (6 cache tables, 5 RPC functions, 2 edge functions, 2 dashboards):**

| Surface | Location | Problem |
|---------|----------|---------|
| `analytics_tag_weekly` | SQL cache table | Overlaps with engagement daily cache; both aggregate by tag |
| `analytics_trending_tags` | SQL cache table | Derived from tag_weekly; could be a view or computed in the summary RPC |
| `analytics_market_snapshot` | SQL cache table | External data (Ticketmaster/SeatGeek); separate concern but shares `analytics_cache_meta` |
| `analytics_engagement_daily` | SQL cache table | Newest; only covers views, not revenue/tickets |
| `get_event_analytics()` | RPC (live) | Returns ticket stats + check-ins; ignores views entirely |
| `get_ticket_stats()` | RPC (live) | Lightweight subset of `get_event_analytics()`; redundant |
| `get_event_engagement()` | RPC (live) | Returns views + conversion; doesn't include revenue/check-in data |
| `refresh-analytics` | Edge function | Chains `refresh-market-analytics`; `refresh_engagement_cache()` is NOT chained in |
| Flutter Analytics Dashboard | `features/analytics/` | Enterprise-tier only; shows market/tag trends but no engagement data |
| Admin Overview | `dashboard/overview/` | KPIs via live queries in `/api/admin/stats`; no caching |
| Admin Engagement | `dashboard/engagement/` | Separate page; should be part of a unified analytics view |

**Consolidation goals:**
1. **Unify per-event analytics**: Merge `get_event_analytics()`, `get_ticket_stats()`, and `get_event_engagement()` into a single `get_event_dashboard(event_id)` RPC that returns tickets + check-ins + views + conversion in one call
2. **Unify cache refresh**: Chain `refresh_engagement_cache()` into the existing `refresh-analytics` edge function so one cron job refreshes everything
3. **Merge admin pages**: Consider combining Overview + Engagement into a single analytics dashboard with tabs (Revenue, Engagement, Market)
4. **Flutter analytics screen**: Add engagement data (views, conversion) alongside existing market/tag trends
5. **Drop redundant functions**: Remove `get_ticket_stats()` (subset of event analytics) once callers are updated
6. **Consistent naming**: All cache tables should follow `analytics_{domain}_{granularity}` pattern (already mostly true)

### ACH Bank Transfer + Tickety Wallet System (Completed)

Users can fund a Tickety Wallet via ACH bank transfer (0.8% fee, capped at $5), then buy tickets instantly from wallet balance with only a 5% platform fee (no Stripe processing fee). A $50 ticket costs $52.50 from wallet vs $54.33 via card.

**Database:**
- `wallet_balances` - Per-user available + pending cents, auto-created on first access
- `wallet_transactions` - Double-entry ledger (ach_top_up, ach_top_up_pending, ticket_purchase, refund_credit, admin_adjustment)
- `linked_bank_accounts` - Cached bank account info (Stripe Financial Connections)
- `purchase_from_wallet()` SQL function - Atomic purchase with `FOR UPDATE` row lock to prevent double-spend
- Migration: `20260301100001_create_wallet_system.sql`
- PaymentType constraint updated: added `wallet_purchase`, `wallet_top_up`

**Edge Functions:**
- `get-wallet-balance` - Returns available/pending cents + linked bank accounts (auto-creates wallet)
- `link-bank-account` - Creates Stripe SetupIntent with Financial Connections for ACH bank linking
- `manage-bank-accounts` - List/save/remove linked bank accounts
- `create-wallet-top-up` - ACH PaymentIntent (0.8% fee capped at $5, min $5 / max $2,000), adds to pending_cents
- `purchase-from-wallet` - Validates event, calls `purchase_from_wallet()` SQL function (atomic, no Stripe)
- `stripe-webhook` - Extended: `payment_intent.processing` for ACH logging, wallet top-up settlement on `succeeded`, cleanup on `failed`

**Flutter Models:**
- `wallet/models/wallet_balance.dart` - WalletBalance with formattedAvailable, hasFunds, defaultBank
- `wallet/models/linked_bank_account.dart` - LinkedBankAccount with displayName ("Chase ****1234")
- `wallet/models/wallet_transaction.dart` - WalletTransaction + WalletTransactionType enum
- `payment.dart` - Added `walletPurchase`, `walletTopUp` to PaymentType; `WalletFeeCalculator` (5% only); `ACHFeeCalculator` (0.8% capped at $5)

**Flutter Data/Providers:**
- `wallet/data/wallet_repository.dart` - All wallet edge function calls + direct transaction reads
- `core/providers/wallet_balance_provider.dart` - WalletBalanceNotifier with loadBalance, topUp, purchaseFromWallet

**Flutter UI:**
- `wallet_screen.dart` - Redesigned: Tickety Wallet card (indigo gradient, prominent) → Seller Balance + Crypto cards → Linked Banks section → Actions + Info
- `add_funds_screen.dart` - Preset chips ($10/$25/$50/$100) + custom input, bank selector, ACH fee breakdown
- `link_bank_screen.dart` - Stripe Financial Connections flow via `collectBankAccount()`
- `checkout_screen.dart` - Payment method selector (Wallet vs Card) when wallet has sufficient funds; wallet shows 5%-only fee + savings badge
- `transactions_screen.dart` + `transaction_detail_sheet.dart` - Added wallet_purchase and wallet_top_up icons/labels

**ACH Settlement Flow:**
1. User tops up → PaymentIntent created (processing) → pending_cents increased
2. ACH settles (4-5 days) → webhook `payment_intent.succeeded` → pending→available move
3. ACH fails → webhook `payment_intent.payment_failed` → pending reversed, transaction deleted

**No split payments in v1.** Wallet covers full amount or user pays full by card.

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

## Future: Cardano Phase 2

- NFT-based ticket ownership (mint tickets as CIP-68 NFTs)
- Decentralized ticket resale marketplace
- Multi-address derivation for privacy
- Store public address in user profile for NFT delivery
- Mainnet deployment
