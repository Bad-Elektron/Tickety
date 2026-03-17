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
- **Supabase Storage Content-Type:** Storage serves all files as `text/plain` regardless of upload headers. For HTML that must render in browsers, serve via an edge function with explicit `Content-Type: text/html` header, or use `iframe.srcdoc` injection.
- **Edge function template literals:** When embedding HTML/JS in a TypeScript template literal (`const html = \`...\``), `$` followed by `{` triggers interpolation. Use string concatenation for inner JS instead of template literals.

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
│   ├── config/            # Environment config (EnvConfig)
│   ├── errors/            # App exceptions (CardanoException, etc.)
│   ├── graphics/          # Perlin noise generation & canvas painting
│   ├── models/            # Shared models (PaginatedResult, VerificationResult)
│   ├── providers/         # Shared providers (cardano, favor ticket, waitlist, wallet pass, etc.)
│   ├── services/          # Core services (Blockfrost, CardanoWallet, GooglePlaces, OfflineCheckIn, CheckInSync)
│   └── input/             # Input handling utilities
├── features/              # Feature modules (vertical slices)
│   ├── events/            # Events (models, data, presentation, widgets)
│   ├── tickets/           # Ticket viewing & management
│   ├── payments/          # Payments, resale, promo codes
│   ├── favor_tickets/     # Comp/gift ticket system
│   ├── venues/            # Venue builder, seat picker
│   ├── wallet/            # Crypto wallet, bank accounts, wallet passes
│   ├── waitlist/          # Waitlist system
│   ├── notifications/     # Notification models & screens
│   └── profile/           # User profile & verification
└── shared/                # Reusable widgets (NoiseBackground, PlacesAutocompleteField, VerifiedBadge)
```

### Theme Configuration

- Material 3 with color seed `#6366F1` (Indigo)
- Light: white background / Dark: `#121212` background
- System-aware dark/light mode switching

### Library Exports

Each module uses a library file (e.g., `events.dart`, `widgets.dart`) for clean exports. Import the library file rather than individual files.

## Key Technical Notes

### Pagination

All list-fetching repository methods use `PaginatedResult<T>` with Supabase `.range()`. Fetch `pageSize + 1` to determine `hasMore`. Providers have `loadMore()` + `isLoadingMore` + `hasMore` + `currentPage` for infinite scroll.

### Stripe Integration

- **Edge functions** use `https://esm.sh/stripe@14.21.0` (not `@13.10.0?target=deno`) for Supabase Edge Runtime compatibility
- **Webhook endpoint:** `https://hnouslchigcmbiovdbfz.supabase.co/functions/v1/stripe-webhook`
- **Webhook events:** `customer.subscription.*`, `identity.verification_session.*`, `payment_intent.*`
- **Fee structure:** 5% platform + 2.9%+$0.30 Stripe (card) or 5% + 0.8% capped $5 (ACH)
- **Test values:** Verification `000000`, SSN `000-00-0000`, Bank routing `110000000`, Account `000123456789` (success) / `000222222227` (fail)

### Cardano Integration

- **Preview testnet** — all addresses `addr_test1...`. Mainnet = change Blockfrost URL + project ID
- **Platform minting wallet** — mnemonic as `PLATFORM_CARDANO_MNEMONIC` Supabase secret
- **CIP-68 NFT** — dual-token pattern: Reference NFT (`000643b0`) + User Token (`000de140`)
- **Key derivation** — BIP32-Ed25519 via CIP-1852 path `m/1852'/1815'/0'/0/0`
- **Auto-burn** — 60-day grace period after event ends, pg_cron daily at 1am UTC
- **Blockfrost test:** Get tADA from Cardano Preview Faucet

### Google Places

- HTTP API directly (no native SDK) — works on all platforms
- `GOOGLE_PLACES_API_KEY` in `tickety_app/.env`
- `displayLocation` fallback chain: venue+city → venue → city → formattedAddress → location

### RLS Notes

