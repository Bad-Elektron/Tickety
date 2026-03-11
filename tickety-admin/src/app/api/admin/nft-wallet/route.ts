import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

const BLOCKFROST_BASE = "https://cardano-preview.blockfrost.io/api/v0";
const BLOCKFROST_PROJECT_ID = process.env.BLOCKFROST_PROJECT_ID ?? "";

async function blockfrostGet(path: string) {
  const res = await fetch(`${BLOCKFROST_BASE}${path}`, {
    headers: { project_id: BLOCKFROST_PROJECT_ID },
    next: { revalidate: 30 },
  });
  if (!res.ok) return null;
  return res.json();
}

export async function GET(request: NextRequest) {
  const supabase = createAdminClient();
  const eventId = request.nextUrl.searchParams.get("event_id");

  // If event_id is provided, return per-event NFT stats
  if (eventId) {
    const { data: entries } = await supabase
      .from("nft_mint_queue")
      .select("id, ticket_id, status, tx_hash, policy_id, error_message, retry_count, action, created_at")
      .eq("event_id", eventId)
      .order("created_at", { ascending: false })
      .limit(50);

    const queue: Record<string, number> = {};
    let policyId: string | null = null;
    for (const entry of entries ?? []) {
      queue[entry.status] = (queue[entry.status] ?? 0) + 1;
      if (!policyId && entry.policy_id) policyId = entry.policy_id;
    }

    // Also check event's nft_policy_id
    if (!policyId) {
      const { data: evt } = await supabase
        .from("events")
        .select("nft_policy_id")
        .eq("id", eventId)
        .single();
      if (evt?.nft_policy_id) policyId = evt.nft_policy_id;
    }

    return NextResponse.json({
      eventNft: { queue, policyId, entries: entries ?? [] },
    });
  }

  // Global dashboard (original behavior)

  // Fetch platform config
  const { data: configRows } = await supabase
    .from("platform_cardano_config")
    .select("key, value");

  const config: Record<string, string> = {};
  for (const row of configRows ?? []) {
    config[row.key] = row.value;
  }

  const mintingAddress = config.minting_address ?? null;

  // Fetch wallet balance from Blockfrost
  let balanceAda = 0;
  let utxoCount = 0;
  if (mintingAddress && BLOCKFROST_PROJECT_ID) {
    const addressInfo = await blockfrostGet(`/addresses/${mintingAddress}`);
    if (addressInfo) {
      const lovelace = addressInfo.amount?.find(
        (a: any) => a.unit === "lovelace"
      );
      balanceAda = lovelace
        ? parseInt(lovelace.quantity) / 1_000_000
        : 0;
    }
    const utxos = await blockfrostGet(`/addresses/${mintingAddress}/utxos`);
    utxoCount = Array.isArray(utxos) ? utxos.length : 0;
  }

  // Fetch mint queue stats
  const [queuedResult, mintingResult, mintedResult, failedResult, skippedResult, burningResult, burnedResult, recentResult] =
    await Promise.all([
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "queued"),
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "minting"),
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "minted"),
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "failed"),
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "skipped"),
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "burning"),
      supabase
        .from("nft_mint_queue")
        .select("*", { count: "exact", head: true })
        .eq("status", "burned"),
      supabase
        .from("nft_mint_queue")
        .select("id, ticket_id, event_id, buyer_address, status, tx_hash, policy_id, error_message, retry_count, action, created_at, updated_at")
        .order("created_at", { ascending: false })
        .limit(50),
    ]);

  // Fetch NFT-enabled events count
  const { count: nftEnabledEvents } = await supabase
    .from("events")
    .select("*", { count: "exact", head: true })
    .eq("nft_enabled", true)
    .is("deleted_at", null);

  // Fetch total minted tickets
  const { count: totalMintedTickets } = await supabase
    .from("tickets")
    .select("*", { count: "exact", head: true })
    .eq("nft_minted", true);

  return NextResponse.json({
    wallet: {
      address: mintingAddress,
      balanceAda,
      utxoCount,
      network: "preview",
    },
    queue: {
      queued: queuedResult.count ?? 0,
      minting: mintingResult.count ?? 0,
      minted: mintedResult.count ?? 0,
      failed: failedResult.count ?? 0,
      skipped: skippedResult.count ?? 0,
      burning: burningResult.count ?? 0,
      burned: burnedResult.count ?? 0,
    },
    stats: {
      nftEnabledEvents: nftEnabledEvents ?? 0,
      totalMintedTickets: totalMintedTickets ?? 0,
    },
    recentQueue: recentResult.data ?? [],
  });
}

export async function POST(request: NextRequest) {
  const supabase = createAdminClient();
  const body = await request.json();

  if (body.action === "retry" && body.queue_id) {
    // Reset a failed mint queue entry to "queued" for retry
    const { error } = await supabase
      .from("nft_mint_queue")
      .update({ status: "queued", error_message: null })
      .eq("id", body.queue_id)
      .eq("status", "failed");

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Fire-and-forget: trigger the mint/transfer function
    const { data: entry } = await supabase
      .from("nft_mint_queue")
      .select("action")
      .eq("id", body.queue_id)
      .single();

    const fnName = entry?.action === "burn" ? "burn-expired-nfts"
      : entry?.action === "transfer" ? "transfer-ticket-nft" : "mint-ticket-nft";
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL ?? "";
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

    if (supabaseUrl && serviceKey) {
      fetch(`${supabaseUrl}/functions/v1/${fnName}`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ queue_id: body.queue_id }),
      }).catch(() => {});
    }

    return NextResponse.json({ success: true });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
