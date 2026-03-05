import 'package:infection_protocol/src/domain/models/player_turn.dart';
import 'package:infection_protocol/src/domain/models/game_state.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/game_engine.dart';

class TurnFlowController {
  TurnFlowController(this._engine);

  final GameEngine _engine;
  VoteResolutionResult? lastVoteResolution;

  PlayerTurn? nextTurn() => _engine.getNextPlayerTurn();

  void completeTurnAndMaybeAdvancePhase() {
    final phaseBefore = _engine.state.currentPhase;
    _engine.completeCurrentTurn();
    if (phaseBefore == GamePhase.dayDiscussion) {
      _advanceAfterPhase(phaseBefore);
      return;
    }
    final pending = _engine.getNextPlayerTurn();
    if (pending == null) {
      _advanceAfterPhase(_engine.state.currentPhase);
    }
  }

  void _advanceAfterPhase(GamePhase phase) {
    switch (phase) {
      case GamePhase.roleReveal:
        _engine.forcePhase(GamePhase.nightPhase);
        break;
      case GamePhase.nightPhase:
        _engine.resolveNightActions();
        break;
      case GamePhase.infectedConsensus:
        _engine.resolveNightActions();
        break;
      case GamePhase.dayDiscussion:
        _engine.checkWinConditions();
        if (_engine.state.currentPhase != GamePhase.gameOver &&
            _engine.state.currentPhase != GamePhase.saboteurDecision) {
          _engine.forcePhase(GamePhase.votingPhase);
        }
        break;
      case GamePhase.votingPhase:
        lastVoteResolution = _engine.resolveVoting();
        _engine.checkWinConditions();
        if (_engine.state.currentPhase != GamePhase.gameOver &&
            _engine.state.currentPhase != GamePhase.saboteurDecision) {
          _engine.forcePhase(GamePhase.nightPhase);
        }
        break;
      case GamePhase.setup:
      case GamePhase.nightResolution:
      case GamePhase.resultPhase:
      case GamePhase.checkWin:
      case GamePhase.saboteurDecision:
      case GamePhase.gameOver:
        break;
    }
  }
}
