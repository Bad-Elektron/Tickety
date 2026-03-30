import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Caches event/ticket passwords locally so users don't re-enter them.
///
/// Stores a map of event_id → { 'event': password, 'tickets': { ticketTypeId: password } }
/// in SharedPreferences. No sensitive data hits the network.
class PasswordCacheService {
  static const _key = 'event_password_cache';

  static PasswordCacheService? _instance;
  static PasswordCacheService get instance => _instance ??= PasswordCacheService._();
  PasswordCacheService._();

  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _cache = raw != null ? json.decode(raw) as Map<String, dynamic> : {};
    return _cache!;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(_cache));
  }

  /// Save the event-level (master) password for an event.
  Future<void> saveEventPassword(String eventId, String password) async {
    final cache = await _load();
    final entry = (cache[eventId] as Map<String, dynamic>?) ?? {};
    entry['event'] = password;
    cache[eventId] = entry;
    await _save();
  }

  /// Save a ticket-type-level password for an event.
  Future<void> saveTicketPassword(String eventId, String ticketTypeId, String password) async {
    final cache = await _load();
    final entry = (cache[eventId] as Map<String, dynamic>?) ?? {};
    final tickets = (entry['tickets'] as Map<String, dynamic>?) ?? {};
    tickets[ticketTypeId] = password;
    entry['tickets'] = tickets;
    cache[eventId] = entry;
    await _save();
  }

  /// Check if user has unlocked the event via master password.
  Future<bool> hasEventPassword(String eventId) async {
    final cache = await _load();
    final entry = cache[eventId] as Map<String, dynamic>?;
    return entry?['event'] != null;
  }

  /// Get the cached event password (for verification).
  Future<String?> getEventPassword(String eventId) async {
    final cache = await _load();
    final entry = cache[eventId] as Map<String, dynamic>?;
    return entry?['event'] as String?;
  }

  /// Check if user has unlocked a specific ticket type.
  Future<bool> hasTicketPassword(String eventId, String ticketTypeId) async {
    final cache = await _load();
    final entry = cache[eventId] as Map<String, dynamic>?;
    final tickets = entry?['tickets'] as Map<String, dynamic>?;
    return tickets?[ticketTypeId] != null;
  }

  /// Check if a ticket type is accessible (either via master or ticket-specific password).
  Future<bool> isTicketUnlocked(String eventId, String ticketTypeId) async {
    if (await hasEventPassword(eventId)) return true;
    return hasTicketPassword(eventId, ticketTypeId);
  }
}
