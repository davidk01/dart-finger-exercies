import 'dart:io';
import 'dart:collection';
import 'dart:isolate';
import 'dart:async';

Stream<FileSystemEvent> saneEvents(String directory) async* {
  final dir = new Directory(directory);
  await for (final FileSystemEvent ev in dir.watch()) {
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

void associator(FileSystemEvent ev, HashMap accumulator) {
  var filter = (String path) => path.substring(2);
  final String path = ev.path;
  switch (ev.type) {
    case FileSystemEvent.CREATE:
      print('File created: ${path}');
      accumulator[filter(path)] = ev;
      break;
    case FileSystemEvent.DELETE:
      print('File deleted: ${path}');
      accumulator.remove(filter(path));
      break;
    case FileSystemEvent.MODIFY:
      print('File modified: ${path}');
      accumulator[filter(path)] = ev;
      break;
    case FileSystemEvent.MOVE:
      print('File moved: ${path} -> ${(ev as FileSystemMoveEvent).destination}');
      accumulator.remove(filter(path));
      accumulator[filter((ev as FileSystemMoveEvent).destination)] = ev;
      break;
  }
  print(accumulator);
}

Future initialize(String directory, HashMap accumulator) async {
  accumulator.clear();
  final dir = new Directory(directory);
  final entries = dir.list();
  await for (var entry in entries) {
    accumulator[entry.path] = entry;
    print(entry);
  }
}

Future startRegistry(dynamic m) async {
  final receiver = new ReceivePort();
  (m['exchange'] as SendPort).send(receiver.sendPort);
  final accumulator = new HashMap();
  await initialize('./', accumulator);
  saneEvents('./').listen((FileSystemEvent ev) { associator(ev, accumulator); });
}

main() async {
  ReceivePort errorPort = new ReceivePort();
  ReceivePort receiver = new ReceivePort();
  ReceivePort exchanger = new ReceivePort();
  await Isolate.spawn(startRegistry,
      {'parent': receiver.sendPort, 'exchange': exchanger.sendPort},
      onError: errorPort.sendPort);
  SendPort childSender = await exchanger.first;
  errorPort.listen((m) async {
    print('Error with file registry. Restarting.');
    print(m);
    exchanger = new ReceivePort();
    await Isolate.spawn(startRegistry,
        {'parent': receiver.sendPort, 'exchange': exchanger.sendPort},
        onError: errorPort.sendPort);
    childSender = await exchanger.first;
  });
  await for (final m in receiver) {
    print(m);
  }
}
