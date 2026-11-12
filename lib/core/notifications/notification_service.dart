import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String chatChannelId = 'offmas_chat_channel';
  static const String chatChannelName = 'Pesan OFFMAS';
  static const String sosChannelId = 'offmas_sos_channel';
  static const String sosChannelName = 'Peringatan Darurat SOS';
  static const String connectChannelId = 'offmas_connect_channel';
  static const String connectChannelName = 'Permintaan Terhubung OFFMAS';

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked with payload: ${response.payload}');
      },
    );

    // Request notification permissions for Android 13+
    if (Platform.isAndroid) {
      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// Show standard chat message notification
  Future<void> showMessageNotification({
    required String sender,
    required String content,
    String? conversationId,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        chatChannelId,
        chatChannelName,
        channelDescription: 'Notifikasi pesan teks masuk tanpa internet',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final notificationId = sender.hashCode.abs() % 100000;

      await _notificationsPlugin.show(
        notificationId,
        '💬 $sender',
        content,
        notificationDetails,
        payload: conversationId ?? sender,
      );
    } catch (e) {
      debugPrint('Error showing chat notification: $e');
    }
  }

  /// Show high-priority SOS emergency notification
  /// Show connection request notification (even if app is in background)
  Future<void> showConnectionRequestNotification({
    required String senderName,
    required String endpointId,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        connectChannelId,
        connectChannelName,
        channelDescription: 'Notifikasi permintaan terhubung antar perangkat OFFMAS',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF00E676),
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final notificationId = 50000 + (endpointId.hashCode.abs() % 10000);

      await _notificationsPlugin.show(
        notificationId,
        '📡 Permintaan Terhubung',
        '$senderName ingin terhubung ke jaringan Anda',
        notificationDetails,
        payload: 'connect_request:$endpointId',
      );
    } catch (e) {
      debugPrint('Error showing connection request notification: $e');
    }
  }

  /// Show notification when a connection is accepted
  Future<void> showConnectionAcceptedNotification({
    required String peerName,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        connectChannelId,
        connectChannelName,
        channelDescription: 'Notifikasi permintaan terhubung antar perangkat OFFMAS',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF00E676),
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        88888,
        '🟢 Terhubung!',
        '$peerName menerima permintaan koneksi Anda',
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing connection accepted notification: $e');
    }
  }

  Future<void> showSosNotification({
    required String sender,
    required String content,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        sosChannelId,
        sosChannelName,
        channelDescription: 'Peringatan bahaya darurat prioritas tinggi',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
        color: const Color(0xFFFF1744),
        icon: '@mipmap/ic_launcher',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );

      final notificationId = 99999 + (DateTime.now().millisecond % 1000);

      await _notificationsPlugin.show(
        notificationId,
        '🆘 PERINGATAN SOS DARI $sender!',
        content,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing SOS notification: $e');
    }
  }
}
