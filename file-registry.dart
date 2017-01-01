import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:isolate';

Stream<FileSystemEvent> saneEvents(String directory) async* {
  final dir = new Directory(directory);
  await for (final ev in dir.watch()) {
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
      print('File moved: ${path} -> ${ev.destination}');
      accumulator.remove(filter(path));
      accumulator[filter(ev.destination)] = ev;
      break;
  }
  print(accumulator);
}

initialize(String directory, HashMap accumulator) async {
  accumulator.clear();
  var dir = new Directory(directory);
  Stream<FileSystemEntity> entries = dir.list();
  await for (final FileSystemEntity entry in entries) {
    accumulator[entry.path] = entry;
    print(entry);
  }
}

startRegistry(dynamic m) async {
  final accumulator = new HashMap();
  await initialize('./', accumulator);
  await for (final ev in saneEvents('./')) {
    associator(ev, accumulator);
  }
}

main() async {
  final errorPort = new ReceivePort();
  await Isolate.spawn(startRegistry, null, onError: errorPort.sendPort);
  await for (final m in errorPort) {
    print('Error with file registry. Restarting.');
    print(m);
    await Isolate.spawn(startRegistry, null, onError: errorPort.sendPort);
  }
}
