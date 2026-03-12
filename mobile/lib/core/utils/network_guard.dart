import "dart:io";

import "package:http/http.dart" as http;

enum NetworkFailureType { noInternet, backendUnavailable, timeout, unknown }

class NetworkFailure implements Exception {
  NetworkFailure(this.type, this.message);

  final NetworkFailureType type;
  final String message;
}

class NetworkGuard {
  static Future<T> run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SocketException {
      throw NetworkFailure(NetworkFailureType.noInternet, "No internet connection.");
    } on http.ClientException {
      throw NetworkFailure(NetworkFailureType.backendUnavailable, "Backend unreachable.");
    } catch (_) {
      rethrow;
    }
  }
}
