import 'dart:convert'; // Import for decoding the response body
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Security Camera',
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
  final String _notificationMessage = "Waiting for notifications...";
  String? _notificationImageUrl;
  bool _isStreaming = false;
  InAppWebViewController? _webViewController;

  Future<void> _sendPostRequest(String endpoint) async {
    try {
      final url = Uri.parse('http://100.125.19.81:8080/$endpoint');
      final response = await http.post(url);

      if (response.statusCode == 200) {
        print('$endpoint request successful');

        if (endpoint == 'screenshot') {
          // Parse the response to get the image URL
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          final String? imageUrl = jsonResponse['url'];

          if (imageUrl != null) {
            // Print the image URL from the response body
            print('Screenshot uploaded successfully. Image URL: $imageUrl');
            
            // Show the notification popup with the image URL
            _showNotificationPopup(imageUrl);
          }
        } else if (endpoint == 'start') {
          setState(() {
            _isStreaming = true;
          });
          // Load the WebRTC stream
          if (_webViewController != null) {
            _webViewController?.loadUrl(
              urlRequest: URLRequest(url: WebUri('http://100.125.19.81:8889/cam')),
            );
          }
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
          content: SingleChildScrollView(  // Wrap the content in a scrollable view
            child: Column(
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
  void dispose() {
    // Ensure the controller is disposed of when the widget is removed
    _webViewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Camera'),
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
                    initialUrlRequest: URLRequest(url: WebUri('http://100.125.19.81:8889/cam')),
                    initialSettings: InAppWebViewSettings(
                      allowsInlineMediaPlayback: true, // Allow inline playback for WebRTC
                      mediaPlaybackRequiresUserGesture: false, // Avoid requiring user gestures
                      javaScriptEnabled: true, // WebRTC often requires JavaScript
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      return NavigationActionPolicy.ALLOW; // Allow navigation
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
