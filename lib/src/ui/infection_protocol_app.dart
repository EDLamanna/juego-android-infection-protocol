import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infection_protocol/src/audio/audio_manager.dart';
import 'package:infection_protocol/src/domain/models/game_config.dart';
import 'package:infection_protocol/src/domain/models/game_event.dart';
import 'package:infection_protocol/src/domain/models/game_role.dart';
import 'package:infection_protocol/src/domain/models/game_state.dart';
import 'package:infection_protocol/src/domain/models/player.dart';
import 'package:infection_protocol/src/domain/models/player_turn.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/game_engine.dart';
import 'package:infection_protocol/src/domain/services/role_distribution_service.dart';
import 'package:infection_protocol/src/flow/turn_flow_controller.dart';
import 'package:infection_protocol/src/security/anti_spoiler_system.dart';
import 'package:infection_protocol/src/ui/widgets/infection_icon.dart';

class InfectionProtocolApp extends StatelessWidget {
  const InfectionProtocolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infection Protocol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00BFA5)),
        useMaterial3: true,
      ),
      home: const GameRootScreen(),
    );
  }
}

enum UiScreen {
  boot,
  setup,
  nightIntro,
  nightToDiscussion,
  dayToNight,
  captainBrief,
  transfer,
  saboteurTransfer,
  roleReveal,
  investigateResult,
  analyzeResult,
  nightAction,
  saboteurDecision,
  dayDiscussion,
  voting,
  voteResolution,
  gameEnd,
}

class GameRootScreen extends StatefulWidget {
  const GameRootScreen({super.key});

  @override
  State<GameRootScreen> createState() => _GameRootScreenState();
}

class _GameRootScreenState extends State<GameRootScreen> {
  UiScreen _screen = UiScreen.boot;
  int _playerCount = 8;
  int _seed = DateTime.now().millisecondsSinceEpoch;

  GameEngine? _engine;
  TurnFlowController? _turnFlow;
  final AntiSpoilerSystem _antiSpoiler = AntiSpoilerSystem();
  final AudioManager _audioManager = AudioManager();

  PlayerTurn? _currentTurn;
  PlayerTurn? _previousTurn;
  String? _voteResolutionLabel;
  String? _selectedTarget;
  String? _investigationTargetName;
  String? _investigationTeamLabel;
  VoteResolutionVisualData? _voteResolutionData;
  List<String> _generatedPlayerNames = [];
  bool _playersGenerated = false;
  bool _nightIntroPending = false;
  bool _isSubmittingAction = false;
  int? _captainBriefRoundShown;
  int _lastProcessedEventCount = 0;

  void _secureLog(String message) {
    if (!kReleaseMode) {
      developer.log(message, name: 'InfectionProtocol.UI');
    }
  }

  @override
  void dispose() {
    unawaited(_audioManager.dispose());
    super.dispose();
  }

  void _initializeMatch() {
    if (!_playersGenerated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debes generar y completar los nombres de jugadores.')),
      );
      return;
    }

    final cleanedNames = _generatedPlayerNames.map((name) => name.trim()).toList();
    if (cleanedNames.any((name) => name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todos los jugadores deben tener nombre.')),
      );
      return;
    }

    final config = GameConfig.standard(seed: _seed);
    final distribution = RoleDistributionService();
    final players = List.generate(
      _playerCount,
      (index) => Player.alive(id: 'p$index', name: cleanedNames[index]),
    );

    final roles = distribution.generateRolesForMatch(
      playerCount: _playerCount,
      config: config,
    );
    final assigned = distribution.assignRoles(players: players, roles: roles, seed: _seed);

    final engine = GameEngine(config: config, players: assigned, roles: GameRole.catalog)
      ..startGame();

    setState(() {
      _engine = engine;
      _turnFlow = TurnFlowController(engine);
      _previousTurn = null;
      _currentTurn = null;
      _voteResolutionLabel = null;
      _selectedTarget = null;
      _voteResolutionData = null;
      _nightIntroPending = true;
      _lastProcessedEventCount = 0;
    });

