import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const SmartVideoMaker());
}

class SmartVideoMaker extends StatelessWidget {
  const SmartVideoMaker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Video Maker',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<PlatformFile> images = [];
  PlatformFile? audio;

  String format = '9:16';
  String quality = '1080p';
  int fps = 30;

  bool processing = false;

  Future<void> selectImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result.isNotEmpty) {
      setState(() {
        images = result;
      });
    }
  }

  Future<void> selectAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
    );

    if (result.isNotEmpty) {
      setState(() {
        audio = result.first;
      });
    }
  }

  void startCreation() {
    if (images.isEmpty || audio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сначала добавь картинки и озвучку',
          ),
        ),
      );
      return;
    }

    setState(() {
      processing = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Подготовка автоматического монтажа...',
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      setState(() {
        processing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Интерфейс готов. Следующим шагом подключаем настоящий монтаж.',
          ),
        ),
      );
    });
  }

  Widget choice(
    String text,
    bool selected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              vertical: 15,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Video Maker'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 15),

            const Icon(
              Icons.auto_awesome,
              size: 60,
            ),

            const SizedBox(height: 15),

            const Text(
              'Умный автоматический монтаж',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Картинки + озвучка → готовое видео',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed: selectAudio,
              icon: const Icon(Icons.mic),
              label: Text(
                audio == null
                    ? 'Добавить озвучку'
                    : audio!.name,
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(18),
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: selectImages,
              icon: const Icon(Icons.photo_library),
              label: Text(
                images.isEmpty
                    ? 'Добавить картинки'
                    : 'Картинок: ${images.length}',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(18),
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              'Формат видео',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            Row(
              children: [
                choice(
                  '9:16',
                  format == '9:16',
                  () => setState(() => format = '9:16'),
                ),
                choice(
                  '16:9',
                  format == '16:9',
                  () => setState(() => format = '16:9'),
                ),
                choice(
                  '1:1',
                  format == '1:1',
                  () => setState(() => format = '1:1'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Text(
              'Качество',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            Row(
              children: [
                choice(
                  '720p',
                  quality == '720p',
                  () => setState(() => quality = '720p'),
                ),
                choice(
                  '1080p',
                  quality == '1080p',
                  () => setState(() => quality = '1080p'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Text(
              'FPS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            Row(
              children: [
                choice(
                  '30 FPS',
                  fps == 30,
                  () => setState(() => fps = 30),
                ),
                choice(
                  '60 FPS',
                  fps == 60,
                  () => setState(() => fps = 60),
                ),
              ],
            ),

            const SizedBox(height: 35),

            ElevatedButton.icon(
              onPressed: processing ? null : startCreation,
              icon: processing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.movie_creation),
              label: Text(
                processing
                    ? 'СОЗДАНИЕ...'
                    : 'СОЗДАТЬ ВИДЕО',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
              ),
            ),

            const SizedBox(height: 20),

            if (audio != null)
              Text(
                'Озвучка: ${audio!.name}',
                textAlign: TextAlign.center,
              ),

            if (images.isNotEmpty)
              Text(
                'Выбрано изображений: ${images.length}',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
