import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:path_provider/path_provider.dart';

class VideoEngine {
  /// Получает длительность аудио в секундах.
  static Future<double> getAudioDuration(String audioPath) async {
    final session =
        await FFprobeKit.getMediaInformation(audioPath);

    final information = await session.getMediaInformation();

    if (information == null) {
      throw Exception('Не удалось определить длительность аудио');
    }

    final duration =
        double.tryParse(information.getDuration() ?? '');

    if (duration == null || duration <= 0) {
      throw Exception('Длительность аудио не определена');
    }

    return duration;
  }

  /// Создаёт список длительностей для картинок.
  ///
  /// Длительности специально немного отличаются,
  /// чтобы все изображения не стояли одинаковое время.
  static List<double> calculateDurations(
    double audioDuration,
    int imageCount,
  ) {
    if (imageCount <= 0) {
      throw Exception('Нет изображений');
    }

    final average = audioDuration / imageCount;

    final durations = <double>[];

    for (int i = 0; i < imageCount; i++) {
      double multiplier;

      switch (i % 5) {
        case 0:
          multiplier = 0.82;
          break;
        case 1:
          multiplier = 1.12;
          break;
        case 2:
          multiplier = 0.94;
          break;
        case 3:
          multiplier = 1.18;
          break;
        default:
          multiplier = 0.91;
      }

      durations.add(
        max(0.8, average * multiplier),
      );
    }

    final currentTotal =
        durations.fold<double>(0, (a, b) => a + b);

    final correction =
        audioDuration / currentTotal;

    return durations
        .map((d) => d * correction)
        .toList();
  }

  /// Создаёт видео из изображений и озвучки.
  static Future<String> createVideo({
    required List<String> imagePaths,
    required String audioPath,
    required String format,
    required String quality,
    required int fps,
  }) async {
    if (imagePaths.isEmpty) {
      throw Exception('Не выбраны изображения');
    }

    final audioDuration =
        await getAudioDuration(audioPath);

    final durations = calculateDurations(
      audioDuration,
      imagePaths.length,
    );

    final tempDirectory =
        await getTemporaryDirectory();

    final workDirectory = Directory(
      '${tempDirectory.path}/smart_video',
    );

    if (workDirectory.existsSync()) {
      await workDirectory.delete(
        recursive: true,
      );
    }

    await workDirectory.create(
      recursive: true,
    );

    final segmentFiles = <String>[];

    for (int i = 0; i < imagePaths.length; i++) {
      final output =
          '${workDirectory.path}/segment_$i.mp4';

      final size = _getVideoSize(format, quality);

      final command = [
        '-y',
        '-loop',
        '1',
        '-i',
        _quote(imagePaths[i]),
        '-t',
        durations[i].toStringAsFixed(3),
        '-vf',
        'scale=${size.width}:${size.height}:force_original_aspect_ratio=decrease,'
            'pad=${size.width}:${size.height}:(ow-iw)/2:(oh-ih)/2',
        '-r',
        '$fps',
        '-c:v',
        'mpeg4',
        '-q:v',
        '4',
        '-pix_fmt',
        'yuv420p',
        _quote(output),
      ].join(' ');

      final session =
          await FFmpegKit.execute(command);

      final returnCode =
          await session.getReturnCode();

      if (returnCode == null ||
          !returnCode.isValueSuccess()) {
        throw Exception(
          'Ошибка создания изображения ${i + 1}',
        );
      }

      segmentFiles.add(output);
    }

    final concatFile =
        '${workDirectory.path}/concat.txt';

    final concatContent = segmentFiles
        .map((path) => "file '${path.replaceAll("'", "'\\''")}'")
        .join('\n');

    await File(concatFile).writeAsString(
      concatContent,
    );

    final silentVideo =
        '${workDirectory.path}/silent.mp4';

    final concatCommand = [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      _quote(concatFile),
      '-c',
      'copy',
      _quote(silentVideo),
    ].join(' ');

    final concatSession =
        await FFmpegKit.execute(concatCommand);

    final concatReturnCode =
        await concatSession.getReturnCode();

    if (concatReturnCode == null ||
        !concatReturnCode.isValueSuccess()) {
      throw Exception(
        'Не удалось объединить изображения',
      );
    }

    final outputDirectory =
        await getApplicationDocumentsDirectory();

    final outputPath =
        '${outputDirectory.path}/smart_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final finalCommand = [
      '-y',
      '-i',
      _quote(silentVideo),
      '-i',
      _quote(audioPath),
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-shortest',
      _quote(outputPath),
    ].join(' ');

    final finalSession =
        await FFmpegKit.execute(finalCommand);

    final finalReturnCode =
        await finalSession.getReturnCode();

    if (finalReturnCode == null ||
        !finalReturnCode.isValueSuccess()) {
      throw Exception(
        'Не удалось добавить озвучку',
      );
    }

    return outputPath;
  }

  static String _quote(String path) {
    return '"${path.replaceAll('"', '\\"')}"';
  }

  static _VideoSize _getVideoSize(
    String format,
    String quality,
  ) {
    final height = quality == '720p' ? 720 : 1080;

    if (format == '9:16') {
      return _VideoSize(
        (height * 9 / 16).round(),
        height,
      );
    }

    if (format == '1:1') {
      return _VideoSize(
        height,
        height,
      );
    }

    return _VideoSize(
      (height * 16 / 9).round(),
      height,
    );
  }
}

class _VideoSize {
  final int width;
  final int height;

  _VideoSize(this.width, this.height);
}
