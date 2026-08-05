import 'package:flutter/widgets.dart';

/// Provides a small request generation guard for StatefulWidget-owned loads.
/// A newer refresh makes an older response ineligible to update the state.
mixin AsyncRequestGuard<T extends StatefulWidget> on State<T> {
  int _requestGeneration = 0;

  int beginAsyncRequest() => ++_requestGeneration;

  bool isCurrentAsyncRequest(int generation) {
    return mounted && generation == _requestGeneration;
  }
}
