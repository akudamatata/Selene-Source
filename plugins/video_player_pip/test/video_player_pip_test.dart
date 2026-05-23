import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_pip/video_player_pip.dart';
import 'package:video_player_pip/video_player_pip_platform_interface.dart';
import 'package:video_player_pip/video_player_pip_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockVideoPlayerPipPlatform
    with MockPlatformInterfaceMixin
    implements VideoPlayerPipPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');



  @override
  Future<bool> exitPipMode() {
    // TODO: implement exitPipMode
    throw UnimplementedError();
  }

  @override
  Future<bool> isInPipMode() {
    // TODO: implement isInPipMode
    throw UnimplementedError();
  }

  @override
  Future<bool> isPipSupported() {
    // TODO: implement isPipSupported
    throw UnimplementedError();
  }
  
  @override
  Future<bool> enterPipMode(int playerId, {int? width, int? height}) {
    // TODO: implement enterPipMode
    throw UnimplementedError();
  }
}

void main() {
  final VideoPlayerPipPlatform initialPlatform =
      VideoPlayerPipPlatform.instance;

  test('$MethodChannelVideoPlayerPip is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVideoPlayerPip>());
  });

}
