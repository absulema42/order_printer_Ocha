import 'dart:io';

/// Sends raw ESC/POS bytes to a network printer (port 9100 by default).
/// Works the same on Android, Windows and Linux.
class PrinterService {
  static const Duration _timeout = Duration(seconds: 5);

  static Future<void> send(String host, int port, List<int> bytes) async {
    if (host.trim().isEmpty) {
      throw const PrinterException('No printer IP set. Add it in Settings.');
    }
    Socket? socket;
    try {
      socket = await Socket.connect(host.trim(), port, timeout: _timeout);
      socket.add(bytes);
      await socket.flush().timeout(_timeout);
      await socket.close().timeout(_timeout);
    } on SocketException catch (e) {
      socket?.destroy();
      throw PrinterException(
          'Could not reach the printer at $host:$port. '
          'Check it is switched on and on the same Wi-Fi. (${e.message})');
    } on Exception catch (e) {
      socket?.destroy();
      throw PrinterException('Printing failed: $e');
    }
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);
  @override
  String toString() => message;
}
