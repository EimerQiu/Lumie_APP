# Smart Ring Flutter App

A Flutter application to connect and communicate with your Smart Ring (X6B 45CC8) via Bluetooth Low Energy (BLE).

## Features

- **Auto-Connect**: Automatically connects to your Smart Ring when the app opens
- **Real-time Communication**: Send hex commands and receive responses in real-time
- **Health Data Retrieval**: Quick action to request HRV and health data (Command 0x56)
- **Cross-Platform**: Works on both Android and iOS
- **Modern UI**: Clean, intuitive interface with connection status and message history

## Smart Ring Protocol

The app implements the reverse-engineered BLE protocol for the Smart Ring:

- **Device**: X6B 45CC8 (MAC: F8:19:23:14:5C:C8)
- **Service UUID**: `0000fff0-0000-1000-8000-00805f9b34fb`
- **Write Characteristic**: `0000fff6-0000-1000-8000-00805f9b34fb`
- **Notify Characteristic**: `0000fff7-0000-1000-8000-00805f9b34fb`

### Supported Commands

- **HRV Data Request (0x56)**: `56-01-00-00-00-00-00-00-00-00-00-00-00-00-00-57`
- **Custom Hex Commands**: Send any 16-byte hex command

### Data Format

The Smart Ring returns health data in 16-byte packets:
```
0x56 XX 00 YY MM DD HH mm SS HRV STATUS HR STRESS SBP DBP CRC
```

Where:
- `XX`: Data index
- `YY MM DD HH mm SS`: Timestamp (Year, Month, Day, Hour, Minute, Second)
- `HRV`: Heart Rate Variability
- `STATUS`: Data quality status
- `HR`: Heart Rate (BPM)
- `STRESS`: Stress/Fatigue level
- `SBP/DBP`: Systolic/Diastolic Blood Pressure
- `CRC`: Checksum

## Setup Instructions

### Prerequisites

1. **Flutter SDK**: Install Flutter 3.0+ from [flutter.dev](https://flutter.dev)
2. **Development Environment**:
   - For Android: Android Studio with Android SDK
   - For iOS: Xcode (macOS only)

### Installation

1. **Clone and Navigate**:
   ```bash
   cd /Users/ciline/Documents/development/projects/Lumie/smart_ring_app
   ```

2. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the App**:
   ```bash
   # For Android
   flutter run

   # For iOS (macOS only)
   flutter run -d ios
   ```

### Building for Release

#### Android APK
```bash
flutter build apk --release
```
The APK will be available at: `build/app/outputs/flutter-apk/app-release.apk`

#### iOS App (macOS only)
```bash
flutter build ios --release
```
Then open `ios/Runner.xcworkspace` in Xcode to archive and distribute.

## Permissions

The app requires the following permissions:

### Android
- `BLUETOOTH` & `BLUETOOTH_ADMIN`: Basic Bluetooth functionality
- `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE`: Android 12+ BLE permissions
- `ACCESS_FINE_LOCATION`: Required for BLE device scanning

### iOS
- `NSBluetoothAlwaysUsageDescription`: Bluetooth access for Smart Ring connection
- `NSLocationWhenInUseUsageDescription`: Location access for BLE scanning

## Usage

1. **Launch the App**: The app will automatically attempt to connect to your Smart Ring
2. **Connection Status**: Monitor the connection status in the top card
3. **Quick Actions**: Use "Get HRV Data" button to request health data
4. **Custom Commands**: Enter hex commands in the input field and tap "Send"
5. **Message History**: View all sent and received messages in the scrollable list

## Troubleshooting

### Connection Issues
- Ensure your Smart Ring is powered on and in range
- Check that Bluetooth is enabled on your device
- Grant all required permissions when prompted
- Try the "Scan" button to manually search for the device

### Android Specific
- Ensure Location Services are enabled (required for BLE scanning)
- On Android 12+, grant "Nearby devices" permission

### iOS Specific
- Grant Bluetooth permission when prompted
- Ensure the app has location permission for BLE scanning

## Development Notes

The app uses:
- `flutter_blue_plus`: Modern BLE library for Flutter
- `permission_handler`: Runtime permission management
- Material Design 3: Modern UI components

## Protocol Analysis

Based on extensive reverse engineering of the Smart Ring's BLE protocol, this app can:
- Connect to the specific Smart Ring device
- Send properly formatted 16-byte commands
- Parse incoming health data packets
- Handle multi-page data responses (up to 300+ health records)
- Decode timestamps, HRV, heart rate, stress levels, and blood pressure data

The protocol implementation is based on analysis of actual BLE communication logs and supports the complete health monitoring feature set of the Smart Ring device.
