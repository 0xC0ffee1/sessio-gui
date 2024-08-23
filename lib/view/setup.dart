import 'package:flutter/material.dart';

class SetupWidget extends StatefulWidget {
  final Function(String, String) onSubmit;

  SetupWidget({required this.onSubmit});

  @override
  _SetupWidgetState createState() => _SetupWidgetState();
}

class _SetupWidgetState extends State<SetupWidget> {
  final _formKey = GlobalKey<FormState>();
  final _coordinatorUrlController = TextEditingController();
  final _deviceIdController = TextEditingController();

  @override
  void dispose() {
    _coordinatorUrlController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (_formKey.currentState?.validate() ?? false) {
      String coordinatorUrl = _coordinatorUrlController.text;
      String deviceId = _deviceIdController.text;

      // Pass the values to the parent widget using the callback
      widget.onSubmit(coordinatorUrl, deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double panelWidth = MediaQuery.of(context).size.width * 0.3;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          width: panelWidth,
          child: Card(
            elevation: 4.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Initial setup"),
                    TextFormField(
                      controller: _coordinatorUrlController,
                      decoration: InputDecoration(
                        labelText: 'Coordinator URL',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a Coordinator URL';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16.0),
                    TextFormField(
                      controller: _deviceIdController,
                      decoration: InputDecoration(
                        labelText: 'Device ID',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a Device ID';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 32.0),
                    ElevatedButton(
                      onPressed: _submitForm,
                      child: Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
