import 'package:flutter_test/flutter_test.dart';
import 'package:infection_protocol/src/domain/models/player_turn.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/security/anti_spoiler_system.dart';

void main() {
  test('AntiSpoilerSystem exige transfer screen cuando cambia jugador', () {
    const previous = PlayerTurn(
      playerId: 'p1',
      phase: GamePhase.votingPhase,
      turnType: TurnType.voting,
      allowedTargets: ['p2'],
      timeLimit: 60,
      actionType: ActionType.vote,
    );
    const next = PlayerTurn(
      playerId: 'p2',
      phase: GamePhase.votingPhase,
      turnType: TurnType.voting,
      allowedTargets: ['p1'],
      timeLimit: 60,
      actionType: ActionType.vote,
    );

    final system = AntiSpoilerSystem();
    expect(system.mustShowTransferScreen(previousTurn: previous, nextTurn: next), true);
  });
}
