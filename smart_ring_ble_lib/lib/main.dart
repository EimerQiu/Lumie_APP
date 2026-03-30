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
  String _selectedDeviceName = 'X6B 27279';
  static const List<String> _deviceNameOptions = ['X6B 27279', 'X6B 05997', 'X6B 45CC8'];

  String _connectionStatus = 'Disconnected';
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isExerciseActive = false;
  bool _isRealtimeActive = false; // 0x09 real-time stream state
  bool _isHrMeasureActive = false; // 0x28 HR measurement state
  int _ignoreRealtimeUntilMs =
      0; // guard window after Stop to ignore trailing 0x09 packets
  List<String> _messages = [];
  String _structuredDataTitle = '';
  String _structuredDataOutput = '';

  @override
  void initState() {
    super.initState();
    // Prefill target fields from BleService defaults/current target
    final name = _bleService.targetDeviceName;
    final mac = _bleService.targetMacAddress;
    if (name != null && name.isNotEmpty && _deviceNameOptions.contains(name)) {
      _selectedDeviceName = name;
    }
    _deviceNameController.text = _selectedDeviceName;
    if (mac != null && mac.isNotEmpty) {
      _macAddressController.text = mac;
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
      if (status == 'Connected') {
        Future.delayed(const Duration(milliseconds: 300), () {
          _bleService.sendSetCurrentTimeCommand();
        });
      }
    });

    _bleService.messageStream.listen((message) {
      _addMessage('Received: $message');
      _updateExerciseStateFromMessage(message);
      _updateRealtimeStateFromMessage(message);
      // Optionally update 0x28 HR measurement state when we add parser support
    });
    _addMessage('BLE initialized. Tap Connect to scan for Smart Ring.');
  }

  Future<void> _showSetUserInfoDialog() async {
    // Fetch current user info from ring first
    final currentInfo = await _bleService.fetchUserInfo(timeout: const Duration(seconds: 2));

    final genderOptions = ['Female', 'Male'];
    String selectedGender = currentInfo != null
        ? (currentInfo['gender'] == 0 ? 'Female' : 'Male')
        : 'Female';
    final ageController = TextEditingController(
        text: currentInfo?['age']?.toString() ?? '30');
    final heightController = TextEditingController(
        text: currentInfo?['height_cm']?.toString() ?? '170');
    final weightController = TextEditingController(
        text: currentInfo?['weight_kg']?.toString() ?? '65');
    final stepLenController = TextEditingController(
        text: currentInfo?['step_len_cm']?.toString() ?? '60');
    final ringIdController = TextEditingController(
        text: currentInfo?['ring_id']?.toString() ?? '000000');

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
                          .map((g) => DropdownMenuItem<String>(
                              value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setStateDialog(() => selectedGender = v);
                      },
                    ),
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Age (years, 0-120)'),
                    ),
                    TextField(
                      controller: heightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Height (cm, 50-250)'),
                    ),
                    TextField(
                      controller: weightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Weight (kg, 10-300)'),
                    ),
                    TextField(
                      controller: stepLenController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Step Length (cm, 20-120)'),
                    ),
                    TextField(
                      controller: ringIdController,
                      decoration: const InputDecoration(
                          labelText: 'Ring ID (ASCII up to 6 chars)'),
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
                      int height =
                          int.tryParse(heightController.text.trim()) ?? 0;
                      int weight =
                          int.tryParse(weightController.text.trim()) ?? 0;
                      int stepLen =
                          int.tryParse(stepLenController.text.trim()) ?? 0;
                      String ringId = ringIdController.text.trim();

                      // Basic validation ranges
                      if (age < 0 || age > 120) throw 'Age must be 0-120';
                      if (height < 50 || height > 250)
                        throw 'Height must be 50-250 cm';
                      if (weight < 10 || weight > 300)
                        throw 'Weight must be 10-300 kg';
                      if (stepLen < 20 || stepLen > 120)
                        throw 'Step length must be 20-120 cm';
                      if (ringId.isEmpty) ringId = '000000';

                      setState(() {
                        _structuredDataTitle = 'Set User Info (0x02)';
                        _structuredDataOutput = '⏳ Sending SET command...';
                      });

                      int messagesCountBefore = _messages.length;
                      final sentCmd = await _bleService.sendSetUserInfoCommand(
                        gender: gender,
                        age: age,
                        heightCm: height,
                        weightKg: weight,
                        stepLengthCm: stepLen,
                        ringId: ringId,
                      );

                      if (mounted) {
                        Navigator.of(ctx).pop();

                        // Get the ACK response
                        String receivedMsg = 'No response received';
                        if (_messages.length > messagesCountBefore) {
                          final lastMsg = _messages.last;
                          if (lastMsg.contains('Received:')) {
                            receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
                          }
                        }

                        final buf = StringBuffer();
                        buf.writeln('📤 SENT:\n$sentCmd\n');
                        buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
                        buf.writeln('📊 PARSED DATA:');
                        buf.writeln('✅ SET User Info (0x02) ACK');
                        buf.writeln('👤 Gender: ${selectedGender}');
                        buf.writeln('🎂 Age: $age years');
                        buf.writeln('📏 Height: $height cm');
                        buf.writeln('⚖️ Weight: $weight kg');
                        buf.writeln('👣 Step Length: $stepLen cm');
                        buf.writeln('🆔 Ring ID: $ringId');

                        setState(() { _structuredDataOutput = buf.toString(); });
                        _addMessage(
                            '✅ Set User Info (0x02) command sent.');

                        // Auto-fetch to verify
                        await Future.delayed(const Duration(milliseconds: 500));
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
      const sentCmd = '42-00-00-00-00-00-00-00-00-00-00-00-00-00-00-42';
      setState(() {
        _structuredDataTitle = 'User Info (0x42)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final result = await _bleService.fetchUserInfo(timeout: const Duration(seconds: 2));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (result == null) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0xC2)'; });
        _addMessage('❌ User info fetch failed or timed out.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('👤 Gender: ${result['gender_name']} (${result['gender']})');
      buf.writeln('🎂 Age: ${result['age']}');
      buf.writeln('📏 Height: ${result['height_cm']} cm');
      buf.writeln('⚖️ Weight: ${result['weight_kg']} kg');
      buf.writeln('👣 Step Length: ${result['step_len_cm']} cm');
      buf.writeln('💍 Ring ID: ${result['ring_id']}');
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ User Info: ${result['gender_name']}, age ${result['age']}, ${result['height_cm']}cm/${result['weight_kg']}kg');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'User Info (0x42)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch user info: $e');
    }
  }

  Future<void> _sendGetExerciseModeDataLatest() async {
    try {
      const sentCmd = '5C-00-00-00-00-00-00-00-00-00-00-00-00-00-00-5C';
      setState(() {
        _structuredDataTitle = 'Exercise Latest (0x5C)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchExerciseLatest(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No exercise records received'; });
        _addMessage('❌ No exercise data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🏃 ${records.length} exercise record(s):');
      buf.writeln('');
      for (final r in records) {
        buf.writeln('${r['timestamp']}: ${r['exercise_type_name']} - HR:${r['heart_rate']}bpm, ${r['duration_seconds']}s, ${r['steps']} steps, ${(r['distance'] as double).toStringAsFixed(2)}km, ${(r['calories'] as double).toStringAsFixed(1)}kcal');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Exercise Latest: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Exercise Latest (0x5C)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch exercise latest: $e');
    }
  }

  Future<void> _sendGetExerciseModeDataContinue() async {
    try {
      const sentCmd = '5C-02-00-00-00-00-00-00-00-00-00-00-00-00-00-5E';
      setState(() {
        _structuredDataTitle = 'Exercise Continue (0x5C)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchExerciseContinue(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No more exercise records'; });
        _addMessage('❌ No more exercise data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🏃 ${records.length} exercise record(s):');
      buf.writeln('');
      for (final r in records) {
        buf.writeln('${r['timestamp']}: ${r['exercise_type_name']} - HR:${r['heart_rate']}bpm, ${r['duration_seconds']}s, ${r['steps']} steps, ${(r['distance'] as double).toStringAsFixed(2)}km, ${(r['calories'] as double).toStringAsFixed(1)}kcal');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Exercise Continue: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Exercise Continue (0x5C)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch exercise continue: $e');
    }
  }

  Future<void> _sendDeleteExerciseModeDetails() async {
    try {
      const sentCmd = '5C-99-00-00-00-00-00-00-00-00-00-00-00-00-00-F5';
      setState(() {
        _structuredDataTitle = 'Exercise Delete (0x5C)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final success = await _bleService.deleteExerciseHistory(timeout: const Duration(seconds: 2));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      if (success) {
        buf.writeln('✅ Exercise history deleted successfully.');
      } else {
        buf.writeln('❌ Delete failed or no confirmation received.');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage(success ? '✅ Exercise history deleted.' : '❌ Exercise delete failed.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Exercise Delete (0x5C)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to delete exercise history: $e');
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

  /// Get the last received message from the message log
  String _getLastReceivedMessage() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].contains('Received:')) {
        return _messages[i].replaceFirst('Received: ', '').trim();
      }
    }
    return 'No response received';
  }

  /// Format command display with sent → received → parsed data
  String _formatCommandDisplay(String sentCmd, String receivedMsg, String parsedData) {
    return '📤 SENT:\n$sentCmd\n\n📥 RECEIVED:\n$receivedMsg\n\n📊 PARSED DATA:\n$parsedData';
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
      // Append incoming exercise data to structured data panel if exercise mode is active
      if (_isExerciseActive) {
        setState(() {
          // Extract just the exercise data lines (skip the header "🏃 Live Exercise Data:")
          final dataLines = message.split('\n').skip(1).join('\n');
          _structuredDataOutput = '📤 SENT:\n19-01-00-00-00-00-00-00-00-00-00-00-00-00-00-1A\n\n📊 Status: 🏃 ACTIVE - Receiving exercise data...\n\n📥 LATEST DATA:\n$dataLines';
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
      // Append incoming realtime data to structured data panel if realtime mode is active
      if (_isRealtimeActive) {
        setState(() {
          // Extract just the realtime data lines (skip the header "📡 Real-time Mode:")
          final dataLines = message.split('\n').skip(1).join('\n');
          _structuredDataOutput = '📤 SENT:\n09-01-01-00-00-00-00-00-00-00-00-00-00-00-00-0B\n\n📊 Status: 📡 ACTIVE - Receiving sensor data...\n\n📥 LATEST DATA:\n$dataLines';
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
    _addMessage(
        '🎯 Target updated to: ${name.isEmpty ? '-' : name} / ${mac.isEmpty ? '-' : mac}');
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
        // STOP HR MEASUREMENT
        const sentCmd = '28-02-00-00-00-00-00-00-00-00-00-00-00-00-00-2A';
        setState(() {
          _structuredDataTitle = 'HR Measurement (0x28)';
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: STOPPING...';
        });
        await _bleService.sendStopMultiParamMeasurement(mode: 0x02);
        setState(() => _isHrMeasureActive = false);
        setState(() {
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: ✅ STOPPED';
        });
      } else {
        // START HR MEASUREMENT
        const sentCmd = '28-02-01-00-00-1E-00-00-00-00-00-00-00-00-00-31';
        setState(() {
          _structuredDataTitle = '❤️ HR Measurement (0x28)';
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: ❤️ RUNNING...\n\n⏳ Measuring for 30 seconds...';
        });
        await _bleService.sendStartMultiParamMeasurement(
            mode: 0x02, durationSeconds: 30);
        setState(() => _isHrMeasureActive = true);
        setState(() {
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: ❤️ ACTIVE - Measuring heart rate...';
        });
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
      final records =
          await _bleService.fetchHrvData(timeout: const Duration(seconds: 3));
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
      final records =
          await _bleService.fetchSleepData(timeout: const Duration(seconds: 4));
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
          _addMessage(
              '  ${r['date']}: ${r['steps']} steps, ${r['exercise_time']}s exercise, ${r['calories']} kcal, ${r['distance']} km');
        }
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
      }

      if (commands.containsKey('detailed_steps')) {
        final data = commands['detailed_steps'];
        _addMessage('\n📊 DETAILED STEPS (${data['count']} 10-min segments):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage(
              '  ${r['timestamp']}: ${r['steps']} steps, ${r['calories']} kcal, ${r['distance']} km');
        }
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
      }

      if (commands.containsKey('sleep')) {
        final data = commands['sleep'];
        _addMessage('\n😴 SLEEP DATA (${data['count']} sessions):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage(
              '  ${r['timestamp']}: ${r['duration_minutes']}min (Deep:${r['deep']} Light:${r['light']} REM:${r['rem']} Awake:${r['awake']})');
        }
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
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
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
      }

      if (commands.containsKey('heart_rate_history')) {
        final data = commands['heart_rate_history'];
        _addMessage(
            '\n💓 HEART RATE HISTORY (${data['count']} single measurements):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage('  ${r['timestamp']}: ${r['heart_rate']} BPM');
        }
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
      }

      if (commands.containsKey('hrv')) {
        final data = commands['hrv'];
        _addMessage('\n📈 HRV DATA (${data['count']} records):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          _addMessage(
              '  ${r['timestamp']}: HRV=${r['hrv_ms']}ms HR=${r['heart_rate']} Fatigue=${r['fatigue']} BP=${r['bp']}');
        }
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
      }

      if (commands.containsKey('temperature')) {
        final data = commands['temperature'];
        _addMessage('\n🌡️ TEMPERATURE (${data['count']} readings):');
        _addMessage('-' * 50);
        final records = data['records'] as List;
        for (int i = 0; i < records.length && i < 10; i++) {
          final r = records[i];
          final temps =
              (r['temperatures'] as List).map((t) => '${t}°C').join(', ');
          _addMessage('  ${r['timestamp']}: [${temps}]');
        }
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
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
        if (records.length > 10)
          _addMessage('  ... and ${records.length - 10} more records');
      }

      _addMessage('\n' + ('=' * 60));
      _addMessage('✅ Bulk download completed successfully!');
      _addMessage(
          'Total of ${result['total_records']} records downloaded and parsed.');
      _addMessage(
          '\nShowing first 10 records of each type. Full data available in result object.');
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
                    const Text('Target Device',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedDeviceName,
                                decoration: const InputDecoration(
                                    labelText: 'Preset Device Names'),
                                items: _deviceNameOptions
                                    .map((n) =>
                                        DropdownMenuItem(
                                            value: n, child: Text(n)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _selectedDeviceName = value);
                                    _deviceNameController.text = value;
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _macAddressController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'MAC Address (optional, e.g. F8:19:23:14:5C:C8)',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deviceNameController,
                          decoration: const InputDecoration(
                            labelText: 'Custom Device Name',
                            hintText: 'Or enter custom name here',
                          ),
                          onChanged: (value) {
                            setState(() => _selectedDeviceName = value.isEmpty
                                ? _deviceNameOptions[0]
                                : value);
                          },
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
                          ? Colors.blue
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
                        const Text('General Data Display',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: _structuredDataOutput.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(
                                      text: _structuredDataOutput));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Structured data copied to clipboard')),
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
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      height: MediaQuery.of(context).size.height * 0.4,
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
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
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
                    const Text('Quick Actions',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    // Bulk Download Button (prominent)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _connectionStatus == 'Connected'
                            ? _performBulkDownload
                            : null,
                        icon: const Icon(Icons.download, size: 24),
                        label: const Text('📦 BULK DOWNLOAD ALL DATA',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
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
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetTimeCommand
                              : null,
                          icon: const Icon(Icons.access_time, size: 16),
                          label: const Text('Time (0x41)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendSetCurrentTimeCommand
                              : null,
                          icon: const Icon(Icons.watch_later, size: 16),
                          label: const Text('Sync Time (0x01)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lightBlue.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetBatteryCommand
                              : null,
                          icon: const Icon(Icons.battery_std, size: 16),
                          label: const Text('Battery (0x13)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetMacAddressCommand
                              : null,
                          icon: const Icon(Icons.wifi, size: 16),
                          label: const Text('MAC (0x22)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _fetchNewHrvData
                              : null,
                          icon: const Icon(Icons.favorite_border, size: 16),
                          label: const Text('New HRV Data'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _fetchNewSleepData
                              : null,
                          icon: const Icon(Icons.bedtime_off, size: 16),
                          label: const Text('New Sleep Data'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetFirmwareVersionCommand
                              : null,
                          icon: const Icon(Icons.info, size: 16),
                          label: const Text('Firmware (0x27)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade100),
                        ),
                        // New Health Commands
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _promptAndSendGetMeasurementInterval
                              : null,
                          icon: const Icon(Icons.schedule, size: 16),
                          label: const Text('Intervals (0x2B)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _showSetMeasurementIntervalDialog
                              : null,
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('Set Interval (0x2A)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade200),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetExerciseDataCommand
                              : null,
                          icon: const Icon(Icons.fitness_center, size: 16),
                          label: const Text('Exercise Status (0x19)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetUserInfoCommand
                              : null,
                          icon: const Icon(Icons.person, size: 16),
                          label: const Text('User Info (0x42)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _showSetUserInfoDialog
                              : null,
                          icon: const Icon(Icons.person_add, size: 16),
                          label: const Text('Set User Info (0x02)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetExerciseModeDataLatest
                              : null,
                          icon: const Icon(Icons.directions_run, size: 16),
                          label: const Text('Exercise Latest (0x5C)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade200),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetExerciseModeDataContinue
                              : null,
                          icon: const Icon(Icons.navigate_next, size: 16),
                          label: const Text('Exercise Continue (0x5C)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendDeleteExerciseModeDetails
                              : null,
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('Exercise Delete (0x5C)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade50),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _toggleExerciseMode
                              : null,
                          icon: Icon(
                              _isExerciseActive ? Icons.stop : Icons.play_arrow,
                              size: 16),
                          label: Text(_isExerciseActive
                              ? 'End Exercise (0x19)'
                              : 'Start Exercise (0x19)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isExerciseActive
                                ? Colors.red.shade100
                                : Colors.green.shade100,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _toggleRealtimeMode
                              : null,
                          icon: Icon(
                              _isRealtimeActive
                                  ? Icons.stop_circle
                                  : Icons.play_circle,
                              size: 16),
                          label: Text(_isRealtimeActive
                              ? 'Stop Realtime (0x09)'
                              : 'Start Realtime (0x09)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRealtimeActive
                                ? Colors.red.shade100
                                : Colors.lightGreen.shade100,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _toggleHrMeasurement
                              : null,
                          icon: Icon(
                              _isHrMeasureActive ? Icons.stop : Icons.favorite,
                              size: 16),
                          label: Text(_isHrMeasureActive
                              ? 'Stop HR Measure (0x28)'
                              : 'Start HR Measure (0x28)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isHrMeasureActive
                                ? Colors.red.shade100
                                : Colors.purple.shade50,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetTotalStepCountCommand
                              : null,
                          icon: const Icon(Icons.directions_walk, size: 16),
                          label: const Text('Steps (0x51)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetDetailedStepCountCommand
                              : null,
                          icon: const Icon(Icons.bar_chart, size: 16),
                          label: const Text('Step Details (0x52)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lime.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetDetailedHeartRateCommand
                              : null,
                          icon: const Icon(Icons.monitor_heart, size: 16),
                          label: const Text('HR Detail (0x54)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pink.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetHeartRateHistoryCommand
                              : null,
                          icon: const Icon(Icons.history, size: 16),
                          label: const Text('HR History (0x55)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetTemperatureDataCommand
                              : null,
                          icon: const Icon(Icons.thermostat, size: 16),
                          label: const Text('Temperature (0x62)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange.shade100),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetRingTemperatureCommand
                              : null,
                          icon: const Icon(Icons.device_thermostat, size: 16),
                          label: const Text('Ring Temp (0x14)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange.shade200),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectionStatus == 'Connected'
                              ? _sendGetBloodOxygenDataCommand
                              : null,
                          icon: const Icon(Icons.air, size: 16),
                          label: const Text('Blood O2 (0x66)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lightBlue.shade100),
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
                      onPressed: _connectionStatus == 'Connected'
                          ? _sendMessage
                          : null,
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
                              onPressed: () =>
                                  setState(() => _messages.clear()),
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
                                final isReceived =
                                    message.contains('Received:');
                                return Container(
                                  margin: const EdgeInsets.all(4),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isReceived
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: GestureDetector(
                                    onLongPress: () {
                                      // Copy message to clipboard
                                      Clipboard.setData(
                                          ClipboardData(text: message));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Message copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      message,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12),
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
  Future<void> _sendGetTimeCommand() async {
    try {
      setState(() {
        _structuredDataTitle = 'Ring Time (0x41)';
        _structuredDataOutput = 'Fetching ring time...';
      });
      final result =
          await _bleService.fetchTime(timeout: const Duration(seconds: 2));
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _structuredDataOutput = 'No time response received (timeout or failure 0xC1).';
        });
        _addMessage('❌ Get Time failed or timed out.');
        return;
      }
      final phoneNow = DateTime.now();
      final drift = result.ringTime.difference(phoneNow).inSeconds;
      final buf = StringBuffer();
      buf.writeln('🕐 Ring Time:  ${result.ringTime}');
      buf.writeln('📱 Phone Time: $phoneNow');
      buf.writeln('⏱️  Drift:      ${drift}s (ring − phone)');
      buf.writeln('');
      buf.writeln('Weekday: ${result.weekday} (1=Mon..7=Sun, may be unreliable)');
      buf.writeln('Max MTU: ${result.maxMtu}');
      setState(() {
        _structuredDataOutput = buf.toString();
      });
      _addMessage('✅ Ring Time fetched: ${result.ringTime} (drift: ${drift}s)');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Ring Time (0x41)';
        _structuredDataOutput = 'Error fetching time: $e';
      });
      _addMessage('❌ Failed to fetch Ring Time: $e');
    }
  }

  Future<void> _sendSetCurrentTimeCommand() async {
    try {
      setState(() {
        _structuredDataTitle = 'Sync Time (0x01 → 0x41)';
        _structuredDataOutput = '⏳ Syncing phone time to ring...';
      });

      int messagesCountBefore = _messages.length;
      final result =
          await _bleService.syncTimeAndVerify(timeout: const Duration(seconds: 3));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n${result.sentCmd}\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('📱 Phone Time Sent: ${result.phoneSentAt}');
      if (result.ringReadback != null) {
        buf.writeln('🕐 Ring Readback:   ${result.ringReadback}');
        buf.writeln('⏱️  Drift:           ${result.driftSeconds}s (ring − phone)');
        if (result.driftSeconds!.abs() <= 1) {
          buf.writeln('');
          buf.writeln('✅ Sync verified — ring clock matches phone.');
        } else {
          buf.writeln('');
          buf.writeln('⚠️ Drift > 1s — sync may not have applied correctly.');
        }
      } else {
        buf.writeln('🕐 Ring Readback:   N/A (no response from 0x41)');
        buf.writeln('');
        buf.writeln('⚠️ Could not verify — 0x01 was sent but readback timed out.');
      }
      if (result.maxMtu != null) {
        buf.writeln('');
        buf.writeln('Max MTU: ${result.maxMtu}');
      }
      setState(() {
        _structuredDataOutput = buf.toString();
      });
      _addMessage(
        '✅ Sync Time: sent=${result.phoneSentAt} readback=${result.ringReadback ?? "N/A"} drift=${result.driftSeconds ?? "?"}s',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Sync Time (0x01 → 0x41)';
        _structuredDataOutput = 'Error syncing time: $e';
      });
      _addMessage('❌ Failed to sync time: $e');
    }
  }

  Future<void> _sendGetBatteryCommand() async {
    try {
      const sentCmd = '13-00-00-00-00-00-00-00-00-00-00-00-00-00-00-13';
      setState(() {
        _structuredDataTitle = 'Battery (0x13)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final result = await _bleService.fetchBattery(timeout: const Duration(seconds: 2));

      if (!mounted) return;

      // Get received message (should be added during fetch)
      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (result == null) {
        setState(() {
          _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0x93)';
        });
        _addMessage('❌ Battery fetch failed or timed out.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🔋 Battery Level: ${result['battery_level']}%');
      buf.writeln('⚡ Charging: ${result['charging'] ? 'Yes' : 'No'}');
      buf.writeln('🔌 Voltage 1: ${(result['voltage_high'] as double).toStringAsFixed(1)}V');
      buf.writeln('🔌 Voltage 2: ${(result['voltage_low'] as double).toStringAsFixed(1)}V');
      buf.writeln('🔍 Raw: 0x${(result['raw_byte3'] as int).toRadixString(16).padLeft(2, '0')} 0x${(result['raw_byte4'] as int).toRadixString(16).padLeft(2, '0')}');
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Battery: ${result['battery_level']}% ${result['charging'] ? '(charging)' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Battery (0x13)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch battery: $e');
    }
  }

  Future<void> _sendGetMacAddressCommand() async {
    try {
      const sentCmd = '22-00-00-00-00-00-00-00-00-00-00-00-00-00-00';
      setState(() {
        _structuredDataTitle = 'MAC Address (0x22)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });
      int messagesCountBefore = _messages.length;
      final result = await _bleService.fetchMacAddress(timeout: const Duration(seconds: 2));
      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (result == null) {
        setState(() {
          _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0xA2)';
        });
        _addMessage('❌ MAC address fetch failed or timed out.');
        return;
      }
      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('📡 MAC Address: ${result['mac']}');
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ MAC: ${result['mac']}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'MAC Address (0x22)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch MAC address: $e');
    }
  }

  Future<void> _sendGetFirmwareVersionCommand() async {
    try {
      const sentCmd = '27-00-00-00-00-00-00-00-00-00-00-00-00-00-00-FF';
      setState(() {
        _structuredDataTitle = 'Firmware (0x27)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final result = await _bleService.fetchFirmwareVersion(timeout: const Duration(seconds: 2));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (result == null) {
        setState(() {
          _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0xA7)';
        });
        _addMessage('❌ Firmware fetch failed or timed out.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('📦 Version: ${result['version']}');
      buf.writeln('📅 Build Date: ${result['build_date']}');
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Firmware: ${result['version']} (${result['build_date']})');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Firmware (0x27)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch firmware: $e');
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
                decoration:
                    const InputDecoration(labelText: 'Measurement Type'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Heart Rate')),
                  DropdownMenuItem(value: 2, child: Text('Blood Oxygen')),
                  DropdownMenuItem(value: 4, child: Text('HRV')),
                ],
                onChanged: (v) => setStateDialog(() => selType = v ?? 1),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      // Build the sent command
                      String sentCmd = '2B-${selType.toRadixString(16).padLeft(2, '0')}-00-00-00-00-00-00-00-00-00-00-00-00-00';
                      int checksum = (0x2B + selType) & 0xFF;
                      sentCmd += '-${checksum.toRadixString(16).padLeft(2, '0').toUpperCase()}';

                      setState(() {
                        _structuredDataTitle = 'Intervals (0x2B)';
                        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
                      });

                      int messagesCountBefore = _messages.length;
                      final result = await _bleService.fetchMeasurementInterval(selType, timeout: const Duration(seconds: 2));

                      if (!mounted) return;

                      String receivedMsg = 'No response received';
                      if (_messages.length > messagesCountBefore) {
                        final lastMsg = _messages.last;
                        if (lastMsg.contains('Received:')) {
                          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
                        }
                      }

                      if (result == null) {
                        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0xAB)'; });
                        _addMessage('❌ Interval fetch failed.');
                        return;
                      }
                      const typeNames = {1: 'Heart Rate', 2: 'Blood Oxygen', 4: 'HRV'};
                      final bits = result['weekday_bits'] as int;
                      String weekdayStr = '';
                      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
                      for (int i = 0; i < 7; i++) {
                        if ((bits >> i) & 1 == 1) weekdayStr += '${days[i]} ';
                      }
                      final buf = StringBuffer();
                      buf.writeln('📤 SENT:\n$sentCmd\n');
                      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
                      buf.writeln('📊 PARSED DATA:');
                      buf.writeln('📋 Type: ${typeNames[result['measurement_type']] ?? result['measurement_type']}');
                      buf.writeln('⚙️ Mode: ${result['working_mode']}');
                      buf.writeln('🕐 Window: ${result['start_hour'].toString().padLeft(2, '0')}:${result['start_min'].toString().padLeft(2, '0')} - ${result['end_hour'].toString().padLeft(2, '0')}:${result['end_min'].toString().padLeft(2, '0')}');
                      buf.writeln('📅 Days: ${weekdayStr.trim()}');
                      buf.writeln('⏱️ Interval: ${result['interval_minutes']} min');
                      setState(() { _structuredDataOutput = buf.toString(); });
                      _addMessage('✅ Interval: ${typeNames[result['measurement_type']] ?? selType} every ${result['interval_minutes']}min');
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _structuredDataTitle = 'Intervals (0x2B)';
                        _structuredDataOutput = 'Error: $e';
                      });
                      _addMessage('❌ Failed to fetch interval: $e');
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
    final startHourCtl = TextEditingController(text: '00');
    final startMinCtl = TextEditingController(text: '00');
    final endHourCtl = TextEditingController(text: '23');
    final endMinCtl = TextEditingController(text: '59');
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
                      decoration:
                          const InputDecoration(labelText: 'Measurement Type'),
                      items: typeOptions
                          .map((m) => DropdownMenuItem<int>(
                              value: m['value'] as int,
                              child: Text(m['label'] as String)))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => selType = v ?? 1),
                    ),
                    DropdownButtonFormField<int>(
                      value: selMode,
                      decoration: const InputDecoration(labelText: 'Mode'),
                      items: modeOptions
                          .map((m) => DropdownMenuItem<int>(
                              value: m['value'] as int,
                              child: Text(m['label'] as String)))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => selMode = v ?? 0),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: startHourCtl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Start HH'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: startMinCtl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Start mm'))),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: endHourCtl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'End HH'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: endMinCtl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'End mm'))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Weekdays'),
                    Wrap(
                      spacing: 4,
                      children: List.generate(7, (i) {
                        const names = [
                          'Sun',
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat'
                        ];
                        return FilterChip(
                          label: Text(names[i]),
                          selected: weekdaySel[i],
                          onSelected: (v) =>
                              setStateDialog(() => weekdaySel[i] = v),
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
                        helperText: selMode != 2
                            ? 'Enable Interval Mode to edit'
                            : null,
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
                      if (selMode != 2)
                        throw 'Mode must be Interval Mode to set interval';
                      if (sh < 0 || sh > 23) throw 'Start hour 0-23';
                      if (sm < 0 || sm > 59) throw 'Start minute 0-59';
                      if (eh < 0 || eh > 23) throw 'End hour 0-23';
                      if (em < 0 || em > 59) throw 'End minute 0-59';
                      if (interval <= 0 || interval > 1440)
                        throw 'Interval 1-1440 minutes';

                      // weekday bits: bit0=Sun .. bit6=Sat
                      int wbits = 0;
                      for (int i = 0; i < 7; i++) {
                        if (weekdaySel[i]) wbits |= (1 << i);
                      }

                      setState(() {
                        _structuredDataTitle = 'Set Interval (0x2A)';
                        _structuredDataOutput = '⏳ Sending SET command...';
                      });

                      int messagesCountBefore = _messages.length;
                      final sentCmd = await _bleService.sendSetMeasurementIntervalCommand(
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

                        // Get the ACK response
                        String receivedMsg = 'No response received';
                        if (_messages.length > messagesCountBefore) {
                          final lastMsg = _messages.last;
                          if (lastMsg.contains('Received:')) {
                            receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
                          }
                        }

                        final buf = StringBuffer();
                        buf.writeln('📤 SENT:\n$sentCmd\n');
                        buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
                        buf.writeln('📊 PARSED DATA:');
                        buf.writeln('✅ SET Measurement Interval (0x2A) ACK');
                        buf.writeln('📋 Type: ${selType == 1 ? 'Heart Rate' : selType == 2 ? 'Blood Oxygen' : selType == 4 ? 'HRV' : 'Unknown'}');
                        buf.writeln('⏱️ Interval: $interval min');

                        setState(() { _structuredDataOutput = buf.toString(); });
                        _addMessage(
                            '✅ Set Measurement Interval (0x2A) command sent.');

                        // Auto-fetch to verify
                        await Future.delayed(const Duration(milliseconds: 500));
                        await _bleService
                            .sendGetMeasurementIntervalCommand(selType);
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
      const sentCmd = '19-05-00-00-00-00-00-00-00-00-00-00-00-00-00-24';
      setState(() {
        _structuredDataTitle = 'Exercise Status (0x19)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final result = await _bleService.fetchExerciseStatus(timeout: const Duration(seconds: 2));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (result == null) {
        setState(() {
          _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0x99)';
        });
        _addMessage('❌ Exercise status fetch failed or timed out.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🏃 Active: ${result['is_active'] ? 'Yes' : 'No'}');
      buf.writeln('🕐 Has Timestamp: ${result['has_timestamp'] ? 'Yes' : 'No'}');
      if (result['timestamp'] != null) {
        buf.writeln('📅 Timestamp: ${result['timestamp']}');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Exercise: ${result['is_active'] ? 'ACTIVE' : 'Inactive'}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Exercise Status (0x19)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch exercise status: $e');
    }
  }

  Future<void> _toggleExerciseMode() async {
    try {
      if (_isExerciseActive) {
        // END EXERCISE
        const sentCmd = '19-06-00-00-00-00-00-00-00-00-00-00-00-00-00-25';
        setState(() {
          _structuredDataTitle = 'Exercise Mode (0x19)';
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: STOPPING...';
        });

        await _bleService.sendEndExerciseCommand();
        setState(() => _isExerciseActive = false);
        setState(() {
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: ✅ STOPPED';
        });
        _addMessage('✅ End Exercise command sent.');

        Future.delayed(const Duration(milliseconds: 700), () async {
          try {
            await _bleService.sendGetExerciseDataCommand();
          } catch (_) {}
        });
      } else {
        // START EXERCISE
        const sentCmd = '19-01-00-00-00-00-00-00-00-00-00-00-00-00-00-1A';
        setState(() {
          _structuredDataTitle = 'Exercise Mode (0x19)';
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: 🏃 RUNNING...\n\n⏳ Waiting for exercise data...';
        });

        await _bleService.sendStartExerciseCommand();
        setState(() => _isExerciseActive = true);
        setState(() {
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: 🏃 ACTIVE - Receiving exercise data...';
        });
        _addMessage('✅ Start Exercise command sent.');

        Future.delayed(const Duration(milliseconds: 700), () async {
          try {
            await _bleService.sendGetExerciseDataCommand();
          } catch (_) {}
        });
      }
    } catch (e) {
      setState(() {
        _structuredDataOutput = '❌ Failed: $e';
      });
      _addMessage(
          '❌ Failed to toggle exercise mode: $e.');
    }
  }

  Future<void> _toggleRealtimeMode() async {
    try {
      if (_isRealtimeActive) {
        // STOP REALTIME
        const sentCmd = '09-00-00-00-00-00-00-00-00-00-00-00-00-00-00-09';
        setState(() {
          _structuredDataTitle = 'Realtime Mode (0x09)';
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: STOPPING...';
        });
        await _bleService.sendStopRealtimeMode();
        setState(() => _isRealtimeActive = false);
        // Ignore trailing 0x09 frames for 1.5s so UI doesn't flip back to active
        _ignoreRealtimeUntilMs = DateTime.now().millisecondsSinceEpoch + 1500;
        setState(() {
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: ✅ STOPPED';
        });
      } else {
        // START REALTIME
        const sentCmd = '09-01-01-00-00-00-00-00-00-00-00-00-00-00-00-0B';
        setState(() {
          _structuredDataTitle = 'Realtime Mode (0x09)';
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: 📡 RUNNING...\n\n⏳ Waiting for sensor data...';
        });
        await _bleService.sendStartRealtimeMode(enableTemperature: true);
        setState(() => _isRealtimeActive = true);
        _ignoreRealtimeUntilMs = 0; // clear guard on start
        setState(() {
          _structuredDataOutput = '📤 SENT:\n$sentCmd\n\n📊 Status: 📡 ACTIVE - Receiving sensor data...';
        });
      }
    } catch (e) {
      _addMessage(
          '❌ Failed to toggle realtime mode: $e. _toggleRealtimeMode()');
    }
  }

  Future<void> _sendGetTotalStepCountCommand() async {
    try {
      const sentCmd = '51-00-00-00-00-00-00-00-00-00-00-00-00-00-00-51';
      setState(() {
        _structuredDataTitle = 'Steps (0x51)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchTotalSteps(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No step records received'; });
        _addMessage('❌ No step data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('📊 ${records.length} day(s) of step data:');
      buf.writeln('');
      for (final r in records) {
        buf.writeln('${r['date']}: ${r['steps']} steps, ${r['exercise_time_seconds']}s exercise, ${(r['calories_kcal'] as double).toStringAsFixed(1)} kcal, ${(r['distance_km'] as double).toStringAsFixed(2)} km');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Steps fetched: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Steps (0x51)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch steps: $e');
    }
  }

  Future<void> _sendGetDetailedStepCountCommand() async {
    try {
      const sentCmd = '52-00-00-00-00-00-00-00-00-00-00-00-00-00-00-52';
      setState(() {
        _structuredDataTitle = 'Step Details (0x52)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchDetailedSteps(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No detailed step records received'; });
        _addMessage('❌ No detailed step data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('📊 ${records.length} segment(s) of detailed steps:');
      buf.writeln('');
      for (final r in records) {
        buf.writeln('${r['timestamp']}: ${r['steps']} steps, ${(r['calories'] as double).toStringAsFixed(1)} kcal, ${(r['distance'] as double).toStringAsFixed(2)} km, ${(r['per_minute'] as List).length} min entries');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Step Details: ${records.length} segments');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Step Details (0x52)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch detailed steps: $e');
    }
  }

  Future<void> _sendGetDetailedHeartRateCommand() async {
    try {
      const sentCmd = '54-00-00-00-00-00-00-00-00-00-00-00-00-00-00-54';
      setState(() {
        _structuredDataTitle = 'HR Detail (0x54)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchDetailedHeartRate(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No detailed heart rate records received'; });
        _addMessage('❌ No detailed HR data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('❤️ ${records.length} HR measurement(s):');
      buf.writeln('');
      for (final r in records) {
        final rates = (r['heart_rates'] as List).join(', ');
        buf.writeln('${r['timestamp']}: [${rates}] BPM');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ HR Detail: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'HR Detail (0x54)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch detailed heart rate: $e');
    }
  }

  Future<void> _sendGetHeartRateHistoryCommand() async {
    try {
      const sentCmd = '55-00-00-00-00-00-00-00-00-00-00-00-00-00-00-55';
      setState(() {
        _structuredDataTitle = 'HR History (0x55)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchHeartRateHistory(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No heart rate history received'; });
        _addMessage('❌ No HR history received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('💓 ${records.length} HR reading(s):');
      buf.writeln('');
      for (final r in records) {
        buf.writeln('${r['timestamp']}: ${r['heart_rate']} BPM');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ HR History: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'HR History (0x55)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch HR history: $e');
    }
  }

  Future<void> _sendGetTemperatureDataCommand() async {
    try {
      const sentCmd = '62-00-00-00-00-00-00-00-00-00-00-00-00-00-00-62';
      setState(() {
        _structuredDataTitle = 'Temperature (0x62)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchTemperatureData(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No temperature records received'; });
        _addMessage('❌ No temperature data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🌡️ ${records.length} temperature reading(s):');
      buf.writeln('');
      for (final r in records) {
        final temps = (r['temperatures'] as List).map((t) => '${t}°C').join(', ');
        buf.writeln('${r['timestamp']}: [$temps]');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Temperature: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Temperature (0x62)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch temperature data: $e');
    }
  }

  Future<void> _sendGetRingTemperatureCommand() async {
    try {
      const sentCmd = '14-00-00-00-00-00-00-00-00-00-00-00-00-00-00-14';
      setState(() {
        _structuredDataTitle = 'Ring Temp (0x14)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final result = await _bleService.fetchRingTemperature(timeout: const Duration(seconds: 2));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (result == null) {
        setState(() {
          _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No response (0x94)';
        });
        _addMessage('❌ Ring temperature fetch failed or timed out.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🌡️ Highest: ${(result['highest_temp'] as double).toStringAsFixed(1)}°C');
      buf.writeln('🌡️ Decimal Temp: ${(result['decimal_temp'] as double).toStringAsFixed(1)}°C');
      buf.writeln('🧪 NTC1: ${(result['ntc1'] as double).toStringAsFixed(1)}°C');
      buf.writeln('🧪 NTC2: ${(result['ntc2'] as double).toStringAsFixed(1)}°C');
      buf.writeln('🧪 NTC3: ${(result['ntc3'] as double).toStringAsFixed(1)}°C');
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Ring Temp: ${(result['highest_temp'] as double).toStringAsFixed(1)}°C');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Ring Temp (0x14)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch ring temperature: $e');
    }
  }

  Future<void> _sendGetBloodOxygenDataCommand() async {
    try {
      const sentCmd = '66-00-00-00-00-00-00-00-00-00-00-00-00-00-00-66';
      setState(() {
        _structuredDataTitle = 'Blood O2 (0x66)';
        _structuredDataOutput = '📤 Sent: $sentCmd\n\n⏳ Waiting for response...';
      });

      int messagesCountBefore = _messages.length;
      final records = await _bleService.fetchBloodOxygenData(timeout: const Duration(seconds: 4));

      if (!mounted) return;

      String receivedMsg = 'No response received';
      if (_messages.length > messagesCountBefore) {
        final lastMsg = _messages.last;
        if (lastMsg.contains('Received:')) {
          receivedMsg = lastMsg.replaceFirst('Received: ', '').trim();
        }
      }

      if (records.isEmpty) {
        setState(() { _structuredDataOutput = '📤 Sent: $sentCmd\n\n❌ No blood oxygen records received'; });
        _addMessage('❌ No blood oxygen data received.');
        return;
      }

      final buf = StringBuffer();
      buf.writeln('📤 SENT:\n$sentCmd\n');
      buf.writeln('📥 RECEIVED:\n$receivedMsg\n');
      buf.writeln('📊 PARSED DATA:');
      buf.writeln('🩸 ${records.length} SpO2 reading(s):');
      buf.writeln('');
      for (final r in records) {
        buf.writeln('${r['timestamp']}: ${r['spo2']}%');
      }
      setState(() { _structuredDataOutput = buf.toString(); });
      _addMessage('✅ Blood O2: ${records.length} records');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _structuredDataTitle = 'Blood O2 (0x66)';
        _structuredDataOutput = 'Error: $e';
      });
      _addMessage('❌ Failed to fetch blood oxygen data: $e');
    }
  }

  // Connection Control Methods
  Future<void> _connectToSmartRing() async {
    _applyTarget();
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
