import 'dart:async';
import 'package:flutter/material.dart';

class PerformanceUtils {
  static final Map<String, dynamic> _cache = {};

  static T getCached<T>(String key, T Function() compute) {
    if (_cache.containsKey(key)) {
      return _cache[key] as T;
    }
    final value = compute();
    _cache[key] = value;
    return value;
  }

  static void clearCache() {
    _cache.clear();
  }

  static Timer? _debounceTimer;

  static void debounce({
    required VoidCallback action,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(duration, action);
  }

  static DateTime? _lastThrottleTime;

  static void throttle({
    required VoidCallback action,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    final now = DateTime.now();
    if (_lastThrottleTime == null ||
        now.difference(_lastThrottleTime!) > duration) {
      _lastThrottleTime = now;
      action();
    }
  }

  static void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastThrottleTime = null;
  }
}

mixin ResponsiveCacheMixin on Widget {
  String getCacheKey(BuildContext context, String suffix) {
    final size = MediaQuery.of(context).size;
    return '${size.width}x${size.height}_$suffix';
  }
}
