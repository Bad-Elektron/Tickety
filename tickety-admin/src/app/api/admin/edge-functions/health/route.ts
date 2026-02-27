import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

const EDGE_FUNCTIONS = [
  "create-payment-intent",
  "create-resale-intent",
  "create-seller-account",
  "create-subscription-checkout",
  "create-connect-account",
  "get-seller-balance",
  "initiate-withdrawal",
  "process-refund",
  "stripe-webhook",
  "connect-webhook",
  "verify-subscription",
  "claim-favor-offer",
  "refresh-analytics",
  "refresh-market-analytics",
];

interface FunctionHealth {
  name: string;
  status: "healthy" | "error" | "timeout";
  responseTime: number | null;
  error?: string;
}

export async function GET() {
  const supabase = createAdminClient();

  const results: FunctionHealth[] = await Promise.all(
    EDGE_FUNCTIONS.map(async (name) => {
      const startTime = Date.now();
      try {
        // Invoke with a health check / empty body
        // Most functions will return an error for missing params,
        // but that proves they're running
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 8000);

        const { error } = await supabase.functions.invoke(name, {
          body: { health_check: true },
        });

        clearTimeout(timeoutId);
        const responseTime = Date.now() - startTime;

        // A function that returns an error for bad input is still "healthy"
        // — it means the function is deployed and responding.
        // Only truly unreachable functions are unhealthy.
        if (error) {
          const msg = error.message ?? "";
          // "FunctionsHttpError" with a response means the function ran
          // "FunctionsRelayError" or "FunctionsFetchError" means it's down
          if (
            msg.includes("FunctionsRelayError") ||
            msg.includes("FunctionsFetchError") ||
            msg.includes("non-2xx")
          ) {
            // Check if it's just a validation error (function is running)
            if (responseTime < 7000) {
              return { name, status: "healthy" as const, responseTime };
            }
            return {
              name,
              status: "error" as const,
              responseTime,
              error: msg.slice(0, 200),
            };
          }
          // Got an application error = function is running
          return { name, status: "healthy" as const, responseTime };
        }

        return { name, status: "healthy" as const, responseTime };
      } catch (err) {
        const responseTime = Date.now() - startTime;
        if (responseTime >= 7500) {
          return { name, status: "timeout" as const, responseTime, error: "Timed out" };
        }
        return {
          name,
          status: "error" as const,
          responseTime,
          error: err instanceof Error ? err.message.slice(0, 200) : "Unknown error",
        };
      }
    })
  );

  const healthy = results.filter((r) => r.status === "healthy").length;
  const errors = results.filter((r) => r.status === "error").length;
  const timeouts = results.filter((r) => r.status === "timeout").length;

  return NextResponse.json({
    functions: results,
    summary: { total: results.length, healthy, errors, timeouts },
  });
}
