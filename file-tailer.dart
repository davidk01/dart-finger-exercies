import 'dart:io';
import 'dart:async';

// sometimes delete does not mean deleted so we have to
// do an extra check when we receive a delete event
Stream<FileSystemEvent> saneEvents(File f) async* {
  await for (final ev in f.watch()) {
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

// Keep the local state of the file we are tracking and allow operations
// to be performed on said file like reading in a non-blocking manner,
// resetting read position, etc.
class Context {

  final String filename;
  final File tailee;
  RandomAccessFile opened;
  int start;
  int recentPosition;

  Context(final String this.filename) : tailee = new File(filename) {
    // what is our initial starting point
    start = tailee.lengthSync();
    opened = tailee.openSync();
    opened.setPosition(start);
    // we need this for verifying file truncation
    recentPosition = start;
  }

  Future<List<int>> read(int size) => opened.read(size);

  Future<List<int>> get readTillEnd => opened.read(positionDelta);

  bool get positionTooFar => positionDelta < 0;

  int get positionDelta => opened.lengthSync() - position;

  int get position => opened.positionSync();

  void set position(int position) { opened.setPositionSync(position); }

  void resetPosition() { position = 0; }

}

// tails the file by polling
class PollingTailer {

    final Context context;

    PollingTailer(final this.context);

    modificationAction(Timer timer) async {
      List<int> read = await context.readTillEnd;
      while (read.length != 0) {
        print('Polling read: ${read}');
        read = await context.readTillEnd;
        // TODO: Buffer the results and continue to read
      }
      // this probably means the file was re-opened
      if (context.positionTooFar) {
        context.resetPosition();
      }
    }

    // start the polling timer
    start() => new Timer.periodic(new Duration(seconds: 1), modificationAction);

}

// watches the events on the file and tries to read based on event information
class EventedTailer {

  final Context context;

  EventedTailer(final this.context);

  modificationAction(final FileSystemEvent ev) async {
    if ((ev as FileSystemModifyEvent).contentChanged) {
      List<int> read = await context.readTillEnd;
      // we tried to read but got nothing so maybe truncated
      if (read.length == 0) {
        // if there is a position mismatch then reset position to 0.
        // note: it is possible that the file will be truncated and
        // exactly the right of amount data will be written to overwrite
        // up to the position we are currently at. in this case the length
        // and position will match but we won't know that we need
        // to reset the position. i'm going to assume this is very unlikely
        // because i don't know how to avoid it.
        if (context.positionTooFar) {
          // reset to 0 and retry
          context.resetPosition();
          read = await context.readTillEnd;
        }
        // Note: the above logic can fail in an interesting way.
        // write some bytes, write those bytes again
      }
      print('Evented read: ${read}');
      // continue accumulating into the buffer while possible
      while (read.length > 0) {
        read = await context.readTillEnd;
        print('Evented read: ${read}');
      }
      // TODO: transform read buffer
    }
    else { // TODO: content was not modified so what should we do?

    }
  }

  // start listening for file events and performing contextual actions
  start() {
    saneEvents(context.tailee).listen((final FileSystemEvent ev) async {
      print('Event: ${ev}');
      // dispatch on the event type
      switch (ev.type) {
      // can't do anything with a deleted file
        case FileSystemEvent.DELETE:
          return 0;
      // similar to above we just give up and wait to be restarted
        case FileSystemEvent.MOVE:
          return 0;
      // go to beginning
        case FileSystemEvent.CREATE:
          context.resetPosition();
          break;
      // file was modified so we should try to read
        case FileSystemEvent.MODIFY:
          modificationAction(ev);
          break;
      // we covered all event cases above so this can't happen
        default:
          throw "unreachable";
      }
      print('Position: ${context.position}');
    });
  }

}

Future main() async {
  String f = 't.log';
  // nothing to do if the file doesn't exist
  if (!FileSystemEntity.isFileSync(f)) {
    return 0;
  }
  // the file we are interested in watching
  final Context context = new Context(f);
  final EventedTailer eventedTailer = new EventedTailer(context);
  final PollingTailer pollingTailer = new PollingTailer(context);
  print('Starting evented tailer');
  eventedTailer.start();
  print('Starting polling tailer');
  pollingTailer.start();
}