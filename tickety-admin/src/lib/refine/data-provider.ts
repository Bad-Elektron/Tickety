import { dataProvider } from "@refinedev/supabase";
import { createClient } from "@/lib/supabase/client";

export function getDataProvider() {
  const supabase = createClient();
  return dataProvider(supabase);
}
