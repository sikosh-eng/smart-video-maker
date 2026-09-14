import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ScenePlan {
  final int imageIndex;
  final double start;
  final double end;
  final String reason;

  ScenePlan({
    required this.imageIndex,
    required this.start,
    required this.end,
    required this.reason,
  });

  factory ScenePlan.fromJson(Map<String, dynamic> json) {
    return ScenePlan(
      imageIndex: (json['image_index'] as num).toInt(),
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      reason: json['reason']?.toString() ?? '',
    );
  }
}

class AIAnalysisResult {
  final List<ScenePlan> scenes;

  AIAnalysisResult({
    required this.scenes,
  });
}

class AIAnalyzer {
  static const String model = 'gemini-3.1-flash-lite';

  static Future<AIAnalysisResult> analyze({
    required String apiKey,
    required String audioPath,
    required List<String> imagePaths,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Не указан Gemini API key');
    }

    if (imagePaths.isEmpty) {
      throw Exception('Нет изображений для анализа');
    }

    final audioFile = File(audioPath);

    if (!audioFile.existsSync()) {
      throw Exception('Аудиофайл не найден');
    }

    final audioBytes = await audioFile.readAsBytes();

    // Для первого варианта используем inline audio.
    // Google рекомендует Files API для файлов больше 20 MB.
    if (audioBytes.length > 20 * 1024 * 1024) {
      throw Exception(
        'Аудиофайл больше 20 MB. Для таких файлов '
        'подключим Gemini Files API следующим этапом.',
      );
    }

    final parts = <Map<String, dynamic>>[];

    parts.add({
      'text': '''
You are the automatic video editor.

Analyze the supplied voiceover and all supplied images.

Your task is to create a chronological visual editing plan.

IMPORTANT:
1. Understand what is being said in the voiceover.
2. Identify the important visual moments and scene changes.
3. Look at every supplied image.
4. Choose the most relevant image for each part of the narration.
5. Images may be used only when they are relevant.
6. An image can be reused if it is the best match.
7. Do not invent images that were not supplied.
8. Return start/end times in seconds.
9. The first scene must start at 0.
10. The final scene must end at approximately the end of the audio.
11. Avoid extremely short scenes. Prefer roughly 2–8 seconds when possible.
12. The image_index is ZERO-BASED:
    first supplied image = 0
    second supplied image = 1
    third supplied image = 2
    etc.

Return ONLY the requested JSON structure.
''',
    });

    final audioMime = _mimeType(audioPath);

    parts.add({
      'inlineData': {
        'mimeType': audioMime,
        'data': base64Encode(audioBytes),
      },
    });

    for (int i = 0; i < imagePaths.length; i++) {
      final file = File(imagePaths[i]);

      if (!file.existsSync()) {
        continue;
      }

      final bytes = await file.readAsBytes();

      parts.add({
        'text': 'IMAGE INDEX $i',
      });

      parts.add({
        'inlineData': {
          'mimeType': _mimeType(imagePaths[i]),
          'data': base64Encode(bytes),
        },
      });
    }

    final body = {
      'contents': [
        {
          'parts': parts,
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'object',
          'properties': {
            'scenes': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'image_index': {
                    'type': 'integer',
                  },
                  'start': {
                    'type': 'number',
                  },
                  'end': {
                    'type': 'number',
                  },
                  'reason': {
                    'type': 'string',
                  },
                },
                'required': [
                  'image_index',
                  'start',
                  'end',
                  'reason',
                ],
              },
            },
          },
          'required': [
            'scenes',
          ],
        },
      },
    };

    final response = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/'
        'models/$model:generateContent',
      ),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey.trim(),
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(
        'Gemini API error ${response.statusCode}: '
        '${response.body}',
      );
    }

    final decoded =
        jsonDecode(response.body) as Map<String, dynamic>;

    final candidates =
        decoded['candidates'] as List<dynamic>?;

    if (candidates == null || candidates.isEmpty) {
      throw Exception(
        'Gemini не вернул результат',
      );
    }

    final content =
        candidates.first['content'] as Map<String, dynamic>?;

    final responseParts =
        content?['parts'] as List<dynamic>?;

    if (responseParts == null ||
        responseParts.isEmpty) {
      throw Exception(
        'Gemini вернул пустой ответ',
      );
    }

    final text = responseParts
        .map((part) => part['text'])
        .whereType<String>()
        .join();

    if (text.trim().isEmpty) {
      throw Exception(
        'Gemini не вернул JSON',
      );
    }

    final result =
        jsonDecode(text) as Map<String, dynamic>;

    final rawScenes =
        result['scenes'] as List<dynamic>?;

    if (rawScenes == null || rawScenes.isEmpty) {
      throw Exception(
        'Gemini не создал сцены',
      );
    }

    final scenes = rawScenes
        .whereType<Map<String, dynamic>>()
        .map(ScenePlan.fromJson)
        .toList();

    _validateScenes(
      scenes,
      imagePaths.length,
    );

    return AIAnalysisResult(
      scenes: scenes,
    );
  }

  static void _validateScenes(
    List<ScenePlan> scenes,
    int imageCount,
  ) {
    if (scenes.isEmpty) {
      throw Exception('Пустой план монтажа');
    }

    for (final scene in scenes) {
      if (scene.imageIndex < 0 ||
          scene.imageIndex >= imageCount) {
        throw Exception(
          'AI выбрал несуществующее изображение: '
          '${scene.imageIndex}',
        );
      }

      if (scene.start < 0 ||
          scene.end <= scene.start) {
        throw Exception(
          'AI вернул неправильное время сцены',
        );
      }
    }

    scenes.sort(
      (a, b) => a.start.compareTo(b.start),
    );
  }

  static String _mimeType(String path) {
    final lower = path.toLowerCase();

    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }

    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }

    if (lower.endsWith('.m4a')) {
      return 'audio/mp4';
    }

    if (lower.endsWith('.aac')) {
      return 'audio/aac';
    }

    if (lower.endsWith('.ogg')) {
      return 'audio/ogg';
    }

    if (lower.endsWith('.webm')) {
      return 'audio/webm';
    }

    if (lower.endsWith('.png')) {
      return 'image/png';
    }

    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }

    return 'image/jpeg';
  }
}
