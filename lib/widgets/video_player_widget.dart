import 'dart:async';
import 'dart:io';
import 'package:awesome_video_player/awesome_video_player.dart' as awesome;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'mobile_player_controls.dart';
import 'pc_player_controls.dart';
import 'video_player_surface.dart';

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
  final Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final Function(bool isPipMode)? onPipModeChanged;

  const VideoPlayerWidget({
    super.key,
    this.surface = VideoPlayerSurface.mobile,
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
    this.onPipModeChanged,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class VideoPlayerWidgetController {
  VideoPlayerWidgetController._(this._state);
  final _VideoPlayerWidgetState _state;

  Future<void> updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    await _state._updateDataSource(
      url,
      startAt: startAt,
      headers: headers,
    );
  }

  Future<void> seekTo(Duration position) async {
    if (_state._usesAwesomePlayer) {
      await _state._awesomeController?.seekTo(position);
      return;
    }
    await _state._player?.seek(position);
  }

  Duration? get currentPosition {
    if (_state._usesAwesomePlayer) {
      return _state._awesomeController?.videoPlayerController?.value.position;
    }
    return _state._player?.state.position;
  }

  Duration? get duration {
    if (_state._usesAwesomePlayer) {
      return _state._awesomeController?.videoPlayerController?.value.duration;
    }
    return _state._player?.state.duration;
  }

  bool get isPlaying {
    if (_state._usesAwesomePlayer) {
      return _state._awesomeController?.isPlaying() ?? false;
    }
    return _state._player?.state.playing ?? false;
  }

  Future<void> pause() async {
    if (_state._usesAwesomePlayer) {
      await _state._awesomeController?.pause();
      return;
    }
    await _state._player?.pause();
  }

  Future<void> play() async {
    if (_state._usesAwesomePlayer) {
      await _state._awesomeController?.play();
      return;
    }
    await _state._player?.play();
  }

  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  Future<void> setSpeed(double speed) async {
    await _state._setPlaybackSpeed(speed);
  }

  double get playbackSpeed => _state._playbackSpeed.value;

  Future<void> setVolume(double volume) async {
    if (_state._usesAwesomePlayer) {
      final normalizedVolume = (volume / 100).clamp(0.0, 1.0).toDouble();
      await _state._awesomeController?.setVolume(normalizedVolume);
      return;
    }
    await _state._player?.setVolume(volume);
  }

  double? get volume {
    if (_state._usesAwesomePlayer) {
      final awesomeVolume =
          _state._awesomeController?.videoPlayerController?.value.volume;
      return awesomeVolume == null ? null : awesomeVolume * 100;
    }
    return _state._player?.state.volume;
  }

  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }

  Future<void> dispose() async {
    await _state._externalDispose();
  }

  bool get isPipMode => _state._isPipMode;
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  bool get _usesAwesomePlayer => Platform.isIOS;

  Player? _player;
  VideoController? _videoController;
  awesome.BetterPlayerController? _awesomeController;
  final GlobalKey<State<StatefulWidget>> _awesomePlayerKey =
      GlobalKey<State<StatefulWidget>>();
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
  Timer? _awesomeProgressTimer;
  Duration? _pendingAwesomeStartAt;
  bool _awesomeReadyNotified = false;
  final ValueNotifier<double> _playbackSpeed = ValueNotifier<double>(1.0);
  bool _playerDisposed = false;
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
    if (!_usesAwesomePlayer) {
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
      unawaited(_updateDataSource(widget.url!));
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) {
      return;
    }
    if (_usesAwesomePlayer) {
      _initializeAwesomePlayer();
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

  void _initializeAwesomePlayer({Duration? startAt}) {
    _awesomeController = awesome.BetterPlayerController(
      awesome.BetterPlayerConfiguration(
        aspectRatio: 16 / 9,
        autoPlay: true,
        fit: BoxFit.contain,
        handleLifecycle: false,
        autoDispose: false,
        allowedScreenSleep: false,
        eventListener: _handleAwesomePlayerEvent,
        controlsConfiguration: awesome.BetterPlayerControlsConfiguration(
          controlBarColor: Colors.black.withValues(alpha: 0.75),
          iconsColor: Colors.white,
          textColor: Colors.white,
          progressBarPlayedColor: Colors.red,
          progressBarHandleColor: Colors.red,
          progressBarBufferedColor: Colors.white70,
          progressBarBackgroundColor: Colors.white38,
          enablePip: true,
          enablePlaybackSpeed: !widget.live,
          enableSkips: !widget.live,
          enableProgressText: !widget.live,
          enableProgressBar: !widget.live,
          enableProgressBarDrag: !widget.live,
          enableQualities: true,
          enableSubtitles: true,
          enableAudioTracks: true,
          enableOverflowMenu: true,
          backgroundColor: Colors.black,
          loadingColor: Colors.white,
        ),
      ),
    );
    _startAwesomeProgressTimer();
    if (_currentUrl != null) {
      unawaited(_openCurrentMedia(startAt: startAt));
    }
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    } else {
      _isInitialized = true;
    }
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_usesAwesomePlayer) {
      await _openAwesomeMedia(startAt: startAt);
      return;
    }
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }
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
      await _player!.setRate(_playbackSpeed.value);
      setState(() {
        _hasCompleted = false;
        // _isLoadingVideo = false;
      });
      // widget.onReady?.call();
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
    if (_player == null) {
      return;
    }
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
    if (_playerDisposed) {
      return;
    }
    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    if (_usesAwesomePlayer) {
      if (_awesomeController == null) {
        _initializeAwesomePlayer(startAt: startAt);
        return;
      }
      await _openAwesomeMedia(startAt: startAt);
      return;
    }

    if (_player == null) {
      await _initializePlayer();
      return;
    }

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
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
          // _isLoadingVideo = false;
        });
      }
      // widget.onReady?.call();
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
      try {
        listener();
      } catch (error) {
        debugPrint('VideoPlayerWidget: progress listener error $error');
      }
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    if (_usesAwesomePlayer) {
      await _awesomeController?.setSpeed(speed);
      return;
    }
    await _player?.setRate(speed);
  }

  Future<void> _openAwesomeMedia({Duration? startAt}) async {
    if (_playerDisposed || _awesomeController == null || _currentUrl == null) {
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingVideo = true;
      });
    } else {
      _isLoadingVideo = true;
    }
    _hasCompleted = false;
    _awesomeReadyNotified = false;
    _pendingAwesomeStartAt = startAt;

    try {
      await _awesomeController!.setupDataSource(
        awesome.BetterPlayerDataSource.network(
          _currentUrl!,
          liveStream: widget.live,
          headers: _currentHeaders ?? const <String, String>{},
          notificationConfiguration:
              const awesome.BetterPlayerNotificationConfiguration(
            showNotification: false,
          ),
        ),
      );
      await _awesomeController!.setSpeed(_playbackSpeed.value);
      await _awesomeController!.play();
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open awesome media $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      } else {
        _isLoadingVideo = false;
      }
    }
  }

  void _handleAwesomePlayerEvent(awesome.BetterPlayerEvent event) {
    final type = event.betterPlayerEventType;
    if (type == awesome.BetterPlayerEventType.initialized) {
      _handleAwesomeReady();
    } else if (type == awesome.BetterPlayerEventType.progress) {
      _notifyProgressListeners();
    } else if (type == awesome.BetterPlayerEventType.pause) {
      widget.onPause?.call();
    } else if (type == awesome.BetterPlayerEventType.finished) {
      if (!widget.live && !_hasCompleted) {
        _hasCompleted = true;
        widget.onVideoCompleted?.call();
      }
    } else if (type == awesome.BetterPlayerEventType.pipStart) {
      _setPipMode(true);
    } else if (type == awesome.BetterPlayerEventType.pipStop) {
      _setPipMode(false);
    } else if (type == awesome.BetterPlayerEventType.openFullscreen) {
      widget.onWebFullscreenChanged?.call(true);
    } else if (type == awesome.BetterPlayerEventType.hideFullscreen) {
      widget.onWebFullscreenChanged?.call(false);
      widget.onExitFullScreen?.call();
    } else if (type == awesome.BetterPlayerEventType.exception) {
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      } else {
        _isLoadingVideo = false;
      }
    }
  }

  void _handleAwesomeReady() {
    if (!mounted || _playerDisposed) {
      return;
    }
    setState(() {
      _isLoadingVideo = false;
      _hasCompleted = false;
      _isInitialized = true;
    });

    final startAt = _pendingAwesomeStartAt;
    _pendingAwesomeStartAt = null;
    if (startAt != null && startAt > Duration.zero) {
      unawaited(_awesomeController?.seekTo(startAt));
    }
    if (!_awesomeReadyNotified) {
      _awesomeReadyNotified = true;
      widget.onReady?.call();
    }
  }

  void _startAwesomeProgressTimer() {
    _awesomeProgressTimer?.cancel();
    _awesomeProgressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_playerDisposed && _awesomeController != null) {
        _notifyProgressListeners();
      }
    });
  }

  void _setPipMode(bool isPipMode) {
    if (mounted) {
      setState(() {
        _isPipMode = isPipMode;
      });
    } else {
      _isPipMode = isPipMode;
    }
    widget.onPipModeChanged?.call(isPipMode);
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  void _setupPip() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
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
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _pip.registerStateChangedObserver(PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        if (!mounted) return;
        switch (state) {
          case PipState.pipStateStarted:
            debugPrint('PiP started successfully');
            if (mounted) {
              setState(() => _isPipMode = true);
              widget.onPipModeChanged?.call(true);
            }
            break;
          case PipState.pipStateStopped:
            debugPrint('PiP stopped');
            if (mounted) {
              setState(() {
                _isPipMode = false;
              });
              widget.onPipModeChanged?.call(false);
            }
            break;
          case PipState.pipStateFailed:
            debugPrint('PiP failed: $error');
            if (mounted) {
              setState(() => _isPipMode = false);
              widget.onPipModeChanged?.call(false);
            }
            break;
        }
      },
    ));
  }

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    try {
      if (_usesAwesomePlayer) {
        await _awesomeController?.play();
        await _awesomeController?.enablePictureInPicture(_awesomePlayerKey);
        return;
      }
      var support = await _pip.isSupported();
      if (!support) {
        debugPrint('Device does not support PiP!');
        return;
      }
      await _player?.play();
      await _pip.start();
    } catch (e) {
      debugPrint('Failed to enter PiP mode: $e');
      _setupPip();
    }
  }

  Future<void> _externalDispose() async {
    if (!mounted || _playerDisposed) {
      return;
    }
    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _playerDisposed = true;
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();
    _awesomeProgressTimer?.cancel();
    _progressListeners.clear();
    _awesomeController?.removeEventsListener(_handleAwesomePlayerEvent);
    _awesomeController?.dispose(forceDispose: true);
    _awesomeController = null;
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_usesAwesomePlayer && Platform.isAndroid) {
      _pip.unregisterStateChangedObserver();
      _pip.dispose();
    }
    _disposePlayer();
    _playbackSpeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_usesAwesomePlayer) {
      return _buildAwesomePlayer();
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

  Widget _buildAwesomePlayer() {
    return Container(
      color: Colors.black,
      child: _isInitialized && _awesomeController != null
          ? Stack(
              children: [
                Positioned.fill(
                  child: awesome.BetterPlayer(
                    key: _awesomePlayerKey,
                    controller: _awesomeController!,
                  ),
                ),
                if (_isLoadingVideo)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: SafeArea(
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: widget.onBackPressed,
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }
}
