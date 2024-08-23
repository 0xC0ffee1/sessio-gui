import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sessio_ui/grpc_service.dart';
import 'package:sessio_ui/model/session_manager.dart';
import 'package:sessio_ui/model/session_state.dart';
import 'package:sessio_ui/model/sftp/sftp.dart';
import 'package:sessio_ui/model/terminal_state.dart';
import 'package:sessio_ui/src/generated/client_ipc.pbgrpc.dart';
import 'package:sessio_ui/view/mobile_keyboard.dart';
import 'package:sessio_ui/view/portforward_view.dart';
import 'package:sessio_ui/view/session_view.dart';
import 'package:sessio_ui/view/settings_page.dart';
import 'package:sessio_ui/view/setup.dart';
import 'package:sessio_ui/view/sftp_browser.dart';
import 'package:sessio_ui/view/terminal_session_view.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';
import 'package:xterm/xterm.dart';

import '../main.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //Session id is the key
  HashMap<String, SessionView> sessionViews = HashMap();
  int _selectedRailIndex = 0;
  int _selectedSessionIndex = 0;
  bool _isDrawerOpen = true; // New state variable to track drawer state
  final PageController _pageController = PageController();

  Map<String, List<Widget>> sessionTree = {};

  Timer? _healthTimer;
  bool _isDaemonErrorOpen = false;
  bool _settingsValid = true;

  late Future<void> serviceFuture;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    initAndroid();
    _checkDaemonHealth(null);
    _healthTimer = Timer.periodic(Duration(seconds: 5), _checkDaemonHealth);
  }

  void initAndroid() {
    if (!Platform.isAndroid) return;
    checkPerms();
    initializeService();
  }

  Future<void> checkSettingsValidity() async {
    final valid = (await Provider.of<GrpcService>(context, listen: false)
            .client
            .startCoordinator(CoordinatorStartRequest()))
        .started;

    setState(() {
      _settingsValid = valid;
    });
  }

  void resetSessions() {
    sessionViews = HashMap();
    sessionTree = HashMap();
  }

  void _checkDaemonHealth(Timer? timer) async {
    try {
      final nat = await Provider.of<GrpcService>(context, listen: false)
          .client
          .getNatFilterType(NatFilterRequest());
    } catch (e) {
      if (e is grpc.GrpcError) {
        if (e.code == grpc.StatusCode.unavailable && !_isDaemonErrorOpen) {
          _isDaemonErrorOpen = true;
          await showDialog(
            context: navigatorKey.currentContext!,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Could not connect to daemon'),
                  ],
                ),
                content: Text(e.message!),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      resetSessions();
                      serviceFuture = _loadSessions();
                      _isDaemonErrorOpen = false;
                    },
                    child: Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () {
                      exit(0);
                    },
                    child: Text('Quit'),
                  ),
                ],
              );
            },
          );
        }
      } else {
        print('Error during daemon check: $e');
      }
    }
  }

  void listenToEvents() async {
    final eventStream = await Provider.of<GrpcService>(context, listen: false)
        .events
        .subscribe(SubscribeRequest());
    await for (var event in eventStream) {
      // Handle the response
      switch (event.whichKind()) {
        case ClientEvent_Kind.close:
          {
            final sessionManager =
                Provider.of<SessionManager>(context, listen: false);
            if (event.close.streamType == ClientEvent_StreamType.TRANSPORT) {
              //Marking it as offline
              setState(() {
                sessionManager.setDeviceStatus(event.close.id, false);
              });

              final sessions = sessionManager.getDeviceSessions(event.close.id);
              sessions?.forEach((sesId) => sessionManager.closeSession(sesId));
            } else {
              sessionManager.closeSession(event.close.id);
            }
            break;
          }
        case ClientEvent_Kind.notSet:
          {}
      }
    }
  }

  Future<void> _loadSessions() async {
    final service = Provider.of<GrpcService>(context, listen: false);
    serviceFuture = service.init();
    await serviceFuture;

    await checkSettingsValidity();

    final sessionMap = await service.getActiveSessions();

    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
      SnackBar(
        content: Text('Connected to daemon'),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            Theme.of(navigatorKey.currentContext!).colorScheme.primary,
        duration: Duration(seconds: 1),
      ),
    );

    listenToEvents();

    for (var entry in sessionMap.map.entries) {
      var sessionData = entry.value;
      var clientId = sessionData.deviceId;

      if (sessionData.hasPty()) {
        await _addNewSession(
            clientId, sessionData.username, 'PTY', sessionData.sessionId);
      } else if (sessionData.hasSftp()) {
        await _addNewSession(
            clientId, sessionData.username, 'SFTP', sessionData.sessionId);
      } else if (sessionData.hasLpf()) {
        var lpf = sessionData.lpf;
        await _addLocalPFSession(
            clientId,
            sessionData.username,
            lpf.localHost,
            lpf.localPort,
            lpf.remoteHost,
            lpf.remotePort,
            sessionData.sessionId);
      }
    }
  }

  Future<void> initializeService() async {
    if (await FlutterBackgroundService().isRunning()) return;

    final service = FlutterBackgroundService();
    const notificationId = 888;
    const notificationChannelId = 'sessio_grpc_service';

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId, // id
      'sessio_grpc_service', // title
      description:
          'This channel is used for important notifications.', // description
      importance: Importance.low, // importance must be at low or higher level
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
        androidConfiguration: AndroidConfiguration(
          // this will be executed when app is in foreground or background in separated isolate
          onStart: onStart,

          // auto start service
          autoStart: true,
          isForegroundMode: true,

          notificationChannelId:
              notificationChannelId, // this must match with notification channel you created above.
          initialNotificationTitle: 'Sessio',
          initialNotificationContent: 'Sessio is running',
          foregroundServiceNotificationId: notificationId,
        ),
        iosConfiguration: IosConfiguration());
  }

  void checkPerms() async {
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
    if (!await Permission.notification.isGranted &&
        !await Permission.notification.isPermanentlyDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _showClientIdDialog() async {
    TextEditingController clientIdController = TextEditingController();
    TextEditingController usernameController = TextEditingController();
    TextEditingController localHostPortController = TextEditingController();
    TextEditingController remoteHostPortController = TextEditingController();
    String sessionType = "PTY"; // Default session type

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Enter Device ID'),
              content: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField(usernameController, 'Username'),
                      SizedBox(height: 10),
                      _buildTextField(clientIdController, 'Device ID'),
                      SizedBox(height: 20),
                      Text(
                        'Select Session Type',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 10.0,
                        children: [
                          _buildFilterChip(
                            context,
                            setState,
                            'PTY',
                            sessionType,
                            Icons.terminal,
                            () => setState(() => sessionType = 'PTY'),
                          ),
                          _buildFilterChip(
                            context,
                            setState,
                            'SFTP',
                            sessionType,
                            Icons.folder_open,
                            () => setState(() => sessionType = 'SFTP'),
                          ),
                          _buildFilterChip(
                            context,
                            setState,
                            'L-PF',
                            sessionType,
                            Symbols.valve,
                            () => setState(() => sessionType = 'L-PF'),
                          ),
                        ],
                      ),
                      if (sessionType == 'L-PF') ...[
                        SizedBox(height: 10),
                        _buildTextField(
                            localHostPortController, 'Local Host:Port'),
                        SizedBox(height: 10),
                        _buildTextField(
                            remoteHostPortController, 'Remote Host:Port'),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text('Connect'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (sessionType == 'L-PF') {
                      var localHostPort =
                          localHostPortController.text.split(':');
                      var remoteHostPort =
                          remoteHostPortController.text.split(':');
                      _addLocalPFSession(
                          clientIdController.text,
                          usernameController.text,
                          localHostPort[0],
                          int.parse(localHostPort[1]),
                          remoteHostPort[0],
                          int.parse(remoteHostPort[1]),
                          null);
                    } else {
                      _addNewSession(clientIdController.text,
                          usernameController.text, sessionType, null);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String hintText) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        hintText: hintText,
      ),
    );
  }

  Widget _buildFilterChip(
      BuildContext context,
      StateSetter setState,
      String label,
      String selectedType,
      IconData icon,
      VoidCallback onSelected) {
    bool isSelected = selectedType == label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: FilterChip(
        avatar: Icon(icon, color: isSelected ? Colors.white : Colors.black),
        label: Container(
          width: 50,
          child: Center(child: Text(label)),
        ),
        selected: isSelected,
        onSelected: (selected) => onSelected(),
        selectedColor: Colors.pink,
        backgroundColor: Colors.grey[200],
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
        showCheckmark: false,
      ),
    );
  }

  Future<void> _addLocalPFSession(
      String clientId,
      String username,
      String hostLocal,
      int portLocal,
      String hostRemote,
      int portRemote,
      String? sessionId) async {
    GrpcService service = Provider.of<GrpcService>(context, listen: false);

    final data = SessionData(
        sessionId: sessionId,
        deviceId: clientId,
        username: username,
        lpf: SessionData_LPFSession(
            localHost: hostLocal,
            localPort: portLocal,
            remoteHost: hostRemote,
            remotePort: portRemote));

    NewSessionResponse sessionResponse = await service.newSshSession(data);

    String sessionIdActual = sessionResponse.sessionId;

    Provider.of<GrpcService>(context, listen: false)
        .connectLPF(data, sessionIdActual);

    if (!sessionTree.containsKey(clientId)) {
      sessionTree[clientId] = [];
    }
    sessionTree[clientId]!.add(
      Row(
        children: [
          Icon(Symbols.valve),
          SizedBox(width: 8),
          Text("L-PF"),
        ],
      ),
    );

    setState(() {
      sessionViews[sessionIdActual] = PortForwardView(
        localAddress: hostLocal,
        localPort: portLocal,
        remoteAddress: hostRemote,
        remotePort: portRemote,
        sessionId: sessionResponse.sessionId,
        sessionData: data,
      );
    });
  }

  Future<void> _addNewSession(
      String clientId, String username, String type, String? sessionId) async {
    if (!sessionTree.containsKey(clientId)) {
      sessionTree[clientId] = [];
    }
    GrpcService service = Provider.of<GrpcService>(context, listen: false);
    int currentIndex = sessionTree[clientId]!.length;
    sessionTree[clientId]!.add(
      Row(
        children: [
          Icon(type == "PTY" ? Icons.terminal : Icons.folder_open),
          SizedBox(width: 8),
          Text(type),
          Spacer(),
          IconButton(
              onPressed: () {
                if (sessionId != null) {
                  Provider.of<GrpcService>(context, listen: false)
                      .deleteSessionSave(sessionId);
                }
                setState(() {
                  sessionTree[clientId]!.removeAt(currentIndex);
                  if (sessionTree[clientId]!.isEmpty) {
                    sessionTree.remove(clientId);
                  }
                });
              },
              icon: Icon(Icons.delete))
        ],
      ),
    );

    if (type == "PTY") {
      print("added session 2!");
      final sessionState = SessioTerminalState();
      final keyboard = VirtualKeyboard(defaultInputHandler);
      sessionState.terminal.inputHandler = keyboard;

      final sessionIdFinal = sessionId == null ? Uuid().v4() : sessionId;

      final data = SessionData(
          sessionId: sessionIdFinal,
          username: username,
          deviceId: clientId,
          pty: SessionData_PTYSession());

      setState(() {
        sessionViews[sessionIdFinal] = TerminalSessionView(
          terminalState: sessionState,
          keyboard: keyboard,
          sessionId: sessionIdFinal,
          sessionData: data,
        );
      });

      print("added session 2.1");

      Provider.of<SessionManager>(context, listen: false)
          .createSession(context, data, sessionState);
      print("added session 3!");
    } else if (type == "SFTP") {
      final data = SessionData(
          sessionId: sessionId,
          deviceId: clientId,
          username: username,
          sftp: SessionData_SFTPSession());
      NewSessionResponse sessionResponse = await service.newSshSession(data);

      SftpBrowser browser =
          await Provider.of<GrpcService>(context, listen: false)
              .connectSFTP(data, sessionResponse.sessionId);

      setState(() {
        sessionViews[sessionResponse.sessionId] = FileBrowserView(
          browser: browser,
          sessionId: sessionResponse.sessionId,
          sessionData: data,
        );
      });
    }
  }

  Widget _buildConnStatus(String deviceId) {
    return Consumer<SessionManager>(
      builder: (context, sessionManager, child) {
        final enabled = sessionManager.getDeviceStatus(deviceId);
        return Tooltip(
          message: enabled ? "Online" : "Offline",
          child: Icon(Icons.circle_outlined,
              color: enabled ? Colors.green : Colors.red, size: 15),
        );
      },
    );
  }

  Widget _buildMioLeftNavRail() {
    final theme = Theme.of(context);
    return Row(children: [
      NavigationRail(
        backgroundColor: theme.colorScheme.surfaceBright,
        indicatorColor: const Color.fromARGB(50, 233, 30, 99),
        selectedIndex: _selectedRailIndex <= 1 ? _selectedRailIndex : 0,
        minWidth: 80,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedRailIndex = index;
            _updateCurrentPageIndex(index);
          });
        },
        labelType: NavigationRailLabelType.all,
        destinations: [
          NavigationRailDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_filled),
            label: Text('Sessions'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('Settings'),
          ),
        ],
      ),
      _buildMioNavigationDrawer()
    ]);
  }

  Widget _buildSessionListView() {
    int offset = 0;
    return ListView(
      padding: EdgeInsets.zero, // Remove any padding
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(children: [
            SizedBox(height: 20),
            TextButton(
              onPressed: () async {
                await _showClientIdDialog();
              },
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add),
                    SizedBox(width: 10),
                    Text('New Session')
                  ]),
            )
          ]),
        ),
        ...sessionTree.keys.map((parent) {
          final tile = ExpansionTile(
            shape: Border(),
            title: Row(children: [
              _buildConnStatus(parent),
              SizedBox(width: 8),
              Text(
                parent,
              )
            ]),
            children: sessionTree[parent]!.asMap().entries.map((entry) {
              int index = entry.key + offset;
              Widget session = entry.value;
              return Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: ListTile(
                  title: session,
                  selected: _selectedSessionIndex - 2 == index,
                  selectedColor: Colors.pink,
                  onTap: () {
                    setState(() {
                      _selectedSessionIndex =
                          index + 2; // Ensure session indices start from 2
                      print("Setting index to ${_selectedSessionIndex}");
                    });
                  },
                ),
              );
            }).toList(),
          );
          offset += sessionTree[parent]!.length;
          return tile;
        }).toList(),
      ],
    );
  }

  Widget _buildMioNavigationDrawer() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Stack(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 200),
              curve: Curves.easeIn,
              width: _isDrawerOpen ? 200 : 0,
              color: theme.colorScheme
                  .surfaceContainerHigh, // Ensure background color matches
              child: ClipRect(
                child: Align(
                    alignment: Alignment.topLeft,
                    widthFactor: _isDrawerOpen ? 1.0 : 0.0,
                    child: _buildSessionListView()),
              ),
            ),
          ],
        ),
        VerticalDivider(thickness: 1, width: 1),
      ],
    );
  }

  void _updateCurrentPageIndex(int index) {
    if (index != 0 && _isDrawerOpen) {
      _isDrawerOpen = !_isDrawerOpen;
    } else if (index == 0) {
      _isDrawerOpen = !_isDrawerOpen;
    }
  }

  Widget _buildSessionPage() {
    return Row(children: [
      Expanded(
          child: _selectedSessionIndex > 1
              ? sessionViews.values.elementAt(_selectedSessionIndex - 2)
              : Center(child: Text('No sessions yet!'))),
    ]);
  }

  Widget _buildSessionPageSmall() {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sessions"),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu),
            onPressed: () {
              // Open the drawer using the context provided by Builder
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
      ),
      drawer: Drawer(child: _buildSessionListView()),
      body: _selectedSessionIndex > 1
          ? sessionViews.values.elementAt(_selectedSessionIndex - 2)
          : Center(child: Text('No sessions yet!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: serviceFuture, // This should be your Future
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show a loading indicator while the future is resolving
          return Center(
            child: CircularProgressIndicator(),
          );
        } else if (snapshot.hasError) {
          // Handle errors if the future fails
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        } else {
          // Once the future is resolved, build the main UI
          if (!_settingsValid) {
            return SettingsPage(
                caption: "Initial Setup",
                onSubmit: () {
                  checkSettingsValidity();
                });
          }
          return Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 600) {
                  // Larger screens
                  return Row(
                    children: [
                      _buildMioLeftNavRail(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: 100),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          child: _selectedRailIndex == 0
                              ? _buildSessionPage()
                              : SettingsPage(),
                        ),
                      ),
                    ],
                  );
                } else {
                  // Smaller screens
                  return Column(
                    children: [
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _selectedRailIndex = index;
                            });
                          },
                          children: [_buildSessionPageSmall(), SettingsPage()],
                        ),
                      ),
                      BottomNavigationBar(
                        currentIndex: _selectedRailIndex,
                        onTap: (int index) {
                          setState(() {
                            _selectedRailIndex = index;
                            _pageController.animateToPage(index,
                                duration: Duration(milliseconds: 200),
                                curve: Curves.easeIn);
                          });
                        },
                        items: [
                          BottomNavigationBarItem(
                            icon: Icon(Icons.home),
                            label: 'Sessions',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.settings),
                            label: 'Settings',
                          ),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
          );
        }
      },
    );
  }
}
