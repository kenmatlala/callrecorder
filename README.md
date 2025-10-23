# 📞 Phone Call Recorder App

A Flutter-based Android application that records phone calls and automatically backs them up to Google Drive.

## ✨ Features

- 🎙️ **High-Quality Call Recording** - Records phone calls in M4A format
- ☁️ **Google Drive Integration** - Automatic backup to your Google Drive
- 📱 **Contact Integration** - Access your phonebook and identify callers
- ⏯️ **Playback Controls** - Play, pause, and manage recordings
- 📊 **Recording History** - View all your past recordings with timestamps
- 🔒 **Secure Storage** - Local storage with cloud backup option
- 🎨 **Modern UI** - Clean and intuitive Material Design interface

## 📋 Requirements

- Flutter SDK 3.0.0 or higher
- Android device or emulator (API level 21+)
- Android Studio (for emulator and SDK management)
- Google Account (for Drive backup feature)

## 🚀 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/call_recorder_app.git
cd call_recorder_app
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure Google Drive (Optional)

To enable Google Drive backup:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable **Google Drive API**
4. Create OAuth 2.0 credentials:
   - Application type: Android
   - Package name: `com.example.call_recorder_app`
   - SHA-1 fingerprint: Get it by running:
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
5. Add your SHA-1 fingerprint to the credentials

### 4. Run the App

#### Start an Android Emulator:
```bash
flutter emulators --launch Pixel_9_Pro_API_35
```

#### Or connect your physical Android device with USB debugging enabled

#### Then run:
```bash
flutter run
```

## 📱 Usage

### Recording a Call

1. **Enter a phone number** or select from contacts
2. **Tap "Start Call"** to initiate the call
3. When prompted, choose **"Yes, Record"** to start recording
4. During the call:
   - ⏸️ **Pause/Resume** recording as needed
   - ⏹️ **Stop** recording when done
5. The recording is automatically saved

### Managing Recordings

- **▶️ Play** - Listen to any recording
- **☁️ Upload** - Backup to Google Drive (requires sign-in)
- **📥 Download** - Restore from Google Drive
- **🗑️ Delete** - Remove recordings (locally and from Drive)

### Google Drive Backup

1. **Sign in** with your Google account
2. Recordings are stored in a folder named **"Call Recordings"**
3. Upload recordings manually or they sync automatically
4. Access your recordings from any device with your Google account

## 🔧 Configuration

### Permissions Required

The app requests the following permissions:

- **Microphone** - For recording audio
- **Contacts** - For accessing your phonebook
- **Phone** - For initiating calls and accessing call logs
- **Storage** - For saving recordings locally

### pubspec.yaml Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  permission_handler: ^11.0.1
  flutter_contacts: ^1.1.7+1
  path_provider: ^2.1.1
  record: ^6.1.2
  audioplayers: ^5.2.1
  url_launcher: ^6.2.1
  http: ^1.1.0
  intl: ^0.18.1
  google_sign_in: ^6.1.5
  googleapis: ^11.4.0
  googleapis_auth: ^1.4.1
  path: ^1.8.3
```

## 🏗️ Project Structure

```
call_recorder_app/
├── android/              # Android native configuration
├── lib/
│   └── main.dart        # Main application code
├── assets/              # App icons and resources
├── pubspec.yaml         # Dependencies configuration
└── README.md           # This file
```

## ⚠️ Important Notes

### Legal Considerations

- **Check local laws** - Call recording laws vary by location
- **Consent requirements** - Some jurisdictions require all parties' consent
- **Notification** - Some regions require you to notify the other party
- **Use responsibly** - Only record calls for legitimate purposes

### Known Limitations

- **Android Only** - iOS does not support call recording due to platform restrictions
- **Native Dialer** - Uses the device's native phone app for calls
- **Recording Quality** - Depends on device hardware and Android version
- **Call History** - Feature temporarily disabled (coming soon)

## 🐛 Troubleshooting

### App won't build

```bash
flutter clean
flutter pub get
flutter run
```

### Google Drive sign-in fails

1. Verify OAuth credentials are configured correctly
2. Check that SHA-1 fingerprint matches your debug keystore
3. Ensure Google Drive API is enabled in Cloud Console

### Recording not working

1. Check microphone permissions are granted
2. Verify storage permissions are enabled
3. Try restarting the app
4. Some Android versions have restrictions on call recording

### Can't access contacts

1. Grant contacts permission in app settings
2. If permission denied, go to Settings > Apps > Call Recorder > Permissions

## 🔄 Future Enhancements

- [ ] Call history integration
- [ ] Automatic recording toggle
- [ ] Recording filters and search
- [ ] Export recordings to other cloud services
- [ ] Recording quality settings
- [ ] Dark mode support
- [ ] Multi-language support
- [ ] Recording encryption

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👨‍💻 Developer

Created with ❤️ using Flutter

## 📞 Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Email: support@callrecorder.com

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- All open-source package contributors
- Google Drive API documentation

---

**Note**: This app is for personal use only. Always comply with local laws and regulations regarding call recording.

## 📸 Screenshots

_Coming soon..._

## 🔐 Privacy

- All recordings are stored locally on your device
- Google Drive backup is optional and encrypted in transit
- No data is shared with third parties
- You have full control over your recordings

## 📊 Tech Stack

- **Framework**: Flutter
- **Language**: Dart
- **Cloud Storage**: Google Drive API
- **Audio Recording**: record package
- **Audio Playback**: audioplayers package
- **State Management**: StatefulWidget

---

Made with Flutter 💙
