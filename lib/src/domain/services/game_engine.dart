import 'dart:developer' as developer;

import '../models/game_config.dart';
import '../models/game_event.dart';
import '../models/game_role.dart';
import '../models/game_state.dart';
import '../models/night_action.dart';
import '../models/player.dart';
import '../models/player_turn.dart';
import '../models/player_view.dart';
import '../models/value_objects.dart';
import '../models/vote_action.dart';
import 'seeded_random.dart';

class GameEngine {
  GameEngine({
    required this.config,
    required List<Player> players,
    required this.roles,
  }) : _state = GameState.initial(
          players: players,
          alphaInfected: _alphaInfected(players),
        ),
        _rng = SeededRandom(config.seed);

  final GameConfig config;
  final List<GameRole> roles;
  final SeededRandom _rng;

  GameState _state;
  final Set<String> _sabotageUsedBy = <String>{};
  final Map<String, int> _lastInvestigateRoundBy = <String, int>{};
  int _roleRevealCursor = 0;
  int _infectedCursor = 0;
  int _nightActionCursor = 0;
  int _votingCursor = 0;
  static const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');

  void _secureLog(String message) {
    if (!_isReleaseBuild) {
      developer.log(message, name: 'InfectionProtocol.Engine');
    }
  }

  GameState get state => _state;

  void startGame() {
    _appendEvent(
      EventType.gameStarted,
      'Partida iniciada',
      EventVisibility.public,
      const [],
    );
    _setPhase(GamePhase.roleReveal);
    _appendEvent(
      EventType.roundStarted,
      'Ronda iniciada',
      EventVisibility.public,
      const [],
    );
  }

  void forcePhase(GamePhase phase) {
    _setPhase(phase);
  }

  void advancePhase() {
    switch (_state.currentPhase) {
      case GamePhase.setup:
        _setPhase(GamePhase.roleReveal);
        break;
      case GamePhase.roleReveal:
        _setPhase(GamePhase.nightPhase);
        break;
      case GamePhase.nightPhase:
        _setPhase(GamePhase.infectedConsensus);
        break;
      case GamePhase.infectedConsensus:
        _setPhase(GamePhase.nightResolution);
        break;
      case GamePhase.nightResolution:
        _setPhase(GamePhase.dayDiscussion);
        break;
      case GamePhase.dayDiscussion:
        _setPhase(GamePhase.votingPhase);
        break;
      case GamePhase.votingPhase:
        _setPhase(GamePhase.resultPhase);
        break;
      case GamePhase.resultPhase:
        _setPhase(GamePhase.checkWin);
        break;
      case GamePhase.checkWin:
        if (checkWinConditions() == null) {
          _setPhase(GamePhase.nightPhase);
        }
        break;
      case GamePhase.saboteurDecision:
        break;
      case GamePhase.gameOver:
        break;
    }
  }

  Player playerById(String id) {
    return _state.players.firstWhere((p) => p.id == id);
  }

  List<Player> getAlivePlayers() {
    return _state.players.where((p) => p.isAlive).toList();
  }

  List<String> getValidTargets({required String playerId, required ActionType actionType}) {
    final actor = playerById(playerId);
    if (!actor.isAlive) {
      return const [];
    }

    final aliveOthers = _state.players.where((p) => p.isAlive && p.id != playerId).toList();
    switch (actionType) {
      case ActionType.kill:
        if (actor.team == Team.infected && !config.allowStrategicKill) {
          return aliveOthers.where((p) => p.team != Team.infected).map((p) => p.id).toList();
        }
        return aliveOthers.map((p) => p.id).toList();
      case ActionType.protect:
      case ActionType.investigate:
      case ActionType.sabotage:
      case ActionType.vote:
        return aliveOthers.map((p) => p.id).toList();
      case ActionType.analyze:
        return _state.players.where((p) => !p.isAlive).map((p) => p.id).toList();
    }
  }

