import 'game_event.dart';

class VisiblePlayer {
  const VisiblePlayer({
    required this.id,
    required this.name,
    required this.status,
    required this.roleLabel,
    required this.teamLabel,
    required this.roleHidden,
  });

  final String id;
  final String name;
  final String status;
  final String roleLabel;
  final String teamLabel;
  final bool roleHidden;
}

class PlayerView {
  const PlayerView({
    required this.requesterId,
    required this.players,
    required this.visibleEvents,
  });

  final String requesterId;
  final List<VisiblePlayer> players;
  final List<GameEvent> visibleEvents;
}

class PublicPlayerRef {
  const PublicPlayerRef({required this.id, required this.name});

  final String id;
  final String name;
}
