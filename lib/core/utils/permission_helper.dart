import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<bool> requestNearbyPermissions() async {
    try {
      if (Platform.isAndroid) {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
          Permission.nearbyWifiDevices,
          Permission.location,
        ].request();

        bool hasBluetooth = (statuses[Permission.bluetoothScan]?.isGranted ?? false) ||
                            (statuses[Permission.bluetoothConnect]?.isGranted ?? false) ||
                            (statuses[Permission.location]?.isGranted ?? false);

        debugPrint('OFFMAS Permission Status: $statuses');
        return hasBluetooth;
      } else if (Platform.isIOS) {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetooth,
        ].request();

        return statuses[Permission.bluetooth]?.isGranted ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  static Future<bool> checkPermissionsGranted() async {
    if (Platform.isAndroid) {
      bool scan = await Permission.bluetoothScan.isGranted;
      bool connect = await Permission.bluetoothConnect.isGranted;
      bool loc = await Permission.location.isGranted;
      return (scan && connect) || loc;
    } else if (Platform.isIOS) {
      return await Permission.bluetooth.isGranted;
    }
    return true;
  }
}