- Recipient policies use `auth.jwt() ->> 'email'` (not `SELECT FROM auth.users`) — `authenticated` role cannot query `auth.users`
- Trigger functions use `profiles` table for email lookups. `SECURITY DEFINER` alone is not enough for `auth.users` in Supabase hosted.

## Completed Features

### Seller Wallet System
Stripe Express accounts for resale sellers. Funds held in seller's Stripe account (avoids Money Transmitter License). Minimal account on first listing, bank details only for withdrawal. Tables: `seller_balances`. Edge functions: `create-seller-account`, `get-seller-balance`, `initiate-withdrawal`, `create-resale-intent`.

### Favor Ticket System
Organizers send comp/gift tickets by email. Ticket modes: `private` (off-chain, no resale), `public` (on-chain NFT), `standard`. Two-phase lifecycle: offer → accept/pay. Tables: `ticket_offers`, `ticket_mode` on tickets. Triggers for notification on offer creation and new user signup matching.

### Organizer Verification & Event Security
Stripe Identity verification for 250+ capacity events. Auto-hold unverified large events. Event reporting system. Tables: `identity_verification_status` on profiles, `status` on events, `event_reports`. `find_similar_events()` pg_trgm function. Feature flags in DB.

### Google Places Location
Events use Google Places Autocomplete with lat/lng/formatted_address. Location card opens Google Maps. Legacy `location` column auto-populated for backward compat.

### Analytics Consolidation
Unified `get_event_dashboard(event_id)` RPC. Single `refresh-analytics` edge function chains all cache refreshes. Admin dashboard with Overview + Engagement tabs.

### ACH Direct Bank Payment
Bank transfer at checkout via Stripe Financial Connections. Tickets issued immediately, ACH settles 4-5 days. Failure = tickets revoked. Replaced old wallet top-up system. Tables: `linked_bank_accounts`.

### Cardano Wallet (Phase 1)
Auto-created HD wallet on Preview testnet. Mnemonic synced to `user_wallets` table, cached in `flutter_secure_storage`. Send/receive ADA, transaction history via Blockfrost.

### CIP-68 NFT Tickets (Phase 2A-2D)
- **2A Minting:** Purchase → stripe-webhook enqueues → `mint-ticket-nft` builds/signs/submits CIP-68 tx. All events NFT-enabled by default.
- **2B Transfer:** Resale triggers NFT transfer to new buyer via `transfer-ticket-nft`.
- **2C Admin:** NFT Wallet dashboard, per-event mint stats, retry controls.
- **2D Burn:** Auto-burn 60 days after event. Reclaims ~1.5 ADA per NFT to platform. Dual-witness (platform + buyer keys). `burn-expired-nfts` edge function.

### Offline Check-in (Priority 1)
SQLite door list with O(1) HashMap index. 3-tier verification: Offline → Blockchain → Database. Background sync every 7s. Conflict resolution. 34-test suite. `OfflineCheckInService`, `CheckInSyncService`, `BlockchainVerifyService`.

### Promo Codes (Priority 2)
Percentage or fixed discount codes per event. Server-side re-validation. One use per user per code. `validate_promo_code()` / `redeem_promo_code()` SQL functions. Works with both card and ACH checkout.

### Waitlists (Priority 3)
"Notify Me" or "Auto-Buy" modes. FIFO queue processed on resale listings. Off-session Stripe payment for auto-buy. pg_cron expires past-event waitlists. `process-waitlist` edge function.

### Apple/Google Wallet Passes (Priority 4)
PKPass generation + Google Wallet JWT. QR code for check-in. Pass updates on event changes. **Secrets not configured** — code ready, needs Apple/Google signing credentials.

### Seating Charts (Priority 5)
Phase 1: Drag-and-drop venue builder (sections, elements, seat generation). Phase 2: Seat selection at checkout with normalized grid, replace-selection UX, 10-min seat holds, seat labels on tickets.

