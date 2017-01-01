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

Future main() async {
  String f = 't.log';
  // nothing to do if the file doesn't exist
  if (!FileSystemEntity.isFileSync(f)) {
    return 0;
  }
  // we need a utf8 decoder
  final decoder = new Utf8Encoder();
  // the file we are interested in watching
  final File tailee = new File(f);
  // what is our initial starting point
  int start = tailee.lengthSync();
  // open the file
  final RandomAccessFile opened = tailee.openSync();
  // seek to the starting position
  opened.setPositionSync(start);
  print('Starting length: ${start}');
  // we need this for verifying file truncation
  int recentPosition = start;
  while (true) {
    await for (final FileSystemEvent ev in saneEvents(tailee)) {
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
          opened.setPositionSync(0);
          break;
        // file was modified so we should try to read
        case FileSystemEvent.MODIFY:
          if ((ev as FileSystemModifyEvent).contentChanged) {
            List<int> read = await opened.read(200);
            // we tried to read but got nothing so maybe truncated
            if (read.length == 0) {
              // if there is a position mismatch then reset position to 0.
              // note: it is possible that the file will be truncated and
              // exactly the right of amount data will be written to overwrite
              // up to the position we are currently at. in this case the length
              // and position will match but we won't know that we need
              // to reset the position. i'm going to assume this is very unlikely
              // because i don't know how to avoid it.
              if (recentPosition != opened.lengthSync()) {
                // reset to 0 and retry
                opened.setPositionSync(0);
                read = await opened.read(200);
              }
              // Note: the above logic can fail in an interesting way.
              // write some bytes, write those bytes again
            }
            print('Read: ${read}');
            // continue accumulating into the buffer while possible
            while (read.length > 0) {
              read = await opened.read(200);
              print('Read: ${read}');
            }
            recentPosition = opened.positionSync();
            // TODO: transform read buffer
          } else { // file was modified but content did not change
            // TODO: No idea what this actually means so empty for now
          }
          break;
        // we covered all event cases above so this can't happen
        default:
          throw "unreachable";
      }
      final int endPosition = await opened.position();
      print('Position: ${endPosition}');
    }
  }
}