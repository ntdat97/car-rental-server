import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';

class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  final env = DotEnv()..load();
  final String apiUrl = 'https://api.imgbb.com/1/upload';

  Future<String?> uploadImage(String base64Image) async {
    try {
      // You should store this in your .env file
      final apiKey = env['IMGBB_API_KEY'] ??
          (() => throw StateError(
              'IMGBB_API_KEY not found in environment variables'))();

      // Remove data URI prefix if present
      final String imageData =
          base64Image.contains(',') ? base64Image.split(',')[1] : base64Image;

      final response = await http.post(
        Uri.parse('$apiUrl?key=$apiKey'),
        body: {
          'image': imageData,
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          // Return the direct image URL
          return responseData['data']['url'];
        }
      }

      print('Failed to upload image: ${response.body}');
      return null;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }
}

final imageService = ImageService();
