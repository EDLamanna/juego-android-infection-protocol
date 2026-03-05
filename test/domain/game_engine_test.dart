import 'package:flutter_test/flutter_test.dart';
import 'package:infection_protocol/src/domain/models/game_config.dart';
import 'package:infection_protocol/src/domain/models/game_role.dart';
import 'package:infection_protocol/src/domain/models/player.dart';
import 'package:infection_protocol/src/domain/models/value_objects.dart';
import 'package:infection_protocol/src/domain/services/game_engine.dart';

void main() {
  group('GameEngine core rules', () {
    late GameEngine engine;

    setUp(() {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human),
        Player.alive(id: 'h3', name: 'H3', roleId: RoleId.angelGuardian, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();
    });

    test('consenso infectado por mayoría fija target final', () {
      engine.forcePhase(GamePhase.infectedConsensus);

      engine.submitInfectedVote(playerId: 'i1', targetId: 'h1');
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');

      expect(engine.state.infectedVotingState.finalTarget, 'h1');
      expect(engine.state.infectedVotingState.isLocked, true);
    });

    test('en noche todos los vivos reciben turno y los sin rol nocturno no tienen acción', () {
      engine.forcePhase(GamePhase.nightPhase);

      final firstTurn = engine.getNextPlayerTurn();
      expect(firstTurn, isNotNull);
      expect(firstTurn!.playerId, 'h1');
      expect(firstTurn.turnType, TurnType.nightAction);
      expect(firstTurn.actionType, isNull);
      expect(firstTurn.allowedTargets, isEmpty);

      engine.completeCurrentTurn();
      final secondTurn = engine.getNextPlayerTurn();
      expect(secondTurn, isNotNull);
      expect(secondTurn!.playerId, 'h2');
      expect(secondTurn.actionType, ActionType.investigate);
    });

    test('protección bloquea kill nocturno', () {
      engine.forcePhase(GamePhase.nightPhase);

      engine.submitNightAction(
        playerId: 'h3',
        actionType: ActionType.protect,
        targetId: 'h1',
      );

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i1', targetId: 'h1');
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');

      engine.resolveNightActions();

      expect(engine.playerById('h1').status, PlayerStatus.alive);
      expect(
        engine.state.eventLog.any((e) => e.type == EventType.playerAttackBlocked),
        true,
      );
    });

    test('resolución de empate en votación no elimina en primer empate', () {
      engine.forcePhase(GamePhase.votingPhase);

      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i2');
      engine.submitVote(voterId: 'h3', targetId: 'i1');
      engine.submitVote(voterId: 'i1', targetId: 'i2');
      engine.submitVote(voterId: 'i2', targetId: 'h1');

      final result = engine.resolveVoting();

      expect(result.expelledPlayerId, isNull);
      expect(engine.state.tieCounter, 1);
    });

    test('votante no puede votar dos veces en la misma ronda', () {
      engine.forcePhase(GamePhase.votingPhase);

      engine.submitVote(voterId: 'h1', targetId: 'i1');
      expect(
        () => engine.submitVote(voterId: 'h1', targetId: 'i2'),
        throwsA(isA<StateError>()),
      );
    });

    test('no se permite auto-voto', () {
      engine.forcePhase(GamePhase.votingPhase);

      expect(
        () => engine.submitVote(voterId: 'h1', targetId: 'h1'),
        throwsA(isA<StateError>()),
      );
    });

    test('segundo empate consecutivo activa muerte súbita y expulsa por historial', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human),
        Player.alive(id: 'h3', name: 'H3', roleId: RoleId.angelGuardian, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected)
            .copyWith(totalVotesReceived: 5),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected)
            .copyWith(totalVotesReceived: 1),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine.forcePhase(GamePhase.votingPhase);
      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i2');
      engine.submitVote(voterId: 'h3', targetId: 'i1');
      engine.submitVote(voterId: 'i1', targetId: 'i2');
      engine.submitVote(voterId: 'i2', targetId: 'h1');

      final firstTie = engine.resolveVoting();
      expect(firstTie.expelledPlayerId, isNull);
      expect(engine.state.tieCounter, 1);

      engine.forcePhase(GamePhase.votingPhase);
      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i2');
      engine.submitVote(voterId: 'h3', targetId: 'i1');
      engine.submitVote(voterId: 'i1', targetId: 'i2');
      engine.submitVote(voterId: 'i2', targetId: 'h1');

      final secondTie = engine.resolveVoting();
      expect(secondTie.expelledPlayerId, 'i1');
      expect(engine.playerById('i1').status, PlayerStatus.eliminated);
      expect(engine.state.tieCounter, 0);
    });

    test('al iniciar voting phase todos los jugadores tienen peso de voto 10', () {
      final boostedSetup = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human)
            .copyWith(totalVotesReceived: 4),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human)
            .copyWith(totalVotesReceived: 0),
        Player.alive(id: 'h3', name: 'H3', roleId: RoleId.angelGuardian, team: Team.human)
            .copyWith(totalVotesReceived: 3),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected)
            .copyWith(totalVotesReceived: 3),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: boostedSetup,
        roles: GameRole.catalog,
      )..startGame();

      engine.forcePhase(GamePhase.votingPhase);

      expect(engine.playerById('h1').voteWeight, 10);
      expect(engine.playerById('h2').voteWeight, 10);
      expect(engine.playerById('h3').voteWeight, 10);
      expect(engine.playerById('i1').voteWeight, 10);
      expect(
        engine.state.eventLog.any((event) => event.type == EventType.voteWeightBoost),
        false,
      );
    });

    test('con 3 jugadores vivos no aplica boost dinámico y todos votan 10', () {
      final threeAlive = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human)
            .copyWith(totalVotesReceived: 4),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human)
            .copyWith(totalVotesReceived: 0),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected)
            .copyWith(totalVotesReceived: 3),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: threeAlive,
        roles: GameRole.catalog,
      )..startGame();

      engine.forcePhase(GamePhase.votingPhase);

      expect(engine.playerById('h1').voteWeight, 10);
      expect(engine.playerById('h2').voteWeight, 10);
      expect(engine.playerById('i1').voteWeight, 10);
      expect(
        engine.state.eventLog.any((event) => event.type == EventType.voteWeightBoost),
        false,
      );
    });

    test('sabotaje cancela la primera acción válida no-kill', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h3', name: 'H3', roleId: RoleId.angelGuardian, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      )..startGame();

      engine.forcePhase(GamePhase.nightPhase);

      engine.submitNightAction(
        playerId: 's1',
        actionType: ActionType.sabotage,
        targetId: 'h1',
      );
      engine.submitNightAction(
        playerId: 'h3',
        actionType: ActionType.protect,
        targetId: 'h1',
      );

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');
      engine.resolveNightActions();

      expect(engine.playerById('h1').status, PlayerStatus.eliminated);
    });

    test('ingeniero genera evento privado con resultado de investigación', () {
      engine = engine.eliminatePlayers(const []);
      engine.forcePhase(GamePhase.votingPhase);
      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i1');
      engine.submitVote(voterId: 'h3', targetId: 'i1');
      engine.submitVote(voterId: 'i1', targetId: 'h1');
      engine.submitVote(voterId: 'i2', targetId: 'h1');
      engine.resolveVoting();

      engine.forcePhase(GamePhase.nightPhase);

      engine.submitNightAction(
        playerId: 'h2',
        actionType: ActionType.investigate,
        targetId: 'i2',
      );

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');
      engine.resolveNightActions();

      final investigationEvents = engine.state.eventLog.where((event) => event.type == EventType.investigationResult).toList();
      expect(investigationEvents.isNotEmpty, true);
      expect(investigationEvents.last.visibility, EventVisibility.private);
      expect(investigationEvents.last.playersInvolved, contains('h2'));
      expect(investigationEvents.last.message.contains('INFECTADO'), true);
    });

    test('si ingeniero investiga saboteador, saboteador muere aunque infectados maten a otro', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine.forcePhase(GamePhase.nightPhase);
      engine.submitNightAction(
        playerId: 'h2',
        actionType: ActionType.investigate,
        targetId: 's1',
      );

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i1', targetId: 'h1');
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');
      engine.resolveNightActions();

      expect(engine.playerById('s1').status, PlayerStatus.eliminated);
      expect(engine.playerById('h1').status, PlayerStatus.eliminated);
    });

    test('si infectados eligen saboteador, no muere nadie en la noche', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i1', targetId: 's1');
      engine.submitInfectedVote(playerId: 'i2', targetId: 's1');
      engine.resolveNightActions();

      expect(engine.playerById('s1').status, PlayerStatus.alive);
      expect(engine.playerById('h1').status, PlayerStatus.alive);
      expect(engine.playerById('h2').status, PlayerStatus.alive);
      final killedEvents = engine.state.eventLog.where((event) => event.type == EventType.playerKilled).toList();
      expect(killedEvents, isEmpty);
    });

    test('si infectados eligen saboteador pero ingeniero lo investiga, saboteador muere', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.ingeniero, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine.forcePhase(GamePhase.nightPhase);
      engine.submitNightAction(
        playerId: 'h2',
        actionType: ActionType.investigate,
        targetId: 's1',
      );

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i1', targetId: 's1');
      engine.submitInfectedVote(playerId: 'i2', targetId: 's1');
      engine.resolveNightActions();

      expect(engine.playerById('s1').status, PlayerStatus.eliminated);
      expect(engine.playerById('h1').status, PlayerStatus.alive);
      final killedEvents = engine.state.eventLog.where((event) => event.type == EventType.playerKilled).toList();
      expect(killedEvents.length, 1);
      expect(killedEvents.single.playersInvolved, contains('s1'));
    });

    test('ingeniero puede investigar en primera noche y no en la siguiente', () {
      engine.forcePhase(GamePhase.nightPhase);
      expect(
        () => engine.submitNightAction(
          playerId: 'h2',
          actionType: ActionType.investigate,
          targetId: 'i1',
        ),
        returnsNormally,
      );

      engine.forcePhase(GamePhase.votingPhase);
      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i1');
      engine.submitVote(voterId: 'h3', targetId: 'i2');
      engine.submitVote(voterId: 'i1', targetId: 'h1');
      engine.submitVote(voterId: 'i2', targetId: 'h1');
      engine.resolveVoting();

      engine.forcePhase(GamePhase.nightPhase);
      expect(
        () => engine.submitNightAction(
          playerId: 'h2',
          actionType: ActionType.investigate,
          targetId: 'i2',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('ingeniero vuelve a poder investigar tras esperar una noche', () {
      engine.forcePhase(GamePhase.nightPhase);
      engine.submitNightAction(
        playerId: 'h2',
        actionType: ActionType.investigate,
        targetId: 'i1',
      );

      engine.forcePhase(GamePhase.votingPhase);
      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i1');
      engine.submitVote(voterId: 'h3', targetId: 'i2');
      engine.submitVote(voterId: 'i1', targetId: 'h1');
      engine.submitVote(voterId: 'i2', targetId: 'h1');
      engine.resolveVoting();

      engine.forcePhase(GamePhase.votingPhase);
      engine.submitVote(voterId: 'h1', targetId: 'i1');
      engine.submitVote(voterId: 'h2', targetId: 'i1');
      engine.submitVote(voterId: 'h3', targetId: 'i2');
      engine.submitVote(voterId: 'i1', targetId: 'h1');
      engine.submitVote(voterId: 'i2', targetId: 'h1');
      engine.resolveVoting();

      engine.forcePhase(GamePhase.nightPhase);
      expect(
        () => engine.submitNightAction(
          playerId: 'h2',
          actionType: ActionType.investigate,
          targetId: 'i2',
        ),
        returnsNormally,
      );
    });

    test('doctor analiza eliminado y recibe autopsia privada', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'd1', name: 'D1', roleId: RoleId.doctor, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.angelGuardian, team: Team.human),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine = engine.eliminatePlayers(const ['i1']);
      engine.forcePhase(GamePhase.nightPhase);
      engine.submitNightAction(
        playerId: 'd1',
        actionType: ActionType.analyze,
        targetId: 'i1',
      );

      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');
      engine.resolveNightActions();

      final autopsyEvents = engine.state.eventLog.where((event) => event.type == EventType.autopsyResult).toList();
      expect(autopsyEvents.isNotEmpty, true);
      expect(autopsyEvents.last.visibility, EventVisibility.private);
      expect(autopsyEvents.last.playersInvolved, contains('d1'));
      expect(autopsyEvents.last.message.contains('INFECTADO'), true);
    });

    test('doctor no puede analizar jugador vivo', () {
      final players = [
        Player.alive(id: 'd1', name: 'D1', roleId: RoleId.doctor, team: Team.human),
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.angelGuardian, team: Team.human),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 13),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine.forcePhase(GamePhase.nightPhase);
      expect(
        () => engine.submitNightAction(
          playerId: 'd1',
          actionType: ActionType.analyze,
          targetId: 'h1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza acción nocturna que no corresponde al rol', () {
      engine.forcePhase(GamePhase.nightPhase);
      expect(
        () => engine.submitNightAction(
          playerId: 'h2',
          actionType: ActionType.sabotage,
          targetId: 'i1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('saboteador no puede usar sabotaje más de una vez', () {
      final players = [
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 'h2', name: 'H2', roleId: RoleId.angelGuardian, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
        Player.alive(id: 'i2', name: 'I2', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 44),
        players: players,
        roles: GameRole.catalog,
      );
      engine.startGame();

      engine.forcePhase(GamePhase.nightPhase);
      engine.submitNightAction(playerId: 's1', actionType: ActionType.sabotage, targetId: 'h1');
      engine.forcePhase(GamePhase.infectedConsensus);
      engine.submitInfectedVote(playerId: 'i1', targetId: 'h1');
      engine.submitInfectedVote(playerId: 'i2', targetId: 'h1');
      engine.resolveNightActions();

      engine.forcePhase(GamePhase.nightPhase);
      expect(
        () => engine.submitNightAction(playerId: 's1', actionType: ActionType.sabotage, targetId: 'h2'),
        throwsA(isA<StateError>()),
      );
    });

    test('consenso infectado rechaza voto de infectado eliminado', () {
      engine = engine.eliminatePlayers(const ['i1']);
      engine.forcePhase(GamePhase.infectedConsensus);

      expect(
        () => engine.submitInfectedVote(playerId: 'i1', targetId: 'h1'),
        throwsA(isA<StateError>()),
      );
    });

    test('infectados ganan cuando no quedan humanos verdaderos', () {
      final players = [
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 31),
        players: players,
        roles: GameRole.catalog,
      )..startGame();

      final winner = engine.checkWinConditions();
      expect(winner, Team.infected);
    });

    test('infectados ganan por dominancia cuando no hay saboteador vivo', () {
      final updated = engine.eliminatePlayers(const ['h1', 'h2']);
      engine = updated;

      final winner = engine.checkWinConditions();
      expect(winner, Team.infected);
    });

    test('si hay escenario kingmaker (1 humano, 1 infectado, 1 saboteador), no se decide ganador automático', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 32),
        players: players,
        roles: GameRole.catalog,
      )..startGame();

      final winner = engine.checkWinConditions();
      expect(winner, isNull);
      expect(engine.state.currentPhase, GamePhase.saboteurDecision);
      final turn = engine.getNextPlayerTurn();
      expect(turn, isNotNull);
      expect(turn!.turnType, TurnType.saboteurDecision);
      expect(turn.playerId, 's1');
      expect(turn.allowedTargets, containsAll(['h1', 'i1']));
    });

    test('en fase kingmaker, si saboteador elimina infectado ganan humanos', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 41),
        players: players,
        roles: GameRole.catalog,
      )..startGame();

      engine.checkWinConditions();
      engine.submitSaboteurDecision(playerId: 's1', targetId: 'i1');

      expect(engine.state.currentPhase, GamePhase.gameOver);
      expect(engine.state.winner, Team.human);
    });

    test('en fase kingmaker, si saboteador elimina humano ganan infectados', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
        Player.alive(id: 'i1', name: 'I1', roleId: RoleId.infectado, team: Team.infected),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 42),
        players: players,
        roles: GameRole.catalog,
      )..startGame();

      engine.checkWinConditions();
      engine.submitSaboteurDecision(playerId: 's1', targetId: 'h1');

      expect(engine.state.currentPhase, GamePhase.gameOver);
      expect(engine.state.winner, Team.infected);
    });

    test('humanos ganan cuando no quedan infectados vivos aunque saboteador siga vivo', () {
      final players = [
        Player.alive(id: 'h1', name: 'H1', roleId: RoleId.tripulante, team: Team.human),
        Player.alive(id: 's1', name: 'S1', roleId: RoleId.saboteador, team: Team.human),
      ];

      engine = GameEngine(
        config: GameConfig.standard(seed: 33),
        players: players,
        roles: GameRole.catalog,
      )..startGame();

      final winner = engine.checkWinConditions();
      expect(winner, Team.human);
    });

    test('humanos ganan cuando no quedan infectados vivos', () {
      final updated = engine.eliminatePlayers(const ['i1', 'i2']);
      engine = updated;

      final winner = engine.checkWinConditions();
      expect(winner, Team.human);
    });
  });
}
