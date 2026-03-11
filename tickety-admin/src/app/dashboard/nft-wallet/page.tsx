"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { KpiCard } from "@/components/dashboard/kpi-card";
import {
  RefreshCw,
  Wallet,
  CheckCircle2,
  XCircle,
  Clock,
  Coins,
  Calendar,
  Ticket,
  ExternalLink,
  Copy,
  AlertTriangle,
  Loader2,
  SkipForward,
  Filter,
  X,
} from "lucide-react";
import { Input } from "@/components/ui/input";

interface WalletInfo {
  address: string | null;
  balanceAda: number;
  utxoCount: number;
  network: string;
}

interface QueueStats {
  queued: number;
  minting: number;
  minted: number;
  failed: number;
  skipped: number;
  burning: number;
  burned: number;
}

interface NftStats {
  nftEnabledEvents: number;
  totalMintedTickets: number;
}

interface QueueEntry {
  id: string;
  ticket_id: string;
  event_id: string;
  buyer_address: string;
  status: string;
  tx_hash: string | null;
  policy_id: string | null;
  error_message: string | null;
  retry_count: number;
  created_at: string;
  updated_at: string;
}

interface DashboardData {
  wallet: WalletInfo;
  queue: QueueStats;
  stats: NftStats;
  recentQueue: QueueEntry[];
}

