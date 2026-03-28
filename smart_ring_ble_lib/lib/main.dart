// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ble_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Ring Ble Lib',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Smart Ring Ble Lib'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final BleService _bleService = BleService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _macAddressController = TextEditingController();
  
  String _connectionStatus = 'Disconnected';
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isExerciseActive = false;
  bool _isRealtimeActive = false; // 0x09 real-time stream state
  bool _isHrMeasureActive = false; // 0x28 HR measurement state
  int _ignoreRealtimeUntilMs = 0; // guard window after Stop to ignore trailing 0x09 packets
  List<String> _messages = [];
  String _structuredDataTitle = '';
  String _structuredDataOutput = '';

  @override
  void initState() {
    super.initState();
    // Prefill target fields from BleService defaults/current target
    final name = _bleService.targetDeviceName;
    final mac = _bleService.targetMacAddress;
    if (name != null && name.isNotEmpty) {
      _deviceNameController.text = name;
    } else {
      _deviceNameController.text = 'X6B 45CC8';
    }
    if (mac != null && mac.isNotEmpty) {
      _macAddressController.text = mac;
    } else {
      _macAddressController.text = 'F8:19:23:14:5C:C8';
    }
    // Push initial target into BleService
    _applyTarget();
    _initializeBle();
  }

  Future<void> _initializeBle() async {
    _bleService.connectionStatusStream.listen((status) {
      setState(() {
        _connectionStatus = status;
      });
    });

    _bleService.messageStream.listen((message) {
      _addMessage('Received: $message');
      _updateExerciseStateFromMessage(message);
      _updateRealtimeStateFromMessage(message);
      // Optionally update 0x28 HR measurement state when we add parser support
    });

    await _autoConnectToSmartRing();
  }

  Future<void> _autoConnectToSmartRing() async {
    setState(() {
      _isConnecting = true;
    });
    
    try {
      _addMessage('Auto-connecting to Smart Ring...');
      await _bleService.connectToSmartRing();
      _addMessage('Successfully connected to Smart Ring!');
    } catch (e) {
      _addMessage('Auto-connect failed: $e');
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _showSetUserInfoDialog() async {
    final genderOptions = ['Female', 'Male'];
    String selectedGender = 'Female';
    final ageController = TextEditingController(text: '30');
    final heightController = TextEditingController(text: '170');
    final weightController = TextEditingController(text: '65');
    final stepLenController = TextEditingController(text: '60');
    final ringIdController = TextEditingController(text: '000000');

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Set User Info (0x02)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: genderOptions
                          .map((g) => DropdownMenuItem<String>(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setStateDialog(() => selectedGender = v);
                      },
                    ),
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Age (years, 0-120)'),
                    ),
                    TextField(
                      controller: heightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Height (cm, 50-250)'),
                    ),
                    TextField(
                      controller: weightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Weight (kg, 10-300)'),
                    ),
                    TextField(
                      controller: stepLenController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Step Length (cm, 20-120)'),
                    ),
                    TextField(
                      controller: ringIdController,
                      decoration: const InputDecoration(labelText: 'Ring ID (ASCII up to 6 chars)'),
                      maxLength: 6,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      int gender = selectedGender == 'Male' ? 1 : 0;
                      int age = int.tryParse(ageController.text.trim()) ?? 0;
                      int height = int.tryParse(heightController.text.trim()) ?? 0;
                      int weight = int.tryParse(weightController.text.trim()) ?? 0;
                      int stepLen = int.tryParse(stepLenController.text.trim()) ?? 0;
                      String ringId = ringIdController.text.trim();

                      // Basic validation ranges
                      if (age < 0 || age > 120) throw 'Age must be 0-120';
                      if (height < 50 || height > 250) throw 'Height must be 50-250 cm';
                      if (weight < 10 || weight > 300) throw 'Weight must be 10-300 kg';
                      if (stepLen < 20 || stepLen > 120) throw 'Step length must be 20-120 cm';
                      if (ringId.isEmpty) ringId = '000000';

                      await _bleService.sendSetUserInfoCommand(
                        gender: gender,
                        age: age,
                        heightCm: height,
                        weightKg: weight,
                        stepLengthCm: stepLen,
                        ringId: ringId,
                      );
                      if (mounted) {
                        Navigator.of(ctx).pop();
                        _addMessage('✅ Set User Info (0x02) command sent. sendSetUserInfoCommand()');
                        // Optionally refresh readback
                        await _bleService.sendGetUserInfoCommand();
                      }
                    } catch (e) {
                      _addMessage('❌ Failed to set user info: $e');
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _sendGetUserInfoCommand() async {
    try {
      await _bleService.sendGetUserInfoCommand();
      _addMessage('✅ Get User Info (0x42) command sent. sendGetUserInfoCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get User Info (0x42): $e. sendGetUserInfoCommand()');
    }
  }

  Future<void> _sendGetExerciseModeDataLatest() async {
    try {
      await _bleService.sendGetExerciseModeDataLatest();
      _addMessage('✅ Exercise Latest (0x5C) command sent. sendGetExerciseModeDataLatest()');
    } catch (e) {
      _addMessage('❌ Failed to send Exercise Latest (0x5C): $e. sendGetExerciseModeDataLatest()');
    }
  }

  Future<void> _sendGetExerciseModeDataContinue() async {
    try {
      await _bleService.sendGetExerciseModeDataContinue();
      _addMessage('✅ Exercise Continue (0x5C) command sent. sendGetExerciseModeDataContinue()');
    } catch (e) {
      _addMessage('❌ Failed to send Exercise Continue (0x5C): $e. sendGetExerciseModeDataContinue()');
    }
  }

  Future<void> _sendDeleteExerciseModeDetails() async {
    try {
      await _bleService.sendDeleteExerciseModeDetails();
      _addMessage('✅ Exercise Delete (0x5C) command sent. sendDeleteExerciseModeDetails()');
    } catch (e) {
      _addMessage('❌ Failed to send Exercise Delete (0x5C): $e. sendDeleteExerciseModeDetails()');
    }
  }

  void _addMessage(String message) {
    setState(() {
      _messages.add(message);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _updateExerciseStateFromMessage(String message) {
    // Update exercise state based on parsed responses
    if (message.contains('🏃 Exercise Status:')) {
      setState(() {
        _isExerciseActive = message.contains('✅ Exercise mode is ACTIVE');
      });
    } else if (message.contains('🏃 Live Exercise Data:')) {
      // If we're receiving live exercise data, exercise must be active
      if (message.contains('🛑 Exercise mode ended')) {
        setState(() {
          _isExerciseActive = false;
        });
      } else if (message.contains('🏃 Exercise in progress')) {
        setState(() {
          _isExerciseActive = true;
        });
      }
    }
  }

  void _updateRealtimeStateFromMessage(String message) {
    // Mark real-time stream as active when 0x09 parsed response arrives
    if (message.contains('📡 Real-time Mode:')) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now > _ignoreRealtimeUntilMs && !_isRealtimeActive) {
        setState(() {
          _isRealtimeActive = true;
        });
      }
    }
    // If a stop confirmation message format is added later, handle it here to set false.
  }

  void _applyTarget() {
    final name = _deviceNameController.text.trim();
    final mac = _macAddressController.text.trim();
    _bleService.setTarget(
      deviceName: name.isEmpty ? null : name,
      macAddress: mac.isEmpty ? null : mac,
    );
    _addMessage('🎯 Target updated to: ${name.isEmpty ? '-' : name} / ${mac.isEmpty ? '-' : mac}');
  }

  @override
  void dispose() {
    _bleService.dispose();
    _deviceNameController.dispose();
    _macAddressController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleHrMeasurement() async {
    try {
      if (_isHrMeasureActive) {
        await _bleService.sendStopMultiParamMeasurement(mode: 0x02);
        _addMessage('✅ Stop HR Measure (0x28) command sent.');
        setState(() => _isHrMeasureActive = false);
      } else {
        await _bleService.sendStartMultiParamMeasurement(mode: 0x02, durationSeconds: 30);
        _addMessage('✅ Start HR Measure (0x28) command sent.');
        setState(() => _isHrMeasureActive = true);
      }
    } catch (e) {
      _addMessage('❌ Failed to toggle HR measurement: $e.');
    }
  }

  Future<void> _fetchNewHrvData() async {
    try {
      setState(() {
        _structuredDataTitle = 'HRV Data (0x56)';
        _structuredDataOutput = 'Fetching HRV data...';
      });
      final records = await _bleService.fetchHrvData(timeout: const Duration(seconds: 3));
      if (!mounted) return;
      if (records.isEmpty) {
        setState(() {
          _structuredDataOutput = 'No HRV records received within timeout.';
        });
        return;
      }
      final buf = StringBuffer();
      buf.writeln('Count: ${records.length}');
      for (final r in records) {
        buf.writeln('- ${r.toString()}');
      }
      setState(() {
        _structuredDataOutput = buf.toString();
      });
      _addMessage('✅ New HRV Data fetched: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'HRV Data (0x56)';
        _structuredDataOutput = 'Error fetching HRV data: $e';
      });
      _addMessage('❌ Failed to fetch HRV data: $e');
    }
  }

  Future<void> _fetchNewSleepData() async {
    try {
      setState(() {
        _structuredDataTitle = 'Sleep Data (0x53)';
        _structuredDataOutput = 'Fetching Sleep data...';
      });
      final records = await _bleService.fetchSleepData(timeout: const Duration(seconds: 4));
      if (!mounted) return;
      if (records.isEmpty) {
        setState(() {
          _structuredDataOutput = 'No Sleep records received within timeout.';
        });
        return;
      }
      final buf = StringBuffer();
      buf.writeln('Count: ${records.length}');
      for (final r in records) {
        buf.writeln('- ${r.toString()}');
      }
      setState(() {
        _structuredDataOutput = buf.toString();
      });
      _addMessage('✅ New Sleep Data fetched: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Sleep Data (0x53)';
        _structuredDataOutput = 'Error fetching Sleep data: $e';
      });
      _addMessage('❌ Failed to fetch Sleep data: $e');
    }
  }

  Future<void> _performBulkDownload() async {
    try {
      setState(() {
        _structuredDataTitle = '📦 Bulk Download - All Data';
        _structuredDataOutput = 'Initializing bulk download...';
      });
      _addMessage('🚀 Starting bulk download of ALL data...');
      
      // StringBuffer to accumulate progress messages
      final progressLog = StringBuffer();
      progressLog.writeln('📦 BULK DOWNLOAD PROGRESS');
      progressLog.writeln('=' * 50);
      
      final result = await _bleService.bulkDownloadAllData(
        onProgress: (String message) {
          // Update progress in real-time
          progressLog.writeln(message);
          if (mounted) {
            setState(() {
              _structuredDataOutput = progressLog.toString();
            });
          }
        },
      );
      
      if (!mounted) return;
      
      // Display summary in structured data area
      setState(() {
        _structuredDataTitle = '🎉 Bulk Download Complete';
        _structuredDataOutput = result['summary'] as String;
      });
      
      // Show detailed package contents in messages
      _addMessage('\n' + ('=' * 60));
      _addMessage('📦 BULK DOWNLOAD PACKAGE CONTENTS');
      _addMessage('=' * 60);
      _addMessage('Timestamp: ${result['timestamp']}');
      _addMessage('Total Records: ${result['total_records']}');
      _addMessage('');
      
      final commands = result['commands'] as Map<String, dynamic>;
      
      // Display each command's data with actual records
      if (commands.containsKey('total_steps')) {
        final data = commands['total_steps'];
        _addMessage('\n👣 TOTAL STEPS (${data['count']} records):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['date']}: ${r['steps']} steps, ${r['exercise_time']}s exercise, ${r['calories']} kcal, ${r['distance']} km');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('detailed_steps')) {
        final data = commands['detailed_steps'];
        _addMessage('\n📊 DETAILED STEPS (${data['count']} 10-min segments):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['timestamp']}: ${r['steps']} steps, ${r['calories']} kcal, ${r['distance']} km');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('sleep')) {
        final data = commands['sleep'];
        _addMessage('\n😴 SLEEP DATA (${data['count']} sessions):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['timestamp']}: ${r['duration_minutes']}min (Deep:${r['deep']} Light:${r['light']} REM:${r['rem']} Awake:${r['awake']})');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('heart_rate_details')) {
        final data = commands['heart_rate_details'];
        _addMessage('\n❤️ HEART RATE DETAILS (${data['count']} measurements):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          final rates = (r['heart_rates'] as List).join(', ');
          _addMessage('  ${r['timestamp']}: [${rates}] BPM');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('heart_rate_history')) {
        final data = commands['heart_rate_history'];
        _addMessage('\n💓 HEART RATE HISTORY (${data['count']} single measurements):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['timestamp']}: ${r['heart_rate']} BPM');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('hrv')) {
        final data = commands['hrv'];
        _addMessage('\n📈 HRV DATA (${data['count']} records):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['timestamp']}: HRV=${r['hrv_ms']}ms HR=${r['heart_rate']} Fatigue=${r['fatigue']} BP=${r['bp']}');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('temperature')) {
        final data = commands['temperature'];
        _addMessage('\n🌡️ TEMPERATURE (${data['count']} readings):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          final temps = (r['temperatures'] as List).map((t) => '${t}°C').join(', ');
          _addMessage('  ${r['timestamp']}: [${temps}]');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      if (commands.containsKey('blood_oxygen')) {
        final data = commands['blood_oxygen'];
        _addMessage('\n🩸 BLOOD OXYGEN (${data['count']} SpO2 readings):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['timestamp']}: ${r['spo2']}%');
        }
        if (records.length > 10) _addMessage('  ... and ${records.length - 10} more records');
      }
      
      _addMessage('\n' + ('=' * 60));
      _addMessage('✅ Bulk download completed successfully!');
      _addMessage('Total of ${result['total_records']} records downloaded and parsed.');
      _addMessage('\nShowing first 10 records of each type. Full data available in result object.');
      
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = '❌ Bulk Download Error';
        _structuredDataOutput = 'Failed to complete bulk download: $e';
      });
      _addMessage('❌ Bulk download failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Target Device Settings
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Target Device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _deviceNameController,
                            decoration: const InputDecoration(
                              labelText: 'Device Name (exact match, optional)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _macAddressController,
                            decoration: const InputDecoration(
                              labelText: 'MAC Address (optional, e.g. F8:19:23:14:5C:C8)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _applyTarget,
                          child: const Text('Apply Target'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Connection Status
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _connectionStatus == 'Connected' 
                          ? Icons.bluetooth_connected 
                          : Icons.bluetooth_disabled,
                      color: _connectionStatus == 'Connected' 
                          ? Colors.green 
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Status: $_connectionStatus'),
                    ),
                    // Smart Connection Button
                    IconButton(
                      onPressed: _connectionStatus == 'Connected' 
                          ? _disconnectFromSmartRing 
                          : _connectToSmartRing,
                      icon: Icon(
                        _connectionStatus == 'Connected' 
                            ? Icons.bluetooth_disabled 
                            : Icons.bluetooth_searching,
                        color: _connectionStatus == 'Connected' 
                            ? Colors.red 
                            : Colors.blue,
                      ),
                      tooltip: _connectionStatus == 'Connected' 
                          ? 'Disconnect' 
                          : 'Connect',
                    ),
                  ],
                ),
              ),
            ),

            // General Structured Data Output (main page)
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('General Data Display', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: _structuredDataOutput.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(text: _structuredDataOutput));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Structured data copied to clipboard')),
                                  );
                                },
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    if (_structuredDataTitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _structuredDataTitle,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _structuredDataOutput.isEmpty
                              ? 'No structured data yet. Use "New HRV Data" or "New Sleep Data" after connecting.'
                              : _structuredDataOutput,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Quick Actions
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    // Bulk Download Button (prominent)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _connectionStatus == 'Connected' ? _performBulkDownload : null,
                        icon: const Icon(Icons.download, size: 24),
                        label: const Text('📦 BULK DOWNLOAD ALL DATA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Original Commands
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetHrvDataCommand : null,
                          icon: const Icon(Icons.favorite, size: 16),
                          label: const Text('HRV Data (0x56)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetTimeCommand : null,
                          icon: const Icon(Icons.access_time, size: 16),
                          label: const Text('Time (0x41)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetBatteryCommand : null,
                          icon: const Icon(Icons.battery_std, size: 16),
                          label: const Text('Battery (0x13)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetMacAddressCommand : null,
                          icon: const Icon(Icons.wifi, size: 16),
                          label: const Text('MAC (0x22)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _fetchNewHrvData : null,
                          icon: const Icon(Icons.favorite_border, size: 16),
                          label: const Text('New HRV Data'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _fetchNewSleepData : null,
                          icon: const Icon(Icons.bedtime_off, size: 16),
                          label: const Text('New Sleep Data'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetFirmwareVersionCommand : null,
                          icon: const Icon(Icons.info, size: 16),
                          label: const Text('Firmware (0x27)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade100),
                        ),
                        // New Health Commands
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _promptAndSendGetMeasurementInterval : null,
                          icon: const Icon(Icons.schedule, size: 16),
                          label: const Text('Intervals (0x2B)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _showSetMeasurementIntervalDialog : null,
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('Set Interval (0x2A)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade200),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetExerciseDataCommand : null,
                          icon: const Icon(Icons.fitness_center, size: 16),
                          label: const Text('Exercise Status (0x19)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetUserInfoCommand : null,
                          icon: const Icon(Icons.person, size: 16),
                          label: const Text('User Info (0x42)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _showSetUserInfoDialog : null,
                          icon: const Icon(Icons.person_add, size: 16),
                          label: const Text('Set User Info (0x02)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetExerciseModeDataLatest : null,
                          icon: const Icon(Icons.directions_run, size: 16),
                          label: const Text('Exercise Latest (0x5C)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade200),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetExerciseModeDataContinue : null,
                          icon: const Icon(Icons.navigate_next, size: 16),
                          label: const Text('Exercise Continue (0x5C)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendDeleteExerciseModeDetails : null,
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('Exercise Delete (0x5C)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _toggleExerciseMode : null,
                          icon: Icon(_isExerciseActive ? Icons.stop : Icons.play_arrow, size: 16),
                          label: Text(_isExerciseActive ? 'End Exercise (0x19)' : 'Start Exercise (0x19)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isExerciseActive ? Colors.red.shade100 : Colors.green.shade100,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _toggleRealtimeMode : null,
                          icon: Icon(_isRealtimeActive ? Icons.stop_circle : Icons.play_circle, size: 16),
                          label: Text(_isRealtimeActive ? 'Stop Realtime (0x09)' : 'Start Realtime (0x09)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRealtimeActive ? Colors.red.shade100 : Colors.lightGreen.shade100,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _toggleHrMeasurement : null,
                          icon: Icon(_isHrMeasureActive ? Icons.stop : Icons.favorite, size: 16),
                          label: Text(_isHrMeasureActive ? 'Stop HR Measure (0x28)' : 'Start HR Measure (0x28)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isHrMeasureActive ? Colors.red.shade100 : Colors.purple.shade50,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetTotalStepCountCommand : null,
                          icon: const Icon(Icons.directions_walk, size: 16),
                          label: const Text('Steps (0x51)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetDetailedStepCountCommand : null,
                          icon: const Icon(Icons.bar_chart, size: 16),
                          label: const Text('Step Details (0x52)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.lime.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetSleepDataCommand : null,
                          icon: const Icon(Icons.bedtime, size: 16),
                          label: const Text('Sleep (0x53)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetDetailedHeartRateCommand : null,
                          icon: const Icon(Icons.monitor_heart, size: 16),
                          label: const Text('HR Detail (0x54)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetHeartRateHistoryCommand : null,
                          icon: const Icon(Icons.history, size: 16),
                          label: const Text('HR History (0x55)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetTemperatureDataCommand : null,
                          icon: const Icon(Icons.thermostat, size: 16),
                          label: const Text('Temperature (0x62)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetRingTemperatureCommand : null,
                          icon: const Icon(Icons.device_thermostat, size: 16),
                          label: const Text('Ring Temp (0x14)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade200),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected' ? _sendGetBloodOxygenDataCommand : null,
                          icon: const Icon(Icons.air, size: 16),
                          label: const Text('Blood O2 (0x66)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue.shade100),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Message Input
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Enter hex message (e.g., 56-01-00-00...)',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _connectionStatus == 'Connected' ? _sendMessage : null,
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ),
            ),
            
            // Messages
            Container(
              height: 500,
              margin: const EdgeInsets.all(16),
              child: Card(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.message),
                          const SizedBox(width: 8),
                          Text('Messages (${_messages.length})'),
                          const Spacer(),
                          if (_messages.isNotEmpty)
                            IconButton(
                              onPressed: () => setState(() => _messages.clear()),
                              icon: const Icon(Icons.clear),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(child: Text('No messages yet'))
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final isReceived = message.contains('Received:');
                                return Container(
                                  margin: const EdgeInsets.all(4),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isReceived ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: GestureDetector(
                                    onLongPress: () {
                                      // Copy message to clipboard
                                      Clipboard.setData(ClipboardData(text: message));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Message copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      message,
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isNotEmpty) {
      _addMessage('Sent: $message');
      await _bleService.sendMessage(message);
      _messageController.clear();
    }
  }

  Future<void> _sendCommand(String command) async {
    _addMessage('Sending: $command');
    await _bleService.sendMessage(command);
  }

  // Smart Ring Command Methods
  Future<void> _sendGetHrvDataCommand() async {
    try {
      await _bleService.sendHrvCommand();
      _addMessage('✅ HRV Data command sent. sendHrvCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send HRV Data command: $e. sendHrvCommand()');
    }
  }

  Future<void> _sendGetTimeCommand() async {
    try {
      await _bleService.sendGetTimeCommand();
      _addMessage('✅ Get Time command sent. sendGetTimeCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Time command: $e. sendGetTimeCommand()');
    }
  }

  Future<void> _sendGetBatteryCommand() async {
    try {
      await _bleService.sendGetBatteryCommand();
      _addMessage('✅ Get Battery command sent. sendGetBatteryCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Battery command: $e. sendGetBatteryCommand()');
    }
  }

  Future<void> _sendGetMacAddressCommand() async {
    try {
      await _bleService.sendGetMacAddressCommand();
      _addMessage('✅ Get MAC Address command sent. sendGetMacAddressCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get MAC Address command: $e. sendGetMacAddressCommand()');
    }
  }

  Future<void> _sendGetFirmwareVersionCommand() async {
    try {
      await _bleService.sendGetFirmwareVersionCommand();
      _addMessage('✅ Get Firmware Version command sent. sendGetFirmwareVersionCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Firmware Version command: $e. sendGetFirmwareVersionCommand()');
    }
  }

  Future<void> _promptAndSendGetMeasurementInterval() async {
    int selType = 1;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Get Measurement Interval (0x2B)'),
              content: DropdownButtonFormField<int>(
                value: selType,
                decoration: const InputDecoration(labelText: 'Measurement Type'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Heart Rate')),
                  DropdownMenuItem(value: 2, child: Text('Blood Oxygen')),
                  DropdownMenuItem(value: 4, child: Text('HRV')),
                ],
                onChanged: (v) => setStateDialog(() => selType = v ?? 1),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _bleService.sendGetMeasurementIntervalCommand(selType);
                      if (mounted) Navigator.of(ctx).pop();
                      _addMessage('✅ Get Measurement Interval (0x2B) sent for type=$selType');
                    } catch (e) {
                      _addMessage('❌ Failed to send 0x2B: $e');
                    }
                  },
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSetMeasurementIntervalDialog() async {
    final typeOptions = const [
      {'label': 'Heart Rate', 'value': 1},
      {'label': 'Blood Oxygen', 'value': 2},
      {'label': 'HRV', 'value': 4},
    ];
    final modeOptions = const [
      {'label': 'Off', 'value': 0},
      {'label': 'Interval Mode', 'value': 2},
    ];
    int selType = 1;
    int selMode = 2;
    final startHourCtl = TextEditingController(text: '08');
    final startMinCtl = TextEditingController(text: '00');
    final endHourCtl = TextEditingController(text: '22');
    final endMinCtl = TextEditingController(text: '00');
    final intervalCtl = TextEditingController(text: '10');
    List<bool> weekdaySel = List<bool>.filled(7, true); // Sun..Sat

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Set Measurement Interval (0x2A)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selType,
                      decoration: const InputDecoration(labelText: 'Measurement Type'),
                      items: typeOptions
                          .map((m) => DropdownMenuItem<int>(value: m['value'] as int, child: Text(m['label'] as String)))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => selType = v ?? 1),
                    ),
                    DropdownButtonFormField<int>(
                      value: selMode,
                      decoration: const InputDecoration(labelText: 'Mode'),
                      items: modeOptions
                          .map((m) => DropdownMenuItem<int>(value: m['value'] as int, child: Text(m['label'] as String)))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => selMode = v ?? 0),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: startHourCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Start HH'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: startMinCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Start mm'))),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: endHourCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'End HH'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: endMinCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'End mm'))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Weekdays'),
                    Wrap(
                      spacing: 4,
                      children: List.generate(7, (i) {
                        const names = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
                        return FilterChip(
                          label: Text(names[i]),
                          selected: weekdaySel[i],
                          onSelected: (v) => setStateDialog(() => weekdaySel[i] = v),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: intervalCtl,
                      keyboardType: TextInputType.number,
                      readOnly: selMode != 2,
                      decoration: InputDecoration(
                        labelText: 'Interval (minutes)',
                        helperText: selMode != 2 ? 'Enable Interval Mode to edit' : null,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      int sh = int.tryParse(startHourCtl.text.trim()) ?? 0;
                      int sm = int.tryParse(startMinCtl.text.trim()) ?? 0;
                      int eh = int.tryParse(endHourCtl.text.trim()) ?? 0;
                      int em = int.tryParse(endMinCtl.text.trim()) ?? 0;
                      int interval = int.tryParse(intervalCtl.text.trim()) ?? 0;
                      if (selMode != 2) throw 'Mode must be Interval Mode to set interval';
                      if (sh < 0 || sh > 23) throw 'Start hour 0-23';
                      if (sm < 0 || sm > 59) throw 'Start minute 0-59';
                      if (eh < 0 || eh > 23) throw 'End hour 0-23';
                      if (em < 0 || em > 59) throw 'End minute 0-59';
                      if (interval <= 0 || interval > 1440) throw 'Interval 1-1440 minutes';

                      // weekday bits: bit0=Sun .. bit6=Sat
                      int wbits = 0;
                      for (int i = 0; i < 7; i++) {
                        if (weekdaySel[i]) wbits |= (1 << i);
                      }

                      await _bleService.sendSetMeasurementIntervalCommand(
                        measurementType: selType,
                        workingMode: selMode,
                        startHour: sh,
                        startMinute: sm,
                        endHour: eh,
                        endMinute: em,
                        weekdayBits: wbits,
                        intervalMinutes: interval,
                      );
                      if (mounted) {
                        Navigator.of(ctx).pop();
                        _addMessage('✅ Set Measurement Interval (0x2A) command sent.');
                        await _bleService.sendGetMeasurementIntervalCommand(selType);
                      }
                    } catch (e) {
                      _addMessage('❌ Failed to set interval: $e');
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _sendGetExerciseDataCommand() async {
    try {
      await _bleService.sendGetExerciseDataCommand();
      _addMessage('✅ Get Exercise Status command sent. sendGetExerciseDataCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Exercise Status command: $e. sendGetExerciseDataCommand()');
    }
  }

  Future<void> _toggleExerciseMode() async {
    try {
      if (_isExerciseActive) {
        await _bleService.sendEndExerciseCommand();
        _addMessage('✅ End Exercise command sent. _toggleExerciseMode()');
        // Optimistically update UI, then verify with a status poll shortly after
        setState(() => _isExerciseActive = false);
        Future.delayed(const Duration(milliseconds: 700), () async {
          try {
            await _bleService.sendGetExerciseDataCommand();
          } catch (_) {}
        });
      } else {
        await _bleService.sendStartExerciseCommand();
        _addMessage('✅ Start Exercise command sent. _toggleExerciseMode()');
        // Optimistically update UI, then verify with a status poll shortly after
        setState(() => _isExerciseActive = true);
        Future.delayed(const Duration(milliseconds: 700), () async {
          try {
            await _bleService.sendGetExerciseDataCommand();
          } catch (_) {}
        });
      }
    } catch (e) {
      _addMessage('❌ Failed to toggle exercise mode: $e. _toggleExerciseMode()');
    }
  }

  Future<void> _toggleRealtimeMode() async {
    try {
      if (_isRealtimeActive) {
        await _bleService.sendStopRealtimeMode();
        _addMessage('✅ Stop Realtime command sent. _toggleRealtimeMode()');
        // Ignore trailing 0x09 frames for 1.5s so UI doesn't flip back to active
        _ignoreRealtimeUntilMs = DateTime.now().millisecondsSinceEpoch + 1500;
        setState(() => _isRealtimeActive = false);
      } else {
        await _bleService.sendStartRealtimeMode(enableTemperature: true);
        _addMessage('✅ Start Realtime command sent. _toggleRealtimeMode()');
        // Optimistically set to true; will remain true when first 0x09 packet arrives
        setState(() {
          _isRealtimeActive = true;
          _ignoreRealtimeUntilMs = 0; // clear guard on start
        });
      }
    } catch (e) {
      _addMessage('❌ Failed to toggle realtime mode: $e. _toggleRealtimeMode()');
    }
  }

  Future<void> _sendGetTotalStepCountCommand() async {
    try {
      await _bleService.sendGetTotalStepCountCommand();
      _addMessage('✅ Get Total Step Count command sent. sendGetTotalStepCountCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Total Step Count command: $e. sendGetTotalStepCountCommand()');
    }
  }

  Future<void> _sendGetDetailedStepCountCommand() async {
    try {
      await _bleService.sendGetDetailedStepCountCommand();
      _addMessage('✅ Get Detailed Step Count command sent. sendGetDetailedStepCountCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Detailed Step Count command: $e. sendGetDetailedStepCountCommand()');
    }
  }

  Future<void> _sendGetSleepDataCommand() async {
    try {
      await _bleService.sendGetSleepDataCommand();
      _addMessage('✅ Get Sleep Data command sent. sendGetSleepDataCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Sleep Data command: $e. sendGetSleepDataCommand()');
    }
  }

  Future<void> _sendGetDetailedHeartRateCommand() async {
    try {
      await _bleService.sendGetDetailedHeartRateCommand();
      _addMessage('✅ Get Detailed Heart Rate command sent. sendGetDetailedHeartRateCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Detailed Heart Rate command: $e. sendGetDetailedHeartRateCommand()');
    }
  }

  Future<void> _sendGetHeartRateHistoryCommand() async {
    try {
      await _bleService.sendGetHeartRateHistoryCommand();
      _addMessage('✅ Get Heart Rate History command sent. sendGetHeartRateHistoryCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Heart Rate History command: $e. sendGetHeartRateHistoryCommand()');
    }
  }

  Future<void> _sendGetTemperatureDataCommand() async {
    try {
      await _bleService.sendGetTemperatureDataCommand();
      _addMessage('✅ Get Temperature Data command sent. sendGetTemperatureDataCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Temperature Data command: $e. sendGetTemperatureDataCommand()');
    }
  }

  Future<void> _sendGetRingTemperatureCommand() async {
    try {
      await _bleService.sendGetRingTemperatureCommand();
      _addMessage('✅ Get Ring Temperature (0x14) command sent. sendGetRingTemperatureCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Ring Temperature (0x14): $e. sendGetRingTemperatureCommand()');
    }
  }

  Future<void> _sendGetBloodOxygenDataCommand() async {
    try {
      await _bleService.sendGetBloodOxygenDataCommand();
      _addMessage('✅ Get Blood Oxygen Data command sent. sendGetBloodOxygenDataCommand()');
    } catch (e) {
      _addMessage('❌ Failed to send Get Blood Oxygen Data command: $e. sendGetBloodOxygenDataCommand()');
    }
  }

  // Connection Control Methods
  Future<void> _connectToSmartRing() async {
    try {
      _addMessage('🔍 Searching for Smart Ring...');
      await _bleService.startScan();
      _addMessage('✅ Scan started. connectToSmartRing()');
    } catch (e) {
      _addMessage('❌ Failed to start scan: $e. connectToSmartRing()');
    }
  }

  Future<void> _disconnectFromSmartRing() async {
    try {
      _addMessage('🔌 Disconnecting from Smart Ring...');
      await _bleService.disconnect();
      _addMessage('✅ Disconnected from Smart Ring. disconnectFromSmartRing()');
    } catch (e) {
      _addMessage('❌ Failed to disconnect: $e. disconnectFromSmartRing()');
    }
  }
}
