enum GamePhase {
  setup,
  roleReveal,
  nightPhase,
  infectedConsensus,
  nightResolution,
  dayDiscussion,
  votingPhase,
  resultPhase,
  checkWin,
  saboteurDecision,
  gameOver,
}

enum PlayerStatus { alive, eliminated }

enum Team { human, infected, neutral }

enum ActionType { kill, protect, investigate, analyze, sabotage, vote }

enum TurnType {
  passDevice,
  roleReveal,
  nightAction,
  infectedVote,
  saboteurDecision,
  dayDiscussion,
  voting,
  resultDisplay,
}

enum EventVisibility { public, private, team }

enum EventType {
  gameStarted,
  roundStarted,
  infectedVoteUpdated,
  infectedTargetLocked,
  playerAttackBlocked,
  playerProtected,
  playerKilled,
  playerExpelled,
  investigationResult,
  autopsyResult,
  voteTieNoElimination,
  voteWeightBoost,
  gameEnded,
}

enum RoleId {
  tripulante,
  infectado,
  ingeniero,
  doctor,
  angelGuardian,
  saboteador,
  capitan,
}
