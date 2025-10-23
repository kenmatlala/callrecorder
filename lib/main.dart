// main.dart - Flutter Phone Call Recorder with Google Drive Integration
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
// import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:path/path.dart' as path;
import 'package:call_log/call_log.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF0F4FF),
        useMaterial3: true,
      ),
      home: const CallRecorderHome(),
    );
  }
}

// Google API Client for authenticated requests
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class CallRecorderHome extends StatefulWidget {
  const CallRecorderHome({super.key});

  @override
  State<CallRecorderHome> createState() => _CallRecorderHomeState();
}

class _CallRecorderHomeState extends State<CallRecorderHome> {
  // Call state
  bool isInCall = false;
  bool showRecordPrompt = false;
  bool isRecording = false;
  bool isPaused = false;
  int recordingTime = 0;

  // Configuration
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController contactSearchController = TextEditingController();

  // Data
  List<RecordingData> recordings = [];
  List<Contact> contacts = [];
  List<Contact> filteredContacts = [];
  List<CallLogEntry> callLogs = [];
  Contact? selectedContact;
  Map<String, String> uploadStatus = {};

  // Google Drive Integration - Updated configuration
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  bool isSignedIn = false;
  String? driveFolderId;

  // Recording objects
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _timer;
  String? currentRecordingPath;

  bool showContactsModal = false;
  bool showCallLogsModal = false;

