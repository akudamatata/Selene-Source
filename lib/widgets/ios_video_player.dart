import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_pip/index.dart';

class IosVideoPlayer extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final Duration? startAt;
  final VoidCallback? onReady;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onBackPressed;
  final bool live;
  final Function(bool)? onFullscreenChanged;
  final Function(VideoPlayerController) onControllerCreated;

  const IosVideoPlayer({
    super.key,
    required this.url,
    this.headers,
    this.startAt,
    this.onReady,
    this.onVideoCompleted,
    this.onBackPressed,
    this.live = false,
    this.onFullscreenChanged,
    required this.onControllerCreated,
  });

  @override
  State<IosVideoPlayer> createState() => _IosVideoPlayerState();
}

class _IosVideoPlayerState extends State<IosVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isDisposed = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isSeeking = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant IosVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposePlayer();
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers ?? const <String, String>{},
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true, mixWithOthers: true),
    );
    _controller = controller;

    widget.onControllerCreated(controller);

    try {
      await controller.initialize();
    } catch (e) {
      debugPrint("iOS VideoPlayer initialization failed: $e");
    }

    if (_isDisposed || _controller != controller) return;

    if (widget.startAt != null) {
      await controller.seekTo(widget.startAt!);
    }

    if (_isDisposed || _controller != controller) return;

    controller.addListener(_videoListener);
    
    // Auto play
    await controller.play();
    
    if (_isDisposed || _controller != controller) return;
    
    _startHideTimer();

    if (mounted) {
      setState(() {});
      widget.onReady?.call();
    }
  }

  void _videoListener() {
    if (_isDisposed) return;
    
    if (_controller?.value.position == _controller?.value.duration) {
      widget.onVideoCompleted?.call();
    }
    
    // Trigger rebuilds for progress bar if controls are visible and not seeking
    if (_controlsVisible && !_isSeeking && mounted) {
      setState(() {});
    }
  }

  void _disposePlayer() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _disposePlayer();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_controller?.value.isPlaying ?? false) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _controlsVisible = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _hideTimer?.cancel();
      setState(() {
        _controlsVisible = true;
      });
    } else {
      _controller!.play();
      _startHideTimer();
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    widget.onFullscreenChanged?.call(_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Layer
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        
        // Gesture Layer
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: _togglePlayPause,
          ),
        ),
        
        // Controls Layer
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Stack(
                children: [
                  // Top Gradient
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Bottom Gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // SafeArea for Controls
                  Positioned.fill(
                    child: SafeArea(
                      top: _isFullscreen,
                      bottom: _isFullscreen,
                      left: _isFullscreen,
                      right: _isFullscreen,
                      child: Stack(
                        children: [
                          // Back Button
                          Positioned(
                            top: 8,
                            left: 8,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () {
                                if (_isFullscreen) {
                                  _toggleFullscreen();
                                } else if (widget.onBackPressed != null) {
                                  widget.onBackPressed!();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                          ),
                          
                          // PiP Button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.picture_in_picture, color: Colors.white),
                              onPressed: () {
                                final aspectRatio = _controller!.value.aspectRatio;
                                const width = 300;
                                final height = width / aspectRatio;
                                _controller!.enterPipMode(
                                  width: width,
                                  height: height.toInt(),
                                );
                              },
                            ),
                          ),
                          
                          // Center Play/Pause
                          Center(
                            child: GestureDetector(
                              onTap: _togglePlayPause,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                          
                          // Bottom Progress Bar
                          if (!widget.live)
                            Positioned(
                              bottom: 0,
                              left: 16,
                              right: 16,
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(_controller!.value.position),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        activeTrackColor: Colors.red,
                                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                                        thumbColor: Colors.red,
                                      ),
                                      child: Slider(
                                        value: _controller!.value.position.inMilliseconds.toDouble(),
                                        min: 0.0,
                                        max: _controller!.value.duration.inMilliseconds.toDouble(),
                                        onChangeStart: (_) {
                                          _isSeeking = true;
                                          _hideTimer?.cancel();
                                        },
                                        onChanged: (value) {
                                          setState(() {
                                            _controller!.seekTo(Duration(milliseconds: value.toInt()));
                                          });
                                        },
                                        onChangeEnd: (_) {
                                          _isSeeking = false;
                                          _startHideTimer();
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDuration(_controller!.value.duration),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: Colors.white,
                                    ),
                                    onPressed: _toggleFullscreen,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
