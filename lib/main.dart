import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'webview_page.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lichen Identifier',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Lichen Identifier'),
      debugShowCheckedModeBanner: false,
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
  late CameraController _controller;
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();
  bool _isCapturing = false;
  bool _cameraInitialized = false;
  String? _resultText;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(_cameras[0], ResolutionPreset.medium);
    try {
      await _controller.initialize();
      setState(() {
        _cameraInitialized = true;
      });
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  Future<void> _takePicture() async {
    if (_isCapturing || !_controller.value.isInitialized) return;
    setState(() => _isCapturing = true);
    try {
      final XFile image = await _controller.takePicture();
      setState(() {
        _imagePath = image.path;
        _resultText = null;
      });
      await _runInferenceAndUpload(image.path);
    } catch (e) {
      debugPrint('Error taking picture: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _imagePath = image.path;
        _resultText = null;
      });
      await _runInferenceAndUpload(image.path);
    }
  }

  Future<void> _runInferenceAndUpload(String imagePath) async {
    setState(() {
      _loading = true;
      _resultText = null;
    });

    final url = Uri.parse("https://predict.ultralytics.com");
    final headers = {"x-api-key": "99aa2048e2c4a2563aa2d16612e4fb675294f2c9e2"};
    final data = {
      "model": "https://hub.ultralytics.com/models/EIVlhb5m3omH3ZT7Fz3w",
      "imgsz": "640",
      "conf": "0.25",
      "iou": "0.45"
    };

    try {
      var file = File(imagePath);

      var request = http.MultipartRequest("POST", url)
        ..headers.addAll(headers)
        ..fields.addAll(data)
        ..files.add(await http.MultipartFile.fromPath("file", file.path));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      String resultText = "Unknown";
      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(responseBody);
        var results = jsonResponse['images']?[0]?['results'];
        resultText = (results != null && results.isNotEmpty)
            ? results[0]['name'] ?? "Unknown"
            : "No results found";
      } else {
        resultText = "Error: ${response.statusCode} - $responseBody";
      }

      setState(() {
        _resultText = resultText;
      });
      await _uploadToServer(imagePath, resultText);
    } catch (e) {
      setState(() {
        _resultText = "Inference error: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _uploadToServer(String imagePath, String result) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return;

      Position position = await _getCurrentPosition();

      final url = Uri.parse("https://mb73pr7n-3000.asse.devtunnels.ms/upload");

      var request = http.MultipartRequest('POST', url)
        ..fields['result'] = result
        ..fields['latitude'] = position.latitude.toString()
        ..fields['longitude'] = position.longitude.toString()
        ..files.add(await http.MultipartFile.fromPath('image', imagePath));

      await request.send();
    } catch (e) {
      // Optionally handle upload errors
    }
  }

  Future<Position> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      throw Exception("Location services are disabled");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Location permission denied");
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permission permanently denied");
    }

    return await Geolocator.getCurrentPosition();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  Widget _buildCameraPreview() {
    return _controller.value.isInitialized
        ? SizedBox.expand(
            child: CameraPreview(_controller),
          )
        : const Center(child: CircularProgressIndicator());
  }

  Widget _buildImagePreview() {
    if (_imagePath == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(_imagePath!),
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildResultCard() {
    if (_resultText == null) return const SizedBox.shrink();
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.eco, color: Colors.green, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _resultText!,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton(
              heroTag: "camera",
              onPressed: _isCapturing || _loading ? null : _takePicture,
              backgroundColor: Colors.green.shade200,
              child: const Icon(Icons.camera_alt, size: 32),
              tooltip: "Capture with Camera",
              ),
              const SizedBox(width: 32),
              FloatingActionButton(
              heroTag: "gallery",
              onPressed: _isCapturing || _loading ? null : _pickImage,
              backgroundColor: Colors.green.shade200,
              child: const Icon(Icons.photo_library, size: 32),
              tooltip: "Pick from Gallery",
              ),
              const SizedBox(width: 32),
              FloatingActionButton(
              heroTag: "web",
              onPressed: _isCapturing || _loading
                ? null
                : () {
                  const url = "https://mb73pr7n-3000.asse.devtunnels.ms/gallery";
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                    builder: (context) => WebViewPage(url: url),
                    ),
                  );
                  },
              backgroundColor: Colors.green.shade200,
              child: const Icon(Icons.web, size: 32),
              tooltip: "Open Gallery Web",
              ),
              const SizedBox(width: 32),
              FloatingActionButton(
              heroTag: "calculate",
              onPressed: _isCapturing || _loading
                ? null
                : () {
                  const url = "https://mb73pr7n-3000.asse.devtunnels.ms/calculate";
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                    builder: (context) => WebViewPage(url: url),
                    ),
                  );
                  },
              backgroundColor: Colors.green.shade200,
              tooltip: "Calculate",
              child: const Icon(Icons.calculate, size: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: !_cameraInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildCameraPreview(),
                SafeArea(
                  child: Column(
                    children: [
                      const Spacer(),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      _buildImagePreview(),
                      _buildResultCard(),
                      _buildActionButtons(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
