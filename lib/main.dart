import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'firebase_options.dart';

// Handle background notifications
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Doorbell',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: const NotificationScreen(),
    );
  }
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _notificationMessage = "Waiting for notifications...";
  String? _notificationImageUrl;
  bool _isStreaming = false;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _setupFirebaseMessaging();
  }

  void _setupFirebaseMessaging() {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request notification permissions
    messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Print and display the FCM token
    messaging.getToken().then((token) {
      print("FCM Token: $token");
    });

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      setState(() {
        _notificationMessage =
            message.notification?.body ?? "No message content.";
        _notificationImageUrl = message.data['imageUrl'];
      });

      if (_notificationImageUrl != null) {
        _showNotificationPopup(_notificationImageUrl!);
      }
    });

    // Handle when notification is opened
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("Message clicked!");
    });
  }

  Future<void> _sendPostRequest(String endpoint) async {
    try {
      final url = Uri.parse('http://100.125.19.81:8080/$endpoint');
      final response = await http.post(url);

      if (response.statusCode == 200) {
        print('$endpoint request successful');

        if (endpoint == 'start') {
          setState(() {
            _isStreaming = true;
          });
          // Load the WebRTC stream
          _webViewController?.loadUrl(
            urlRequest:
                URLRequest(url: WebUri('http://100.125.19.81:8889/cam')),
          );
        } else if (endpoint == 'stop') {
          setState(() {
            _isStreaming = false;
          });
        }
      } else {
        print('$endpoint request failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending $endpoint request: $e');
    }
  }

  void _showNotificationPopup(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Screenshot Uploaded'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your screenshot has been uploaded to the cloud.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              Image.network(imageUrl),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Doorbell Notifications'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // InAppWebView for live view
          SizedBox(
            width: double.infinity,
            height: 200,
            child: _isStreaming
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                        url: WebUri('http://100.125.19.81:8889/cam')),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                  )
                : Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: Text(
                        'Live View Placeholder',
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          // Buttons for controlling the camera
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => _sendPostRequest('start'),
                child: const Text('Start'),
              ),
              ElevatedButton(
                onPressed: () => _sendPostRequest('screenshot'),
                child: const Text('Screenshot'),
              ),
              ElevatedButton(
                onPressed: () => _sendPostRequest('stop'),
                child: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Notification message display
          Text(
            _notificationMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
          // Display notification image if available
          if (_notificationImageUrl != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.network(_notificationImageUrl!),
            ),
        ],
      ),
    );
  }
}
