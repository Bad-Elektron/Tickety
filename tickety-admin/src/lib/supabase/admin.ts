import { createClient } from "@supabase/supabase-js";

// IMPORTANT: Only use this in Route Handlers (src/app/api/).
// Never import this in client components or server components.
// The service_role key bypasses RLS and has full database access.
export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}
