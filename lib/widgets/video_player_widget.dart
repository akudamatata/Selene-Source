import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'package:video_player_pip/index.dart';
import 'mobile_player_controls.dart';
import 'pc_player_controls.dart';
import 'video_player_surface.dart';
import 'ios_video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerSurface surface;
  final String? url;
  final Map<String, String>? headers;
  final VoidCallback? onBackPressed;
  final Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final Function(bool)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;

  const VideoPlayerWidget({
    super.key,
    this.surface = VideoPlayerSurface.desktop,
    this.url,
    this.headers,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onNextEpisode,
    this.onVideoCompleted,
    this.onPause,
    this.isLastEpisode = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
    this.onWebFullscreenChanged,
    this.onExitFullScreen,
    this.live = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class VideoPlayerWidgetController {
  final _VideoPlayerWidgetState _state;

  VideoPlayerWidgetController._(this._state);

  Future<void> pause() async {
    if (_state._usesIosPlayer) {
      await _state._iosController?.pause();
      return;
    }
    await _state._player?.pause();
  }

  Future<void> play() async {
    if (_state._usesIosPlayer) {
      await _state._iosController?.play();
      return;
    }
    await _state._player?.play();
  }

  Future<void> seekTo(Duration position) async {
    if (_state._usesIosPlayer) {
      await _state._iosController?.seekTo(position);
      return;
    }
    await _state._player?.seek(position);
  }

  Duration? get position {
    if (_state._usesIosPlayer) {
      return _state._iosController?.value.position;
    }
    return _state._player?.state.position;
  }

  Duration? get currentPosition => position;

  Duration? get duration {
    if (_state._usesIosPlayer) {
      return _state._iosController?.value.duration;
    }
    return _state._player?.state.duration;
  }

  bool get isPlaying {
    if (_state._usesIosPlayer) {
      return _state._iosController?.value.isPlaying ?? false;
    }
    return _state._player?.state.playing ?? false;
  }

  Future<void> setVolume(double volume) async {
    final normalizedVolume = volume.clamp(0.0, 100.0);
    if (_state._usesIosPlayer) {
      await _state._iosController?.setVolume(normalizedVolume / 100.0);
      return;
    }
    await _state._player?.setVolume(normalizedVolume);
  }

  double? get volume {
    if (_state._usesIosPlayer) {
      final vol = _state._iosController?.value.volume;
      return vol == null ? null : vol * 100;
    }
    return _state._player?.state.volume;
  }

  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }

  Future<void> dispose() async {
    await _state._externalDispose();
  }
  
  Future<void> updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    await _state._updateDataSource(url, startAt: startAt, headers: headers);
  }

  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  bool get isPipMode => _state._isPipMode;
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  bool get _usesIosPlayer => Platform.isIOS;

  Player? _player;
  VideoController? _videoController;
  VideoPlayerController? _iosController;
  
  bool _isInitialized = false;
  bool _hasCompleted = false;
  bool _isLoadingVideo = false;
  String? _currentUrl;
  Map<String, String>? _currentHeaders;
  final List<VoidCallback> _progressListeners = [];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  
  final ValueNotifier<double> _playbackSpeed = ValueNotifier<double>(1.0);
  bool _playerDisposed = false;
  int _updateSessionId = 0;
  VoidCallback? _exitWebFullscreenCallback;
  final Pip _pip = Pip();
  bool _isPipMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    if (!_usesIosPlayer) {
      _setupPip();
      _registerPipObserver();
    }
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headers != oldWidget.headers && widget.headers != null) {
      _currentHeaders = widget.headers;
    }
    if (widget.url != oldWidget.url && widget.url != null) {
      _updateDataSource(widget.url!);
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) return;
    
    if (_usesIosPlayer) {
      setState(() {
        _isInitialized = true;
      });
      return;
    }
    
    _player = Player();
    _videoController = VideoController(_player!);
    _setupPlayerListeners();
    if (_currentUrl != null) {
      await _openCurrentMedia();
    }
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_usesIosPlayer) return; // ios player handles its own open
    
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }
    final sessionId = ++_updateSessionId;
    setState(() {
      _isLoadingVideo = true;
    });
    try {
      await _player!.open(
        Media(
          _currentUrl!,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      if (_playerDisposed || _player == null || _updateSessionId != sessionId) return;
      await _player!.setRate(_playbackSpeed.value);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
        });
      }
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open media $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _setupPlayerListeners() {
    if (_player == null) return;
    
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();

    _positionSubscription = _player!.stream.position.listen((_) {
      _notifyProgressListeners();
    });

    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (!mounted) return;
      if (!playing) {
        setState(() {
          _hasCompleted = false;
        });
        _pip.setup(const PipOptions(
          autoEnterEnabled: false,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      } else {
        _pip.setup(const PipOptions(
          autoEnterEnabled: true,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      }
    });

    if (!widget.live) {
      _completedSubscription = _player!.stream.completed.listen((completed) {
        if (!mounted) return;
        if (completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onVideoCompleted?.call();
        }
      });
    }

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (!mounted) return;
      if (duration != Duration.zero) {
        if (_isLoadingVideo) {
          setState(() {
            _isLoadingVideo = false;
          });
        }
        widget.onReady?.call();
      }
    });
  }

  Future<void> _updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    if (_playerDisposed) return;
    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    if (_usesIosPlayer) {
      setState(() {}); // IosVideoPlayer handles didUpdateWidget
      return;
    }

    if (_player == null) {
      await _initializePlayer();
      return;
    }

    final sessionId = ++_updateSessionId;
    setState(() {
      _isLoadingVideo = true;
    });

    try {
      final currentSpeed = _player!.state.rate;
      await _player!.open(
        Media(
          url,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      if (_playerDisposed || _player == null || _updateSessionId != sessionId) return;
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
        });
      }
    } catch (error) {
      debugPrint('VideoPlayerWidget: error while changing source $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  void _notifyProgressListeners() {
    for (final listener in List<VoidCallback>.from(_progressListeners)) {
      listener();
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    if (_usesIosPlayer) {
      await _iosController?.setPlaybackSpeed(speed);
      return;
    }
    if (_player != null) {
      await _player!.setRate(speed);
    }
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  Future<void> _externalDispose() async {
    _disposePlayer();
  }

  void _setupPip() {
    _pip.setup(const PipOptions(
      autoEnterEnabled: true,
      aspectRatioX: 16,
      aspectRatioY: 9,
      preferredContentWidth: 480,
      preferredContentHeight: 270,
      controlStyle: 2,
    ));
  }

  void _registerPipObserver() {
    _pip.registerStateChangedObserver(PipStateChangedObserver(
      onPipStateChanged: (PipState state, String? error) {
        if (!mounted) return;
        setState(() {
          _isPipMode = state == PipState.pipStateStarted;
        });
        debugPrint("Pip mode changed: ${state == PipState.pipStateStarted}");
      },
    ));
  }

  Future<void> _enterPipMode() async {
    if (_usesIosPlayer) {
      // Handled internally by IosVideoPlayer
      return;
    }
    
    if (Platform.isAndroid) {
      final pipAvailable = await _pip.isSupported();
      if (pipAvailable) {
        debugPrint('Entering pip mode');
        _pip.start();
      } else {
        debugPrint('Pip mode is not supported');
      }
    }
  }

  void _disposePlayer() {
    _playerDisposed = true;
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();
    _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null && _iosController == null) {
      return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_usesIosPlayer && Platform.isAndroid) {
      _pip.unregisterStateChangedObserver();
      _pip.dispose();
    }
    _disposePlayer();
    _playbackSpeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_usesIosPlayer) {
      return Container(
        color: Colors.black,
        child: IosVideoPlayer(
          url: _currentUrl ?? '',
          headers: _currentHeaders,
          live: widget.live,
          onBackPressed: widget.onBackPressed,
          onReady: widget.onReady,
          onVideoCompleted: widget.onVideoCompleted,
          onFullscreenChanged: widget.onWebFullscreenChanged,
          onControllerCreated: (controller) {
            _iosController = controller;
            _addProgressListener(() {
               if (mounted) setState(() {});
            });
            controller.addListener(() {
               _notifyProgressListeners();
            });
          },
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? Video(
              controller: _videoController!,
              controls: (state) {
                return widget.surface == VideoPlayerSurface.desktop
                    ? PCPlayerControls(
                        state: state,
                        player: _player!,
                        onBackPressed: widget.onBackPressed,
                        onNextEpisode: widget.onNextEpisode,
                        onPause: widget.onPause,
                        videoUrl: _currentUrl ?? '',
                        isLastEpisode: widget.isLastEpisode,
                        isLoadingVideo: _isLoadingVideo,
                        onCastStarted: widget.onCastStarted,
                        videoTitle: widget.videoTitle,
                        currentEpisodeIndex: widget.currentEpisodeIndex,
                        totalEpisodes: widget.totalEpisodes,
                        sourceName: widget.sourceName,
                        onWebFullscreenChanged: widget.onWebFullscreenChanged,
                        onExitWebFullscreenCallbackReady: (callback) {
                          _exitWebFullscreenCallback = callback;
                        },
                        onExitFullScreen: widget.onExitFullScreen,
                        live: widget.live,
                        playbackSpeedListenable: _playbackSpeed,
                        onSetSpeed: _setPlaybackSpeed,
                      )
                    : MobilePlayerControls(
                        player: _player!,
                        state: state,
                        onControlsVisibilityChanged: (_) {},
                        onBackPressed: widget.onBackPressed,
                        onFullscreenChange: (_) {},
                        onNextEpisode: widget.onNextEpisode,
                        onPause: widget.onPause,
                        videoUrl: _currentUrl ?? '',
                        isLastEpisode: widget.isLastEpisode,
                        isLoadingVideo: _isLoadingVideo,
                        onCastStarted: widget.onCastStarted,
                        videoTitle: widget.videoTitle,
                        currentEpisodeIndex: widget.currentEpisodeIndex,
                        totalEpisodes: widget.totalEpisodes,
                        sourceName: widget.sourceName,
                        onExitFullScreen: widget.onExitFullScreen,
                        live: widget.live,
                        playbackSpeedListenable: _playbackSpeed,
                        onSetSpeed: _setPlaybackSpeed,
                        onEnterPipMode: _enterPipMode,
                        isPipMode: _isPipMode,
                      );
              },
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }
}
