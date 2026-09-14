import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_analyzer.dart';

class VideoEngine {
  static Future<double> getAudioDuration(String audioPath) async {
    final session =
        await FFprobeKit.getMediaInformation(audioPath);

    final information =
        await session.getMediaInformation();

    if (information == null) {
      throw Exception(
        'Не удалось определить длительность аудио',
      );
    }

    final duration =
        double.tryParse(information.getDuration() ?? '');

    if (duration == null || duration <= 0) {
      throw Exception(
        'Длительность аудио не определена',
      );
    }

    return duration;
  }

  // Старый автоматический режим.
  static List<double> calculateDurations(
    double audioDuration,
    int imageCount,
  ) {
    if (imageCount <= 0) {
      throw Exception('Нет изображений');
    }

    final average =
        audioDuration / imageCount;

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
        durations.fold<double>(
      0,
      (a, b) => a + b,
    );

    final correction =
        audioDuration / currentTotal;

    return durations
        .map((d) => d * correction)
        .toList();
  }

  // НОВЫЙ РЕЖИМ:
  // AI выбирает картинку и точную длительность каждой сцены.
  static Future<String> createVideoFromScenes({
    required List<String> imagePaths,
    required String audioPath,
    required List<ScenePlan> scenes,
    required String format,
    required String quality,
    required int fps,
  }) async {
    if (imagePaths.isEmpty) {
      throw Exception('Нет изображений');
    }

    if (scenes.isEmpty) {
      throw Exception('AI не создал план сцен');
    }

    // Получаем настоящую длину озвучки.
    final audioDuration =
        await getAudioDuration(audioPath);

    // Сортируем сцены по времени.
    final sortedScenes =
        List<ScenePlan>.from(scenes)
          ..sort(
            (a, b) =>
                a.start.compareTo(b.start),
          );

    // Вычисляем длительность каждой AI-сцены.
    final rawDurations = <double>[];

    for (final scene in sortedScenes) {
      final duration =
          scene.end - scene.start;

      if (duration <= 0) {
        continue;
      }

      rawDurations.add(
        max(0.3, duration),
      );
    }

    if (rawDurations.isEmpty) {
      throw Exception(
        'AI создал некорректные длительности сцен',
      );
    }

    // Нормализуем длительности так,
    // чтобы видео точно совпало с озвучкой.
    final rawTotal =
        rawDurations.fold<double>(
      0,
      (a, b) => a + b,
    );

    final correction =
        audioDuration / rawTotal;

    final durations =
        rawDurations
            .map(
              (duration) =>
                  duration * correction,
            )
            .toList();

    final tempDirectory =
        await getTemporaryDirectory();

    final workDirectory = Directory(
      '${tempDirectory.path}/smart_video_ai',
    );

    if (workDirectory.existsSync()) {
      await workDirectory.delete(
        recursive: true,
      );
    }

    await workDirectory.create(
      recursive: true,
    );

    final size =
        _getVideoSize(format, quality);

    final segmentFiles = <String>[];

    int sceneNumber = 0;

    for (int i = 0;
        i < sortedScenes.length;
        i++) {
      final scene = sortedScenes[i];

      if (scene.imageIndex < 0 ||
          scene.imageIndex >= imagePaths.length) {
        continue;
      }

      if (sceneNumber >= durations.length) {
        break;
      }

      final imagePath =
          imagePaths[scene.imageIndex];

      final duration =
          durations[sceneNumber];

      final output =
          '${workDirectory.path}/scene_$sceneNumber.mp4';

      final command = [
        '-y',
        '-loop',
        '1',
        '-i',
        _quote(imagePath),
        '-t',
        duration.toStringAsFixed(3),
        '-vf',
        'scale=${size.width}:${size.height}:'
            'force_original_aspect_ratio=decrease,'
            'pad=${size.width}:${size.height}:'
            '(ow-iw)/2:(oh-ih)/2',
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
          await FFmpegKit.execute(
        command,
      );

      final returnCode =
          await session.getReturnCode();

      if (returnCode == null ||
          !returnCode.isValueSuccess()) {
        throw Exception(
          'Ошибка создания AI-сцены '
          '${sceneNumber + 1}',
        );
      }

      segmentFiles.add(output);

      sceneNumber++;
    }

    if (segmentFiles.isEmpty) {
      throw Exception(
        'Не удалось создать ни одной сцены',
      );
    }

    // Создаём файл для объединения сцен.
    final concatFile =
        '${workDirectory.path}/concat.txt';

    final concatContent =
        segmentFiles
            .map(
              (path) =>
                  "file '${path.replaceAll(
                    "'",
                    "'\\''",
                  )}'",
            )
            .join('\n');

    await File(concatFile).writeAsString(
      concatContent,
    );

    // Объединяем все AI-сцены.
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
        await FFmpegKit.execute(
      concatCommand,
    );

    final concatReturnCode =
        await concatSession.getReturnCode();

    if (concatReturnCode == null ||
        !concatReturnCode.isValueSuccess()) {
      throw Exception(
        'Не удалось объединить AI-сцены',
      );
    }

    // Финальный MP4.
    final outputDirectory =
        await getApplicationDocumentsDirectory();

    final outputPath =
        '${outputDirectory.path}/'
        'smart_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

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
        await FFmpegKit.execute(
      finalCommand,
    );

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

    final durations =
        calculateDurations(
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

    for (int i = 0;
        i < imagePaths.length;
        i++) {
      final output =
          '${workDirectory.path}/segment_$i.mp4';

      final size =
          _getVideoSize(
        format,
        quality,
      );

      final command = [
        '-y',
        '-loop',
        '1',
        '-i',
        _quote(imagePaths[i]),
        '-t',
        durations[i].toStringAsFixed(3),
        '-vf',
        'scale=${size.width}:${size.height}:'
            'force_original_aspect_ratio=decrease,'
            'pad=${size.width}:${size.height}:'
            '(ow-iw)/2:(oh-ih)/2',
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
          await FFmpegKit.execute(
        command,
      );

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

    final concatContent =
        segmentFiles
            .map(
              (path) =>
                  "file '${path.replaceAll(
                    "'",
                    "'\\''",
                  )}'",
            )
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
        await FFmpegKit.execute(
      concatCommand,
    );

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
        '${outputDirectory.path}/'
        'smart_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

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
        await FFmpegKit.execute(
      finalCommand,
    );

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
    final height =
        quality == '720p'
            ? 720
            : 1080;

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

  _VideoSize(
    this.width,
    this.height,
  );
}ц
