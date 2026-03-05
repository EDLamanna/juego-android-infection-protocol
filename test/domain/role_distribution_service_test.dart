import 'package:flutter_test/flutter_test.dart';
import 'package:infection_protocol/src/domain/models/game_config.dart';
import 'package:infection_protocol/src/domain/models/player.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/role_distribution_service.dart';

void main() {
  group('RoleDistributionService', () {
    test('genera distribución base correcta para 8 jugadores', () {
      final service = RoleDistributionService();
      final config = GameConfig.standard(seed: 7);

      final roles = service.generateRolesForMatch(
        playerCount: 8,
        config: config,
      );

      final infected = roles.where((r) => r.team == Team.infected).length;
      final saboteador = roles.where((r) => r.id == RoleId.saboteador).length;
      final ingeniero = roles.where((r) => r.id == RoleId.ingeniero).length;

      expect(roles.length, 8);
      expect(infected, 2);
      expect(saboteador, 1);
      expect(ingeniero, 1);
    });

    test('lanza error cuando playerCount está fuera de rango', () {
      final service = RoleDistributionService();
      final config = GameConfig.standard(seed: 7);

      expect(
        () => service.generateRolesForMatch(playerCount: 4, config: config),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('asigna roles de forma determinista por seed', () {
      final service = RoleDistributionService();
      final config = GameConfig.standard(seed: 42);
      final players = List.generate(
        8,
        (i) => Player.alive(id: 'p$i', name: 'P$i'),
      );

      final assignedA = service.assignRoles(
        players: players,
        roles: service.generateRolesForMatch(playerCount: 8, config: config),
        seed: 42,
      );
      final assignedB = service.assignRoles(
        players: players,
        roles: service.generateRolesForMatch(playerCount: 8, config: config),
        seed: 42,
      );

      expect(
        assignedA.map((p) => p.roleId).toList(),
        assignedB.map((p) => p.roleId).toList(),
      );
    });

    test('incluye capitán en partidas de 9 o más jugadores', () {
      final service = RoleDistributionService();
      final config = GameConfig.standard(seed: 21);

      final roles = service.generateRolesForMatch(
        playerCount: 9,
        config: config,
      );

      final capitanCount = roles.where((r) => r.id == RoleId.capitan).length;
      expect(capitanCount, 1);
    });
  });
}
