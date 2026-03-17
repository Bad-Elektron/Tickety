# Competitive Analysis & Go-To-Market Strategy

## Market Map

The ticketing market is fragmented into specialists. Nobody does the full vertical.

| Platform | Primary Sales | Resale | Buyer App | Organizer Tools | NFTs | Merch |
|----------|:---:|:---:|:---:|:---:|:---:|:---:|
| **Tickety** | Yes | Yes | Yes | Yes | Yes | Yes |
| **TicketSwap** | No | Yes | Yes | No | No | No |
| **Ticket Tailor** | Yes | No | No | Yes | No | No |
| **Eventbrite** | Yes | No | Yes | Yes | No | No |
| **DICE** | Yes | Locked | Yes | Limited | No | No |
| **StubHub/Viagogo** | No | Yes | Yes | No | No | No |
| **Ticketmaster** | Yes | Yes | Yes | Yes | No | No |
| **Twickets** | No | Face-value | Yes | No | No | No |

## Key Competitors

### TicketSwap
- **What:** Fan-to-fan resale marketplace (secondary market only)
- **Scale:** ~11M users, ~$39M ARR, 36 countries, 6K+ event partnerships
- **Funding:** $12.2M (Series A)
- **HQ:** Amsterdam (2012)
- **Traffic:** ~1.7-1.9M monthly web visits, 44.5% direct, 33% organic search
- **Model:** Commission on both buyer and seller per transaction. 20% max markup over face value.
- **Key feature:** "SecureSwap/Sealed Tickets" — partners with primary ticketing companies (Eventix, See Tickets) via API to invalidate original barcodes and reissue new ones on resale, eliminating fraud.
- **How events get listed:** Seller-driven. Events appear when a fan uploads a ticket for resale. For partnered events, organizers proactively enable the resale channel. No API aggregation.
- **Weakness:** No primary ticketing. Entirely dependent on other platforms selling the initial tickets. Revenue leaks from organizers' ecosystems.

### Ticket Tailor
- **What:** Primary ticketing platform for organizers (no buyer app)
- **Scale:** ~73K organizers, $6.6M ARR, $0.26/ticket
- **Model:** Per-ticket fee to organizers. No buyer-facing app.
- **Bootstrapped by:** Cold-calling venues directly
- **Weakness:** No buyer app, no resale marketplace, no event discovery. Organizers' customers have no reason to come back.

### DICE
- **What:** Primary ticketing with locked resale (no above-face-value)
- **Scale:** UK, US, Europe. Mobile-first. Backed by SoftBank.
- **Model:** Tickets live only in the DICE app. No PDFs, no transfers outside the app. If you can't attend, DICE handles the resale at face value via a waiting list.
- **Weakness:** Very locked down. Organizers have limited control. No organizer tools beyond basic event creation.

### Eventbrite
- **What:** Primary ticketing + event discovery
- **Scale:** Public company, millions of events
- **Model:** Per-ticket fees + subscription tiers for organizers
- **Weakness:** Search API deprecated (Dec 2019). No resale. Platform feels dated. Heavy competition from free alternatives for small events. No NFTs, no crypto, no merch.

### Ticketmaster / Live Nation
- **What:** Full-stack but closed ecosystem. Owns venues, promotes tours, sells tickets.
- **Scale:** Dominant in large events globally
- **Weakness:** Universally hated (fees, anti-competitive behavior, bot problems). DOJ antitrust case pending. Small/mid organizers can't access the platform. Doesn't serve the long tail.

### Twickets
- **What:** Face-value only resale
- **Scale:** UK, Europe, US
- **Model:** Strict face-value policy. Partners with organizers and venues.
- **Weakness:** Very niche. No primary ticketing. Limited scale.

## Why TicketSwap Isn't a Direct Threat

TicketSwap is resale-only. They don't sell primary tickets. The reason TicketSwap exists is because primary platforms like Eventbrite and Ticket Tailor have **no built-in resale**. Fans who can't attend have nowhere to go except a third-party marketplace.

**Tickety makes TicketSwap unnecessary** for events sold on our platform — resale is built in. Revenue from resale stays in the organizer's ecosystem instead of leaking to a third party.

TicketSwap's "SecureSwap" feature (barcode reissuance) is impressive, but it requires partnerships with primary ticketing companies. Tickety doesn't need this — we control the entire ticket lifecycle from creation to check-in.

## Where Tickety Wins

### Full Vertical Integration
One platform handles everything: event creation → ticket sales → resale → merch → check-in → analytics → NFTs. No revenue leakage. No fragmented tooling.

