import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sessio_ui/grpc_service.dart';
import 'package:sessio_ui/src/generated/proto/client_ipc.pbgrpc.dart';

class SettingsPage extends StatefulWidget {
  final String? caption;
  final VoidCallback? onSubmit;

  SettingsPage({this.caption, this.onSubmit});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<Settings> _settingsFuture;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _deviceIdController = TextEditingController();
  late GrpcService _grpcService;
  String publicKey = '';

  @override
  void initState() {
    super.initState();
    _grpcService = Provider.of<GrpcService>(context, listen: false);
    _settingsFuture = _grpcService.client.getSettings(SettingsRequest());

    _loadPublicKey();
    _loadInitialSettings();
  }

  void _loadPublicKey() async {
    publicKey = (await _grpcService.client.getPublicKey(GetKeyRequest())).key;
  }

  void _loadInitialSettings() async {
    try {
      final settings = await _settingsFuture;
      _urlController.text = settings.coordinatorUrl;
      _deviceIdController.text = settings.deviceId;
    } catch (e) {}
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState?.validate() ?? false) {
      final newSettings = Settings(
        coordinatorUrl: _urlController.text,
        deviceId: _deviceIdController.text,
      );

      try {
        await _grpcService.client.saveSettings(newSettings);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settings saved successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: Duration(seconds: 1),
          ),
        );
        if (widget.onSubmit != null) {
          widget.onSubmit!();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _generateKeyPair() async {
    await _grpcService.client.genKeys(GenKeysRequest());
    final newKey =
        (await _grpcService.client.getPublicKey(GetKeyRequest())).key;
    setState(() {
      publicKey = newKey;
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: publicKey));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Public key copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.caption ?? 'Settings'),
      ),
      body: FutureBuilder<Settings>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return Center(child: Text('No data found.'));
          } else {
            return Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(16.0),
                children: [
                  ListTile(
                    leading: Icon(Icons.public),
                    title: Text('Coordinator URL'),
                    subtitle: TextFormField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter your coordinator URL',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a Coordinator URL';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(height: 16.0),
                  ListTile(
                    leading: Icon(Icons.perm_identity),
                    title: Text('Device ID'),
                    subtitle: TextFormField(
                      controller: _deviceIdController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter the ID of this device',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a Device ID';
                        }
                        return null;
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.key),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Public Key'),
                        SizedBox(height: 8.0),
                        TextFormField(
                          controller: TextEditingController(text: publicKey),
                          readOnly: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'No keys generated',
                            suffixIcon: publicKey.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.copy),
                                    onPressed: _copyToClipboard,
                                  )
                                : null,
                          ),
                        ),
                        SizedBox(height: 8.0),
                        ElevatedButton(
                          onPressed: _generateKeyPair,
                          child: Text('Generate new pair'),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveSettings,
        backgroundColor: Colors.pink,
        child: Icon(Icons.save),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }
}