### Recurring Events (Priority 6)
Daily/weekly/biweekly/monthly. Materialized occurrences (real `events` rows). Template snapshot JSONB. Rolling window via pg_cron. `event_series` table. Dart weekday → PG DOW: `date.weekday % 7`.

### Virtual Events (Priority 7)
In-Person/Virtual/Hybrid format. Meeting URL + password hidden until 1h before event. pg_cron lockdown every 5min: locks event, cancels resale listings, reveals link, notifies holders. `_VirtualEventCard` with "Join Event" button and countdown.

### Merch & Products (Priority 9)
Two systems: **Part A — Redeemable Tickets** (add-ons using existing ticket infrastructure) and **Part B — Physical Merch Store** (Enterprise-gated Shopify/Stripe integration).

**Part A:** `category` field on ticket types (`'entry'` or `'redeemable'`). Redeemable items (drink tokens, merch pickups, glow sticks) use same QR/check-in/resale/NFT infrastructure. Add-ons section in buy sheet below entry tickets. Webhook copies category from `ticket_items` metadata. SQLite offline schema v4 with category + item_icon.

**Part B:** Tables: `organizer_merch_config`, `merch_products`, `merch_variants`, `merch_orders` with full RLS. Edge functions: `sync-shopify-products`, `create-merch-payment`, `shopify-webhook`. Stripe webhook extended for `merch_purchase`. Flutter: `features/merch/` with models, repository, providers, 4 screens (ProductDetailScreen, OrganizerProductsScreen, OrganizerOrdersScreen, MyMerchOrdersScreen). Profile "My Orders" menu. EventDetailsScreen "Shop" section. AdminEventScreen "Merch Store" card. `MerchFeeCalculator` (5% platform + Stripe). Enterprise-only via `canUseMerchStore(tier)`.

### Embeddable Checkout Widget (Priority 8)
JavaScript widget organizers embed on their own website. iframe-based checkout modal with 3-step flow (select tickets → enter email → pay via Stripe Elements). Guest checkout creates lightweight Supabase auth users so existing ticket/webhook flow works unchanged.

**Architecture:** Widget JS (`tickety-widget.js`) fetches checkout HTML from `widget-checkout-page` edge function, injects into iframe via `srcdoc` (bypasses Supabase Storage Content-Type issues). Stripe Elements runs inside iframe for PCI compliance.

**Auth:** Widget API keys (`twk_live_xxx`) — SHA-256 hashed in DB, scoped by event IDs and allowed origins. Rate-limited (checkout sessions per key per minute). No buyer auth required (guest checkout).

**Database:** `widget_api_keys` (organizer keys with hash, scoping, rate limits), `widget_configs` (appearance customization), `widget_guest_buyers` (guest email/Stripe customer linking), `widget_checkout_sessions` (session tracking, 30min auto-expiry via pg_cron).

**Edge Functions:** `widget-get-event` (public event data + ticket types + widget config), `widget-create-checkout` (validates availability, creates guest user, Stripe PaymentIntent, payment record with `ticket_items` metadata), `widget-validate-promo` (promo code validation for guests), `widget-checkout-page` (serves checkout HTML with correct Content-Type). `stripe-webhook` updated to mark widget sessions as completed.

**Flutter:** `features/widget/` with models (`WidgetApiKey`, `WidgetConfig`), data (`WidgetRepository` with secure key generation via `crypto` package), presentation (`WidgetSettingsScreen` — key management, embed code snippet, appearance config). AdminEventScreen "Embed Widget" card. All tiers get widget access (Base requires "Powered by Tickety" branding).

**Embed code:**
```html
<script src="https://hnouslchigcmbiovdbfz.supabase.co/storage/v1/object/public/widget/v1/tickety-widget.js"></script>
<script>Tickety.init({ key: 'twk_live_xxx', eventId: 'uuid', container: '#btn' });</script>
```

## Dev Seed Data

Engagement seed data for dashboard development in `supabase/seeds/`. Marker: `analytics_cache_meta` where `key = 'dev_seed_marker'`. Idempotent insert, cleanup script included.

