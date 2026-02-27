"use client";

import { useGetIdentity, useLogout } from "@refinedev/core";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { CommandSearch } from "@/components/layout/command-search";
import { LogOut, Search } from "lucide-react";

interface Identity {
  id: string;
  email: string;
  role: string;
}

export function Header() {
  const { data: identity } = useGetIdentity<Identity>();
  const { mutate: logout } = useLogout();

  return (
    <>
      <CommandSearch />
      <header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-zinc-800 bg-zinc-950/80 px-6 backdrop-blur-sm">
        <Button
          variant="outline"
          size="sm"
          className="border-zinc-700 bg-zinc-800/50 text-zinc-500 hover:bg-zinc-800 hover:text-zinc-300"
          onClick={() =>
            document.dispatchEvent(
              new KeyboardEvent("keydown", { key: "k", metaKey: true })
            )
          }
        >
          <Search className="mr-2 h-3 w-3" />
          Search...
          <kbd className="ml-4 rounded border border-zinc-700 bg-zinc-800 px-1.5 py-0.5 text-[10px] text-zinc-500">
            Ctrl+K
          </kbd>
        </Button>
        <div className="flex items-center gap-4">
          {identity && (
            <>
              <span className="text-sm text-zinc-400">{identity.email}</span>
              <Badge
                variant="outline"
                className="border-indigo-500/30 text-indigo-400"
              >
                {identity.role}
              </Badge>
            </>
          )}
          <Button
            variant="ghost"
            size="sm"
            onClick={() => logout()}
            className="text-zinc-400 hover:text-white"
          >
            <LogOut className="mr-2 h-4 w-4" />
            Sign out
          </Button>
        </div>
      </header>
    </>
  );
}
