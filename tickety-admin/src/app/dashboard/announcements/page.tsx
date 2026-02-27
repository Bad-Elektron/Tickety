"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { formatRelative } from "@/lib/utils/format";
import { Megaphone, Send, RefreshCw, Users, Crown, Globe } from "lucide-react";

interface Announcement {
  id: string;
  author_id: string;
  title: string;
  body: string;
  audience: string;
  severity: string;
  sent_count: number;
  created_at: string;
  author?: { display_name: string | null; email: string | null };
}

export default function AnnouncementsPage() {
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [audience, setAudience] = useState("all");
  const [severity, setSeverity] = useState("info");

  const fetchAnnouncements = async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/admin/announcements");
      const data = await res.json();
      setAnnouncements(Array.isArray(data) ? data : []);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAnnouncements();
  }, []);

  const handleSend = async () => {
    if (!title.trim() || !body.trim()) return;
    setSending(true);
    try {
      const res = await fetch("/api/admin/announcements", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: title.trim(),
          body: body.trim(),
          audience,
          severity,
        }),
      });
      if (res.ok) {
        setTitle("");
        setBody("");
        setAudience("all");
        setSeverity("info");
        setDialogOpen(false);
        fetchAnnouncements();
      }
    } finally {
      setSending(false);
    }
  };

  const audienceIcon = (aud: string) => {
    switch (aud) {
      case "organizers":
        return <Crown className="h-3 w-3" />;
      case "subscribers":
        return <Crown className="h-3 w-3" />;
      default:
        return <Globe className="h-3 w-3" />;
    }
  };

  const severityColor: Record<string, string> = {
    info: "border-blue-500/30 text-blue-400",
    warning: "border-amber-500/30 text-amber-400",
    critical: "border-red-500/30 text-red-400",
    success: "border-emerald-500/30 text-emerald-400",
  };

  const audienceColor: Record<string, string> = {
    all: "border-zinc-500/30 text-zinc-400",
    organizers: "border-purple-500/30 text-purple-400",
    subscribers: "border-amber-500/30 text-amber-400",
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white">Announcements</h1>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={fetchAnnouncements}
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
                <Send className="mr-2 h-3 w-3" />
                New Broadcast
              </Button>
            </DialogTrigger>
            <DialogContent className="border-zinc-700 bg-zinc-900 sm:max-w-lg">
              <DialogHeader>
                <DialogTitle className="text-white">
                  Send Announcement
                </DialogTitle>
              </DialogHeader>
              <div className="space-y-4 pt-2">
                <div>
                  <label className="mb-1 block text-sm text-zinc-400">
                    Title
                  </label>
                  <Input
                    placeholder="Announcement title"
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    className="border-zinc-700 bg-zinc-800 text-white"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-sm text-zinc-400">
                    Message
                  </label>
                  <Textarea
                    placeholder="Write your announcement..."
                    value={body}
                    onChange={(e) => setBody(e.target.value)}
                    rows={4}
                    className="border-zinc-700 bg-zinc-800 text-white"
                  />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="mb-1 block text-sm text-zinc-400">
                      Audience
                    </label>
                    <Select value={audience} onValueChange={setAudience}>
                      <SelectTrigger className="border-zinc-700 bg-zinc-800 text-white">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent className="border-zinc-700 bg-zinc-800">
                        <SelectItem value="all">All Users</SelectItem>
                        <SelectItem value="organizers">
                          Organizers Only
                        </SelectItem>
                        <SelectItem value="subscribers">
                          Paid Subscribers
                        </SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <label className="mb-1 block text-sm text-zinc-400">
                      Severity
                    </label>
                    <Select value={severity} onValueChange={setSeverity}>
                      <SelectTrigger className="border-zinc-700 bg-zinc-800 text-white">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent className="border-zinc-700 bg-zinc-800">
                        <SelectItem value="info">Info</SelectItem>
                        <SelectItem value="warning">Warning</SelectItem>
                        <SelectItem value="critical">Critical</SelectItem>
                        <SelectItem value="success">Success</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                <p className="text-xs text-zinc-500">
                  This will send a push notification to all users in the
                  selected audience. This action cannot be undone.
                </p>
                <Button
                  onClick={handleSend}
                  disabled={sending || !title.trim() || !body.trim()}
                  className="w-full bg-indigo-600 text-white hover:bg-indigo-700"
                >
                  {sending ? "Sending..." : "Send to all"}
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        </div>
      </div>

      <p className="text-sm text-zinc-500">
        Broadcast announcements to users via in-app notifications. Each
        broadcast creates a notification for every user in the target audience.
      </p>

      {loading && !announcements.length ? (
        <div className="space-y-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-24 w-full bg-zinc-800" />
          ))}
        </div>
      ) : announcements.length === 0 ? (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardContent className="flex h-48 items-center justify-center">
            <div className="text-center">
              <Megaphone className="mx-auto mb-3 h-8 w-8 text-zinc-600" />
              <p className="text-zinc-500">
                No announcements sent yet. Click &quot;New Broadcast&quot; to
                send your first announcement.
              </p>
            </div>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {announcements.map((a) => (
            <Card key={a.id} className="border-zinc-800 bg-zinc-900">
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h3 className="text-sm font-medium text-white">
                        {a.title}
                      </h3>
                      <Badge
                        variant="outline"
                        className={severityColor[a.severity] ?? "text-zinc-400"}
                      >
                        {a.severity}
                      </Badge>
                      <Badge
                        variant="outline"
                        className={
                          audienceColor[a.audience] ?? "text-zinc-400"
                        }
                      >
                        {audienceIcon(a.audience)}
                        <span className="ml-1">{a.audience}</span>
                      </Badge>
                    </div>
                    <p className="mt-1 text-sm text-zinc-400">{a.body}</p>
                    <div className="mt-2 flex items-center gap-3 text-xs text-zinc-600">
                      <span>
                        By{" "}
                        {a.author?.display_name ?? a.author?.email ?? "Unknown"}
                      </span>
                      <span>{formatRelative(a.created_at)}</span>
                      <span className="flex items-center gap-1">
                        <Users className="h-3 w-3" />
                        {a.sent_count} sent
                      </span>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
