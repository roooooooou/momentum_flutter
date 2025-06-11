import 'dart:developer';

class Logger {
  static void d(String msg) => log(msg);
  static void e(String msg, Object? err, StackTrace? st) =>
      log(msg, error: err, stackTrace: st);
}
