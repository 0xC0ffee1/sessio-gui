import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sessio_ui/model/session_manager.dart';
import 'package:sessio_ui/src/generated/client_ipc.pbgrpc.dart';
import 'package:grpc/grpc.dart' as grpc;

abstract class SessionView extends StatefulWidget {
  final String sessionId;
  final SessionData sessionData;

  SessionView({required this.sessionId, required this.sessionData})
      : super(key: ValueKey(sessionId));
}

abstract class SessionViewState<T extends SessionView> extends State<T> {
  bool _showLocalDialog = false;
  String _errorMsg = "";
  String _errorTitle = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final session =
        Provider.of<SessionManager>(context).getSession(widget.sessionId);

    if (session?.closed == true && !_showLocalDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _showLocalDialog = true;
          _errorMsg = "Session has been closed.";
          _errorTitle = "Session Closed";
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = Provider.of<SessionManager>(context, listen: false);
    final future = manager.getSession(widget.sessionId)?.connectionFuture;
    return Stack(
      children: [
        FutureBuilder<void>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // Show loading indicator while connecting
              return Center(
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              // Handle any error that might have occurred during connect
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _showLocalDialog = true;
                  if (snapshot.error is grpc.GrpcError) {
                    final grpcError = snapshot.error as grpc.GrpcError;
                    _errorTitle = "Connection error";
                    _errorMsg = grpcError.message ?? "Unknown gRPC error";
                  } else {
                    _errorTitle = "Connection error";
                    _errorMsg = snapshot.error.toString();
                  }
                });
              });
              return Container();
            } else {
              // Once the future completes, show the session view
              return buildSessionView(context);
            }
          },
        ),
        if (_showLocalDialog)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showLocalDialog = false;
                });
              },
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorTitle,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        SizedBox(height: 16),
                        Text(_errorMsg),
                        SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              Provider.of<SessionManager>(context,
                                      listen: false)
                                  .reconnectSession(context, widget.sessionId);
                              _showLocalDialog = false;
                            });
                            // Optionally, you might want to reconnect or take other action here
                          },
                          child: Text('Reconnect'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget buildSessionView(BuildContext context);
}
