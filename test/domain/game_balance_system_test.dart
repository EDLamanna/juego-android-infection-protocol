import 'package:flutter_test/flutter_test.dart';
import 'package:infection_protocol/src/domain/models/game_config.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/role_distribution_service.dart';

void main() {
  group('Game Balance System', () {
    final service = RoleDistributionService();
    final config = GameConfig.standard(seed: 99);

    for (var players = 5; players <= 12; players++) {
      test('balance válido para $players jugadores', () {
        final roles = service.generateRolesForMatch(playerCount: players, config: config);

        final infected = roles.where((role) => role.team == Team.infected).length;
        final humans = roles.where((role) => role.team == Team.human).length;
        final saboteador = roles.where((role) => role.id == RoleId.saboteador).length;

        expect(roles.length, players);
        expect(infected, inInclusiveRange(1, 3));
        expect(infected < humans, true);
        expect(saboteador <= 1, true);

        if (players >= 7) {
          expect(saboteador, 1);
        } else {
          expect(saboteador, 0);
        }
      });
    }
  });
}
