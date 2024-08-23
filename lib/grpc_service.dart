import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:grpc/grpc.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sessio_ui/main.dart';
import 'package:sessio_ui/model/session_manager.dart';
import 'package:sessio_ui/model/sftp/sftp.dart';
import 'package:sessio_ui/model/terminal_state.dart';
import 'package:sessio_ui/src/generated/client_ipc.pbgrpc.dart';
import 'package:path_provider/path_provider.dart';

class GrpcService {
  late ClientIPCClient _client;
  late ClientEventServiceClient _events;

  Future<void> init() async {
    this._client = await _createClientIPCClient();
  }

  ClientEventServiceClient get events => _events;

  Future<SessionMap> getActiveSessions() async {
    final response = await _client.getActiveSessions(SessionRequest());
    return response;
  }

  Future<void> deleteSessionSave(String id) async {
    final user_data = await _client.getSaveData(GetSaveDataRequest());
    user_data.savedSessions.remove(id);
    await _client.saveUserData(user_data);
  }

  Future<ClientIPCClient> _createClientIPCClient() async {
    final ClientChannel channel;
    Directory appDir = await getApplicationSupportDirectory();
    if (Platform.isAndroid) {
      //Waiting for the tokio runtime to start
      await Future.delayed(Duration(seconds: 1));
    }

    if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
      String unixPath = Platform.isAndroid
          ? appDir.path + "/sessio.sock"
          : Platform.environment['HOME']! + "/.sessio/sessio.sock";
      final InternetAddress host =
          InternetAddress(unixPath, type: InternetAddressType.unix);
      channel = ClientChannel(
        host,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
    } else {
      channel = ClientChannel(
        'localhost',
        port: 53051, // Replace with your actual server port
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
    }
    final client = ClientIPCClient(channel);
    _events = ClientEventServiceClient(channel);

    return ClientIPCClient(channel);
  }

  ClientIPCClient get client {
    return _client;
  }

  Future<String> getIpv6() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        print(addr);
        if (addr.type == InternetAddressType.IPv6 &&
            addr.isLinkLocal == false) {
          return addr.address;
        }
      }
    }
    return "";
  }

  Future<NewSessionResponse> newSshSession(SessionData data) async {
    Settings settings = await client.getSettings(SettingsRequest());
    var wifiIPv6 = await getIpv6();
    wifiIPv6 = wifiIPv6.split("%")[
        0]; //For some reason android adds this to even non link-local addresses?

    NewConnectionResponse connectionResponse =
        await client.newConnection(NewConnectionRequest()
          ..coordinatorUrl = settings.coordinatorUrl
          ..targetId = data.deviceId
          ..ownIpv6 = wifiIPv6);
          

    NewSessionResponse sessionResponse =
        await client.newSession(NewSessionRequest()
          ..privateKey = "keys/id_ed25519"
          ..knownHostsPath = "known_hosts"
          ..sessionData = data);

    return sessionResponse;
  }

  Future<void> newSession(SessionData data, SessioTerminalState? terminalState) async {
    final res = await newSshSession(data);
    data.sessionId = res.sessionId;
    switch(data.whichKind()) {
      case SessionData_Kind.pty:
        connectPTY(terminalState!, res.sessionId);
        break;
      case SessionData_Kind.lpf:
        connectLPF(data, res.sessionId);
        break;
      case SessionData_Kind.sftp:
        connectSFTP(data, res.sessionId);
        break;
      case SessionData_Kind.notSet:
        break;
    };
  }

    Future<void> reconnectSession(SessionData data, String sessionId, SessioTerminalState? terminalState) async {
    switch(data.whichKind()) {
      case SessionData_Kind.pty:
        connectPTY(terminalState!, sessionId);
        break;
      case SessionData_Kind.lpf:
        connectLPF(data, sessionId);
        break;
      case SessionData_Kind.sftp:
        connectSFTP(data, sessionId);
        break;
      case SessionData_Kind.notSet:
        break;
    };
  }

  Future<SftpBrowser> connectSFTP(SessionData data, String sessionId) async {
    final t = DateTime.now().millisecondsSinceEpoch;
    data.sessionId = sessionId;
    final res = await client.openSftpChannel(data);
    final browser = SftpBrowser(client, sessionId);
    await browser.refreshFileList();
    return browser;
  }

  void connectLPF(SessionData data, String sessionId) async {
    data.sessionId = sessionId;

    await client.localPortForward(data);
  }

void reconnectPTY(SessioTerminalState state, String sessionId) async {
    state.streamController = StreamController();
    final streamController = state.streamController;
    var t = DateTime.now().millisecondsSinceEpoch;

    final responseStream = client.openChannel(streamController.stream);
    state.terminal.write("Reconnected!\r\n");

    streamController.add(Msg()..channelInit = (Msg_ChannelInit()..sessionId = sessionId));

        streamController.add(Msg()
    ..ptyRequest = (Msg_PtyRequest()
      ..colWidth = state.terminal.viewWidth
      ..rowHeight = state.terminal.viewHeight));


    streamController.add(Msg()..shellRequest = (Msg_ShellRequest()));
  }

  void connectPTY(SessioTerminalState state, String sessionId) async {
    state.streamController = StreamController();
    final streamController = state.streamController;
    var t = DateTime.now().millisecondsSinceEpoch;

    final responseStream = client.openChannel(streamController.stream);
    state.terminal.write("Connected! Session ID is: ${sessionId} \r\n");

    streamController.add(Msg()..channelInit = (Msg_ChannelInit()..sessionId = sessionId));

        streamController.add(Msg()
    ..ptyRequest = (Msg_PtyRequest()
      ..colWidth = state.terminal.viewWidth
      ..rowHeight = state.terminal.viewHeight));

    streamController.add(Msg()..shellRequest = (Msg_ShellRequest()));

    // Handle terminal output
    state.terminal.onOutput = (data) {
      // Add the data to the stream
      streamController
          .add(Msg()..data = (Msg_Data()..payload = data.codeUnits));
      // Write the data to the terminal
      //state.terminal.write(data);
    };

    state.terminal.onResize = (w, h, pw, ph) {
      streamController.add(Msg()
        ..ptyResize = (Msg_PtyResize()
          ..colWidth = w
          ..rowHeight = h));
    };

    bool pinged = false;

    //state.terminal.buffer.clear();
    //state.terminal.buffer.setCursor(0, 0);

    streamController.add(Msg()
      ..ptyResize = (Msg_PtyResize()
        ..colWidth = state.terminal.viewWidth
        ..rowHeight = state.terminal.viewHeight));

    //This will trigger a redraw
    //Also causes weird bash malloc issues
    
    // Handle responses
    await for (var response in responseStream) {
      // Handle the response
      if (response.hasData()) {
        if (!pinged) {
          state.terminal.write(
              "Took to connect: ${DateTime.now().millisecondsSinceEpoch - t}ms.\r\n");

          pinged = true;
        }
        String data = utf8.decode(response.data.payload, allowMalformed: true);
        //state.terminal.write("\b \b");
        try {
          state.terminal.write(data);
        } catch (e) {}
      }
    }
  }
}
