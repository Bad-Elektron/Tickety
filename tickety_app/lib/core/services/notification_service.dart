import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../errors/errors.dart';

/// Singleton service for local notifications.
///
/// Must call [initialize] before using notifications.
/// Note: Local notifications work on iOS and Android only.
class NotificationService {
  static NotificationService? _instance;
  static FlutterLocalNotificationsPlugin? _notificationsPlugin;

  /// Whether local notifications are supported on the current platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// The singleton instance. Throws if [initialize] hasn't been called.
  static NotificationService get instance {
    if (_instance == null) {
      throw StateError(
        'NotificationService not initialized. Call NotificationService.initialize() first.',
      );
    }
    return _instance!;
  }

  NotificationService._();

  /// Initializes the local notifications plugin.
  ///
  /// Call this once at app startup.
  /// On unsupported platforms (Windows, macOS, Linux, Web), this creates
  /// a stub instance without initializing notifications.
  static Future<void> initialize() async {
    if (_instance != null) {
      return;
    }

    // Local notifications only work on iOS and Android
    if (!isSupported) {
      AppLogger.warning(
        'Local notifications not supported on this platform.',
        tag: 'NotificationService',
      );
      _instance = NotificationService._();
      return;
    }

    AppLogger.debug('Initializing notification service', tag: 'NotificationService');

    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final initialized = await _notificationsPlugin!.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (initialized == true) {
      AppLogger.info('Notification service initialized successfully', tag: 'NotificationService');
    } else {
      AppLogger.warning('Notification service initialization returned false', tag: 'NotificationService');
    }

    _instance = NotificationService._();
  }

  /// Handle notification tap.
  static void _onNotificationTapped(NotificationResponse response) {
    AppLogger.debug(
      'Notification tapped: ${response.payload}',
      tag: 'NotificationService',
    );
    // Navigation will be handled by the notification provider
  }

  /// Request notification permissions from the user.
  ///
  /// Returns true if permissions were granted.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;

    AppLogger.debug('Requesting notification permissions', tag: 'NotificationService');

    if (Platform.isAndroid) {
      // Android 13+ requires explicit permission
      final status = await Permission.notification.request();
      final granted = status.isGranted;
      AppLogger.info(
        'Android notification permission: ${granted ? 'granted' : 'denied'}',
        tag: 'NotificationService',
      );
      return granted;
    }

    if (Platform.isIOS) {
      final result = await _notificationsPlugin!
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      final granted = result ?? false;
      AppLogger.info(
        'iOS notification permission: ${granted ? 'granted' : 'denied'}',
        tag: 'NotificationService',
      );
      return granted;
    }

    return false;
  }

  /// Check if notification permissions are granted.
  Future<bool> hasPermissions() async {
    if (!isSupported) return false;

    if (Platform.isAndroid) {
      return await Permission.notification.isGranted;
    }

    if (Platform.isIOS) {
      // iOS doesn't have a direct way to check, assume granted if we can show
      return true;
    }

    return false;
  }

  /// Show a local notification.
  ///
  /// [id] - Unique notification ID (used to update/cancel later).
  /// [title] - Notification title.
  /// [body] - Notification body text.
  /// [payload] - Optional data to pass when notification is tapped.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!isSupported || _notificationsPlugin == null) {
      AppLogger.debug(
        'Skipping notification on unsupported platform',
        tag: 'NotificationService',
      );
      return;
    }

    AppLogger.debug(
      'Showing notification: $title',
      tag: 'NotificationService',
    );

    const androidDetails = AndroidNotificationDetails(
      'tickety_notifications',
      'Tickety Notifications',
      channelDescription: 'Notifications from Tickety app',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin!.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    AppLogger.debug('Notification shown successfully', tag: 'NotificationService');
  }

  /// Cancel a specific notification by ID.
  Future<void> cancelNotification(int id) async {
    if (!isSupported || _notificationsPlugin == null) return;
    await _notificationsPlugin!.cancel(id);
  }

  /// Cancel all notifications.
  Future<void> cancelAllNotifications() async {
    if (!isSupported || _notificationsPlugin == null) return;
    await _notificationsPlugin!.cancelAll();
  }
}
