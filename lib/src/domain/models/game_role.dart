import 'value_objects.dart';

class GameRole {
  const GameRole({
    required this.id,
    required this.name,
    required this.team,
    required this.actionType,
    required this.priority,
    required this.maxUses,
    required this.cooldown,
  });

  final RoleId id;
  final String name;
  final Team team;
  final ActionType? actionType;
  final int priority;
  final int? maxUses;
  final int cooldown;

  static const List<GameRole> catalog = [
    GameRole(
      id: RoleId.tripulante,
      name: 'Tripulante',
      team: Team.human,
      actionType: null,
      priority: 99,
      maxUses: null,
      cooldown: 0,
    ),
    GameRole(
      id: RoleId.infectado,
      name: 'Infectado',
      team: Team.infected,
      actionType: ActionType.kill,
      priority: 2,
      maxUses: null,
      cooldown: 0,
    ),
    GameRole(
      id: RoleId.ingeniero,
      name: 'Ingeniero',
      team: Team.human,
      actionType: ActionType.investigate,
      priority: 3,
      maxUses: null,
      cooldown: 2,
    ),
    GameRole(
      id: RoleId.doctor,
      name: 'Doctor',
      team: Team.human,
      actionType: ActionType.analyze,
      priority: 4,
      maxUses: null,
      cooldown: 0,
    ),
    GameRole(
      id: RoleId.angelGuardian,
      name: 'Ángel Guardián',
      team: Team.human,
      actionType: ActionType.protect,
      priority: 1,
      maxUses: null,
      cooldown: 0,
    ),
    GameRole(
      id: RoleId.saboteador,
      name: 'Saboteador',
      team: Team.human,
      actionType: ActionType.sabotage,
      priority: 0,
      maxUses: 1,
      cooldown: 0,
    ),
    GameRole(
      id: RoleId.capitan,
      name: 'Capitán',
      team: Team.human,
      actionType: null,
      priority: 99,
      maxUses: null,
      cooldown: 0,
    ),
  ];
}