  @override
  void initState() {
    super.initState();
    initializeApp();
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      setState(() {
        _currentUser = account;
        isSignedIn = account != null;
      });
      if (account != null) {
        _initializeDriveApi();
      }
    });
    _googleSignIn.signInSilently();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    phoneController.dispose();
    contactSearchController.dispose();
    super.dispose();
  }

  Future<void> initializeApp() async {
    await requestPermissions();
    await loadRecordings();
  }

  Future<void> requestPermissions() async {
    // Request all necessary permissions
    final permissions = [
      Permission.microphone,
      Permission.contacts,
      Permission.storage,
      Permission.phone,
      Permission.manageExternalStorage,
    ];

    // Add Android-specific permissions
    if (Platform.isAndroid) {
      permissions.addAll([
        Permission.accessMediaLocation,
      ]);

      // For Android 13+
      if (await DeviceInfoPlugin()
          .androidInfo
          .then((info) => info.version.sdkInt >= 33)) {
        permissions.add(Permission.audio);
      }
    }

    final statuses = await permissions.request();

    // Check critical permissions
    if (!await Permission.microphone.isGranted) {
      _showError('Microphone permission is required for recording');
      return;
    }

    if (!await Permission.phone.isGranted) {
      _showError('Phone permission is required for call features');
      return;
    }

    // Add call log permission for Android
    if (Platform.isAndroid) {
      permissions.add(Permission.phone);
    }

    // Check if all permissions are granted
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        debugPrint('Permission $permission not granted: $status');
      }
    });

    if (!allGranted) {
      _showError(
          'Some permissions were not granted. App may not work properly.');
    }
  }

  // Google Drive Authentication - Fixed version
  Future<void> _handleGoogleSignIn() async {
    try {
      // Sign out first to clear any cached credentials
      await _googleSignIn.signOut();

      // Sign in with user interaction
      final account = await _googleSignIn.signIn();

      if (account != null) {
        setState(() {
          _currentUser = account;
          isSignedIn = true;
        });

        await _initializeDriveApi();
        await _createCallRecordingFolder();
        _showSuccess('Successfully signed in to Google Drive');
      } else {
        _showError('Sign-in was cancelled');
      }
    } catch (error) {
      debugPrint('Sign-in error: $error');
      _showError('Error signing in. Please check your Google Play Services.');
    }
  }

  Future<void> _handleGoogleSignOut() async {
    await _googleSignIn.signOut();
    setState(() {
      _currentUser = null;
      isSignedIn = false;
      _driveApi = null;
      driveFolderId = null;
    });
    _showSuccess('Signed out from Google Drive');
  }

  Future<void> _initializeDriveApi() async {
    try {
      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      setState(() {
        _driveApi = drive.DriveApi(authenticateClient);
      });
    } catch (e) {
      debugPrint('Error initializing Drive API: $e');
      _showError('Failed to initialize Google Drive');
    }
  }

  Future<void> _createCallRecordingFolder() async {
    if (_driveApi == null) return;

    try {
      // Check if folder already exists
      final folderList = await _driveApi!.files.list(
        q: "name='Call Recordings' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        spaces: 'drive',
      );

      if (folderList.files != null && folderList.files!.isNotEmpty) {
        driveFolderId = folderList.files!.first.id;
      } else {
        // Create new folder
        final folder = drive.File();
        folder.name = 'Call Recordings';
        folder.mimeType = 'application/vnd.google-apps.folder';

        final createdFolder = await _driveApi!.files.create(folder);
        driveFolderId = createdFolder.id;
      }
    } catch (e) {
      debugPrint('Error creating folder: $e');
      _showError('Failed to create Drive folder');
    }
  }

  // Upload to Google Drive
  Future<void> uploadToDrive(RecordingData recording) async {
    if (!isSignedIn || _driveApi == null) {
      _showError('Please sign in to Google Drive first');
      return;
    }

    if (driveFolderId == null) {
      await _createCallRecordingFolder();
      if (driveFolderId == null) {
        _showError('Failed to create Drive folder');
        return;
      }
    }

    setState(() {
      uploadStatus[recording.id] = 'uploading';
    });

    try {
      final file = File(recording.path);

      if (!await file.exists()) {
        throw Exception('Recording file not found');
      }

      final fileName = path.basename(recording.path);

      // Create metadata
      final driveFile = drive.File();
      driveFile.name = fileName;
      driveFile.parents = [driveFolderId!];
      driveFile.description =
          'Call recording - ${recording.contactName} (${recording.phoneNumber}) - ${formatDate(recording.date)}';

      // Upload file
      final media = drive.Media(file.openRead(), file.lengthSync());
      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );

      if (uploadedFile.id != null) {
        setState(() {
          uploadStatus[recording.id] = 'success';
          final index = recordings.indexWhere((r) => r.id == recording.id);
          if (index != -1) {
            recordings[index] = recording.copyWith(
              uploaded: true,
              driveFileId: uploadedFile.id,
            );
          }
        });

        await saveRecordingsMetadata();
        _showSuccess('Recording uploaded to Google Drive');

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              uploadStatus.remove(recording.id);
            });
          }
        });
      }
    } catch (e) {
      setState(() {
        uploadStatus[recording.id] = 'error';
      });
      debugPrint('Upload error: $e');
      _showError('Failed to upload: ${e.toString()}');
    }
  }

  // Download from Google Drive
  Future<void> downloadFromDrive(RecordingData recording) async {
    if (!isSignedIn || _driveApi == null || recording.driveFileId == null) {
      _showError('Cannot download: Not signed in or file not on Drive');
      return;
    }

    try {
      _showSuccess('Downloading from Google Drive...');

      final response = await _driveApi!.files.get(
        recording.driveFileId!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${directory.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final file = File(recording.path);
      final sink = file.openWrite();

      await response.stream.pipe(sink);
      await sink.close();

      _showSuccess('Downloaded successfully');
    } catch (e) {
      _showError('Failed to download: $e');
    }
  }

  // Delete from Google Drive
  Future<void> deleteFromDrive(RecordingData recording) async {
    if (!isSignedIn || _driveApi == null || recording.driveFileId == null) {
      return;
    }

    try {
      await _driveApi!.files.delete(recording.driveFileId!);
      _showSuccess('Deleted from Google Drive');
    } catch (e) {
      debugPrint('Error deleting from Drive: $e');
    }
  }

  // Load contacts with proper permission handling
  Future<void> loadContacts() async {
    try {
      // Request permission explicitly
      final permission = await Permission.contacts.request();

      if (permission.isDenied) {
        _showError('Contacts permission denied');
        return;
      }

      if (permission.isPermanentlyDenied) {
        _showError(
            'Contacts permission permanently denied. Please enable in settings.');
        await openAppSettings();
        return;
      }

      if (permission.isGranted) {
        final allContacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        setState(() {
          contacts = allContacts.where((c) => c.phones.isNotEmpty).toList();
          filteredContacts = contacts;
          showContactsModal = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      _showError('Failed to load contacts: ${e.toString()}');
    }
  }

  // Load call logs
  Future<void> loadCallLogs() async {
    try {
      final permission = await Permission.phone.request();

      if (permission.isDenied) {
        _showError('Phone permission denied');
        return;
      }

      if (permission.isPermanentlyDenied) {
        _showError(
            'Phone permission permanently denied. Please enable in settings.');
        await openAppSettings();
        return;
      }

      if (permission.isGranted) {
        final Iterable<CallLogEntry> entries = await CallLog.get();
        setState(() {
          callLogs = entries.take(50).toList(); // Get last 50 calls
          showCallLogsModal = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading call logs: $e');
      _showError('Failed to load call logs: ${e.toString()}');
    }
  }

  void filterContacts(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredContacts = contacts;
      } else {
        filteredContacts = contacts.where((contact) {
          final name = contact.displayName.toLowerCase();
          final phone =
              contact.phones.isNotEmpty ? contact.phones.first.number : '';
          return name.contains(query.toLowerCase()) || phone.contains(query);
        }).toList();
      }
    });
  }

  void selectContact(Contact contact) {
    setState(() {
      selectedContact = contact;
      phoneController.text =
          contact.phones.isNotEmpty ? contact.phones.first.number : '';
      showContactsModal = false;
      contactSearchController.clear();
    });
  }

  void selectCallLog(CallLogEntry entry) {
    setState(() {
      phoneController.text = entry.number ?? '';
      showCallLogsModal = false;

      // Try to find matching contact
      final matchingContact = contacts.firstWhere(
        (c) => c.phones.any((p) =>
            p.number.replaceAll(RegExp(r'[^\d]'), '') ==
            entry.number?.replaceAll(RegExp(r'[^\d]'), '')),
        orElse: () => Contact(),
      );

      if (matchingContact.displayName.isNotEmpty) {
        selectedContact = matchingContact;
      }
    });
  }

  Future<void> startCall() async {
    if (phoneController.text.trim().isEmpty) {
      _showError('Please enter a phone number or select a contact');
      return;
    }

    await _initiateRegularCall(phoneController.text);

    setState(() {
      isInCall = true;
      showRecordPrompt = true;
    });
  }

  Future<void> _initiateRegularCall(String number) async {
    final cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanNumber');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showError('Cannot make phone calls on this device');
      }
    } catch (e) {
      _showError('Failed to initiate call: $e');
    }
  }

  void endCall() {
    if (isRecording) {
      stopRecording();
    }
    setState(() {
      isInCall = false;
      showRecordPrompt = false;
      selectedContact = null;
    });
  }

  Future<void> startRecording() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      _showError('Microphone access is required');
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${directory.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanNumber = phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
      final fileName = 'call_${cleanNumber}_$timestamp.m4a';
      currentRecordingPath = '${recordingsDir.path}/$fileName';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: currentRecordingPath!,
      );

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            recordingTime++;
          });
        }
      });

      setState(() {
        isRecording = true;
        showRecordPrompt = false;
        recordingTime = 0;
      });
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> pauseRecording() async {
    await _audioRecorder.pause();
    _timer?.cancel();
    setState(() {
      isPaused = true;
    });
  }

  Future<void> resumeRecording() async {
    await _audioRecorder.resume();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          recordingTime++;
        });
      }
    });
    setState(() {
      isPaused = false;
    });
  }

  Future<void> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _timer?.cancel();

      if (path != null) {
        final newRecording = RecordingData(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          path: path,
          phoneNumber: phoneController.text,
          contactName: selectedContact?.displayName ?? 'Unknown',
          duration: recordingTime,
          date: DateTime.now(),
          uploaded: false,
          driveFileId: null,
        );

        setState(() {
          recordings.insert(0, newRecording);
          isRecording = false;
          isPaused = false;
          recordingTime = 0;
          currentRecordingPath = null;
        });

        await saveRecordingsMetadata();
      }
    } catch (e) {
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> playRecording(String path) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      _showError('Failed to play recording: $e');
    }
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
  }

  Future<void> deleteRecording(RecordingData recording) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording'),
        content: const Text('Are you sure you want to delete this recording?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Delete from Drive if uploaded
        if (recording.uploaded && recording.driveFileId != null) {
          await deleteFromDrive(recording);
        }

        // Delete local file
        final file = File(recording.path);
        if (await file.exists()) {
          await file.delete();
        }

        setState(() {
          recordings.removeWhere((r) => r.id == recording.id);
        });

        await saveRecordingsMetadata();
        _showSuccess('Recording deleted');
      } catch (e) {
        _showError('Failed to delete recording: $e');
      }
    }
  }

  Future<void> saveRecordingsMetadata() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/recordings_metadata.json');
      final json = jsonEncode(recordings.map((r) => r.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('Error saving metadata: $e');
    }
  }

  Future<void> loadRecordings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/recordings_metadata.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> json = jsonDecode(content);

        final loadedRecordings = <RecordingData>[];
        for (var item in json) {
          final recording = RecordingData.fromJson(item);
          final recordingFile = File(recording.path);
          if (await recordingFile.exists()) {
            loadedRecordings.add(recording);
          }
        }

        setState(() {
          recordings = loadedRecordings;
        });
      }
    } catch (e) {
      debugPrint('Error loading recordings: $e');
    }
  }

  String formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy hh:mm a').format(date);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    '📞 Phone Call Recorder',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildGoogleDriveCard(),
                  const SizedBox(height: 16),
                  _buildMainCard(),
                  const SizedBox(height: 16),
                  _buildRecordingsList(),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                ],
              ),
            ),
            if (showRecordPrompt) _buildRecordPromptDialog(),
            if (showContactsModal) _buildContactsModal(),
            if (showCallLogsModal) _buildCallLogsModal(),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleDriveCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isSignedIn ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  size: 32,
                  color: isSignedIn
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSignedIn ? 'Google Drive Connected' : 'Google Drive',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSignedIn
                              ? const Color(0xFF166534)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                      if (isSignedIn && _currentUser != null)
                        Text(
                          _currentUser!.email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF15803D),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    isSignedIn ? _handleGoogleSignOut : _handleGoogleSignIn,
                icon: Icon(isSignedIn ? Icons.logout : Icons.login),
                label: Text(isSignedIn ? 'Sign Out' : 'Sign In with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSignedIn
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPhoneInput(),
            if (selectedContact != null) ...[
              const SizedBox(height: 16),
              _buildSelectedContact(),
            ],
            const SizedBox(height: 16),
            _buildCallButton(),
            if (isInCall) ...[
              const SizedBox(height: 16),
              _buildInCallUI(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Column(
      children: [
        TextField(
          controller: phoneController,
          decoration: InputDecoration(
            hintText: 'Enter phone number',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
          ),
          keyboardType: TextInputType.phone,
          enabled: !isInCall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isInCall ? null : loadContacts,
                icon: const Icon(Icons.contacts),
                label: const Text('Contacts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isInCall ? null : loadCallLogs,
                icon: const Icon(Icons.history),
                label: const Text('Call History'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedContact() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF4F46E5),
            child: Text(
              selectedContact!.displayName.isNotEmpty
                  ? selectedContact!.displayName[0]
                  : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedContact!.displayName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  selectedContact!.phones.isNotEmpty
                      ? selectedContact!.phones.first.number
                      : '',
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton() {
    if (!isInCall) {
      return ElevatedButton(
        onPressed: startCall,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          '📞 Start Call',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    } else {
      return ElevatedButton(
        onPressed: endCall,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          '📞 End Call',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }
  }

  Widget _buildInCallUI() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Calling',
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 4),
          Text(
            selectedContact?.displayName ?? phoneController.text,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4F46E5),
            ),
          ),
          if (selectedContact != null) ...[
            const SizedBox(height: 4),
            Text(
              phoneController.text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ],
          if (isRecording) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatTime(recordingTime),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: isPaused ? resumeRecording : pauseRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPaused
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFF59E0B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    isPaused ? '▶ Resume' : '⏸ Pause',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: stopRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    '⏹ Stop',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingsList() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved Recordings (${recordings.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (recordings.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Text(
                        'No recordings yet',
                        style:
                            TextStyle(fontSize: 18, color: Color(0xFF9CA3AF)),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Start a call and record it!',
                        style:
                            TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...recordings.map((recording) => _buildRecordingItem(recording)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingItem(RecordingData recording) {
    final status = uploadStatus[recording.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recording.contactName != 'Unknown'
                ? recording.contactName
                : recording.phoneNumber,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (recording.contactName != 'Unknown') ...[
            const SizedBox(height: 4),
            Text(
              recording.phoneNumber,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatDate(recording.date),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const Text('•',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              Text(
                formatTime(recording.duration),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              if (recording.uploaded)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '☁ On Drive',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => playRecording(recording.path),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    '▶ Play',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: status == 'uploading' || !isSignedIn
                      ? null
                      : () => uploadToDrive(recording),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    !isSignedIn
                        ? '🔒 Sign In'
                        : status == 'uploading'
                            ? '⏳ Uploading...'
                            : status == 'success'
                                ? '✓ Uploaded!'
                                : status == 'error'
                                    ? '✗ Failed'
                                    : recording.uploaded
                                        ? '✓ On Drive'
                                        : '☁ Upload',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => deleteRecording(recording),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  '🗑',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (recording.uploaded && recording.driveFileId != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => downloadFromDrive(recording),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download from Drive'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFF4F46E5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        border: Border.all(color: const Color(0xFFFCD34D), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ℹ️ Important Notes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF92400E),
            ),
          ),
          SizedBox(height: 8),
          Text(
            '• Sign in to Google Drive to backup recordings\n'
            '• All recordings stored in "Call Recordings" folder\n'
            '• Access your contacts and call history\n'
            '• Recordings saved in M4A format\n'
            '• Check local laws regarding call recording\n'
            '• Grant all permissions for full functionality',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF78350F),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordPromptDialog() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Record this call?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Would you like to record this conversation? The recording will be saved as M4A.',
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'Yes, Record',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => showRecordPrompt = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'No, Thanks',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactsModal() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '👥 Select Contact',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                IconButton(
                  icon: const Text('✕',
                      style: TextStyle(fontSize: 32, color: Color(0xFF6B7280))),
                  onPressed: () => setState(() => showContactsModal = false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: contactSearchController,
              onChanged: filterContacts,
              decoration: InputDecoration(
                hintText: '🔍 Search contacts...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFD1D5DB), width: 2),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
          Expanded(
            child: filteredContacts.isEmpty
                ? const Center(
                    child: Text(
                      'No contacts found',
                      style: TextStyle(fontSize: 18, color: Color(0xFF9CA3AF)),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredContacts.length,
                    itemBuilder: (context, index) {
                      final contact = filteredContacts[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Material(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () => selectContact(contact),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: const Color(0xFF4F46E5),
                                    child: Text(
                                      contact.displayName.isNotEmpty
                                          ? contact.displayName[0]
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          contact.displayName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          contact.phones.isNotEmpty
                                              ? contact.phones.first.number
                                              : '',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallLogsModal() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📞 Call History',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                IconButton(
                  icon: const Text('✕',
                      style: TextStyle(fontSize: 32, color: Color(0xFF6B7280))),
                  onPressed: () => setState(() => showCallLogsModal = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: callLogs.isEmpty
                ? const Center(
                    child: Text(
                      'No call history found',
                      style: TextStyle(fontSize: 18, color: Color(0xFF9CA3AF)),
                    ),
                  )
                : ListView.builder(
                    itemCount: callLogs.length,
                    itemBuilder: (context, index) {
                      final log = callLogs[index];
                      final callTypeIcon = log.callType == CallType.incoming
                          ? '📥'
                          : log.callType == CallType.outgoing
                              ? '📤'
                              : log.callType == CallType.missed
                                  ? '📵'
                                  : '📞';

                      final callTypeColor = log.callType == CallType.missed
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6B7280);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Material(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () => selectCallLog(log),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Text(
                                    callTypeIcon,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          log.name ?? log.number ?? 'Unknown',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          log.number ?? '',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: callTypeColor,
                                          ),
                                        ),
                                        if (log.timestamp != null)
                                          Text(
                                            formatDate(DateTime
                                                .fromMillisecondsSinceEpoch(
                                                    log.timestamp!)),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Recording Data Model
class RecordingData {
  final String id;
  final String path;
  final String phoneNumber;
  final String contactName;
  final int duration;
  final DateTime date;
  final bool uploaded;
  final String? driveFileId;

  RecordingData({
    required this.id,
    required this.path,
    required this.phoneNumber,
    required this.contactName,
    required this.duration,
    required this.date,
    required this.uploaded,
    this.driveFileId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'phoneNumber': phoneNumber,
        'contactName': contactName,
        'duration': duration,
        'date': date.toIso8601String(),
        'uploaded': uploaded,
        'driveFileId': driveFileId,
      };

  factory RecordingData.fromJson(Map<String, dynamic> json) => RecordingData(
        id: json['id'],
        path: json['path'],
        phoneNumber: json['phoneNumber'],
        contactName: json['contactName'],
        duration: json['duration'],
        date: DateTime.parse(json['date']),
        uploaded: json['uploaded'] ?? false,
        driveFileId: json['driveFileId'],
      );

  RecordingData copyWith({
    String? id,
    String? path,
    String? phoneNumber,
    String? contactName,
    int? duration,
    DateTime? date,
    bool? uploaded,
    String? driveFileId,
  }) {
    return RecordingData(
      id: id ?? this.id,
      path: path ?? this.path,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      duration: duration ?? this.duration,
      date: date ?? this.date,
      uploaded: uploaded ?? this.uploaded,
      driveFileId: driveFileId ?? this.driveFileId,
    );
  }
}
