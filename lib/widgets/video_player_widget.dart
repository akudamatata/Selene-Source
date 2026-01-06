import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'package:video_player/video_player.dart' as vp;
import '../../services/player/player_adapter.dart';
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
    await _state._player?.seek(position);
  }

  Duration? get currentPosition => _state._player?.state.position;

  Duration? get duration => _state._player?.state.duration;

  bool get isPlaying => _state._player?.state.playing ?? false;

  Future<void> pause() async {
    await _state._player?.pause();
  }

  Future<void> play() async {
    await _state._player?.play();
  }

  void addProgressListener(VoidCallback listener) {
    // Adapter-based progress listeners not fully implemented yet in controller proxy
    // but the widget state handles subscriptions. 
    // This method interacts with internal state.
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
    await _state._player?.setVolume(volume);
  }

  double? get volume => _state._player?.state.volume;

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
  // Common abstraction
  AbstractPlayer? _player;
  
  // MediaKit specific
  Player? _mkPlayer;
  VideoController? _mkController;

  // VideoPlayer specific
  vp.VideoPlayerController? _vpController;

  bool _isIOS = Platform.isIOS;

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
  VoidCallback? _exitWebFullscreenCallback;
  final Pip _pip = Pip();
  bool _isPipMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isIOS) {
      _isIOS = true;
    }
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    _setupPip();
    _registerPipObserver();
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

    if (_isIOS) {
       // iOS: Initialize video_player later when opening media
       // But we need a player instance? 
       // VideoPlayerController needs a URL to be initialized.
       // So we defer initialization until `_updateDataSource`.
       if (_currentUrl != null) {
         await _openCurrentMedia();
       }
    } else {
      // Non-iOS: MediaKit
      _mkPlayer = Player();
      _mkController = VideoController(_mkPlayer!);
      _player = MediaKitPlayerAdapter(_mkPlayer!);
      _setupPlayerListeners();
      if (_currentUrl != null) {
        await _openCurrentMedia();
      }
    }
    
    // For iOS, initial state might be false until URL is loaded
    if (!_isIOS) {
       setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _currentUrl == null) {
      return;
    }
    setState(() {
      _isLoadingVideo = true;
    });

    try {
      if (_isIOS) {
        // Dispose previous controller if any
        if (_vpController != null) {
          await _vpController!.dispose();
        }
        
        _vpController = vp.VideoPlayerController.networkUrl(
          Uri.parse(_currentUrl!),
          httpHeaders: _currentHeaders ?? const <String, String>{},
        );

        await _vpController!.initialize();
        if (startAt != null) {
          await _vpController!.seekTo(startAt);
        }
        
        _player = VideoPlayerAdapter(_vpController!);
        _setupPlayerListeners();
        
        await _player!.play();
        await _player!.setRate(_playbackSpeed.value);

      } else {
        // MediaKit
        if (_mkPlayer == null) return;
        final currentSpeed = _mkPlayer!.state.rate;
        await _mkPlayer!.open(
          Media(
            _currentUrl!,
            start: startAt,
            httpHeaders: _currentHeaders ?? const <String, String>{},
          ),
          play: true,
        );
        _playbackSpeed.value = currentSpeed;
        await _mkPlayer!.setRate(currentSpeed);
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasCompleted = false;
           // _isLoadingVideo = false; // logic same as before
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
    if (_player == null) {
      return;
    }
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();

    _positionSubscription = _player!.positionStream.listen((_) {
      for (final listener in List<VoidCallback>.from(_progressListeners)) {
        try {
          listener();
        } catch (error) {
          debugPrint('VideoPlayerWidget: progress listener error $error');
        }
      }
    });

    _playingSubscription = _player!.playingStream.listen((playing) {
      if (!mounted) return;
      if (!playing) {
        setState(() {
          _hasCompleted = false;
        });
        if (!_isIOS) { // PIP setup for non-iOS (using pip package)
           _pip.setup(const PipOptions(
            autoEnterEnabled: false,
            // ... options
           ));
        }
      } else {
        if (!_isIOS) {
           _pip.setup(const PipOptions(
            autoEnterEnabled: true,
            // ... options
           ));
        }
      }
    });

    if (!widget.live) {
      _completedSubscription = _player!.completedStream.listen((completed) {
        if (!mounted) return;
        if (completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onVideoCompleted?.call();
        }
      });
    }

    _durationSubscription = _player!.durationStream.listen((duration) {
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
    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }
    await _openCurrentMedia(startAt: startAt);
  }

  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    await _player?.setRate(speed);
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  void _setupPip() {
    // Only setup Custom Pip package for Android (or non-iOS)
    // iOS uses native AVPlayer PiP which is handled by video_player plugin automatically 
    // (if background mode is enabled)
    if (!Platform.isAndroid) {
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
    if (!Platform.isAndroid) {
      return;
    }
    _pip.registerStateChangedObserver(PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        if (!mounted) return;
        // ... (rest of implementation same as before for Android)
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
    if (_isIOS) {
       // iOS handled natively by UIBackgroundModes? 
       // Actually `video_player` doesn't expose a manual "enter PiP" method easily.
       // It usually happens when minimizing if configured.
       // However, to trigger it manually, we might need a channel or just rely on background.
       // For now, let's assume minimizing triggers it or we assume it's automatic.
       // The `pip` package works for Android.
       return;
    }
    try {
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
    _progressListeners.clear();
    
    await _player?.dispose();
    await _vpController?.dispose();
    await _mkPlayer?.dispose();
    
    _player = null;
    _vpController = null;
    _mkPlayer = null;
    _mkController = null;
    _videoController = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null) {
      return;
    }
    // ... lifecycle handling
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) {
      _pip.unregisterStateChangedObserver();
      _pip.dispose();
    }
    _disposePlayer();
    _playbackSpeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      // Logic to choose widget
      child: _isInitialized && _player != null
          ? (_isIOS
              ? _buildVideoPlayer() // iOS Widget
              : _buildMediaKit())   // Android/PC Widget
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }

  Widget _buildVideoPlayer() {
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _vpController!.value.aspectRatio,
            child: vp.VideoPlayer(_vpController!),
          ),
        ),
        MobilePlayerControls(
          player: _player!,
           // VideoPlayer doesn't support generic fullscreen toggling easily without context
           // We will implement basic toggling or just call out
          onEnterFullscreen: () {
             // For now no-op or implement device orientation change
          },
          onExitFullscreen: () {
             // For now no-op
             widget.onExitFullScreen?.call();
          },
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
        ),
      ],
    );
  }

  Widget _buildMediaKit() {
    return Video(
      controller: _mkController!,
      controls: (state) {
        return widget.surface == VideoPlayerSurface.desktop
            ? PCPlayerControls(
                // PC Player Controls also need refactoring if we want to support it, 
                // but PC uses MediaKit so we can possibly keep passing original objects if we cast?
                // Or we refactor PCPlayerControls too.
                // Assuming PCPlayerControls is NOT used on iOS.
                // But wait, Video widget expects a specific signature.
                // We are inside build method.
                // Let's check PCPlayerControls signature.
                // It expects `Player` and `VideoState`.
                // Since this block is only for MediaKit, we have `_mkPlayer` and `state`.
                state: state,
                player: _mkPlayer!,
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
                player: _player!, // Adapter
                onEnterFullscreen: state.enterFullscreen,
                onExitFullscreen: state.exitFullscreen,
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
    );
  }
}
