import 'package:audioplayers/audioplayers.dart';
import '../core/utils/logger.dart';

class AlertAudioService {
  static final AlertAudioService _instance = AlertAudioService._internal();
  factory AlertAudioService() => _instance;
  AlertAudioService._internal();

  AudioPlayer? _player;

  static const String _alertAsset = 'assets/alert.wav';

  /// Play the alert/siren sound. Silently does nothing if the asset file is
  /// missing (e.g. not yet bundled). Returns true if playback was started.
  Future<bool> playAlert({double volume = 0.8}) async {
    try {
      _player?.dispose();
      _player = AudioPlayer();

      // Use a low-level source check: try to set source; if the asset doesn't
      // exist the player will call onPlayerError but won't crash the app.
      await _player!.setSource(AssetSource(_alertAsset));
      await _player!.setVolume(volume);
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.resume();

      Log.i('[AlertAudio] Playing alert sound');
      return true;
    } catch (e) {
      Log.w('[AlertAudio] Could not play alert sound: $e');
      return false;
    }
  }

  /// Stop any currently playing alert sound.
  Future<void> stopAlert() async {
    try {
      await _player?.stop();
      await _player?.dispose();
      _player = null;
      Log.i('[AlertAudio] Alert sound stopped');
    } catch (e) {
      Log.w('[AlertAudio] Error stopping alert: $e');
    }
  }
}
