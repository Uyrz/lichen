import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

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
      title: 'Camera + Upload',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Camera Inference + Location'),
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
      debugPrint("✅ Camera initialized successfully");
    } catch (e) {
      debugPrint("‼️ Camera initialization error: $e");
    }
  }

  Future<void> _takePicture() async {
    if (_isCapturing || !_controller.value.isInitialized) return;
    _isCapturing = true;
    try {
      final XFile image = await _controller.takePicture();
      debugPrint("📸 Picture taken: ${image.path}");
      setState(() {
        _imagePath = image.path;
      });
      await _runInferenceAndUpload(image.path);
    } catch (e) {
      debugPrint('‼️ Error taking picture: $e');
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      debugPrint("🖼️ Image picked from gallery: ${image.path}");
      setState(() {
        _imagePath = image.path;
      });
      await _runInferenceAndUpload(image.path);
    } else {
      debugPrint("⚠️ No image selected.");
    }
  }

  Future<void> _runInferenceAndUpload(String imagePath) async {
    debugPrint("🚀 Starting inference for: $imagePath");

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
      debugPrint("🗂️ File exists: ${await file.exists()}");

      var request = http.MultipartRequest("POST", url)
        ..headers.addAll(headers)
        ..fields.addAll(data)
        ..files.add(await http.MultipartFile.fromPath("file", file.path));

      debugPrint("📤 Sending inference request...");
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      debugPrint("📥 Inference response: ${response.statusCode}");
      debugPrint("📥 Response body: $responseBody");

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

      debugPrint("🔍 Inference result: $resultText");
      _showResult(resultText);
      await _uploadToServer(imagePath, resultText);
    } catch (e, stackTrace) {
      debugPrint("‼️ Inference error: $e");
      debugPrint("📋 Stack trace:\n$stackTrace");
    }
  }

  Future<void> _uploadToServer(String imagePath, String result) async {
    debugPrint("🚀 Starting upload process...");
    debugPrint("🖼️ Image path: $imagePath");
    debugPrint("📄 Result: $result");

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint("❌ Image file does not exist. Aborting.");
        return;
      }

      Position position = await _getCurrentPosition();
      debugPrint("📍 Location - Lat: ${position.latitude}, Lon: ${position.longitude}");

      final url = Uri.parse("https://mb73pr7n-3000.asse.devtunnels.ms/upload");

      var request = http.MultipartRequest('POST', url)
        ..fields['result'] = result
        ..fields['latitude'] = position.latitude.toString()
        ..fields['longitude'] = position.longitude.toString()
        ..files.add(await http.MultipartFile.fromPath('image', imagePath));

      debugPrint("📤 Sending upload request...");
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      debugPrint("📥 Upload response status: ${response.statusCode}");
      debugPrint("📥 Upload response body: $responseBody");

      if (response.statusCode == 200) {
        debugPrint("✅ Upload successful.");
      } else {
        debugPrint("❌ Upload failed with status ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      debugPrint("‼️ Upload error: $e");
      debugPrint("📋 Stack trace:\n$stackTrace");
    }
  }

  Future<Position> _getCurrentPosition() async {
    debugPrint("📡 Checking location permission...");
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

    Position position = await Geolocator.getCurrentPosition();
    debugPrint("📍 Location retrieved: ${position.latitude}, ${position.longitude}");
    return position;
  }

  void _showResult(String result) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Prediction Result"),
        content: Text(result),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"))
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: !_cameraInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(child: CameraPreview(_controller)),
                Positioned(
                  bottom: 40,
                  left: MediaQuery.of(context).size.width / 2 - 70,
                  child: Row(
                    children: [
                      FloatingActionButton(
                        onPressed: _takePicture,
                        child: const Icon(Icons.camera),
                      ),
                      const SizedBox(width: 20),
                      FloatingActionButton(
                        onPressed: _pickImage,
                        child: const Icon(Icons.photo_library),
                      ),
                    ],
                  ),
                ),
                if (_imagePath != null)
                  Positioned(
                    bottom: 40,
                    right: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_imagePath!),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