  bool canUseNightAction({required String playerId, required ActionType actionType}) {
    final actor = playerById(playerId);
    if (!actor.isAlive) {
      return false;
    }
    final expectedAction = _nightActionForRole(actor.roleId);
    if (expectedAction == null) {
      return false;
    }
    if (expectedAction != actionType) {
      return false;
    }
    if (actor.roleId == RoleId.saboteador && actionType == ActionType.sabotage && _sabotageUsedBy.contains(playerId)) {
      return false;
    }
    if (actor.roleId == RoleId.ingeniero && actionType == ActionType.investigate) {
      final lastRound = _lastInvestigateRoundBy[playerId];
      if (lastRound != null && (_state.roundNumber - lastRound) < 2) {
        return false;
      }
    }
    return true;
  }

  List<PublicPlayerRef> getInfectedTeammates(String requesterId) {
    final requester = playerById(requesterId);
    if (requester.team != Team.infected) {
      throw StateError('AccessDenied');
    }
    return _state.players
        .where((p) => p.team == Team.infected && p.id != requesterId)
        .map((p) => PublicPlayerRef(id: p.id, name: p.name))
        .toList();
  }

  PlayerView getPlayerView(String requesterId) {
    final requester = playerById(requesterId);
    final players = _state.players.map((player) {
      final isSelf = player.id == requesterId;
      final isVisibleInfectedMate = requester.team == Team.infected && player.team == Team.infected;

      if (isSelf || isVisibleInfectedMate) {
        return VisiblePlayer(
          id: player.id,
          name: player.name,
          status: player.status.name,
          roleLabel: player.roleId.name,
          teamLabel: player.team.name,
          roleHidden: false,
        );
      }

      return VisiblePlayer(
        id: player.id,
        name: player.name,
        status: player.status.name,
        roleLabel: 'hidden',
        teamLabel: 'unknown',
        roleHidden: true,
      );
    }).toList();

    final visibleEvents = _state.eventLog.where((event) {
      if (event.visibility == EventVisibility.public) {
        return true;
      }
      if (event.visibility == EventVisibility.private) {
        return event.playersInvolved.contains(requesterId);
      }
      if (event.visibility == EventVisibility.team) {
        return requester.team == Team.infected;
      }
      return false;
    }).toList();

    return PlayerView(requesterId: requesterId, players: players, visibleEvents: visibleEvents);
  }

  PlayerTurn? getNextPlayerTurn() {
    switch (_state.currentPhase) {
      case GamePhase.roleReveal:
        final players = _state.players;
        if (_roleRevealCursor >= players.length) {
          return null;
        }
        final player = players[_roleRevealCursor];
        return PlayerTurn(
          playerId: player.id,
          phase: _state.currentPhase,
          turnType: TurnType.roleReveal,
          actionType: null,
          allowedTargets: const [],
          timeLimit: 0,
        );
      case GamePhase.infectedConsensus:
        final infected = _state.players.where((p) => p.isAlive && p.team == Team.infected).toList();
        if (_infectedCursor >= infected.length) {
          return null;
        }
        final player = infected[_infectedCursor];
        return PlayerTurn(
          playerId: player.id,
          phase: _state.currentPhase,
          turnType: TurnType.infectedVote,
          actionType: ActionType.kill,
          allowedTargets: getValidTargets(playerId: player.id, actionType: ActionType.kill),
          timeLimit: config.infectedConsensusTimer,
        );
      case GamePhase.nightPhase:
        final eligible = _state.players.where((p) => p.isAlive).toList();

        if (_nightActionCursor >= eligible.length) {
          return null;
        }
        final player = eligible[_nightActionCursor];
        final action = _nightActionForRole(player.roleId);
        return PlayerTurn(
          playerId: player.id,
          phase: _state.currentPhase,
          turnType: TurnType.nightAction,
          actionType: action,
          allowedTargets: action == null ? const [] : getValidTargets(playerId: player.id, actionType: action),
          timeLimit: config.nightActionTimer,
        );
      case GamePhase.votingPhase:
        final alive = getAlivePlayers();
        if (_votingCursor >= alive.length) {
          return null;
        }
        final player = alive[_votingCursor];
        return PlayerTurn(
          playerId: player.id,
          phase: _state.currentPhase,
          turnType: TurnType.voting,
          actionType: ActionType.vote,
          allowedTargets: getValidTargets(playerId: player.id, actionType: ActionType.vote),
          timeLimit: config.votingTimer,
        );
      case GamePhase.saboteurDecision:
        final saboteur = _state.players.where((p) => p.isAlive && p.roleId == RoleId.saboteador).toList();
        if (saboteur.isEmpty) {
          return null;
        }
        final player = saboteur.first;
        final targets = _state.players
            .where((p) => p.isAlive && p.id != player.id && (p.team == Team.human || p.team == Team.infected))
            .map((p) => p.id)
            .toList();
        return PlayerTurn(
          playerId: player.id,
          phase: _state.currentPhase,
          turnType: TurnType.saboteurDecision,
          actionType: ActionType.kill,
          allowedTargets: targets,
          timeLimit: config.nightActionTimer,
        );
      case GamePhase.dayDiscussion:
        final alive = getAlivePlayers();
        if (alive.isEmpty) {
          return null;
        }
        return PlayerTurn(
          playerId: alive.first.id,
          phase: _state.currentPhase,
          turnType: TurnType.dayDiscussion,
          actionType: null,
          allowedTargets: const [],
          timeLimit: config.discussionTimer,
        );
      case GamePhase.setup:
      case GamePhase.nightResolution:
      case GamePhase.resultPhase:
      case GamePhase.checkWin:
      case GamePhase.gameOver:
        return null;
    }
  }

