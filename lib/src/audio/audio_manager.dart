import 'package:audioplayers/audioplayers.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';

class AudioManager {
  AudioManager() : _player = AudioPlayer();

  final AudioPlayer _player;

  Future<void> playForAction(ActionType actionType) async {
    switch (actionType) {
      case ActionType.vote:
        await _playAsset('audio/vote_cast.wav');
        break;
      case ActionType.sabotage:
        await _playAsset('audio/sabotage.wav');
        break;
      case ActionType.kill:
      case ActionType.protect:
      case ActionType.investigate:
      case ActionType.analyze:
        break;
    }
  }

  Future<void> playForEvent(EventType eventType) async {
    switch (eventType) {
      case EventType.playerKilled:
        await _playAsset('audio/night_kill.wav');
        break;
      case EventType.gameEnded:
        await _playAsset('audio/victory.wav');
        break;
      case EventType.gameStarted:
      case EventType.roundStarted:
      case EventType.infectedVoteUpdated:
      case EventType.infectedTargetLocked:
      case EventType.playerAttackBlocked:
      case EventType.playerProtected:
      case EventType.playerExpelled:
      case EventType.investigationResult:
      case EventType.autopsyResult:
      case EventType.voteTieNoElimination:
      case EventType.voteWeightBoost:
        break;
    }
  }

  Future<void> playTimerWarning() async {
    await _playAsset('audio/timer_warning.wav');
  }

  Future<void> playButtonTap() async {
    await _playAsset('audio/vote_cast.wav');
  }

  Future<void> playTransferAlarm() async {
    await _playAsset('audio/timer_warning.wav');
  }

  Future<void> _playAsset(String assetPath) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath));
  }

  Future<void> dispose() => _player.dispose();
}