export default function NftWalletPage() {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [eventFilter, setEventFilter] = useState("");
  const [retryLoading, setRetryLoading] = useState<string | null>(null);

  const fetchData = async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/admin/nft-wallet");
      const json = await res.json();
      setData(json);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const handleRetry = async (queueId: string) => {
    setRetryLoading(queueId);
    try {
      await fetch("/api/admin/nft-wallet", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "retry", queue_id: queueId }),
      });
      await fetchData();
    } finally {
      setRetryLoading(null);
    }
  };

  const filteredQueue = data?.recentQueue.filter((entry) => {
    if (!eventFilter) return true;
    return entry.event_id.toLowerCase().includes(eventFilter.toLowerCase());
  }) ?? [];

  const copyAddress = () => {
    if (data?.wallet.address) {
      navigator.clipboard.writeText(data.wallet.address);
    }
  };

  const truncate = (s: string, len = 16) =>
    s.length > len ? `${s.slice(0, len / 2)}...${s.slice(-len / 2)}` : s;

  const statusBadge = (status: string) => {
    const styles: Record<string, string> = {
      queued: "border-blue-500/30 text-blue-400",
      minting: "border-amber-500/30 text-amber-400",
      minted: "border-emerald-500/30 text-emerald-400",
      failed: "border-red-500/30 text-red-400",
      skipped: "border-zinc-500/30 text-zinc-400",
      burning: "border-orange-500/30 text-orange-400",
      burned: "border-purple-500/30 text-purple-400",
    };
    return (
      <Badge variant="outline" className={styles[status] ?? "text-zinc-400"}>
        {status}
      </Badge>
    );
  };

  const statusIcon = (status: string) => {
    switch (status) {
      case "minted":
        return <CheckCircle2 className="h-4 w-4 text-emerald-400" />;
      case "failed":
        return <XCircle className="h-4 w-4 text-red-400" />;
      case "minting":
        return <Loader2 className="h-4 w-4 animate-spin text-amber-400" />;
      case "queued":
        return <Clock className="h-4 w-4 text-blue-400" />;
      case "skipped":
        return <SkipForward className="h-4 w-4 text-zinc-400" />;
      case "burning":
        return <Loader2 className="h-4 w-4 animate-spin text-orange-400" />;
      case "burned":
        return <Coins className="h-4 w-4 text-purple-400" />;
      default:
        return null;
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white">NFT Wallet</h1>
        <Button
          variant="outline"
          size="sm"
          onClick={fetchData}
          disabled={loading}
          className="border-zinc-700 bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
        >
          <RefreshCw
            className={`mr-2 h-3 w-3 ${loading ? "animate-spin" : ""}`}
          />
          Refresh
        </Button>
      </div>

      {/* Platform Wallet Card */}
      <Card className="border-zinc-800 bg-zinc-900">
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-sm font-medium text-zinc-400">
            <Wallet className="h-4 w-4" />
            Platform Minting Wallet
            <Badge
              variant="outline"
              className="ml-2 border-indigo-500/30 text-indigo-400"
            >
              {data?.wallet.network ?? "preview"} testnet
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {loading && !data ? (
            <Skeleton className="h-20 w-full bg-zinc-800" />
          ) : data?.wallet.address ? (
            <>
              <div className="flex items-center gap-2">
                <code className="flex-1 rounded bg-zinc-800 px-3 py-2 font-mono text-sm text-zinc-300">
                  {data.wallet.address}
                </code>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={copyAddress}
                  className="text-zinc-400 hover:text-white"
                >
                  <Copy className="h-4 w-4" />
                </Button>
                <a
                  href={`https://preview.cardanoscan.io/address/${data.wallet.address}`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <Button
                    variant="ghost"
                    size="icon"
                    className="text-zinc-400 hover:text-white"
                  >
                    <ExternalLink className="h-4 w-4" />
                  </Button>
                </a>
              </div>
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
                <div>
                  <p className="text-xs text-zinc-500">Balance</p>
                  <p className="text-lg font-semibold text-white">
                    {data.wallet.balanceAda.toFixed(2)} ADA
                  </p>
                </div>
                <div>
                  <p className="text-xs text-zinc-500">UTxOs</p>
                  <p className="text-lg font-semibold text-white">
                    {data.wallet.utxoCount}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-zinc-500">Status</p>
                  <p className="text-lg font-semibold text-emerald-400">
                    {data.wallet.balanceAda > 5 ? "Funded" : data.wallet.balanceAda > 0 ? "Low" : "Empty"}
                  </p>
                </div>
              </div>
              {data.wallet.balanceAda < 5 && data.wallet.balanceAda > 0 && (
                <div className="flex items-center gap-2 rounded bg-amber-500/10 px-3 py-2 text-sm text-amber-400">
                  <AlertTriangle className="h-4 w-4" />
                  Low balance — each mint costs ~0.5 ADA. Fund from the Preview faucet.
                </div>
              )}
              {data.wallet.balanceAda === 0 && (
                <div className="flex items-center gap-2 rounded bg-red-500/10 px-3 py-2 text-sm text-red-400">
                  <XCircle className="h-4 w-4" />
                  Wallet is empty — minting will fail. Fund from the Preview faucet.
                </div>
              )}
            </>
          ) : (
            <div className="rounded bg-red-500/10 px-3 py-2 text-sm text-red-400">
              No minting address configured. Insert into platform_cardano_config table.
            </div>
          )}
        </CardContent>
      </Card>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7">
        <KpiCard
          label="Queued"
          value={String(data?.queue.queued ?? 0)}
          icon={Clock}
          loading={loading && !data}
        />
        <KpiCard
          label="Minting"
          value={String(data?.queue.minting ?? 0)}
          icon={Loader2}
          loading={loading && !data}
        />
        <KpiCard
          label="Minted"
          value={String(data?.queue.minted ?? 0)}
          icon={CheckCircle2}
          loading={loading && !data}
          deltaType="positive"
        />
        <KpiCard
          label="Burned"
          value={String(data?.queue.burned ?? 0)}
          icon={Coins}
          loading={loading && !data}
        />
        <KpiCard
          label="Failed"
          value={String(data?.queue.failed ?? 0)}
          icon={XCircle}
          loading={loading && !data}
          deltaType={data?.queue.failed ? "negative" : undefined}
        />
        <KpiCard
          label="NFT Events"
          value={String(data?.stats.nftEnabledEvents ?? 0)}
          icon={Calendar}
          loading={loading && !data}
        />
        <KpiCard
          label="NFT Tickets"
          value={String(data?.stats.totalMintedTickets ?? 0)}
          icon={Ticket}
          loading={loading && !data}
        />
      </div>

      {/* Recent Mint Queue */}
      <Card className="border-zinc-800 bg-zinc-900">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-sm font-medium text-zinc-400">
            Mint Queue (Recent 50)
          </CardTitle>
          <div className="relative w-64">
            <Filter className="absolute left-2 top-1/2 h-3 w-3 -translate-y-1/2 text-zinc-500" />
            <Input
              placeholder="Filter by event ID..."
              value={eventFilter}
              onChange={(e) => setEventFilter(e.target.value)}
              className="h-8 border-zinc-700 bg-zinc-800 pl-7 text-xs text-white placeholder:text-zinc-500"
            />
            {eventFilter && (
              <button
                onClick={() => setEventFilter("")}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-zinc-500 hover:text-zinc-300"
              >
                <X className="h-3 w-3" />
              </button>
            )}
          </div>
        </CardHeader>
        <CardContent>
          {loading && !data ? (
            <div className="space-y-2">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-14 w-full bg-zinc-800" />
              ))}
            </div>
          ) : !filteredQueue.length ? (
            <p className="py-8 text-center text-sm text-zinc-500">
              {eventFilter
                ? "No entries match this event ID."
                : "No mint queue entries yet. Create an NFT-enabled event and purchase a ticket to trigger minting."}
            </p>
          ) : (
            <div className="space-y-2">
              {filteredQueue.map((entry) => (
                <div
                  key={entry.id}
                  className="flex items-center justify-between rounded-lg border border-zinc-800 bg-zinc-950 p-3"
                >
                  <div className="flex items-center gap-3">
                    {statusIcon(entry.status)}
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-xs text-zinc-300">
                          {truncate(entry.ticket_id)}
                        </span>
                        {statusBadge(entry.status)}
                        {entry.retry_count > 0 && (
                          <span className="text-xs text-zinc-500">
                            retry #{entry.retry_count}
                          </span>
                        )}
                      </div>
                      <p className="mt-0.5 font-mono text-[10px] text-zinc-600">
                        event: {truncate(entry.event_id, 12)}
                      </p>
                      {entry.error_message && (
                        <p className="mt-1 max-w-md truncate text-xs text-red-400">
                          {entry.error_message}
                        </p>
                      )}
                      {entry.tx_hash && (
                        <a
                          href={`https://preview.cardanoscan.io/transaction/${entry.tx_hash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="mt-1 flex items-center gap-1 text-xs text-indigo-400 hover:underline"
                        >
                          {truncate(entry.tx_hash, 20)}
                          <ExternalLink className="h-3 w-3" />
                        </a>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    {entry.status === "failed" && (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => handleRetry(entry.id)}
                        disabled={retryLoading === entry.id}
                        className="border-amber-500/30 text-amber-400 hover:bg-amber-950/30"
                      >
                        {retryLoading === entry.id ? (
                          <RefreshCw className="h-3 w-3 animate-spin" />
                        ) : (
                          "Retry"
                        )}
                      </Button>
                    )}
                    <div className="text-right">
                      <p className="text-xs text-zinc-500">
                        {new Date(entry.created_at).toLocaleDateString()}
                      </p>
                      <p className="text-xs text-zinc-600">
                        {new Date(entry.created_at).toLocaleTimeString()}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
