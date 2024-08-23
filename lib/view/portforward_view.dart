import 'package:flutter/material.dart';

import 'session_view.dart';

class PortForwardView extends SessionView {
  final String localAddress;
  final int localPort;
  final String remoteAddress;
  final int remotePort;
  

  PortForwardView({
    required this.localAddress,
    required this.localPort,
    required this.remoteAddress,
    required this.remotePort, required super.sessionId, required super.sessionData,
  });

  @override
  _PortForwardViewState createState() => _PortForwardViewState();
  
  @override
  Future<void> connect(BuildContext context) {
    // TODO: implement connect
    throw UnimplementedError();
  }
}

class _PortForwardViewState extends SessionViewState<PortForwardView> {

  @override
  Widget buildSessionView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Port Forwarding'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Currently forwarding from ${widget.localAddress}:${widget.localPort} to ${widget.remoteAddress}:${widget.remotePort}',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
