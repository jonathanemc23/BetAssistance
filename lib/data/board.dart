import 'fixtures.dart';

/// A Matchboard: one workspace per match, holding the chat and the notes the
/// user keeps while studying it.
class Board {
  const Board({
    this.id,
    required this.matchId,
    required this.leagueSlug,
    required this.leagueName,
    required this.home,
    required this.away,
    this.homeLogo,
    this.awayLogo,
    required this.kickoff,
    required this.created,
    required this.updated,
    this.noteCount = 0,
    this.lastNote,
  });

  final int? id;
  final String matchId;
  final String leagueSlug;
  final String leagueName;
  final String home;
  final String away;
  final String? homeLogo;
  final String? awayLogo;
  final DateTime kickoff; // UTC
  final String created;
  final String updated;

  /// Filled in by the list query only.
  final int noteCount;
  final String? lastNote;

  String get title => '$home vs $away';

  factory Board.fromMatch(Match m, String now) => Board(
        matchId: m.id,
        leagueSlug: m.league.slug,
        leagueName: m.league.name,
        home: m.home.name,
        away: m.away.name,
        homeLogo: m.home.logo,
        awayLogo: m.away.logo,
        kickoff: m.kickoff,
        created: now,
        updated: now,
      );

  /// Enough of a [Match] to fetch its details again.
  Match toMatch() => Match(
        id: matchId,
        league: League(leagueSlug, leagueName),
        kickoff: kickoff,
        home: Team(home, home, homeLogo, null),
        away: Team(away, away, awayLogo, null),
        state: MatchState.other,
        detail: '',
      );

  Map<String, Object?> toRow() => {
        'match_id': matchId,
        'league_slug': leagueSlug,
        'league_name': leagueName,
        'home': home,
        'away': away,
        'home_logo': homeLogo,
        'away_logo': awayLogo,
        'kickoff': kickoff.toUtc().toIso8601String(),
        'created': created,
        'updated': updated,
      };

  factory Board.fromRow(Map<String, Object?> r) => Board(
        id: r['id'] as int?,
        matchId: r['match_id'] as String,
        leagueSlug: r['league_slug'] as String,
        leagueName: r['league_name'] as String? ?? '',
        home: r['home'] as String,
        away: r['away'] as String,
        homeLogo: r['home_logo'] as String?,
        awayLogo: r['away_logo'] as String?,
        kickoff: DateTime.parse(r['kickoff'] as String).toUtc(),
        created: r['created'] as String,
        updated: r['updated'] as String,
        noteCount: (r['note_count'] as int?) ?? 0,
        lastNote: r['last_note'] as String?,
      );
}

enum ChatRole { user, assistant }

class BoardMessage {
  const BoardMessage({this.id, required this.boardId, required this.role, required this.text, required this.created});
  final int? id;
  final int boardId;
  final ChatRole role;
  final String text;
  final String created;

  Map<String, Object?> toRow() => {'board_id': boardId, 'role': role.name, 'text': text, 'created': created};

  factory BoardMessage.fromRow(Map<String, Object?> r) => BoardMessage(
        id: r['id'] as int?,
        boardId: r['board_id'] as int,
        role: r['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
        text: r['text'] as String,
        created: r['created'] as String,
      );
}

/// A key fact or note pinned to the board. [source] is 'assistant' for saved
/// answers and 'user' for notes typed by hand.
class BoardNote {
  const BoardNote({
    this.id,
    required this.boardId,
    required this.category,
    required this.title,
    required this.body,
    this.source = 'assistant',
    this.pinned = false,
    required this.created,
  });
  final int? id;
  final int boardId;
  final String category;
  final String title;
  final String body;
  final String source;
  final bool pinned;
  final String created;

  BoardNote copyWith({bool? pinned}) => BoardNote(
        id: id,
        boardId: boardId,
        category: category,
        title: title,
        body: body,
        source: source,
        pinned: pinned ?? this.pinned,
        created: created,
      );

  Map<String, Object?> toRow() => {
        'board_id': boardId,
        'category': category,
        'title': title,
        'body': body,
        'source': source,
        'pinned': pinned ? 1 : 0,
        'created': created,
      };

  factory BoardNote.fromRow(Map<String, Object?> r) => BoardNote(
        id: r['id'] as int?,
        boardId: r['board_id'] as int,
        category: r['category'] as String,
        title: r['title'] as String,
        body: r['body'] as String,
        source: r['source'] as String? ?? 'assistant',
        pinned: (r['pinned'] as int? ?? 0) == 1,
        created: r['created'] as String,
      );
}
