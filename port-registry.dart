import 'dart:isolate';
import 'dart:async';
import 'dart:collection';

/// This is the class that requests are supposed to be wrapped in when talking
/// to the registry instance across the registry port.
class PortRegistryRequest {

  /// The 'type' of the request. Can also be handled with sub-classing.
  String request;
  /// Any random object as long as it can be shipped over a port. The
  /// expectation is that this should be some kind of dictionary-like object
  /// that has a port component so that other isolates can communicate with
  /// whatever is in the registry.
  dynamic payload;

  PortRegistryRequest(this.request, this.payload);

  /// The registry instance delegates to the request instance via
  /// double dispatch. This allows clients to subclass the request class
  /// and do whatever they want.
  dispatch(PortRegistry registry) {
    switch (request) {
      case 'register':
        registry[payload['id']] = payload;
        break;
      case 'broadcast':
        registry.broadcast(payload);
        break;
      default:
        print('Unknown request: $request');
    }
  }

}

/// It is a pretty basic registry that maps IDs to arbitrary objects. There
/// are some restrictions because the object must still be allowed to pass
/// through ports. The expectation is also that each object has its own port
/// property that other isolates can query and send messages to.
class PortRegistry {

  /// The mapping of IDs to payloads.
  HashMap<int, dynamic> registry;
  /// The registry listens on this port and dispatches command requests
  /// that are received.
  ReceivePort receiver;

  PortRegistry() {
    registry = new HashMap();
    receiver = new ReceivePort();
    receiver.listen((PortRegistryRequest request) {
      request.dispatch(this);
    });
  }

  /// If isolates want to register and get access to other registered
  /// isolates then they need access to this port. This should be passed
  /// along as the first object when spawning the isolate.
  SendPort get sendPort => receiver.sendPort;

  /// Convenience method for delegating to the underlying hash map.
  operator []=(int id, dynamic registrant) => registry[id] = registrant;

  /// Send whatever is the message to all entries in the registry.
  broadcast(dynamic message) {
    final List<int> errors = [];
    registry.forEach((int id, dynamic entry) {
      try {
        entry['port'].send(message);
      } catch (exception) {
        print('Could not broadcast to entry: $id');
        errors.add(id);
      }
    });
    errors.forEach((int id) => registry.remove(id));
  }

}

/// Simple test case for registration and broadcasting
spammer(SendPort registry) {
  final int id = Isolate.current.hashCode;
  final ReceivePort receiver = new ReceivePort();
  receiver.listen((dynamic message) {
    print('Processing message in isolate $id');
    print(message);
  });
  final SendPort sender = receiver.sendPort;
  registry.send(new PortRegistryRequest('register', {'id': id, 'port': sender}));
  new Timer.periodic(new Duration(seconds: 2), (Timer timer) {
    registry.send(new PortRegistryRequest('broadcast', 'hello from $id'));
  });
}

crasher(SendPort registry) {
  final int id = Isolate.current.hashCode;
  final ReceivePort receiver = new ReceivePort();
  receiver.listen((dynamic message) {
    print('Processing message in crasher isolate $id');
    print(message);
    throw new Exception('Crash!!!');
  });
  final SendPort sender = receiver.sendPort;
  registry.send(new PortRegistryRequest('register', {'id': id, 'port': sender}));
}

main() {
  final PortRegistry registry = new PortRegistry();
  Isolate.spawn(spammer, registry.sendPort);
  Isolate.spawn(spammer, registry.sendPort);
  Isolate.spawn(crasher, registry.sendPort);
}