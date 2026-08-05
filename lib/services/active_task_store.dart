import 'package:shared_preferences/shared_preferences.dart';

/// Persists resumable server tasks without exposing SharedPreferences to UI.
class ActiveTaskStore {
  ActiveTaskStore(this._preferences);

  final SharedPreferences _preferences;

  Future<String?> read({required String prefix, required String scope}) async {
    return _preferences.getString(_key(prefix, scope));
  }

  Future<void> write({
    required String prefix,
    required String scope,
    required String taskId,
  }) async {
    await _preferences.setString(_key(prefix, scope), taskId.trim());
  }

  Future<void> remove({required String prefix, required String scope}) async {
    await _preferences.remove(_key(prefix, scope));
  }

  Future<int> removeScope(String scope) async {
    final keys = _preferences
        .getKeys()
        .where((key) => key.startsWith('active_') && key.endsWith(':$scope'))
        .toList(growable: false);
    for (final key in keys) {
      await _preferences.remove(key);
    }
    return keys.length;
  }

  String _key(String prefix, String scope) => '$prefix:$scope';
}
