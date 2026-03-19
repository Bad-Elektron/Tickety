import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/services.dart';
import '../models/organizer_branding.dart';

class BrandingRepository {
  final _client = SupabaseService.instance.client;

  /// Fetch branding for the current user (organizer).
  Future<OrganizerBranding?> getMyBranding() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('organizer_branding')
        .select()
        .eq('organizer_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return OrganizerBranding.fromJson(response);
  }

  /// Fetch branding for a specific organizer (public read).
  Future<OrganizerBranding?> getBranding(String organizerId) async {
    final response = await _client
        .from('organizer_branding')
        .select()
        .eq('organizer_id', organizerId)
        .maybeSingle();

    if (response == null) return null;
    return OrganizerBranding.fromJson(response);
  }

  /// Upsert branding (create or update).
  Future<OrganizerBranding> saveBranding({
    required String primaryColor,
    String? accentColor,
    String? logoUrl,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final data = {
      'organizer_id': userId,
      'primary_color': primaryColor,
      'accent_color': accentColor,
      'logo_url': logoUrl,
    };

    final response = await _client
        .from('organizer_branding')
        .upsert(data)
        .select()
        .single();

    return OrganizerBranding.fromJson(response);
  }

  /// Upload logo image and return the public URL.
  Future<String> uploadLogo(Uint8List bytes, String fileName) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final path = '$userId/logo_$fileName';

    await _client.storage.from('organizer-logos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    return _client.storage.from('organizer-logos').getPublicUrl(path);
  }
}
