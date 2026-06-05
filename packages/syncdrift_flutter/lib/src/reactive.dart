import 'package:rxdart/rxdart.dart';

/// Extensions to convert regular Dart Streams into reactive, observable [ValueStream]s.
extension SyncdriftStreamExtension<T> on Stream<T> {
  /// Converts the stream into an observable [ValueStream] using a [BehaviorSubject].
  ///
  /// This allows synchronous access to the latest database value through
  /// `stream.value` or checking `stream.hasValue`.
  ValueStream<T> get obs {
    if (this is ValueStream<T>) {
      return this as ValueStream<T>;
    }

    final subject = BehaviorSubject<T>();
    final subscription = listen(
      (value) => subject.add(value),
      onError: (err, stack) => subject.addError(err, stack),
      onDone: () => subject.close(),
    );

    // Cancel the upstream subscription when all listeners cancel.
    subject.onCancel = () => subscription.cancel();
    return subject.stream;
  }
}
