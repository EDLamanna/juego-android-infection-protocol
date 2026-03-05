import 'package:flutter_test/flutter_test.dart';
import 'package:infection_protocol/src/domain/models/game_config.dart';
import 'package:infection_protocol/src/domain/models/game_role.dart';
import 'package:infection_protocol/src/domain/models/player.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/game_engine.dart';

void main() {
  group('Turn flow + security', () {
    late GameEngine engine;

    setUp(() {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human),
        Player.alive(id: 'h3', name: 'H3', roleId: RoleId.angelGuardian, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 17),
        players: players,
        roles: GameRole.catalog,
      )..startGame();
    });

    test('getValidTargets filtra correctamente para infectado', () {
      engine.forcePhase(GamePhase.infectedConsensus);
      final targets = engine.getValidTargets(playerId: 'i1', actionType: ActionType.kill);
      expect(targets, containsAll(const ['h1', 'h2', 'h3']));
      expect(targets, isNot(contains('i2')));
      expect(targets, isNot(contains('i1')));
    });

    test('getNextPlayerTurn en role reveal retorna jugadores secuenciales', () {
      final first = engine.getNextPlayerTurn();
      expect(first, isNotNull);
      expect(first!.turnType, TurnType.roleReveal);
      expect(first.playerId, 'h1');

      engine.completeCurrentTurn();
      final second = engine.getNextPlayerTurn();
      expect(second, isNotNull);
      expect(second!.playerId, 'h2');
    });

    test('getPlayerView oculta rol y equipo ajeno para humano', () {
      final view = engine.getPlayerView('h1');
      final self = view.players.firstWhere((p) => p.id == 'h1');
      final other = view.players.firstWhere((p) => p.id == 'i1');

      expect(self.roleHidden, false);
      expect(self.teamLabel, 'human');
      expect(other.roleHidden, true);
      expect(other.teamLabel, 'unknown');
    });

    test('infectado puede ver sus compañeros infectados', () {
      final mates = engine.getInfectedTeammates('i1');
      expect(mates.length, 1);
      expect(mates.first.id, 'i2');
    });
  });
}
