import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight performance logger.
///
/// - Works in debug/profile/release.
/// - Uses [developer.log] to avoid `print` overhead and allow filtering.
///
/// Enable logs by passing `--dart-define=XDNMB_PERF_LOG=true`.
final class PerfLog {
  static const bool enabled =
      bool.fromEnvironment('XDNMB_PERF_LOG', defaultValue: false);

  static void log(String message, {String name = 'xdnmb.perf'}) {
    if (!enabled) return;
    // 1) 终端可见（flutter run 输出）
    debugPrint('[$name] $message');
    // 2) DevTools/VM Service 可见
    developer.log(message, name: name);
  }

  /// Creates a stage timer to emit multiple checkpoints under the same label.
  static StageTimer stage(String label, {String name = 'xdnmb.perf'}) {
    return StageTimer._(label: label, name: name);
  }

  static T sync<T>(String label, T Function() fn) {
    if (!enabled) return fn();
    final sw = Stopwatch()..start();
    try {
      return fn();
    } finally {
      sw.stop();
      log('$label durMs=${sw.elapsedMilliseconds}');
    }
  }

  static Future<T> time<T>(String label, Future<T> Function() fn) async {
    if (!enabled) return fn();
    final sw = Stopwatch()..start();
    try {
      final r = await fn();
      return r;
    } finally {
      sw.stop();
      log('$label durMs=${sw.elapsedMilliseconds}');
    }
  }
}

/// Helper to measure multiple checkpoints for one multi-step operation.
///
/// Example:
/// ```
/// final t = PerfLog.stage('thread.load');
/// t.check('request.start');
/// ...
/// t.check('request.end');
/// ...
/// t.end('done');
/// ```
final class StageTimer {
  final String label;
  final String name;
  final Stopwatch _sw = Stopwatch()..start();
  int _lastMs = 0;

  StageTimer._({required this.label, required this.name});

  void check(String stage, {Map<String, Object?>? fields}) {
    if (!PerfLog.enabled) return;
    final now = _sw.elapsedMilliseconds;
    final delta = now - _lastMs;
    _lastMs = now;
    PerfLog.log(
      '$label stage=$stage +${delta}ms totalMs=$now${_fmt(fields)}',
      name: name,
    );
  }

  void end([String stage = 'end', Map<String, Object?>? fields]) {
    if (!PerfLog.enabled) return;
    _sw.stop();
    final now = _sw.elapsedMilliseconds;
    final delta = now - _lastMs;
    PerfLog.log(
      '$label stage=$stage +${delta}ms totalMs=$now${_fmt(fields)}',
      name: name,
    );
  }

  static String _fmt(Map<String, Object?>? fields) {
    if (fields == null || fields.isEmpty) return '';
    final parts = <String>[];
    for (final e in fields.entries) {
      parts.add('${e.key}=${e.value}');
    }
    return ' ' + parts.join(' ');
  }
}