### Built-in Resale as Organizer Lock-in
Organizers on Tickety don't need TicketSwap. Their fans resell within the same ecosystem. The organizer retains visibility and can set resale rules. This is a retention moat — once an organizer's tickets are on Tickety with active resale, switching costs go up.

### NFT Tickets (CIP-68 on Cardano)
No competitor has on-chain tickets. This is a differentiator for Web3 events, crypto conferences, and tech-forward organizers. Also enables provable authenticity without needing TicketSwap-style barcode partnerships.

### Redeemable Add-ons + Merch
Drink tokens, merch pickups, VIP perks — all using the same ticket infrastructure. Plus a full Shopify/Stripe merch store for Enterprise organizers. No competitor combines ticketing + merch in one platform.

### Underserved Niche Opportunity
TicketSwap and Ticketmaster focus on big concerts/festivals. The long tail of small events (local comedy, community theater, meetups, church events, school fundraisers, crypto meetups) is poorly served and represents massive volume. Ticket Tailor proved this market exists (73K organizers) but left money on the table by having no buyer app.

## The Real Problem: Distribution

Features don't matter without users. Tickety has every feature advantage but zero users. TicketSwap has 11M.

### Bootstrap Strategy (Three Prongs)

**Prong 1: Event Aggregation via Affiliate Programs (Priority 9 — blocked on approvals)**
Fill the app with Ticketmaster/SeatGeek events. Buyers download Tickety and see a full event catalog immediately. Native Tickety events are mixed in. Over time, the ratio shifts as organizers adopt the platform. **Bonus: earn commission on every referred ticket sale.**

- **Must use affiliate programs** — both APIs have ToS restrictions against competing platforms using data directly
- Ticketmaster Affiliate Program (via Impact.com): explicit permission + commission per referred sale
- SeatGeek Partner Program (via Impact.com): ~$11 avg commission per sale
- Legal research: scraping public event data is legal (*Ticketmaster v. Tickets.com, 2000*; *hiQ v. LinkedIn, 2022*) but affiliate route is safer + generates revenue
- Code is built and deployed, awaiting affiliate approvals + API keys
- External events display with source badge + deep link to source for purchase
- Future: "Claim this event" lets organizers take ownership and sell natively

**Prong 2: Embeddable Widget (Priority 8)**
JavaScript checkout widget organizers drop on their own website. Zero friction — they don't change their workflow, but their events flow into Tickety's catalog and their customers become Tickety users. This is how you build supply without cold-calling.

**Prong 3: Niche Targeting**
Go where Ticketmaster and TicketSwap don't:
- **Web3/crypto events** — NFT tickets are a genuine differentiator here
- **Small local events** — comedy nights, community theater, school fundraisers
- **Markets where TicketSwap isn't present** — they're in 36 countries but thin outside Europe
- **Organizers frustrated with Eventbrite** — dated platform, no resale, high fees

### Flywheel

```
Event aggregation → Buyers discover events → Download app
                                                    ↓
Embeddable widget → Organizers connect events → More native events in feed
                                                    ↓
More buyers → More resale activity → More organizer value → More organizers
                                                    ↓
Built-in resale + merch + NFTs = switching cost moat
```

## Competitive Advantages Summary

| Advantage | vs TicketSwap | vs Ticket Tailor | vs Eventbrite | vs DICE |
|-----------|:---:|:---:|:---:|:---:|
| Primary + secondary in one | We do both | They have no resale | They have no resale | Locked resale only |
| Buyer app + discovery | Both have | They don't | Theirs is weak | Both have |
| NFT tickets | We have | They don't | They don't | They don't |
| Crypto wallet | We have | They don't | They don't | They don't |
| Merch store | We have | They don't | They don't | They don't |
| Redeemable add-ons | We have | They don't | They don't | They don't |
| Offline check-in | We have | Basic | Basic | They have |
| Seating charts | We have | They have | They have | They don't |
| ACH bank payments | We have | They don't | They don't | They don't |
| Embeddable widget | Planned (P8) | They have | They have | They don't |
| Event aggregation | Planned (P9) | They don't | Deprecated | They don't |

## What We Need to Watch

- **DICE** is the closest to our full-vertical model. If they add organizer tools and merch, they become the primary threat.
- **TicketSwap's SecureSwap partnerships** with primary platforms are growing. If they partner with enough primaries, they become a de facto standard for resale.
- **Ticketmaster's DOJ antitrust case** could reshape the market entirely. A breakup or consent decree could open doors for alternatives.
- **Eventbrite** could wake up and add resale. They have the user base but seem focused on enterprise.
