import 'game_event.dart';
import 'night_action.dart';
import 'player.dart';
import 'value_objects.dart';
import 'vote_action.dart';

class GameState {
  const GameState({
    required this.roundNumber,
    required this.currentPhase,
    required this.players,
    required this.nightActions,
    required this.voteActions,
    required this.infectedVotingState,
    required this.eventLog,
    required this.tieCounter,
    required this.winner,
  });

  final int roundNumber;
  final GamePhase currentPhase;
  final List<Player> players;
  final List<NightAction> nightActions;
  final List<VoteAction> voteActions;
  final InfectedVotingState infectedVotingState;
  final List<GameEvent> eventLog;
  final int tieCounter;
  final Team? winner;

  GameState copyWith({
    int? roundNumber,
    GamePhase? currentPhase,
    List<Player>? players,
    List<NightAction>? nightActions,
    List<VoteAction>? voteActions,
    InfectedVotingState? infectedVotingState,
    List<GameEvent>? eventLog,
    int? tieCounter,
    Team? winner,
    bool keepWinner = true,
  }) {
    return GameState(
      roundNumber: roundNumber ?? this.roundNumber,
      currentPhase: currentPhase ?? this.currentPhase,
      players: players ?? this.players,
      nightActions: nightActions ?? this.nightActions,
      voteActions: voteActions ?? this.voteActions,
      infectedVotingState: infectedVotingState ?? this.infectedVotingState,
      eventLog: eventLog ?? this.eventLog,
      tieCounter: tieCounter ?? this.tieCounter,
      winner: keepWinner ? (winner ?? this.winner) : winner,
    );
  }

  factory GameState.initial({required List<Player> players, required String? alphaInfected}) {
    return GameState(
      roundNumber: 1,
      currentPhase: GamePhase.setup,
      players: players,
      nightActions: const [],
      voteActions: const [],
      infectedVotingState: InfectedVotingState.initial(alpha: alphaInfected),
      eventLog: const [],
      tieCounter: 0,
      winner: null,
    );
  }
}

class VoteResolutionResult {
  const VoteResolutionResult({
    this.expelledPlayerId,
    this.tieNoElimination = false,
    this.tally = const {},
    this.votes = const [],
  });

  final String? expelledPlayerId;
  final bool tieNoElimination;
  final Map<String, int> tally;
  final List<VoteAction> votes;
}
