import 'dart:io';
import 'dart:async';
import 'dart:convert';

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

  Future<List<int>> read(int size) {
    return opened.read(size);
  }

  bool positionMismatch() {
    return recentPosition != opened.lengthSync();
  }

  void setPositionSync(int position) {
    opened.setPositionSync(position);
  }

  void updateRecentPosition() {
    recentPosition = opened.positionSync();
  }

  Future<int> position() {
    return opened.position();
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
  // seek to the starting position
  print('Starting length: ${context.start}');
  // the logic for what we do when there is a modification event
  final modificationAction = (final FileSystemEvent ev) async {
    if ((ev as FileSystemModifyEvent).contentChanged) {
      List<int> read = await context.read(200);
      // we tried to read but got nothing so maybe truncated
      if (read.length == 0) {
        // if there is a position mismatch then reset position to 0.
        // note: it is possible that the file will be truncated and
        // exactly the right of amount data will be written to overwrite
        // up to the position we are currently at. in this case the length
        // and position will match but we won't know that we need
        // to reset the position. i'm going to assume this is very unlikely
        // because i don't know how to avoid it.
        if (context.positionMismatch()) {
          // reset to 0 and retry
          context.setPositionSync(0);
          read = await context.read(200);
        }
        // Note: the above logic can fail in an interesting way.
        // write some bytes, write those bytes again
      }
      print('Read: ${read}');
      // continue accumulating into the buffer while possible
      while (read.length > 0) {
        read = await context.read(200);
        print('Read: ${read}');
      }
      context.updateRecentPosition();
      // TODO: transform read buffer
    }
    else { // TODO: content was not modified so what should we do?

    }
  };
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
          context.setPositionSync(0);
          break;
        // file was modified so we should try to read
        case FileSystemEvent.MODIFY:
          modificationAction(ev);
          break;
        // we covered all event cases above so this can't happen
        default:
          throw "unreachable";
      }
      final int endPosition = await context.position();
      print('Position: ${endPosition}');
    });
  }
}