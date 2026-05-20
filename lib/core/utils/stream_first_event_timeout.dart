import 'dart:async';

/// Adds a timeout guard only for the first event of a stream.
///
/// This prevents UI providers from remaining in loading forever when the
/// backend connection is slow/stuck during initial subscription.
Stream<T> withFirstEventTimeout<T>(
  Stream<T> source, {
  Duration timeout = const Duration(seconds: 12),
  String message =
      'La carga inicial esta tardando demasiado. Revisa tu conexion e intentalo nuevamente.',
}) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  var firstEventReceived = false;

  void stopTimer() {
    timer?.cancel();
    timer = null;
  }

  controller = StreamController<T>(
    onListen: () {
      timer = Timer(timeout, () {
        if (firstEventReceived || controller.isClosed) return;
        controller.addError(TimeoutException(message));
      });

      subscription = source.listen(
        (event) {
          firstEventReceived = true;
          stopTimer();
          if (!controller.isClosed) {
            controller.add(event);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          firstEventReceived = true;
          stopTimer();
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        },
        onDone: () {
          stopTimer();
          if (!controller.isClosed) {
            controller.close();
          }
        },
        cancelOnError: false,
      );
    },
    onCancel: () async {
      stopTimer();
      await subscription?.cancel();
    },
  );

  return controller.stream;
}
