import 'dart:async';
import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

part 'bootstrap.dart';
part 'splash_builder.dart';
part 'splash_task.dart';

/// Configuration for logging within Riverboot
class RiverbootLoggingConfig {
  /// Whether to log task start events
  final bool logTaskStart;

  /// Whether to log task completion events
  final bool logTaskCompletion;

  /// Whether to log task errors with full stack traces
  final bool logTaskErrors;

  /// Whether to log timing information for tasks
  final bool logTaskTiming;

  /// Custom logger function for task events
  final void Function(String message, {Object? error, StackTrace? stackTrace})? customLogger;

  const RiverbootLoggingConfig({
    this.logTaskStart = false,
    this.logTaskCompletion = false,
    this.logTaskErrors = true,
    this.logTaskTiming = false,
    this.customLogger,
  });

  /// Default logging configuration with enhanced error logging
  static const RiverbootLoggingConfig enhanced = RiverbootLoggingConfig(
    logTaskStart: true,
    logTaskCompletion: true,
    logTaskErrors: true,
    logTaskTiming: true,
  );

  /// No logging configuration
  static const RiverbootLoggingConfig none = RiverbootLoggingConfig(
    logTaskStart: false,
    logTaskCompletion: false,
    logTaskErrors: false,
    logTaskTiming: false,
  );

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    if (customLogger != null) {
      customLogger!(message, error: error, stackTrace: stackTrace);
    } else {
      log(message, name: 'Riverboot', error: error, stackTrace: stackTrace);
    }
  }
}