    _processNewEvents();
    _prepareNextTurn();
  }

  void _prepareNextTurn() {
    final engine = _engine;
    final turnFlow = _turnFlow;
    if (engine == null || turnFlow == null) {
      return;
    }

    if (engine.state.currentPhase == GamePhase.gameOver) {
      setState(() => _screen = UiScreen.gameEnd);
      return;
    }

    final nextTurn = turnFlow.nextTurn();
    if (nextTurn == null) {
      turnFlow.completeTurnAndMaybeAdvancePhase();
      _processNewEvents();
      if (engine.state.currentPhase == GamePhase.gameOver) {
        setState(() => _screen = UiScreen.gameEnd);
        return;
      }
      _prepareNextTurn();
      return;
    }

    if (engine.state.currentPhase == GamePhase.saboteurDecision) {
      setState(() {
        _currentTurn = nextTurn;
        _selectedTarget = nextTurn.allowedTargets.isNotEmpty ? nextTurn.allowedTargets.first : null;
        _screen = UiScreen.saboteurTransfer;
      });
      return;
    }

    if (_nightIntroPending && nextTurn.phase == GamePhase.nightPhase) {
      setState(() {
        _currentTurn = nextTurn;
        _screen = UiScreen.nightIntro;
      });
      return;
    }

    if (nextTurn.turnType == TurnType.dayDiscussion) {
      setState(() {
        _currentTurn = nextTurn;
        _screen = UiScreen.nightToDiscussion;
      });
      return;
    }

    if (_shouldShowCaptainBrief(nextTurn)) {
      setState(() {
        _currentTurn = nextTurn;
        _captainBriefRoundShown = _engine?.state.roundNumber;
        _screen = UiScreen.captainBrief;
      });
      return;
    }

    final mustTransfer = _antiSpoiler.mustShowTransferScreen(
      previousTurn: _previousTurn,
      nextTurn: nextTurn,
    );

    setState(() {
      _currentTurn = nextTurn;
      _selectedTarget = nextTurn.allowedTargets.isNotEmpty ? nextTurn.allowedTargets.first : null;
      _screen = mustTransfer ? UiScreen.transfer : _screenForTurn(nextTurn);
    });
  }

  UiScreen _screenForTurn(PlayerTurn turn) {
    switch (turn.turnType) {
      case TurnType.roleReveal:
        return UiScreen.roleReveal;
      case TurnType.infectedVote:
      case TurnType.nightAction:
        return UiScreen.nightAction;
      case TurnType.saboteurDecision:
        return UiScreen.saboteurDecision;
      case TurnType.dayDiscussion:
        return UiScreen.dayDiscussion;
      case TurnType.voting:
        return UiScreen.voting;
      case TurnType.resultDisplay:
      case TurnType.passDevice:
        return UiScreen.transfer;
    }
  }

  void _completeTurn() {
    final turnFlow = _turnFlow;
    final turn = _currentTurn;
    if (turnFlow == null || turn == null) {
      return;
    }

    _previousTurn = turn;
    turnFlow.completeTurnAndMaybeAdvancePhase();
    _processNewEvents();

    final resolution = turnFlow.lastVoteResolution;
    if (resolution != null && (resolution.tieNoElimination || resolution.expelledPlayerId != null)) {
      setState(() {
        _voteResolutionLabel = resolution.tieNoElimination
            ? 'Empate: nadie fue expulsado.'
            : 'Jugador expulsado por votación.';
        _voteResolutionData = _buildVoteResolutionVisual(resolution);
        _screen = UiScreen.voteResolution;
      });
      turnFlow.lastVoteResolution = null;
      return;
    }

    _prepareNextTurn();
  }

  Future<void> _submitCurrentAction() async {
    if (_isSubmittingAction) {
      _secureLog('submit ignored: already submitting');
      return;
    }
    _isSubmittingAction = true;

    final engine = _engine;
    final turn = _currentTurn;
    final target = _selectedTarget;
    if (engine == null || turn == null) {
      _secureLog('submit aborted: engine or turn is null');
      _isSubmittingAction = false;
      return;
    }

    _secureLog(
      'submit action turnType=${turn.turnType.name} player=${turn.playerId} action=${turn.actionType?.name} target=$target phase=${engine.state.currentPhase.name} round=${engine.state.roundNumber}',
    );

    if (turn.actionType == null) {
      _completeTurn();
      _isSubmittingAction = false;
      return;
    }

    try {
      switch (turn.actionType!) {
        case ActionType.kill:
          final actor = _playerFor(turn.playerId);
          if (engine.state.currentPhase == GamePhase.saboteurDecision && target != null) {
            engine.submitSaboteurDecision(playerId: turn.playerId, targetId: target);
          } else if ((engine.state.currentPhase == GamePhase.infectedConsensus ||
                  (engine.state.currentPhase == GamePhase.nightPhase && actor.team == Team.infected)) &&
              target != null) {
            engine.submitInfectedVote(playerId: turn.playerId, targetId: target);
          } else if (target != null) {
            engine.submitNightAction(playerId: turn.playerId, actionType: ActionType.kill, targetId: target);
          }
          break;
        case ActionType.protect:
        case ActionType.investigate:
        case ActionType.analyze:
        case ActionType.sabotage:
          if (target != null) {
            engine.submitNightAction(playerId: turn.playerId, actionType: turn.actionType!, targetId: target);
            if (turn.actionType == ActionType.investigate) {
              final targetPlayer = _playerFor(target);
              _investigationTargetName = targetPlayer.name;
              _investigationTeamLabel = targetPlayer.team == Team.human ? 'HUMANO' : 'INFECTADO';
              if (mounted) {
                setState(() => _screen = UiScreen.investigateResult);
              }
              _isSubmittingAction = false;
              return;
            }
            if (turn.actionType == ActionType.analyze) {
              final targetPlayer = _playerFor(target);
              _investigationTargetName = targetPlayer.name;
              _investigationTeamLabel = targetPlayer.team == Team.infected ? 'INFECTADO' : 'HUMANO';
              if (mounted) {
                setState(() => _screen = UiScreen.analyzeResult);
              }
              _isSubmittingAction = false;
              return;
            }
          }
          break;
        case ActionType.vote:
          if (target != null) {
            engine.submitVote(voterId: turn.playerId, targetId: target);
          }
          break;
      }
    } catch (error) {
      _secureLog('submit action error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo confirmar la acción: $error')),
        );
      }
      _isSubmittingAction = false;
      return;
    }

    _completeTurn();
    _secureLog('submit action completed');
    _isSubmittingAction = false;
  }

  void _generatePlayers() {
    setState(() {
      _generatedPlayerNames = List.generate(_playerCount, (index) {
        final current = index < _generatedPlayerNames.length ? _generatedPlayerNames[index].trim() : '';
        return current.isEmpty ? 'Jugador ${index + 1}' : current;
      });
      _playersGenerated = true;
    });
  }

  void _updatePlayerName(int index, String value) {
    if (index >= _generatedPlayerNames.length) {
      return;
    }
    final copy = List<String>.from(_generatedPlayerNames);
    copy[index] = value;
    setState(() => _generatedPlayerNames = copy);
  }

  void _processNewEvents() {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    final events = engine.state.eventLog;
    if (_lastProcessedEventCount >= events.length) {
      return;
    }
    for (var index = _lastProcessedEventCount; index < events.length; index++) {
      unawaited(_audioManager.playForEvent(events[index].type));
    }
    _lastProcessedEventCount = events.length;
  }

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      UiScreen.boot => _BootScreen(
          onStart: () {
            unawaited(_audioManager.playButtonTap());
            setState(() => _screen = UiScreen.setup);
          },
        ),
      UiScreen.setup => _SetupScreen(
          initialPlayers: _playerCount,
          generatedNames: _generatedPlayerNames,
          onPlayersChanged: (value) => setState(() {
            _playerCount = value;
            _playersGenerated = false;
            _generatedPlayerNames = [];
          }),
          onGeneratePlayers: () {
            unawaited(_audioManager.playButtonTap());
            _generatePlayers();
          },
          onNameChanged: _updatePlayerName,
          onStartMatch: () {
            unawaited(_audioManager.playButtonTap());
            _initializeMatch();
          },
        ),
      UiScreen.nightIntro => _NightIntroScreen(
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            setState(() {
              _nightIntroPending = false;
              _screen = UiScreen.transfer;
            });
          },
        ),
      UiScreen.nightToDiscussion => _NightToDiscussionScreen(
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            setState(() => _screen = UiScreen.dayDiscussion);
          },
        ),
      UiScreen.captainBrief => _CaptainBriefScreen(
          captainName: _aliveCaptainName() ?? 'Capitán',
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            setState(() => _screen = UiScreen.dayDiscussion);
          },
        ),
      UiScreen.transfer => _TransferDeviceScreen(
          nextPlayerName: _displayName(_currentTurn?.playerId),
          onHoldStart: () => _audioManager.playTransferAlarm(),
          onContinue: () {
            final turn = _currentTurn;
            if (turn == null) {
              return;
            }
            setState(() => _screen = _screenForTurn(turn));
          },
        ),
      UiScreen.saboteurTransfer => _TransferDeviceScreen(
          nextPlayerName: _displayName(_currentTurn?.playerId),
          onHoldStart: () => _audioManager.playTransferAlarm(),
          onContinue: () {
            setState(() => _screen = UiScreen.saboteurDecision);
          },
        ),
      UiScreen.roleReveal => _RoleRevealScreen(
          player: _playerFor(_currentTurn!.playerId),
          roleImagePath: _roleImagePath(_playerFor(_currentTurn!.playerId).roleId),
          roleDescription: _roleDescription(_playerFor(_currentTurn!.playerId).roleId),
          infectedTeammateNames: _infectedTeammatesFor(_playerFor(_currentTurn!.playerId)),
          onUnderstood: () {
            unawaited(_audioManager.playButtonTap());
            _completeTurn();
          },
        ),
      UiScreen.investigateResult => _InvestigationResultScreen(
          targetName: _investigationTargetName ?? 'Jugador',
          teamLabel: _investigationTeamLabel ?? 'DESCONOCIDO',
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            _completeTurn();
          },
        ),
      UiScreen.analyzeResult => _AnalyzeResultScreen(
          targetName: _investigationTargetName ?? 'Jugador',
          teamLabel: _investigationTeamLabel ?? 'DESCONOCIDO',
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            _completeTurn();
          },
        ),
      UiScreen.nightAction => _ActionSelectionScreen(
          title: _currentTurn!.turnType == TurnType.infectedVote ? 'Consenso infectado' : 'Acción nocturna',
          playerName: _displayName(_currentTurn!.playerId),
          actionLabel: _actionLabelEs(_currentTurn!.actionType),
          targets: _currentTurn!.allowedTargets,
          targetNameForId: _displayName,
          selectedTarget: _selectedTarget,
          onTargetChanged: (value) => setState(() => _selectedTarget = value),
          skipLabel: _skipLabelForCurrentTurn(),
          infoMessage: _nightActionInfoMessage(),
          confirmEnabled: !(_mustSkipEngineerTurn() || _mustPassNightTurn()),
          onSkip: _skipLabelForCurrentTurn() != null
              ? () async {
                  await _audioManager.playButtonTap();
                  _completeTurn();
                }
              : null,
          onConfirm: () async {
            await _audioManager.playButtonTap();
            await _submitCurrentAction();
          },
        ),
      UiScreen.saboteurDecision => _ActionSelectionScreen(
          title: 'Decisión del Saboteador',
          playerName: _displayName(_currentTurn!.playerId),
          actionLabel: 'ELIMINAR',
          targets: _currentTurn!.allowedTargets,
          targetNameForId: _displayName,
          selectedTarget: _selectedTarget,
          onTargetChanged: (value) => setState(() => _selectedTarget = value),
          infoMessage: 'Elige quién será eliminado para decidir al ganador de la partida.',
          onConfirm: () async {
            await _audioManager.playButtonTap();
            await _submitCurrentAction();
          },
        ),
      UiScreen.dayDiscussion => _DayDiscussionScreen(
          timeLimitSeconds: _currentTurn?.timeLimit ?? 180,
          players: _engine?.state.players ?? const [],
          hadNightCasualty: _hadNightCasualtyThisRound(),
          nightVictimName: _nightVictimNameThisRound(),
          gameEndingAfterDiscussion: _willGameEndAfterDiscussion(),
          recentPublicEvents: _publicEvents(_engine?.state.eventLog ?? const []),
          onTimerWarning: () => _audioManager.playTimerWarning(),
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            _completeTurn();
          },
        ),
      UiScreen.voting => _ActionSelectionScreen(
          title: 'Votación',
          playerName: _displayName(_currentTurn!.playerId),
          actionLabel: 'VOTAR (${_playerFor(_currentTurn!.playerId).voteWeight} pts)',
          targets: _currentTurn!.allowedTargets,
          targetNameForId: _displayName,
          selectedTarget: _selectedTarget,
          onTargetChanged: (value) => setState(() => _selectedTarget = value),
          onConfirm: () async {
            await _audioManager.playButtonTap();
            await _submitCurrentAction();
          },
        ),
      UiScreen.voteResolution => _VoteResolutionScreen(
          message: _voteResolutionLabel ?? 'Resolución de votos',
          data: _voteResolutionData,
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            setState(() => _screen = UiScreen.dayToNight);
          },
        ),
      UiScreen.dayToNight => _DayToNightScreen(
          onContinue: () {
            unawaited(_audioManager.playButtonTap());
            _prepareNextTurn();
          },
        ),
      UiScreen.gameEnd => _GameEndScreen(
          winner: _engine?.state.winner,
          players: _engine?.state.players ?? const [],
          onRestart: () => setState(() {
            unawaited(_audioManager.playButtonTap());
            _seed = DateTime.now().millisecondsSinceEpoch;
            _screen = UiScreen.boot;
            _engine = null;
            _turnFlow = null;
            _currentTurn = null;
            _previousTurn = null;
            _voteResolutionLabel = null;
            _voteResolutionData = null;
            _playersGenerated = false;
            _generatedPlayerNames = [];
            _nightIntroPending = false;
            _captainBriefRoundShown = null;
            _lastProcessedEventCount = 0;
          }),
        ),
    };
  }

  VoteResolutionVisualData _buildVoteResolutionVisual(VoteResolutionResult resolution) {
    final entries = resolution.votes
        .map(
          (vote) => VoteVisual(
            voterName: _displayName(vote.voterId),
            targetName: _displayName(vote.targetId),
            weight: vote.voteWeight,
          ),
        )
        .toList();

    final tallyRows = resolution.tally.entries
        .map(
          (entry) => TallyRow(playerName: _displayName(entry.key), points: entry.value),
        )
        .toList()
      ..sort((a, b) => b.points.compareTo(a.points));

    return VoteResolutionVisualData(
      votes: entries,
      tallyRows: tallyRows,
      expelledPlayerName: resolution.expelledPlayerId == null ? null : _displayName(resolution.expelledPlayerId),
      tieNoElimination: resolution.tieNoElimination,
    );
  }

  List<GameEvent> _publicEvents(List<GameEvent> events) {
    return events
        .where((event) => event.visibility == EventVisibility.public)
        .toList()
        .reversed
        .take(5)
        .toList();
  }

  bool _hadNightCasualtyThisRound() {
    final engine = _engine;
    if (engine == null) {
      return false;
    }
    final currentRound = engine.state.roundNumber;
    return engine.state.eventLog.any(
      (event) =>
          event.visibility == EventVisibility.public &&
          event.type == EventType.playerKilled &&
          event.round == currentRound,
    );
  }

  String? _nightVictimNameThisRound() {
    final engine = _engine;
    if (engine == null) {
      return null;
    }
    final currentRound = engine.state.roundNumber;
    for (final event in engine.state.eventLog.reversed) {
      if (event.visibility != EventVisibility.public ||
          event.type != EventType.playerKilled ||
          event.round != currentRound ||
          event.playersInvolved.isEmpty) {
        continue;
      }
      return _displayName(event.playersInvolved.first);
    }
    return null;
  }

  bool _willGameEndAfterDiscussion() {
    final engine = _engine;
    if (engine == null) {
      return false;
    }
    final alive = engine.state.players.where((p) => p.isAlive).toList();
    final aliveInfected = alive.where((p) => p.team == Team.infected).length;
    final aliveSaboteur = alive.where((p) => p.roleId == RoleId.saboteador).length;
    final aliveTrueHumans = alive.where((p) => p.team == Team.human && p.roleId != RoleId.saboteador).length;

    if (aliveTrueHumans == 0 && aliveInfected >= 1) {
      return true;
    }
    if (aliveInfected == 0) {
      return true;
    }
    if (aliveTrueHumans == 1 && aliveInfected == 1 && aliveSaboteur == 1) {
      return false;
    }
    return aliveInfected >= aliveTrueHumans && aliveSaboteur == 0;
  }

  Player _playerFor(String playerId) {
    return _engine!.state.players.firstWhere((p) => p.id == playerId);
  }

  String _displayName(String? playerId) {
    if (playerId == null || _engine == null) {
      return 'Jugador';
    }
    return _playerFor(playerId).name;
  }

  String _roleImagePath(RoleId roleId) {
    switch (roleId) {
      case RoleId.tripulante:
        return 'assets/images/roles/tripulante_marin.jpg';
      case RoleId.infectado:
        return 'assets/images/roles/infectado_a.jpg';
      case RoleId.ingeniero:
        return 'assets/images/roles/Ingeniero.jpg';
      case RoleId.doctor:
        return 'assets/images/roles/doctor.jpg';
      case RoleId.angelGuardian:
        return 'assets/images/roles/angel_guardian.jpg';
      case RoleId.saboteador:
        return 'assets/images/roles/Saboteador.jpg';
      case RoleId.capitan:
        return 'assets/images/roles/capitan.jpg';
    }
  }

  String _roleDescription(RoleId roleId) {
    switch (roleId) {
      case RoleId.tripulante:
        return 'Tripulante regular sin habilidad nocturna.';
      case RoleId.infectado:
        return 'Participa en consenso infectado para eliminar a un humano.';
      case RoleId.ingeniero:
        return 'Investiga a un jugador y descubre si es humano o infectado.';
      case RoleId.doctor:
        return 'Analiza un jugador eliminado para conocer su equipo.';
      case RoleId.angelGuardian:
        return 'Protege a un jugador vivo contra un ataque nocturno.';
      case RoleId.saboteador:
        return 'Cancela la primera acción válida de la noche (una sola vez).';
      case RoleId.capitan:
        return 'Vota como humano en fase diurna.';
    }
  }

  String? _aliveCaptainName() {
    final engine = _engine;
    if (engine == null) {
      return null;
    }
    for (final player in engine.state.players) {
      if (player.roleId == RoleId.capitan && player.isAlive) {
        return player.name;
      }
    }
    return null;
  }

  bool _shouldShowCaptainBrief(PlayerTurn nextTurn) {
    final engine = _engine;
    if (engine == null) {
      return false;
    }
    if (nextTurn.turnType != TurnType.dayDiscussion) {
      return false;
    }
    if (_aliveCaptainName() == null) {
      return false;
    }
    return _captainBriefRoundShown != engine.state.roundNumber;
  }

  String _actionLabelEs(ActionType? actionType) {
    switch (actionType) {
      case ActionType.kill:
        return 'ELIMINAR';
      case ActionType.protect:
        return 'PROTEGER';
      case ActionType.investigate:
        return 'INVESTIGAR';
      case ActionType.analyze:
        return 'ANALIZAR';
      case ActionType.sabotage:
        return 'SABOTEAR';
      case ActionType.vote:
        return 'VOTAR';
      case null:
        return 'SIN ACCIÓN';
    }
  }

  bool _mustPassNightTurn() {
    final turn = _currentTurn;
    if (turn == null) {
      return false;
    }
    return turn.turnType == TurnType.nightAction && turn.actionType == null;
  }

  bool _mustSkipEngineerTurn() {
    final engine = _engine;
    final turn = _currentTurn;
    if (engine == null || turn == null) {
      return false;
    }
    if (turn.turnType != TurnType.nightAction || turn.actionType != ActionType.investigate) {
      return false;
    }
    return !engine.canUseNightAction(playerId: turn.playerId, actionType: ActionType.investigate);
  }

  String? _skipLabelForCurrentTurn() {
    final turn = _currentTurn;
    if (turn == null) {
      return null;
    }
    if (_mustPassNightTurn()) {
      return 'Pasar turno';
    }
    if (turn.actionType == ActionType.sabotage) {
      return 'No usar sabotaje todavía';
    }
    if (_mustSkipEngineerTurn()) {
      return 'Saltar turno';
    }
    return null;
  }

  String? _nightActionInfoMessage() {
    if (_mustPassNightTurn()) {
      return 'Este jugador no tiene acción nocturna. Pasa el móvil al siguiente.';
    }
    if (_mustSkipEngineerTurn()) {
      return 'Ingeniero: esta noche no puedes investigar. Debes saltar turno.';
    }
    return null;
  }

  List<String> _infectedTeammatesFor(Player player) {
    if (player.team != Team.infected || _engine == null) {
      return const [];
    }
    try {
      return _engine!.getInfectedTeammates(player.id).map((mate) => mate.name).toList();
    } catch (_) {
      return const [];
    }
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const InfectionAppIcon(size: 120),
            const SizedBox(height: 20),
            const Text('INFECTION PROTOCOL', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(onPressed: onStart, child: const Text('Start Game')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupScreen extends StatelessWidget {
  const _SetupScreen({
    required this.initialPlayers,
    required this.generatedNames,
    required this.onPlayersChanged,
    required this.onGeneratePlayers,
    required this.onNameChanged,
    required this.onStartMatch,
  });

  final int initialPlayers;
  final List<String> generatedNames;
  final ValueChanged<int> onPlayersChanged;
  final VoidCallback onGeneratePlayers;
  final void Function(int, String) onNameChanged;
  final VoidCallback onStartMatch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Jugadores: $initialPlayers'),
            Slider(
              value: initialPlayers.toDouble(),
              min: 5,
              max: 12,
              divisions: 7,
              label: '$initialPlayers',
              onChanged: (value) => onPlayersChanged(value.round()),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onGeneratePlayers, child: const Text('Generar jugadores')),
            const SizedBox(height: 12),
            if (generatedNames.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: generatedNames.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextFormField(
                        initialValue: generatedNames[index],
                        onChanged: (value) => onNameChanged(index, value),
                        decoration: InputDecoration(
                          labelText: 'Nombre jugador ${index + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(onPressed: onStartMatch, child: const Text('Iniciar partida')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferDeviceScreen extends StatefulWidget {
  const _TransferDeviceScreen({
    required this.nextPlayerName,
    required this.onHoldStart,
    required this.onContinue,
  });

  final String nextPlayerName;
  final Future<void> Function() onHoldStart;
  final VoidCallback onContinue;

  @override
  State<_TransferDeviceScreen> createState() => _TransferDeviceScreenState();
}

class _TransferDeviceScreenState extends State<_TransferDeviceScreen> {
  Timer? _holdTimer;
  Timer? _progressTimer;
  double _progress = 0;
  static const _holdDurationMs = 2000;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startHolding() {
    _holdTimer?.cancel();
    _progressTimer?.cancel();
    setState(() => _progress = 0);

    unawaited(widget.onHoldStart());

    _holdTimer = Timer(const Duration(milliseconds: _holdDurationMs), widget.onContinue);

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _progress += 100 / _holdDurationMs;
        if (_progress > 1) {
          _progress = 1;
        }
      });
      if (_progress >= 1) {
        timer.cancel();
      }
    });
  }

  void _cancelHolding() {
    _holdTimer?.cancel();
    _progressTimer?.cancel();
    setState(() => _progress = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('ACCESS RESTRICTED', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Text('Entrega el dispositivo a: ${widget.nextPlayerName}', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Listener(
                onPointerDown: (_) => _startHolding(),
                onPointerCancel: (_) => _cancelHolding(),
                onPointerUp: (_) => _cancelHolding(),
                child: Container(
                  height: 96,
                  width: 340,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Mantén presionado 2 segundos', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(value: _progress),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleRevealScreen extends StatelessWidget {
  const _RoleRevealScreen({
    required this.player,
    required this.roleImagePath,
    required this.roleDescription,
    required this.infectedTeammateNames,
    required this.onUnderstood,
  });

  final Player player;
  final String roleImagePath;
  final String roleDescription;
  final List<String> infectedTeammateNames;
  final VoidCallback onUnderstood;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Role Reveal')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(player.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.asset(
                  roleImagePath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Rol: ${player.roleId.name.toUpperCase()}'),
            Text('Equipo: ${_teamLabel(player.team)}'),
            const SizedBox(height: 8),
            Text(roleDescription),
            if (infectedTeammateNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Compañeros infectados: ${infectedTeammateNames.join(', ')}'),
            ],
            const Spacer(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(onPressed: onUnderstood, child: const Text('Entendido')),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvestigationResultScreen extends StatelessWidget {
  const _InvestigationResultScreen({
    required this.targetName,
    required this.teamLabel,
    required this.onContinue,
  });

  final String targetName;
  final String teamLabel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado de investigación')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Investigación completada', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('Objetivo: $targetName', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text('Equipo detectado: $teamLabel', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continuar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyzeResultScreen extends StatelessWidget {
  const _AnalyzeResultScreen({
    required this.targetName,
    required this.teamLabel,
    required this.onContinue,
  });

  final String targetName;
  final String teamLabel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado de autopsia')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Autopsia completada', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('Objetivo: $targetName', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text('Equipo detectado: $teamLabel', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continuar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSelectionScreen extends StatelessWidget {
  const _ActionSelectionScreen({
    required this.title,
    required this.playerName,
    required this.actionLabel,
    required this.targets,
    required this.targetNameForId,
    required this.selectedTarget,
    required this.onTargetChanged,
    this.skipLabel,
    this.onSkip,
    this.infoMessage,
    this.confirmEnabled = true,
    required this.onConfirm,
  });

  final String title;
  final String playerName;
  final String actionLabel;
  final List<String> targets;
  final String Function(String?) targetNameForId;
  final String? selectedTarget;
  final ValueChanged<String?> onTargetChanged;
  final String? skipLabel;
  final Future<void> Function()? onSkip;
  final String? infoMessage;
  final bool confirmEnabled;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(playerName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('Acción: $actionLabel'),
            const SizedBox(height: 14),
            if (infoMessage != null) ...[
              Text(infoMessage!, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
            if (targets.isEmpty)
              const Text('Sin objetivos válidos. Turno omitido automáticamente.')
            else
              DropdownButton<String>(
                isExpanded: true,
                value: selectedTarget,
                items: targets
                    .map((target) => DropdownMenuItem(value: target, child: Text(targetNameForId(target))))
                    .toList(),
                onChanged: onTargetChanged,
              ),
            const Spacer(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onSkip != null && skipLabel != null) ...[
                    OutlinedButton(
                      onPressed: () => unawaited(onSkip!()),
                      child: Text(skipLabel!),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton(
                    onPressed: confirmEnabled ? () => unawaited(onConfirm()) : null,
                    child: const Text('Confirmar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDiscussionScreen extends StatefulWidget {
  const _DayDiscussionScreen({
    required this.timeLimitSeconds,
    required this.players,
    required this.hadNightCasualty,
    required this.nightVictimName,
    required this.gameEndingAfterDiscussion,
    required this.recentPublicEvents,
    required this.onTimerWarning,
    required this.onContinue,
  });

  final int timeLimitSeconds;
  final List<Player> players;
  final bool hadNightCasualty;
  final String? nightVictimName;
  final bool gameEndingAfterDiscussion;
  final List<GameEvent> recentPublicEvents;
  final Future<void> Function() onTimerWarning;
  final VoidCallback onContinue;

  @override
  State<_DayDiscussionScreen> createState() => _DayDiscussionScreenState();
}

class _DayDiscussionScreenState extends State<_DayDiscussionScreen> {
  Timer? _timer;
  late int _remaining;
  late List<String> _discussionFeed;
  bool _warningPlayed = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.timeLimitSeconds;
    _discussionFeed = _buildDiscussionFeed();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);

      if (_remaining == 5 && !_warningPlayed) {
        _warningPlayed = true;
        unawaited(widget.onTimerWarning());
      }

      if (_remaining <= 0) {
        timer.cancel();
        widget.onContinue();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<String> _buildDiscussionFeed() {
    final feed = <String>[];

    if (!widget.hadNightCasualty) {
      feed.add('No hubo desapariciones esta noche.');
    } else if (widget.nightVictimName != null) {
      feed.add('⚠️ No aparece en la nave: ${widget.nightVictimName}.');
    }

    for (final event in widget.recentPublicEvents) {
      feed.add(event.message);
    }

    if (widget.gameEndingAfterDiscussion) {
      feed.add('⚠️ La partida terminó. Al continuar verás el resultado final.');
    }

    feed.addAll(_aiAccusations());
    return feed;
  }

  List<String> _aiAccusations() {
    final alive = widget.players.where((p) => p.isAlive).toList();
    if (alive.length < 3) {
      return const [];
    }

    final random = Random(DateTime.now().millisecondsSinceEpoch);
    final infectedAlive = alive.where((p) => p.team == Team.infected).toList();
    final humanAlive = alive.where((p) => p.team == Team.human).toList();

    if (infectedAlive.isEmpty || humanAlive.length < 2) {
      return const [];
    }

    infectedAlive.shuffle(random);
    humanAlive.shuffle(random);

    final suspects = <Player>[infectedAlive.first, humanAlive[0], humanAlive[1]];
    suspects.shuffle(random);

    const lugares = [
      'en el módulo de comunicaciones',
      'cerca del reactor',
      'en la bahía de carga',
      'junto al panel de oxígeno',
      'en los ductos de mantenimiento',
    ];

    const actividades = [
      'manipulando un panel sin autorización',
      'escondiendo herramientas al escuchar pasos',
      'apagando y encendiendo sistemas sin motivo',
      'cambiando rutas de energía de forma extraña',
      'evitando responder al resto de la tripulación',
    ];

    final lines = <String>['🤖 Análisis IA: se detectan 3 perfiles de alta sospecha.'];

    for (final suspect in suspects) {
      final lugar = lugares[random.nextInt(lugares.length)];
      final actividad = actividades[random.nextInt(actividades.length)];
      lines.add('• ${suspect.name}: fue visto $lugar, $actividad.');
    }

    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final warning = _remaining <= 5;
    final color = warning && _remaining.isEven
        ? Colors.red.shade200
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(title: const Text('Discusión')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.hadNightCasualty
                  ? 'SE HA DETECTADO UNA BAJA DURANTE LA NOCHE'
                  : 'NO HUBO DESAPARICIONES ESTA NOCHE',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Text('Tiempo restante: $_remaining s'),
            ),
            const SizedBox(height: 12),
            const Text('Dashboard de jugadores'),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: ListView.builder(
                itemCount: widget.players.length,
                itemBuilder: (context, index) {
                  final player = widget.players[index];
                  final karma = player.totalVotesReceived.clamp(0, 60);
                  final karmaColor = karma < 20
                      ? Colors.blue
                      : (karma < 50 ? Colors.amber : Colors.red);
                  final eliminated = !player.isAlive;
                  return Opacity(
                    opacity: eliminated ? 0.45 : 1,
                    child: ListTile(
                      dense: true,
                      title: Text(
                        player.name,
                        style: TextStyle(
                          decoration: eliminated ? TextDecoration.lineThrough : TextDecoration.none,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Estado: ${eliminated ? 'eliminado' : 'vivo'}'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: karma / 60, color: karmaColor),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const Text('Eventos de sucesos'),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                itemCount: _discussionFeed.length,
                itemBuilder: (context, index) {
                  return Text(_discussionFeed[index]);
                },
              ),
            ),
            const SizedBox(height: 12),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(
                onPressed: widget.onContinue,
                child: Text(widget.gameEndingAfterDiscussion ? 'Ver resultado final' : 'Iniciar votación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NightIntroScreen extends StatelessWidget {
  const _NightIntroScreen({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('FASE NOCTURNA', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Todos los roles ya fueron asignados.\nComienza la noche.'),
              const SizedBox(height: 20),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 24),
                child: FilledButton(onPressed: onContinue, child: const Text('Comenzar fase nocturna')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NightToDiscussionScreen extends StatelessWidget {
  const _NightToDiscussionScreen({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('LA NOCHE YA PASÓ', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Todos los tripulantes se dirigen a la sala de control para empezar la reunión.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 24),
                child: FilledButton(onPressed: onContinue, child: const Text('Ir a discusión')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptainBriefScreen extends StatelessWidget {
  const _CaptainBriefScreen({
    required this.captainName,
    required this.onContinue,
  });

  final String captainName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('PASA EL MÓVIL AL CAPITÁN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Capitán asignado: $captainName', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              const Text(
                'El Capitán debe leer y comunicar los sucesos de la discusión al resto de la tripulación.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 24),
                child: FilledButton(onPressed: onContinue, child: const Text('Capitán listo')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoteResolutionScreen extends StatelessWidget {
  const _VoteResolutionScreen({required this.message, required this.data, required this.onContinue});

  final String message;
  final VoteResolutionVisualData? data;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resolución')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _VoteResolutionAnimatedBody(
            message: message,
            data: data,
            onContinue: onContinue,
          ),
        ),
      ),
    );
  }
}

class _VoteResolutionAnimatedBody extends StatefulWidget {
  const _VoteResolutionAnimatedBody({
    required this.message,
    required this.data,
    required this.onContinue,
  });

  final String message;
  final VoteResolutionVisualData? data;
  final VoidCallback onContinue;

  @override
  State<_VoteResolutionAnimatedBody> createState() => _VoteResolutionAnimatedBodyState();
}

class _VoteResolutionAnimatedBodyState extends State<_VoteResolutionAnimatedBody> {
  int _shownVotes = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final votes = widget.data?.votes ?? const <VoteVisual>[];
    if (votes.isNotEmpty) {
      _timer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _shownVotes++;
          if (_shownVotes >= votes.length) {
            timer.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(widget.message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 24),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 24),
            child: FilledButton(onPressed: widget.onContinue, child: const Text('Continuar')),
          ),
        ],
      );
    }

    final shown = data.votes.take(_shownVotes).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('Votos en curso'),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final vote = shown[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 250),
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset((1 - value) * -60, 0),
                    child: Opacity(opacity: value, child: child),
                  );
                },
                child: Text('🗳️ ${vote.voterName} → ${vote.targetName} (+${vote.weight})'),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Text('Conteo final'),
        const SizedBox(height: 6),
        ...data.tallyRows.map((row) => Text('${row.playerName}: ${row.points} pts')),
        const Spacer(),
        Text(
          data.tieNoElimination
              ? 'Resultado: empate, no hay expulsado.'
              : 'Expulsado: ${data.expelledPlayerName ?? 'N/A'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 24),
          child: FilledButton(onPressed: widget.onContinue, child: const Text('Continuar')),
        ),
      ],
    );
  }
}

class _DayToNightScreen extends StatelessWidget {
  const _DayToNightScreen({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('LA NOCHE LLEGA DE PRISA', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Los tripulantes se sienten indefensos y se van a sus habitaciones a dormir.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 24),
                child: FilledButton(onPressed: onContinue, child: const Text('Ir a fase nocturna')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VoteResolutionVisualData {
  const VoteResolutionVisualData({
    required this.votes,
    required this.tallyRows,
    required this.expelledPlayerName,
    required this.tieNoElimination,
  });

  final List<VoteVisual> votes;
  final List<TallyRow> tallyRows;
  final String? expelledPlayerName;
  final bool tieNoElimination;
}

class VoteVisual {
  const VoteVisual({required this.voterName, required this.targetName, required this.weight});

  final String voterName;
  final String targetName;
  final int weight;
}

class TallyRow {
  const TallyRow({required this.playerName, required this.points});

  final String playerName;
  final int points;
}

class _GameEndScreen extends StatelessWidget {
  const _GameEndScreen({
    required this.winner,
    required this.players,
    required this.onRestart,
  });

  final Team? winner;
  final List<Player> players;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final label = switch (winner) {
      Team.human => 'HUMANOS',
      Team.infected => 'INFECTADOS',
      Team.neutral => 'NEUTRAL',
      null => 'SIN DEFINIR',
    };
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('GAME OVER', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Ganador: $label'),
            const SizedBox(height: 12),
            const Text('Roles finales'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  return ListTile(
                    dense: true,
                    title: Text(player.name),
                    subtitle: Text('${player.roleId.name.toUpperCase()} · ${player.team.name.toUpperCase()}'),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 24),
              child: FilledButton(onPressed: onRestart, child: const Text('Nueva partida')),
            ),
          ],
        ),
      ),
    );
  }
}
