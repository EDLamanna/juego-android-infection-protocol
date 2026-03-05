import 'package:infection_protocol/src/domain/models/player_turn.dart';

class AntiSpoilerSystem {
  bool mustShowTransferScreen({PlayerTurn? previousTurn, PlayerTurn? nextTurn}) {
    if (nextTurn == null) {
      return false;
    }
    if (previousTurn == null) {
      return true;
    }
    return previousTurn.playerId != nextTurn.playerId;
  }
}