  void completeCurrentTurn() {
    switch (_state.currentPhase) {
      case GamePhase.roleReveal:
        _roleRevealCursor++;
        break;
      case GamePhase.infectedConsensus:
        _infectedCursor++;
        break;
      case GamePhase.nightPhase:
        _nightActionCursor++;
        break;
      case GamePhase.votingPhase:
        _votingCursor++;
        break;
      default:
        break;
    }
  }

  void submitNightAction({
    required String playerId,
    required ActionType actionType,
    required String targetId,
  }) {
    _assertPhase(GamePhase.nightPhase);
    _validateActorAndTarget(playerId: playerId, targetId: targetId, actionType: actionType);

    final actor = playerById(playerId);
    _secureLog(
      'submitNightAction round=${_state.roundNumber} player=$playerId role=${actor.roleId.name} action=${actionType.name} target=$targetId',
    );
    final expectedAction = _nightActionForRole(actor.roleId);
    if (expectedAction == null) {
      _secureLog('action rejected: role has no night action, received=${actionType.name}');
      throw StateError('Acción no permitida para el rol ${actor.roleId.name}');
    }
    if (actionType != expectedAction) {
      _secureLog('action rejected: expected=${expectedAction.name} received=${actionType.name}');
      throw StateError('Acción no permitida para el rol ${actor.roleId.name}');
    }

    if (actor.roleId == RoleId.saboteador && actionType == ActionType.sabotage && _sabotageUsedBy.contains(playerId)) {
      throw StateError('El saboteador solo puede usar sabotaje una vez por partida');
    }

    if (actor.roleId == RoleId.ingeniero && actionType == ActionType.investigate) {
      final lastRound = _lastInvestigateRoundBy[playerId];
      _secureLog('ingeniero investigate check: currentRound=${_state.roundNumber} lastRound=$lastRound');
      if (lastRound != null && (_state.roundNumber - lastRound) < 2) {
        _secureLog('ingeniero investigate rejected by cooldown');
        throw StateError('Ingeniero solo puede investigar cada 2 noches');
      }
      _lastInvestigateRoundBy[playerId] = _state.roundNumber;
      _secureLog('ingeniero investigate accepted: newLastRound=${_state.roundNumber}');
    }

    final priority = _priorityFor(actionType);
    final action = NightAction(
      playerId: playerId,
      actionType: actionType,
      targetPlayerId: targetId,
      priority: priority,
      roundNumber: _state.roundNumber,
    );
    _state = _state.copyWith(nightActions: [..._state.nightActions, action]);
  }

