import 'dart:io';
import 'dart:isolate';
import 'dart:collection';
import 'dart:async';

class Watcher {

  HashMap<String, dynamic> accumulator;
  ReceivePort receiver;
  Directory directory;

  Watcher(String dir) {
    this.accumulator = new HashMap();
    this.receiver = new ReceivePort();
    this.directory = new Directory(dir);
    directory.listSync().forEach((FileSystemEntity f) {
      accumulator[filter(f.path)] = f;
    });
    directory.watch().listen((FileSystemEvent ev) {
      associator(ev);
    });
    receiver.listen((dynamic request) {
      SendPort sender = request['sender'];
      sender.send(accumulator);
    });
  }

  SendPort get sendPort => receiver.sendPort;

  String filter(String path) => path.substring(2);

  Stream<FileSystemEvent> saneEvents() async* {
    await for (final ev in directory.watch()) {
      switch (ev.type) {
        case FileSystemEvent.DELETE:
          if (await FileSystemEntity.isFile(ev.path)) {
            break;
          } else {
            yield ev;
          }
          break;
        default:
          yield ev;
      }
    }
  }
  
  void associator(FileSystemEvent ev) {
    final String path = ev.path;
    switch (ev.type) {
      case FileSystemEvent.CREATE:
        accumulator[filter(path)] = ev;
        break;
      case FileSystemEvent.DELETE:
        accumulator.remove(filter(path));
        break;
      case FileSystemEvent.MODIFY:
        accumulator[filter(path)] = ev;
        break;
      case FileSystemEvent.MOVE:
        accumulator.remove(filter(path));
        accumulator[filter((ev as FileSystemMoveEvent).destination)] = ev;
        break;
    }
  }
  
}

Future startServer(SendPort watcher) async {
  final server =
      await HttpServer.bind(InternetAddress.ANY_IP_V4, 8080, shared: true);
  server.autoCompress = true;
  await for (final request in server) {
    final response = request.response;
    try {
      final pathSegments = request.uri.pathSegments;
      if (pathSegments.length == 0) {
        final ReceivePort receiver = new ReceivePort();
        watcher.send({'sender': receiver.sendPort});
        final HashMap<String, dynamic> accumulator = await receiver.first;
        response.add(accumulator.keys.toString().codeUnits);
      } else {
        final fileName = request.uri.pathSegments.first;
        final file = new File(fileName);
        final content = await file.readAsBytes();
        response.add(content);
      }
    } catch (e) {
      response.statusCode = HttpStatus.BAD_REQUEST;
      print(e);
      rethrow;
    } finally {
      response.close();
    }
  }
}

Future main() async {
  final errorPort = new ReceivePort();
  final watcher = new Watcher('./');
  await Isolate.spawn(startServer, watcher.sendPort, onError: errorPort.sendPort);
  await for (final m in errorPort) {
    print('error with worker. restarting');
    print(m);
    await Isolate.spawn(startServer, watcher.sendPort, onError: errorPort.sendPort);
  }
}
