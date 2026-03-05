class VoteAction {
  const VoteAction({
    required this.voterId,
    required this.targetId,
    required this.voteWeight,
    required this.roundNumber,
  });

  final String voterId;
  final String targetId;
  final int voteWeight;
  final int roundNumber;
}

class InfectedVotingState {
  const InfectedVotingState({
    required this.votes,
    required this.finalTarget,
    required this.isLocked,
    required this.alphaInfected,
  });

  final Map<String, String> votes;
  final String? finalTarget;
  final bool isLocked;
  final String? alphaInfected;

  factory InfectedVotingState.initial({String? alpha}) {
    return InfectedVotingState(
      votes: const {},
      finalTarget: null,
      isLocked: false,
      alphaInfected: alpha,
    );
  }

  InfectedVotingState copyWith({
    Map<String, String>? votes,
    String? finalTarget,
    bool? isLocked,
    String? alphaInfected,
  }) {
    return InfectedVotingState(
      votes: votes ?? this.votes,
      finalTarget: finalTarget ?? this.finalTarget,
      isLocked: isLocked ?? this.isLocked,
      alphaInfected: alphaInfected ?? this.alphaInfected,
    );
  }
}
