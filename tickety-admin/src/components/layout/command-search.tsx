"use client";

import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { Users, Calendar, Ticket, CreditCard } from "lucide-react";

interface SearchResults {
  users: { id: string; display_name: string | null; email: string | null; handle: string | null }[];
  events: { id: string; title: string; city: string | null; date: string }[];
  tickets: { id: string; ticket_number: string; owner_email: string | null; event_id: string }[];
  payments: { id: string; stripe_payment_intent_id: string | null; amount_cents: number; status: string }[];
}

export function CommandSearch() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResults | null>(null);
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setOpen((o) => !o);
      }
    };
    document.addEventListener("keydown", down);
    return () => document.removeEventListener("keydown", down);
  }, []);

  const search = useCallback(async (q: string) => {
    if (q.length < 2) {
      setResults(null);
      return;
    }
    setLoading(true);
    try {
      const res = await fetch(`/api/admin/search?q=${encodeURIComponent(q)}`);
      const data = await res.json();
      setResults(data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => search(query), 300);
    return () => clearTimeout(timer);
  }, [query, search]);

  const navigate = (path: string) => {
    setOpen(false);
    setQuery("");
    setResults(null);
    router.push(path);
  };

  const hasResults =
    results &&
    (results.users.length > 0 ||
      results.events.length > 0 ||
      results.tickets.length > 0 ||
      results.payments.length > 0);

  return (
    <CommandDialog open={open} onOpenChange={setOpen}>
      <CommandInput
        placeholder="Search users, events, tickets, payments..."
        value={query}
        onValueChange={setQuery}
      />
      <CommandList>
        {loading && (
          <div className="p-4 text-center text-sm text-zinc-500">
            Searching...
          </div>
        )}
        {!loading && query.length >= 2 && !hasResults && (
          <CommandEmpty>No results found.</CommandEmpty>
        )}
        {results && results.users.length > 0 && (
          <CommandGroup heading="Users">
            {results.users.map((u) => (
              <CommandItem
                key={u.id}
                onSelect={() => navigate(`/dashboard/users/${u.id}`)}
                className="cursor-pointer"
              >
                <Users className="mr-2 h-4 w-4 text-zinc-400" />
                <div>
                  <span className="text-white">
                    {u.display_name ?? u.email}
                  </span>
                  {u.handle && (
                    <span className="ml-2 text-xs text-zinc-500">
                      {u.handle}
                    </span>
                  )}
                  {u.email && u.display_name && (
                    <span className="ml-2 text-xs text-zinc-500">
                      {u.email}
                    </span>
                  )}
                </div>
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        {results && results.events.length > 0 && (
          <CommandGroup heading="Events">
            {results.events.map((e) => (
              <CommandItem
                key={e.id}
                onSelect={() => navigate(`/dashboard/events/${e.id}`)}
                className="cursor-pointer"
              >
                <Calendar className="mr-2 h-4 w-4 text-zinc-400" />
                <span className="text-white">{e.title}</span>
                {e.city && (
                  <span className="ml-2 text-xs text-zinc-500">{e.city}</span>
                )}
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        {results && results.tickets.length > 0 && (
          <CommandGroup heading="Tickets">
            {results.tickets.map((t) => (
              <CommandItem
                key={t.id}
                onSelect={() => navigate(`/dashboard/tickets`)}
                className="cursor-pointer"
              >
                <Ticket className="mr-2 h-4 w-4 text-zinc-400" />
                <span className="font-mono text-xs text-white">
                  {t.ticket_number}
                </span>
                {t.owner_email && (
                  <span className="ml-2 text-xs text-zinc-500">
                    {t.owner_email}
                  </span>
                )}
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        {results && results.payments.length > 0 && (
          <CommandGroup heading="Payments">
            {results.payments.map((p) => (
              <CommandItem
                key={p.id}
                onSelect={() => navigate(`/dashboard/payments`)}
                className="cursor-pointer"
              >
                <CreditCard className="mr-2 h-4 w-4 text-zinc-400" />
                <span className="font-mono text-xs text-white">
                  {p.stripe_payment_intent_id ?? p.id.slice(0, 8)}
                </span>
                <span className="ml-2 text-xs text-zinc-500">
                  ${(p.amount_cents / 100).toFixed(2)} - {p.status}
                </span>
              </CommandItem>
            ))}
          </CommandGroup>
        )}
      </CommandList>
    </CommandDialog>
  );
}
