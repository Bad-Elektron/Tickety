import type { AuthProvider } from "@refinedev/core";
import { createClient } from "@/lib/supabase/client";
import { jwtDecode } from "jwt-decode";
import type { AppRole } from "@/types/database";

interface JwtClaims {
  user_role?: AppRole;
  email?: string;
  sub?: string;
}

const ALLOWED_ROLES: AppRole[] = ["admin", "moderator", "support"];

function getRoleFromSession(accessToken: string): AppRole | null {
  try {
    const decoded = jwtDecode<JwtClaims>(accessToken);
    if (decoded.user_role && ALLOWED_ROLES.includes(decoded.user_role)) {
      return decoded.user_role;
    }
  } catch {
    // Invalid token
  }
  return null;
}

export const authProvider: AuthProvider = {
  login: async ({ email, password }) => {
    const supabase = createClient();
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      return {
        success: false,
        error: { name: "LoginError", message: error.message },
      };
    }

    const role = getRoleFromSession(data.session.access_token);
    if (!role) {
      await supabase.auth.signOut();
      return {
        success: false,
        error: {
          name: "Unauthorized",
          message: "You do not have admin access.",
        },
      };
    }

    return {
      success: true,
      redirectTo: "/dashboard/overview",
    };
  },

  logout: async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    return {
      success: true,
      redirectTo: "/login",
    };
  },

  check: async () => {
    const supabase = createClient();
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (!session) {
      return {
        authenticated: false,
        redirectTo: "/login",
      };
    }

    const role = getRoleFromSession(session.access_token);
    if (!role) {
      return {
        authenticated: false,
        redirectTo: "/login",
        error: {
          name: "Unauthorized",
          message: "You do not have admin access.",
        },
      };
    }

    return { authenticated: true };
  },

  getIdentity: async () => {
    const supabase = createClient();
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (!session) return null;

    const decoded = jwtDecode<JwtClaims>(session.access_token);
    return {
      id: session.user.id,
      email: session.user.email,
      role: decoded.user_role ?? "unknown",
    };
  },

  onError: async (error) => {
    if (error?.status === 401 || error?.status === 403) {
      return { logout: true, redirectTo: "/login" };
    }
    return { error };
  },
};