  void submitInfectedVote({required String playerId, required String targetId}) {
    if (_state.currentPhase != GamePhase.infectedConsensus && _state.currentPhase != GamePhase.nightPhase) {
      throw StateError('Fase inválida para consenso infectado');
    }
    final player = playerById(playerId);
    if (!player.isAlive || player.team != Team.infected) {
      throw StateError('Solo infectados vivos pueden votar en consenso');
    }
    final target = playerById(targetId);
    if (!target.isAlive || target.team == Team.infected) {
      throw StateError('Target inválido para consenso infectado');
    }

    final votes = Map<String, String>.from(_state.infectedVotingState.votes)
      ..[playerId] = targetId;
    final mostVoted = _mostVoted(votes);
    final infectedAlive = _state.players.where((p) => p.isAlive && p.team == Team.infected).length;
    final isLocked = votes.length == infectedAlive && mostVoted != null;

    _state = _state.copyWith(
      infectedVotingState: _state.infectedVotingState.copyWith(
        votes: votes,
        finalTarget: mostVoted,
        isLocked: isLocked,
      ),
    );

    _appendEvent(
      isLocked ? EventType.infectedTargetLocked : EventType.infectedVoteUpdated,
      isLocked ? 'Objetivo infectado bloqueado' : 'Voto infectado actualizado',
      EventVisibility.team,
      [playerId, targetId],
    );
  }

  void submitSaboteurDecision({required String playerId, required String targetId}) {
    _assertPhase(GamePhase.saboteurDecision);
    final saboteur = playerById(playerId);
    final target = playerById(targetId);

    if (!saboteur.isAlive || saboteur.roleId != RoleId.saboteador) {
      throw StateError('Solo el saboteador vivo puede decidir en fase kingmaker');
    }
    if (!target.isAlive || target.id == saboteur.id) {
      throw StateError('Target inválido para decisión del saboteador');
    }
    if (target.team != Team.human && target.team != Team.infected) {
      throw StateError('El saboteador solo puede eliminar humano o infectado');
    }

    final players = _state.players
        .map((p) => p.id == targetId ? p.copyWith(status: PlayerStatus.eliminated) : p)
        .toList();
    _state = _state.copyWith(players: players);

    _appendEvent(
      EventType.playerKilled,
      'El saboteador ha eliminado a un jugador',
      EventVisibility.public,
      [targetId],
    );

    checkWinConditions();
  }

  void resolveNightActions() {
    final consensusTarget = _state.infectedVotingState.finalTarget;
    if (consensusTarget != null) {
      final withTeamKill = [..._state.nightActions];
      withTeamKill.add(
        NightAction(
          playerId: 'INFECTED_TEAM',
          actionType: ActionType.kill,
          targetPlayerId: consensusTarget,
          priority: 2,
          roundNumber: _state.roundNumber,
        ),
      );
      _state = _state.copyWith(nightActions: withTeamKill);
    }

    final sorted = [..._state.nightActions]..sort((a, b) => a.priority.compareTo(b.priority));
    var players = [..._state.players];
    final noNightDeaths = sorted.any(
      (action) =>
          action.actionType == ActionType.kill &&
          _isInfectedKillActor(action.playerId) &&
          _isAliveSaboteador(players, action.targetPlayerId),
    );
    var blockedBySaboteadorImmunityLogged = false;
    var sabotageUsed = false;

    for (final action in sorted) {
      if (action.cancelled) {
        continue;
      }

      if (action.actionType == ActionType.sabotage) {
        _sabotageUsedBy.add(action.playerId);
        sabotageUsed = true;
        continue;
      }

      if (sabotageUsed && _isSabotageCancellable(action.actionType)) {
        sabotageUsed = false;
        continue;
      }

      final targetIndex = players.indexWhere((p) => p.id == action.targetPlayerId);
      if (targetIndex == -1) {
        continue;
      }

      final target = players[targetIndex];
      switch (action.actionType) {
        case ActionType.protect:
          players[targetIndex] = target.copyWith(protected: true);
          _appendEvent(
            EventType.playerProtected,
            'Jugador protegido',
            EventVisibility.private,
            [action.targetPlayerId],
          );
          break;
        case ActionType.kill:
          if (noNightDeaths) {
            if (!blockedBySaboteadorImmunityLogged) {
              _appendEvent(
                EventType.playerAttackBlocked,
                'El saboteador fue objetivo infectado: no hubo muertes esta noche',
                EventVisibility.public,
                const [],
              );
              blockedBySaboteadorImmunityLogged = true;
            }
            break;
          }
          if (target.protected) {
            _appendEvent(
              EventType.playerAttackBlocked,
              'Ataque bloqueado por protección',
              EventVisibility.public,
              [action.targetPlayerId],
            );
          } else {
            players[targetIndex] = target.copyWith(status: PlayerStatus.eliminated);
            _appendEvent(
              EventType.playerKilled,
              'Jugador eliminado durante la noche',
              EventVisibility.public,
              [action.targetPlayerId],
            );
          }
          break;
        case ActionType.investigate:
          final investigatedTeam = target.team == Team.infected ? 'INFECTADO' : 'HUMANO';
          _appendEvent(
            EventType.investigationResult,
            'Resultado de investigación: $investigatedTeam',
            EventVisibility.private,
            [action.playerId],
          );
          if (target.roleId == RoleId.saboteador && target.isAlive) {
            players[targetIndex] = target.copyWith(status: PlayerStatus.eliminated);
            _appendEvent(
              EventType.playerKilled,
              'El saboteador fue eliminado por investigación del ingeniero',
              EventVisibility.public,
              [action.targetPlayerId],
            );
          }
          break;
        case ActionType.analyze:
          final teamLabel = _teamLabel(target.team);
          _appendEvent(
            EventType.autopsyResult,
            'Resultado de autopsia: $teamLabel',
            EventVisibility.private,
            [action.playerId],
          );
          break;
        case ActionType.vote:
          break;
        case ActionType.sabotage:
          break;
      }
    }

    players = players.map((p) => p.copyWith(protected: false)).toList();
    _state = _state.copyWith(
      players: players,
      nightActions: const [],
      infectedVotingState: InfectedVotingState.initial(alpha: _state.infectedVotingState.alphaInfected),
    );
    _setPhase(GamePhase.dayDiscussion);
  }