## Roadmap

### Priority 9 — Event Aggregation & External Listings (BLOCKED — awaiting affiliate approvals)

Populate the discovery feed with events from external sources to solve the cold-start problem. **Code is built and deployed** (database, edge functions, Flutter mixed feed UI) — blocked on API keys pending affiliate program approval.

**Legal research findings (March 2026):**
- **Ticketmaster API ToS** prohibits "deriving revenue" from API data — broadly worded, risky for a competing platform. Safe path: join their **Affiliate Program via Impact.com** (explicit permission + commission per referred sale, 1,200+ partners already do this).
- **SeatGeek API ToS** explicitly prohibits using API to "create a service that directly competes with SeatGeek" and bans persistent data caching (only transient/intermediate allowed). Safe path: **Partner Program via Impact.com** (~$11 avg commission per sale).
- **Web scraping alternative:** Legal precedent supports scraping public event data (*Ticketmaster v. Tickets.com, 2000* — factual data like dates/venues not copyrightable; *hiQ v. LinkedIn, 2022* — scraping public pages doesn't violate CFAA). However, practical risks (IP blocking, legal threats) and Terms of Service breach-of-contract claims make this less attractive than affiliate programs.
- **Other sources:** Eventbrite API deprecated (2019). Bandsintown locked to single-artist keys. Songkick/JamBase require commercial licenses. Facebook Events closed since 2018. PredictHQ is enterprise-priced.

**Action items:**
1. Apply for Ticketmaster Affiliate Program (Impact.com)
2. Apply for SeatGeek Partner Program (Impact.com)
3. Once approved, set API keys + affiliate tracking IDs as Supabase secrets
4. Trigger initial sync: `curl -X POST .../sync-ticketmaster-events`

**Code ready:** `external_events` table, `sync-ticketmaster-events`, `sync-seatgeek-events`, `cleanup-external-events` edge functions, `ExternalEvent` model, `ExternalEventRepository`, mixed feed in `EventsHomeScreen` with source badges and deep links.

### Priority 10 — Event Discovery Algorithm

The home feed currently shows events in basic chronological order. We need a smart recommendation/ranking algorithm that surfaces events users are actually interested in, similar to how Steam handles discovery across many genres and niches.

**Problem:** Most discovery algorithms are proprietary (Spotify Discover, TikTok For You, Steam Discovery Queue). We need to build something that works well at small scale (hundreds of events) and scales to large (millions). Cold-start problem is real — new users have no history.

**Key Signals to Rank On:**
- **Popularity:** Ticket sales velocity (sales/hour), total sales, sell-through rate (% of capacity sold)
- **Engagement:** View count, view-to-purchase conversion rate, save/favorite count, share count
- **Recency:** Time decay — newer events ranked higher, stale events demoted
- **Proximity:** Distance from user's location (lat/lng from device or profile)
- **Social proof:** Friends attending (requires social graph, later phase), organizer follower count
- **User affinity:** Tags/categories the user has purchased or viewed before (collaborative filtering lite)
- **Organizer quality:** Verification status, average event rating, refund rate, report count
- **Price sensitivity:** Match user's historical price range

**Approach — Hybrid Scoring (inspired by Steam):**

Steam's approach works because it combines multiple independent signals with tunable weights, doesn't require deep ML, and handles the cold-start problem via popularity fallback. Their discovery queue uses a weighted scoring model, not pure collaborative filtering.

1. **Base Score** = `popularity_score * recency_decay * organizer_quality`
   - `popularity_score`: normalized 0-1 from sales velocity + engagement metrics
   - `recency_decay`: exponential decay, e.g., `e^(-0.05 * days_until_event)` (sweet spot ~2-4 weeks out)
   - `organizer_quality`: verified=1.2x, high-rating=1.1x, reported=0.5x

2. **Personalization Layer** (when user has history):
   - Tag affinity vector: track which tags/categories user interacts with, weight events matching those tags
   - Price band matching: if user typically buys $20-50 tickets, boost events in that range
   - Location preference: boost events near user's past attendance locations
   - "More like this": Jaccard similarity on tags between events user attended and available events

3. **Cold-Start Fallback** (new users):
   - Pure popularity + proximity ranking
   - Trending: highest sales velocity in last 48h
   - "Popular near you" if location available
   - Diverse category sampling (don't show all music events — mix genres)

4. **Feed Sections:**
   - "Trending Now" — highest velocity events (real-time-ish, refreshed hourly)
   - "Popular Near You" — proximity + popularity
   - "Because You Attended [X]" — tag-based similarity to past purchases
   - "New This Week" — recently created, boosted for discovery
   - "Almost Sold Out" — urgency signal, >80% capacity sold
   - "Free Events" — separate section, lower barrier to entry

**Database:**
- `user_event_interactions` — user_id, event_id, interaction_type (view/save/share/purchase), created_at
- `event_scores` — Materialized scoring table, refreshed by cron. Columns: event_id, popularity_score, velocity_score, engagement_score, composite_score, trending_rank
- `user_tag_affinity` — user_id, tag, affinity_score (incremented on view/purchase, decayed over time)
- SQL function: `get_personalized_feed(user_id, lat, lng, page, page_size)` — combines composite score with user affinity

**Implementation Phases:**
- Phase A: Popularity ranking (velocity + engagement + recency decay). No personalization. Just show better events first.
- Phase B: Location-aware ranking. Proximity boost when user location available.
- Phase C: Tag affinity personalization. Track user interactions, build affinity vectors, personalize feed.
- Phase D: Feed sections (trending, near you, similar, etc.). Multiple ranked lists on home screen.

### Priority 11 — White-Labeling & Custom Domains

Organizers hide Tickety branding, use their own logo/colors. Custom domain for ticket pages (tickets.yourbrand.com). Branded email notifications.

### Priority 12 — Public API

REST API for organizers to integrate with their own systems. Endpoints: events, tickets, orders, check-ins, discount codes. API key auth, rate limiting, webhook subscriptions. Developer documentation site.

### Priority 13 — Affiliate & Referral Tracking

Unique referral links per sales channel. Performance dashboard showing which channels drive sales. Commission tracking for affiliates.

### Priority 14 — Localization (i18n)

Multi-language checkout and app UI. Start with Spanish, French, German, Portuguese. Currency formatting per locale. RTL support for Arabic/Hebrew (later phase). Best done last when all user-facing text is finalized.

## Future: Cardano Phase 3

- Multi-address derivation for privacy
- Mainnet deployment (switch Blockfrost base URL + project ID)
- Organizer NFT customization (custom metadata fields, artwork)

## Competitive Landscape

**Ticket Tailor** (~73K organizers, $6.6M ARR, $0.26/ticket) — Primary ticketing for small/mid organizers. Bootstrapped via cold-calling venues. No buyer app, no resale, no NFTs.

**TicketSwap** (~11M users, ~$39M ARR, 36 countries) — Fan-to-fan resale marketplace. 20% max markup. "SecureSwap" reissues barcodes via primary ticketing API partnerships. Events appear when sellers upload tickets (seller-driven catalog). $12.2M total funding.

**DICE** — Primary ticketing with locked resale (no above-face-value). Strong in UK/US. Mobile-first.

**Twickets** — Face-value only resale. UK/Europe/US.

**Tickety advantages:**
- NFT tickets (CIP-68 on Cardano), crypto wallet (ADA), built-in resale marketplace
- ACH bank payments, native buyer app, event discovery algorithm
- Tap-to-pay NFC, comp/favor tickets, organizer verification
- Redeemable ticket add-ons, physical merch store (Shopify/Stripe), seating charts
- Embeddable checkout widget (iframe, guest checkout, Stripe Elements)
- External event aggregation via affiliate programs (Ticketmaster/SeatGeek) for cold-start bootstrap + commission revenue
