import 'dart:io';
import 'dart:isolate';

void startServer(dynamic m) async {
  final server =
      await HttpServer.bind(InternetAddress.ANY_IP_V4, 8080, shared: true);
  server.autoCompress = true;
  await for (final request in server) {
    final response = request.response;
    try {
      final fileName = request.uri.pathSegments.first;
      final file = new File(fileName);
      final content = await file.readAsBytes();
      response.add(content);
    } catch (e) {
      response.statusCode = HttpStatus.BAD_REQUEST;
      print(e);
      rethrow;
    } finally {
      response.close();
    }
  }
}

void main() async {
  final errorPort = new ReceivePort();
  await Isolate.spawn(startServer, null, onError: errorPort.sendPort);
  await for (final m in errorPort) {
    print('error with worker. restarting');
    print(m);
    await Isolate.spawn(startServer, null, onError: errorPort.sendPort);
  }
}
