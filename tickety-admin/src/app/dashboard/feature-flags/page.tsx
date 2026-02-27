"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { formatRelative } from "@/lib/utils/format";
import { Flag, Plus, Trash2, RefreshCw } from "lucide-react";

interface FeatureFlag {
  id: string;
  key: string;
  enabled: boolean;
  description: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

export default function FeatureFlagsPage() {
  const [flags, setFlags] = useState<FeatureFlag[]>([]);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState<string | null>(null);
  const [newKey, setNewKey] = useState("");
  const [newDesc, setNewDesc] = useState("");
  const [creating, setCreating] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);

  const fetchFlags = async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/admin/feature-flags");
      const data = await res.json();
      setFlags(Array.isArray(data) ? data : []);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchFlags();
  }, []);

  const handleToggle = async (id: string, enabled: boolean) => {
    setToggling(id);
    try {
      await fetch("/api/admin/feature-flags", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id, enabled }),
      });
      setFlags((prev) =>
        prev.map((f) => (f.id === id ? { ...f, enabled } : f))
      );
    } finally {
      setToggling(null);
    }
  };

  const handleCreate = async () => {
    if (!newKey.trim()) return;
    setCreating(true);
    try {
      const res = await fetch("/api/admin/feature-flags", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          key: newKey.trim().toLowerCase().replace(/\s+/g, "_"),
          description: newDesc.trim() || null,
          enabled: false,
        }),
      });
      if (res.ok) {
        setNewKey("");
        setNewDesc("");
        setDialogOpen(false);
        fetchFlags();
      }
    } finally {
      setCreating(false);
    }
  };

  const handleDelete = async (id: string) => {
    setDeleting(id);
    try {
      await fetch("/api/admin/feature-flags", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id }),
      });
      setFlags((prev) => prev.filter((f) => f.id !== id));
    } finally {
      setDeleting(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white">Feature Flags</h1>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={fetchFlags}
            disabled={loading}
            className="border-zinc-700 bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
          >
            <RefreshCw
              className={`mr-2 h-3 w-3 ${loading ? "animate-spin" : ""}`}
            />
            Refresh
          </Button>
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogTrigger asChild>
              <Button
                size="sm"
                className="bg-indigo-600 text-white hover:bg-indigo-700"
              >
                <Plus className="mr-2 h-3 w-3" />
                Add Flag
              </Button>
            </DialogTrigger>
            <DialogContent className="border-zinc-700 bg-zinc-900">
              <DialogHeader>
                <DialogTitle className="text-white">
                  Create Feature Flag
                </DialogTitle>
              </DialogHeader>
              <div className="space-y-4 pt-2">
                <div>
                  <label className="mb-1 block text-sm text-zinc-400">
                    Key
                  </label>
                  <Input
                    placeholder="e.g. new_checkout_flow"
                    value={newKey}
                    onChange={(e) => setNewKey(e.target.value)}
                    className="border-zinc-700 bg-zinc-800 text-white"
                  />
                  <p className="mt-1 text-xs text-zinc-500">
                    Will be lowercased with underscores
                  </p>
                </div>
                <div>
                  <label className="mb-1 block text-sm text-zinc-400">
                    Description
                  </label>
                  <Input
                    placeholder="What this flag controls..."
                    value={newDesc}
                    onChange={(e) => setNewDesc(e.target.value)}
                    className="border-zinc-700 bg-zinc-800 text-white"
                  />
                </div>
                <Button
                  onClick={handleCreate}
                  disabled={creating || !newKey.trim()}
                  className="w-full bg-indigo-600 text-white hover:bg-indigo-700"
                >
                  {creating ? "Creating..." : "Create Flag"}
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        </div>
      </div>

      <p className="text-sm text-zinc-500">
        Toggle features on/off across the platform. Changes take effect
        immediately for all users.
      </p>

      {loading && !flags.length ? (
        <div className="space-y-2">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-20 w-full bg-zinc-800" />
          ))}
        </div>
      ) : flags.length === 0 ? (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardContent className="flex h-48 items-center justify-center">
            <p className="text-zinc-500">
              No feature flags configured. Click &quot;Add Flag&quot; to create
              one.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {flags.map((flag) => (
            <Card key={flag.id} className="border-zinc-800 bg-zinc-900">
              <CardContent className="flex items-center justify-between p-4">
                <div className="flex items-center gap-4">
                  <Flag
                    className={`h-4 w-4 ${
                      flag.enabled ? "text-emerald-400" : "text-zinc-600"
                    }`}
                  />
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-mono text-sm text-white">{flag.key}</p>
                      <Badge
                        variant="outline"
                        className={
                          flag.enabled
                            ? "border-emerald-500/30 text-emerald-400"
                            : "border-zinc-600/30 text-zinc-500"
                        }
                      >
                        {flag.enabled ? "enabled" : "disabled"}
                      </Badge>
                    </div>
                    {flag.description && (
                      <p className="mt-1 text-xs text-zinc-500">
                        {flag.description}
                      </p>
                    )}
                    <p className="mt-0.5 text-xs text-zinc-600">
                      Updated {formatRelative(flag.updated_at)}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <Switch
                    checked={flag.enabled}
                    onCheckedChange={(checked) =>
                      handleToggle(flag.id, checked)
                    }
                    disabled={toggling === flag.id}
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleDelete(flag.id)}
                    disabled={deleting === flag.id}
                    className="text-zinc-500 hover:text-red-400"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
