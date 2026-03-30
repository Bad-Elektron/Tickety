import 'package:flutter/material.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../services/supabase_service.dart';

/// Returns true if the user is authenticated.
/// If not, navigates to the login screen and returns false.
bool requireAuth(BuildContext context) {
  if (SupabaseService.instance.isAuthenticated) return true;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
  );
  return false;
}
