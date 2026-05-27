import 'api_service.dart';

class SessionBootstrapService {
  SessionBootstrapService._();

  static SessionStartResponse? _pendingSession;

  static void stash(SessionStartResponse session) {
    _pendingSession = session;
  }

  static SessionStartResponse? peek() {
    return _pendingSession;
  }

  static SessionStartResponse? consume() {
    final session = _pendingSession;
    _pendingSession = null;
    return session;
  }

  static void clear() {
    _pendingSession = null;
  }
}
