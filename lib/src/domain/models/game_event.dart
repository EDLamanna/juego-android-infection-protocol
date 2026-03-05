import 'value_objects.dart';

class GameEvent {
  const GameEvent({
    required this.type,
    required this.message,
    required this.round,
    required this.playersInvolved,
    required this.timestamp,
    required this.visibility,
    this.winner,
  });

  final EventType type;
  final String message;
  final int round;
  final List<String> playersInvolved;
  final DateTime timestamp;
  final EventVisibility visibility;
  final Team? winner;
}
