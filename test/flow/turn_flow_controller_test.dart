import 'package:flutter_test/flutter_test.dart';
import 'package:infection_protocol/src/domain/models/game_config.dart';
import 'package:infection_protocol/src/domain/models/game_role.dart';
import 'package:infection_protocol/src/domain/models/player.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/game_engine.dart';
import 'package:infection_protocol/src/flow/turn_flow_controller.dart';

void main() {
  test('TurnFlowController avanza de role reveal a night phase', () {
    final players = [
      Player.alive(id: 'p1', name: 'P1', roleId: RoleId.tripulante, team: Team.human),
      Player.alive(id: 'p2', name: 'P2', roleId: RoleId.infectado, team: Team.infected),
      Player.alive(id: 'p3', name: 'P3', roleId: RoleId.ingeniero, team: Team.human),
      Player.alive(id: 'p4', name: 'P4', roleId: RoleId.angelGuardian, team: Team.human),
      Player.alive(id: 'p5', name: 'P5', roleId: RoleId.tripulante, team: Team.human),
    ];

    final engine = GameEngine(
      config: GameConfig.standard(seed: 9),
      players: players,
      roles: GameRole.catalog,
    )..startGame();

    final flow = TurnFlowController(engine);
    for (var i = 0; i < players.length; i++) {
      expect(flow.nextTurn(), isNotNull);
      flow.completeTurnAndMaybeAdvancePhase();
    }

    expect(engine.state.currentPhase, GamePhase.nightPhase);
  });

  test('TurnFlowController avanza de discusión a votación al confirmar', () {
    final players = [
      Player.alive(id: 'p1', name: 'P1', roleId: RoleId.tripulante, team: Team.human),
      Player.alive(id: 'p2', name: 'P2', roleId: RoleId.infectado, team: Team.infected),
      Player.alive(id: 'p3', name: 'P3', roleId: RoleId.ingeniero, team: Team.human),
      Player.alive(id: 'p4', name: 'P4', roleId: RoleId.angelGuardian, team: Team.human),
      Player.alive(id: 'p5', name: 'P5', roleId: RoleId.tripulante, team: Team.human),
    ];

    final engine = GameEngine(
      config: GameConfig.standard(seed: 9),
      players: players,
      roles: GameRole.catalog,
    )..startGame();

    final flow = TurnFlowController(engine);
    engine.forcePhase(GamePhase.dayDiscussion);

    final turn = flow.nextTurn();
    expect(turn, isNotNull);
    expect(turn!.turnType, TurnType.dayDiscussion);

    flow.completeTurnAndMaybeAdvancePhase();

    expect(engine.state.currentPhase, GamePhase.votingPhase);
    final votingTurn = flow.nextTurn();
    expect(votingTurn, isNotNull);
    expect(votingTurn!.turnType, TurnType.voting);
  });

  test('TurnFlowController en 1 humano vs 1 infectado cierra partida tras discusión sin votación', () {
    final players = [
      Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
      Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
    ];

    final engine = GameEngine(
      config: GameConfig.standard(seed: 10),
      players: players,
      roles: GameRole.catalog,
    )..startGame();

    final flow = TurnFlowController(engine);
    engine.forcePhase(GamePhase.dayDiscussion);

    final turn = flow.nextTurn();
    expect(turn, isNotNull);
    expect(turn!.turnType, TurnType.dayDiscussion);

    flow.completeTurnAndMaybeAdvancePhase();

    expect(engine.state.currentPhase, GamePhase.gameOver);
    expect(engine.state.winner, Team.infected);
    expect(flow.nextTurn(), isNull);
  });
}
