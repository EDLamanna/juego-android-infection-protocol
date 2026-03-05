import 'value_objects.dart';

class PlayerTurn {
  const PlayerTurn({
    required this.playerId,
    required this.phase,
    required this.turnType,
    required this.allowedTargets,
    required this.timeLimit,
    this.actionType,
  });

  final String playerId;
  final GamePhase phase;
  final TurnType turnType;
  final ActionType? actionType;
  final List<String> allowedTargets;
  final int timeLimit;
}
