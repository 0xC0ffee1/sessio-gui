import 'package:flutter/material.dart';
import 'package:sessio_ui/model/terminal_state.dart';
import 'package:sessio_ui/src/generated/proto/client_ipc.pbgrpc.dart';

class SessionState extends ChangeNotifier {
  final String sessionId;
  final SessionData sessionData;
  final SessioTerminalState? terminalState;

  DateTime startTime = DateTime.now();
  bool closed = false;
  late Future<void> connectionFuture;

  SessionState(
      {required this.sessionData,
      required this.sessionId,
      required this.terminalState});

  void setFuture(Future<void> connectionFuture) {
    this.connectionFuture = connectionFuture;
  }

  void endSession() {
    this.closed = true;
    notifyListeners();
  }
}
