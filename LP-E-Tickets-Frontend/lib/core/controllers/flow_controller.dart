import 'package:flutter/foundation.dart';

/// Tracks asynchronous business operations independently of widget lifetime.
abstract class FlowController extends ChangeNotifier {
  final Set<String> _pending = {};
  final Map<String, Object> _errors = {};
  bool _disposed = false;

  bool isRunning(String operation) => _pending.contains(operation);
  Object? errorFor(String operation) => _errors[operation];

  @protected
  Future<T> execute<T>(String operation, Future<T> Function() action) async {
    if (_disposed) throw StateError('Controller disposed');
    if (_pending.contains(operation)) {
      throw StateError('Operation already in progress: $operation');
    }
    _pending.add(operation);
    _errors.remove(operation);
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      if (!_disposed) _errors[operation] = error;
      rethrow;
    } finally {
      _pending.remove(operation);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _errors.clear();
    super.dispose();
  }
}
