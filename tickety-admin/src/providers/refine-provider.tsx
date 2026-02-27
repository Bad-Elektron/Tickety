"use client";

import { Suspense } from "react";
import { Refine } from "@refinedev/core";
import routerProvider from "@refinedev/nextjs-router";
import { authProvider } from "@/lib/refine/auth-provider";
import { getDataProvider } from "@/lib/refine/data-provider";
import { resources } from "@/lib/refine/resources";

export function RefineProvider({ children }: { children: React.ReactNode }) {
  return (
    <Suspense>
      <Refine
        routerProvider={routerProvider}
        authProvider={authProvider}
        dataProvider={getDataProvider()}
        resources={resources}
        options={{
          syncWithLocation: true,
          warnWhenUnsavedChanges: true,
        }}
      >
        {children}
      </Refine>
    </Suspense>
  );
}
