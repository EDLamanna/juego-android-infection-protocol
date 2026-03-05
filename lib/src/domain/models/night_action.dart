import 'value_objects.dart';

class NightAction {
  const NightAction({
    required this.playerId,
    required this.actionType,
    required this.targetPlayerId,
    required this.priority,
    required this.roundNumber,
    this.cancelled = false,
  });

  final String playerId;
  final ActionType actionType;
  final String targetPlayerId;
  final int priority;
  final int roundNumber;
  final bool cancelled;

  NightAction copyWith({bool? cancelled}) {
    return NightAction(
      playerId: playerId,
      actionType: actionType,
      targetPlayerId: targetPlayerId,
      priority: priority,
      roundNumber: roundNumber,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}
