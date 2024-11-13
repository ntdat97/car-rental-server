import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import 'package:image/image.dart' as img;

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

  Future<List<String>> uploadMultipleImages(List<String> base64Images) async {
    final List<String> uploadedUrls = [];
    final List<String> failedUploads = [];

    final results = await Future.wait(
      base64Images.map((base64Image) async {
        try {
          final imageUrl = await uploadImage(base64Image);
          if (imageUrl != null) {
            return {'success': true, 'url': imageUrl};
          } else {
            return {'success': false, 'base64': base64Image};
          }
        } catch (e) {
          print('Error uploading individual image: $e');
          return {'success': false, 'base64': base64Image};
        }
      }),
      eagerError: false
    );

    for (final result in results) {
      if (result['success'] == true) {
        uploadedUrls.add(result['url'] as String);
      } else {
        failedUploads.add(result['base64'] as String);
      }
    }

    if (failedUploads.isNotEmpty) {
      print('Some images failed to upload: ${failedUploads.length}');
    }

    return uploadedUrls;
  }

  Future<String?> uploadCompressedImage(
    String base64Image, {
    required int maxWidth,
    required int maxHeight,
    required int quality,
  }) async {
    try {
      final bytes = base64Decode(base64Image);
      
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      
      final aspectRatio = image.width / image.height;
      int newWidth = maxWidth;
      int newHeight = (maxWidth / aspectRatio).round();
      
      if (newHeight > maxHeight) {
        newHeight = maxHeight;
        newWidth = (maxHeight * aspectRatio).round();
      }
      
      final resized = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear
      );
      
      final compressed = img.encodeJpg(resized, quality: quality);
      
      final compressedBase64 = base64Encode(compressed);
      
      final url = await uploadImage(compressedBase64);
      
      return url;
    } catch (e) {
      print('Error compressing image: $e');
      return null;
    }
  }
}

final imageService = ImageService();
