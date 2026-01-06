import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:video_player/video_player.dart' as vp;

/// Unified Player State
class PlayerStateSnapshot {
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool completed;

  const PlayerStateSnapshot({
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.completed = false,
  });

  PlayerStateSnapshot copyWith({
    bool? playing,
    Duration? position,
    Duration? duration,
    double? volume,
    bool? completed,
  }) {
    return PlayerStateSnapshot(
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      completed: completed ?? this.completed,
    );
  }
}

/// Abstract Player Interface
abstract class AbstractPlayer {
  PlayerStateSnapshot get state;
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get completedStream;
  
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

/// Adapter for media_kit
class MediaKitPlayerAdapter implements AbstractPlayer {
  final mk.Player _player;

  MediaKitPlayerAdapter(this._player);

  @override
  PlayerStateSnapshot get state => PlayerStateSnapshot(
    playing: _player.state.playing,
    position: _player.state.position,
    duration: _player.state.duration,
    volume: _player.state.volume / 100.0,
    completed: _player.state.completed,
  );

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> dispose() async {
    // MediaKit player disposal is handled externally by video_player_widget usually, 
    // but if this owns it, we should dispose. 
    // For this refactor, we'll assume the owner disposes it, or we just provide the method.
  }
}

/// Adapter for video_player
class VideoPlayerAdapter implements AbstractPlayer {
  final vp.VideoPlayerController _controller;
  final StreamController<bool> _playingController = StreamController.broadcast();
  final StreamController<Duration> _positionController = StreamController.broadcast();
  final StreamController<Duration> _durationController = StreamController.broadcast();
  final StreamController<bool> _completedController = StreamController.broadcast();
  
  bool _wasPlaying = false;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;

  VideoPlayerAdapter(this._controller) {
    _controller.addListener(_onControllerChanged);
    // Poll for position updates since video_player doesn't stream position effectively for UI sliders
    // Actually video_player relies on the listener.
  }

  void _onControllerChanged() {
    final value = _controller.value;
    
    // Playing stream
    if (value.isPlaying != _wasPlaying) {
      _wasPlaying = value.isPlaying;
      _playingController.add(_wasPlaying);
      if (!_wasPlaying && value.position >= value.duration && value.duration != Duration.zero) {
        _completedController.add(true);
      } else {
        _completedController.add(false);
      }
    }

    // Position stream
    if ((value.position - _lastPosition).abs() > const Duration(milliseconds: 200)) {
       _lastPosition = value.position;
       _positionController.add(_lastPosition);
    }

    // Duration stream
    if (value.duration != _lastDuration) {
      _lastDuration = value.duration;
      _durationController.add(_lastDuration);
    }
  }

  @override
  PlayerStateSnapshot get state => PlayerStateSnapshot(
    playing: _controller.value.isPlaying,
    position: _controller.value.position,
    duration: _controller.value.duration,
    volume: _controller.value.volume,
    completed: _controller.value.position >= _controller.value.duration,
  );

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seek(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _controller.setPlaybackSpeed(rate);

  @override
  Future<void> dispose() async {
    _controller.removeListener(_onControllerChanged);
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _completedController.close();
  }
}
