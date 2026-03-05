class GameConfig {
  const GameConfig({
    required this.minPlayers,
    required this.maxPlayers,
    required this.discussionTimer,
    required this.votingTimer,
    required this.nightActionTimer,
    required this.infectedConsensusTimer,
    required this.allowStrategicKill,
    required this.seed,
  });

  final int minPlayers;
  final int maxPlayers;
  final int discussionTimer;
  final int votingTimer;
  final int nightActionTimer;
  final int infectedConsensusTimer;
  final bool allowStrategicKill;
  final int seed;

  factory GameConfig.standard({required int seed}) {
    return GameConfig(
      minPlayers: 5,
      maxPlayers: 12,
      discussionTimer: 180,
      votingTimer: 60,
      nightActionTimer: 45,
      infectedConsensusTimer: 60,
      allowStrategicKill: false,
      seed: seed,
    );
  }
}
