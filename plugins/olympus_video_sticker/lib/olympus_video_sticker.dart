import 'package:flutter/services.dart';

class OlympusVideoSticker {
  static const MethodChannel _channel = MethodChannel('olympus/video_sticker');

  static Future<String> prepare({
    required String path,
    required int startSeconds,
    required int durationSeconds,
  }) async {
    final outputPath = await _channel.invokeMethod<String>('prepare', {
      'path': path,
      'startSeconds': startSeconds,
      'durationSeconds': durationSeconds,
    });
    if (outputPath == null || outputPath.trim().isEmpty) {
      throw PlatformException(
        code: 'empty_output',
        message: 'O iPhone não retornou o vídeo preparado.',
      );
    }
    return outputPath;
  }
}
