import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sessio_ui/grpc_service.dart';
import 'package:sessio_ui/model/session_state.dart';
import 'package:sessio_ui/model/terminal_state.dart';
import 'package:sessio_ui/src/generated/client_ipc.pbgrpc.dart';
import 'package:uuid/uuid.dart';

class SessionManager extends ChangeNotifier {
  final Map<String, SessionState> _sessions = {};
  final Map<String, List<String>> _deviceSessions = {};
  Map<String, bool> deviceStatus = {};

  void addSession(String deviceId, SessionState sessionState) {
    _sessions[sessionState.sessionId] = sessionState;
    if (!_deviceSessions.containsKey(deviceId)) {
      _deviceSessions[deviceId] = [];
    }
    _deviceSessions[deviceId]!.add(sessionState.sessionId);
  }

  void setDeviceStatus(String deviceId, bool status) {
    deviceStatus[deviceId] = status;
    notifyListeners();
  }

  bool getDeviceStatus(String deviceId) {
    return deviceStatus[deviceId] ?? false;
  }

  List<String>? getDeviceSessions(String deviceId) {
    return _deviceSessions[deviceId];
  }

  void createSession(
      BuildContext context, SessionData data, SessioTerminalState? state) {
    final future = Provider.of<GrpcService>(context, listen: false)
        .newSession(data, state);
    final sessionState = SessionState(
        sessionData: data, sessionId: data.sessionId, terminalState: state);
    sessionState.connectionFuture = future;
    future.then((res) {
      setDeviceStatus(data.deviceId, true);
      notifyListeners();
    });
    addSession(data.deviceId, sessionState);
  }

  void reconnectSession(BuildContext context, String sessionId) {
    final sessionState = getSession(sessionId);
    final data = sessionState?.sessionData;
    sessionState?.closed = false;
    final future = Provider.of<GrpcService>(context, listen: false)
        .newSession(data!, sessionState?.terminalState);
    sessionState?.setFuture(future);
    future.then((res) {
      setDeviceStatus(data.deviceId, true);
      notifyListeners();
    });
    notifyListeners();
  }

  SessionState? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  void closeSession(String sessionId) {
    _sessions[sessionId]?.endSession();
    notifyListeners();
  }
}
