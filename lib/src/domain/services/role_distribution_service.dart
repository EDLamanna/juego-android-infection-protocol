import '../models/game_config.dart';
import '../models/game_role.dart';
import '../models/player.dart';
import '../models/value_objects.dart';
import 'seeded_random.dart';

class RoleDistributionService {
  List<GameRole> generateRolesForMatch({
    required int playerCount,
    required GameConfig config,
  }) {
    if (playerCount < config.minPlayers || playerCount > config.maxPlayers) {
      throw ArgumentError('playerCount fuera de rango');
    }

    final infectedCount = _infectedCount(playerCount);
    final specialHumans = _specialHumanRoles(playerCount);
    final includeSaboteador = playerCount >= 7;

    final roles = <GameRole>[];
    roles.addAll(List.generate(infectedCount, (_) => _role(RoleId.infectado)));
    roles.addAll(specialHumans.map(_role));
    if (includeSaboteador) {
      roles.add(_role(RoleId.saboteador));
    }

    while (roles.length < playerCount) {
      roles.add(_role(RoleId.tripulante));
    }

    _validateRoleSet(roles);
    return roles;
  }

  List<Player> assignRoles({
    required List<Player> players,
    required List<GameRole> roles,
    required int seed,
  }) {
    if (players.length != roles.length) {
      throw ArgumentError('players y roles deben tener igual longitud');
    }

    final random = SeededRandom(seed);
    final shuffled = random.shuffled(roles);

    return List.generate(players.length, (index) {
      final role = shuffled[index];
      return players[index].copyWith(roleId: role.id, team: role.team);
    });
  }

  int _infectedCount(int playerCount) {
    final base = playerCount ~/ 4;
    if (base < 1) {
      return 1;
    }
    if (base > 3) {
      return 3;
    }
    return base;
  }

  List<RoleId> _specialHumanRoles(int playerCount) {
    if (playerCount <= 5) {
      return const [RoleId.ingeniero];
    }
    if (playerCount == 6) {
      return const [RoleId.ingeniero, RoleId.doctor];
    }
    if (playerCount <= 8) {
      return const [RoleId.ingeniero, RoleId.doctor, RoleId.angelGuardian];
    }
    return const [RoleId.ingeniero, RoleId.doctor, RoleId.angelGuardian, RoleId.capitan];
  }

  void _validateRoleSet(List<GameRole> roles) {
    final infected = roles.where((r) => r.team == Team.infected).length;
    final humans = roles.where((r) => r.team == Team.human).length;
    final saboteador = roles.where((r) => r.id == RoleId.saboteador).length;

    if (infected < 1) {
      throw StateError('Debe existir al menos 1 infectado');
    }
    if (infected >= humans) {
      throw StateError('Infectados no puede ser mayor o igual a humanos al inicio');
    }
    if (saboteador > 1) {
      throw StateError('Solo puede existir 1 saboteador');
    }
  }

  GameRole _role(RoleId id) {
    return GameRole.catalog.firstWhere((r) => r.id == id);
  }
}
