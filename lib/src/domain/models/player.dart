import 'value_objects.dart';

class Player {
  const Player({
    required this.id,
    required this.name,
    required this.roleId,
    required this.team,
    required this.status,
    required this.protected,
    required this.totalVotesReceived,
    required this.hasVotedThisRound,
    required this.voteWeight,
  });

  final String id;
  final String name;
  final RoleId roleId;
  final Team team;
  final PlayerStatus status;
  final bool protected;
  final int totalVotesReceived;
  final bool hasVotedThisRound;
  final int voteWeight;

  bool get isAlive => status == PlayerStatus.alive;

  factory Player.alive({
    required String id,
    required String name,
    RoleId roleId = RoleId.tripulante,
    Team team = Team.human,
  }) {
    return Player(
      id: id,
      name: name,
      roleId: roleId,
      team: team,
      status: PlayerStatus.alive,
      protected: false,
      totalVotesReceived: 0,
      hasVotedThisRound: false,
      voteWeight: 10,
    );
  }

  Player copyWith({
    RoleId? roleId,
    Team? team,
    PlayerStatus? status,
    bool? protected,
    int? totalVotesReceived,
    bool? hasVotedThisRound,
    int? voteWeight,
  }) {
    return Player(
      id: id,
      name: name,
      roleId: roleId ?? this.roleId,
      team: team ?? this.team,
      status: status ?? this.status,
      protected: protected ?? this.protected,
      totalVotesReceived: totalVotesReceived ?? this.totalVotesReceived,
      hasVotedThisRound: hasVotedThisRound ?? this.hasVotedThisRound,
      voteWeight: voteWeight ?? this.voteWeight,
    );
  }
}
