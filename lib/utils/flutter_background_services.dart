import 'dart:async';
import 'dart:ui';

import 'package:background_location/background_location.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shake/shake.dart';
import 'package:telephony/telephony.dart';
import 'package:vibration/vibration.dart';
import 'package:women_safety_app/db/db_services.dart';
import 'package:women_safety_app/model/contactsm.dart';

sendMessage(String messageBody) async {
  List<TContact> contactList = await DatabaseHelper().getContactList();
  if (contactList.isEmpty) {
    Fluttertoast.showToast(msg: "No number exists. Please add a number.");
  } else {
    for (var contact in contactList) {
      try {
        await Telephony.backgroundInstance.sendSms(
          to: contact.number,
          message: messageBody,
        );
        Fluttertoast.showToast(msg: "Message sent to ${contact.number}");
      } catch (error) {
        Fluttertoast.showToast(
            msg: "Failed to send message to ${contact.number}");
      }
    }
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  AndroidNotificationChannel channel = AndroidNotificationChannel(
    "script_academy",
    "Foreground Service",
    "cacaca ",
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    iosConfiguration: IosConfiguration(),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: channel.id,
      initialNotificationTitle: "Foreground Service",
      initialNotificationContent: "Initializing...",
      foregroundServiceNotificationId: 888,
    ),
  );

  service.startService();
}

@pragma('vm-entry-point')
void onStart(ServiceInstance service) async {
  Location? currentLocation;

  DartPluginRegistrant.ensureInitialized();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  await BackgroundLocation.setAndroidNotification(
    title: "Location tracking is running in the background!",
    message: "You can turn it off from settings menu inside the app",
    icon: '@mipmap/ic_logo',
  );

  BackgroundLocation.startLocationService(distanceFilter: 20);

  BackgroundLocation.getLocationUpdates((location) {
    currentLocation = location;
    _updateNotificationWithLocation(
        service, flutterLocalNotificationsPlugin, currentLocation);
  });

  if (service is AndroidServiceInstance) {
    if (await service.isForegroundService()) {
      ShakeDetector.autoStart(
        shakeThresholdGravity: 7,
        shakeSlopTimeMS: 500,
        shakeCountResetTime: 3000,
        minimumShakeCount: 1,
        onPhoneShake: () async {
          await _handlePhoneShake(currentLocation);
        },
      );

      // Initial notification
      _updateNotificationWithLocation(
          service, flutterLocalNotificationsPlugin, currentLocation);
    }
  }
}

void _updateNotificationWithLocation(
    ServiceInstance service,
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
    Location? location) {
  String notificationContent = location == null
      ? "Please enable location to use the app."
      : "Shake feature enabled. Current location: (${location.latitude}, ${location.longitude})";

  flutterLocalNotificationsPlugin.show(
    888,
    "Women Safety App",
    notificationContent,
    NotificationDetails(
      android: AndroidNotificationDetails(
        "script_academy",
        "Foreground Service",
        "Used for important notifications",
        icon: 'ic_bg_service_small',
        ongoing: true,
        importance: Importance.low,
        priority: Priority.low,
      ),
    ),
  );
}

Future<void> _handlePhoneShake(Location? location) async {
  if (await Vibration.hasVibrator() ?? false) {
    if (await Vibration.hasCustomVibrationsSupport() ?? false) {
      Vibration.vibrate(duration: 1000);
    } else {
      Vibration.vibrate();
      await Future.delayed(Duration(milliseconds: 500));
      Vibration.vibrate();
    }
  }

  if (location != null) {
    String messageBody =
        "https://www.google.com/maps/search/?api=1&query=${location.latitude}%2C${location.longitude}";
    await sendMessage(messageBody);
  } else {
    Fluttertoast.showToast(
        msg: "Location not available. Ensure location services are enabled.");
  }
}