  bool _isInfectedKillActor(String playerId) {
    if (playerId == 'INFECTED_TEAM') {
      return true;
    }
    final index = _state.players.indexWhere((player) => player.id == playerId);
    if (index == -1) {
      return false;
    }
    return _state.players[index].team == Team.infected;
  }

  bool _isAliveSaboteador(List<Player> players, String playerId) {
    final index = players.indexWhere((player) => player.id == playerId);
    if (index == -1) {
      return false;
    }
    final player = players[index];
    return player.isAlive && player.roleId == RoleId.saboteador;
  }

  void submitVote({required String voterId, required String targetId}) {
    _assertPhase(GamePhase.votingPhase);
    if (voterId == targetId) {
      throw StateError('No se permite auto-voto');
    }
    final voter = playerById(voterId);
    final target = playerById(targetId);
    if (!voter.isAlive || !target.isAlive || voter.hasVotedThisRound) {
      throw StateError('Voto inválido');
    }

    final vote = VoteAction(
      voterId: voterId,
      targetId: targetId,
      voteWeight: voter.voteWeight,
      roundNumber: _state.roundNumber,
    );
    final voteActions = [..._state.voteActions, vote];

    final players = _state.players
        .map((p) => p.id == voterId ? p.copyWith(hasVotedThisRound: true) : p)
        .toList();

    _state = _state.copyWith(players: players, voteActions: voteActions);
  }

  VoteResolutionResult resolveVoting() {
    final roundVotes = List<VoteAction>.from(_state.voteActions);
    final tally = <String, int>{};
    for (final vote in _state.voteActions) {
      tally[vote.targetId] = (tally[vote.targetId] ?? 0) + vote.voteWeight;
    }
    if (tally.isEmpty) {
      return const VoteResolutionResult();
    }

    final maxVotes = tally.values.reduce((a, b) => a > b ? a : b);
    final top = tally.entries.where((e) => e.value == maxVotes).map((e) => e.key).toList();

    if (top.length > 1) {
      final tieCounter = _state.tieCounter + 1;
      _state = _state.copyWith(tieCounter: tieCounter, voteActions: const []);

      if (tieCounter < 2) {
        _appendEvent(
          EventType.voteTieNoElimination,
          'Empate sin eliminación',
          EventVisibility.public,
          top,
        );
        _resetVotingRound();
        return VoteResolutionResult(
          tieNoElimination: true,
          tally: tally,
          votes: roundVotes,
        );
      }

      final expelled = _resolveSuddenDeath(top);
      _expelPlayer(expelled);
      _resetVotingRound();
      return VoteResolutionResult(
        expelledPlayerId: expelled,
        tally: tally,
        votes: roundVotes,
      );
    }

    final expelled = top.first;
    _expelPlayer(expelled);
    _resetVotingRound();
    return VoteResolutionResult(
      expelledPlayerId: expelled,
      tally: tally,
      votes: roundVotes,
    );
  }

