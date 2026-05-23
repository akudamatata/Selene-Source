import 'package:flutter/material.dart';
import 'package:video_player_pip/index.dart';

void main(List<String> args) {
  runApp(const MaterialApp(home: HomeScreen()));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                'https://i1.sndcdn.com/artworks-000005011281-9brqv2-t1080x1080.jpg',
                width: 300,
                height: 300,
              ),
              const Text('Big Buck Bunny'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PlayerScreen()));
                },
                child: const Text('Play'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController _controller;
  String _debugStatus = "Starting initialization";
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    try {
      setState(() {
        _debugStatus = "Creating controller";
      });

      // Create the controller
      _controller = VideoPlayerController.network(
        'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      );

      // Initialize the PipController
      await _controller.initialize();
      await _controller.play();

      setState(() {
        _debugStatus = "Initializing VideoPlayerController";
      });

      _videoInitialized = true;
    } catch (e) {
      print(e);
      setState(() {
        _debugStatus = "Error initializing VideoPlayerController: $e";
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_debugStatus),
      ),
      body: Stack(
        children: [
          Center(
            child: _videoInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(_debugStatus),
                    ],
                  ),
          ),
          if (_videoInitialized)
            Center(
              child: IconButton(
                onPressed: () {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                  setState(() {});
                },
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _videoInitialized
          ? FloatingActionButton(
              onPressed: () {
                final aspectRatio = _controller.value.aspectRatio;
                const width = 300;
                final height = width / aspectRatio;
                _controller.enterPipMode(
                  width: width,
                  height: height.toInt(),
                );
              },
              child: const Icon(Icons.picture_in_picture),
            )
          : null,
    );
  }
}
