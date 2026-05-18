import 'dart:async';

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

bool _isMapLayoutPendingError(PlatformException error) {
  final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
  return message.contains("map size can't be 0");
}

Future<bool> animateCameraWhenMapReady({
  required gmap.GoogleMapController controller,
  required gmap.CameraUpdate Function() cameraUpdateBuilder,
  int maxRetries = 8,
  Duration retryDelay = const Duration(milliseconds: 120),
}) async {
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await controller.animateCamera(cameraUpdateBuilder());
      return true;
    } on PlatformException catch (e) {
      final isRetryable = _isMapLayoutPendingError(e);
      final hasMoreRetries = attempt < maxRetries;
      if (!isRetryable || !hasMoreRetries) {
        return false;
      }
      await Future<void>.delayed(retryDelay);
    } catch (_) {
      return false;
    }
  }
  return false;
}