  Team? checkWinConditions() {
    final alive = _state.players.where((p) => p.isAlive).toList();
    final aliveInfected = alive.where((p) => p.team == Team.infected).length;
    final aliveSaboteur = alive.where((p) => p.roleId == RoleId.saboteador).length;
    final aliveTrueHumans = alive.where((p) => p.team == Team.human && p.roleId != RoleId.saboteador).length;

    if (aliveTrueHumans == 0 && aliveInfected >= 1) {
      _state = _state.copyWith(
        winner: Team.infected,
        keepWinner: false,
      );
      _setPhase(GamePhase.gameOver);
      _appendEvent(
        EventType.gameEnded,
        'Infectados ganan (sin humanos verdaderos)',
        EventVisibility.public,
        const [],
        Team.infected,
      );
      return Team.infected;
    }

    if (aliveInfected == 0) {
      _state = _state.copyWith(
        winner: Team.human,
        keepWinner: false,
      );
      _setPhase(GamePhase.gameOver);
      _appendEvent(
        EventType.gameEnded,
        'Humanos ganan',
        EventVisibility.public,
        const [],
        Team.human,
      );
      return Team.human;
    }

    if (aliveTrueHumans == 1 && aliveInfected == 1 && aliveSaboteur == 1) {
      _setPhase(GamePhase.saboteurDecision);
      return null;
    }

    if (aliveInfected >= aliveTrueHumans && aliveSaboteur == 0) {
      _state = _state.copyWith(
        winner: Team.infected,
        keepWinner: false,
      );
      _setPhase(GamePhase.gameOver);
      _appendEvent(
        EventType.gameEnded,
        'Infectados ganan',
        EventVisibility.public,
        const [],
        Team.infected,
      );
      return Team.infected;
    }

    return null;
  }

  GameEngine eliminatePlayers(List<String> playerIds) {
    final eliminated = _state.players
        .map(
          (p) => playerIds.contains(p.id)
              ? p.copyWith(status: PlayerStatus.eliminated)
              : p,
        )
        .toList();

    return GameEngine(config: config, players: eliminated, roles: roles)
      .._state = _state.copyWith(players: eliminated);
  }

  void _assertPhase(GamePhase expected) {
    if (_state.currentPhase != expected) {
      throw StateError('Fase inválida. Esperada: $expected actual: ${_state.currentPhase}');
    }
  }

  void _validateActorAndTarget({
    required String playerId,
    required String targetId,
    required ActionType actionType,
  }) {
    final actor = playerById(playerId);
    final target = playerById(targetId);
    if (!actor.isAlive) {
      throw StateError('El actor debe estar vivo');
    }
    if (actionType == ActionType.analyze) {
      if (target.status != PlayerStatus.eliminated) {
        throw StateError('Analyze requiere target eliminado');
      }
    } else {
      if (!target.isAlive) {
        throw StateError('Target debe estar vivo para esta acción');
      }
    }
    if (actionType == ActionType.kill && !config.allowStrategicKill && actor.team == Team.infected && target.team == Team.infected) {
      throw StateError('No se permite kill infectado contra infectado');
    }
  }

  int _priorityFor(ActionType actionType) {
    switch (actionType) {
      case ActionType.sabotage:
        return 0;
      case ActionType.protect:
        return 1;
      case ActionType.kill:
        return 2;
      case ActionType.investigate:
        return 3;
      case ActionType.analyze:
        return 4;
      case ActionType.vote:
        return 99;
    }
  }

  String? _mostVoted(Map<String, String> votes) {
    if (votes.isEmpty) {
      return null;
    }
    final count = <String, int>{};
    for (final target in votes.values) {
      count[target] = (count[target] ?? 0) + 1;
    }
    var selected = count.entries.first;
    for (final entry in count.entries.skip(1)) {
      if (entry.value > selected.value) {
        selected = entry;
      }
    }
    return selected.key;
  }

  bool _isSabotageCancellable(ActionType type) {
    return type == ActionType.investigate || type == ActionType.analyze || type == ActionType.protect;
  }

  void _appendEvent(
    EventType type,
    String message,
    EventVisibility visibility,
    List<String> players, [
    Team? winner,
  ]) {
    _state = _state.copyWith(
      eventLog: [
        ..._state.eventLog,
        GameEvent(
          type: type,
          message: message,
          round: _state.roundNumber,
          playersInvolved: players,
          timestamp: DateTime.now(),
          visibility: visibility,
          winner: winner,
        ),
      ],
    );
  }

  void _setPhase(GamePhase phase) {
    _state = _state.copyWith(currentPhase: phase);
    if (phase == GamePhase.roleReveal) {
      _roleRevealCursor = 0;
    }
    if (phase == GamePhase.infectedConsensus) {
      _infectedCursor = 0;
    }
    if (phase == GamePhase.nightPhase) {
      _nightActionCursor = 0;
    }
    if (phase == GamePhase.votingPhase) {
      _votingCursor = 0;
      _recalculateVoteWeights();
    }
    if (phase == GamePhase.saboteurDecision) {
      _nightActionCursor = 0;
    }
  }

  void _recalculateVoteWeights() {
    final alive = _state.players.where((p) => p.isAlive).toList();
    if (alive.isEmpty) {
      return;
    }

    final updatedPlayers = _state.players
        .map(
          (player) => player.copyWith(voteWeight: 10),
        )
        .toList();
    _state = _state.copyWith(players: updatedPlayers);
  }

  ActionType? _nightActionForRole(RoleId roleId) {
    switch (roleId) {
      case RoleId.ingeniero:
        return ActionType.investigate;
      case RoleId.doctor:
        return ActionType.analyze;
      case RoleId.angelGuardian:
        return ActionType.protect;
      case RoleId.saboteador:
        return ActionType.sabotage;
      case RoleId.infectado:
        return ActionType.kill;
      case RoleId.tripulante:
      case RoleId.capitan:
        return null;
    }
  }

  void _expelPlayer(String playerId) {
    final players = _state.players
        .map(
          (p) => p.id == playerId
              ? p.copyWith(status: PlayerStatus.eliminated)
              : p.copyWith(totalVotesReceived: p.totalVotesReceived + _votesReceivedBy(p.id)),
        )
        .toList();
    _state = _state.copyWith(players: players, tieCounter: 0);
    _appendEvent(EventType.playerExpelled, 'Jugador expulsado', EventVisibility.public, [playerId]);
  }

  int _votesReceivedBy(String playerId) {
    return _state.voteActions.where((v) => v.targetId == playerId).length;
  }

  String _resolveSuddenDeath(List<String> tied) {
    final candidates = _state.players.where((p) => tied.contains(p.id)).toList();
    candidates.sort((a, b) => b.totalVotesReceived.compareTo(a.totalVotesReceived));
    if (candidates.length == 1) {
      return candidates.first.id;
    }
    if (candidates[0].totalVotesReceived == candidates[1].totalVotesReceived) {
      return tied[_rng.nextInt(tied.length)];
    }
    return candidates.first.id;
  }

  void _resetVotingRound() {
    final players = _state.players.map((p) => p.copyWith(hasVotedThisRound: false)).toList();
    _state = _state.copyWith(
      players: players,
      voteActions: const [],
      roundNumber: _state.roundNumber + 1,
    );
    _setPhase(GamePhase.nightPhase);
  }

  static String? _alphaInfected(List<Player> players) {
    final infected = players.where((p) => p.team == Team.infected).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return infected.isEmpty ? null : infected.first.id;
  }

  String _teamLabel(Team team) {
    switch (team) {
      case Team.human:
        return 'HUMANO';
      case Team.infected:
        return 'INFECTADO';
      case Team.neutral:
        return 'NEUTRAL';
    }
  }
}
