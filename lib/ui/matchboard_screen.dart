import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/board.dart';
import '../data/fixtures.dart';
import '../data/store.dart';
import '../logic/assistant.dart';
import '../logic/claude_assistant.dart';
import 'matches_screen.dart';

/// Matchboard tab: the workspaces the user has opened, newest activity first.
class MatchboardScreen extends StatelessWidget {
  const MatchboardScreen({super.key, required this.store, required this.api, this.onBrowseMatches});
  final BankStore store;
  final FixturesApi api;
  final VoidCallback? onBrowseMatches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final boards = store.boards;
        if (boards.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.space_dashboard_outlined, size: 56, color: cs.primary),
                const SizedBox(height: 16),
                Text('Your match workspaces', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Open any match and tap the board icon. Ask questions in its chat and every answer is kept '
                  'on the board as a key note, next to your own notes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                if (onBrowseMatches != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onBrowseMatches,
                    icon: const Icon(Icons.sports_soccer),
                    label: const Text('Browse matches'),
                  ),
                ],
              ]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: boards.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _BoardTile(
            board: boards[i],
            onTap: () => openBoard(context, store: store, api: api, board: boards[i]),
            onDelete: () => _confirmDelete(context, boards[i]),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Board b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this board?'),
        content: Text('${b.title}: its chat and ${b.noteCount} notes will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteBoard(b);
  }
}

/// Opens a board. With an AI key in Settings the chat uses Claude with web
/// search, otherwise the offline [DataAssistant].
Future<void> openBoard(BuildContext context,
    {required BankStore store, required FixturesApi api, required Board board, MatchAssistant? assistant}) async {
  final key = assistant == null ? (await store.pref(aiKeyPref))?.trim() ?? '' : '';
  final chosen = assistant ?? (key.isEmpty ? const DataAssistant() : ClaudeAssistant(key));
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => BoardPage(store: store, api: api, board: board, assistant: chosen),
  ));
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.board, required this.onTap, required this.onDelete});
  final Board board;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = board;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(
              width: 52,
              height: 40,
              child: Stack(children: [
                TeamLogo(url: b.homeLogo, name: b.home, size: 32),
                Positioned(right: 0, bottom: 0, child: TeamLogo(url: b.awayLogo, name: b.away, size: 32)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('${b.leagueName} · ${DateFormat.MMMd().add_Hm().format(b.kickoff.toLocal())}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (b.lastNote != null)
                  Text('Latest: ${b.lastNote}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.primary)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text('${b.noteCount}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
                Text('notes', style: theme.textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

const _categoryIcons = <String, IconData>{
  'Summary': Icons.auto_awesome,
  'Odds': Icons.percent,
  'Form': Icons.trending_up,
  'Goals': Icons.sports_soccer,
  'H2H': Icons.compare_arrows,
  'Table': Icons.table_rows,
  'Line-ups': Icons.groups,
  'Stats': Icons.bar_chart,
  'News': Icons.newspaper,
  'Research': Icons.travel_explore,
  'My notes': Icons.edit_note,
};

/// One match's workspace: the board of saved notes and the chat that feeds it.
class BoardPage extends StatefulWidget {
  const BoardPage({
    super.key,
    required this.store,
    required this.api,
    required this.board,
    this.assistant = const DataAssistant(),
  });
  final BankStore store;
  final FixturesApi api;
  final Board board;
  final MatchAssistant assistant;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _input = TextEditingController();
  final _chatScroll = ScrollController();
  List<BoardMessage> _messages = [];
  List<BoardNote> _notes = [];
  String _filter = 'All';
  bool _thinking = false;
  late final Future<MatchDetails?> _details = _loadDetails();

  Board get board => widget.board;
  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _reload(initial: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _input.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<MatchDetails?> _loadDetails() async {
    try {
      return await widget.api.details(board.toMatch());
    } on FixturesException {
      return null;
    }
  }

  Future<void> _reload({bool initial = false}) async {
    final m = await store.messages(board);
    final n = await store.notes(board);
    if (!mounted) return;
    setState(() {
      _messages = m;
      _notes = n;
    });
    // A fresh board opens on the chat, an existing one on its notes.
    if (initial && n.isEmpty) _tabs.index = 1;
    _scrollChat();
  }

  void _scrollChat() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScroll.hasClients) _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
      });

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _thinking) return;
    _input.clear();
    setState(() => _thinking = true);
    await store.addMessage(board, ChatRole.user, q);
    await _reload();
    final details = await _details;
    final history = [
      for (final m in _messages) (m.role == ChatRole.user, m.text),
    ];
    // The question itself was just saved as the last message.
    if (history.isNotEmpty && history.last.$1 && history.last.$2 == q) history.removeLast();
    final AssistantReply reply;
    if (details == null) {
      reply = const AssistantReply("I couldn't load this match's data. Check your connection and ask again.");
    } else {
      reply = await widget.assistant.ask(q, board.toMatch(), details, history: history);
    }
    await store.addMessage(board, ChatRole.assistant, reply.text);
    if (reply.note != null) {
      await store.addNote(board, category: reply.note!.category, title: reply.note!.title, body: reply.note!.body);
    }
    await _reload();
    if (mounted) setState(() => _thinking = false);
    if (reply.note != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Saved to the board: ${reply.note!.title}'),
          persist: false, // an action would otherwise keep it on screen
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: 'View', onPressed: () => _tabs.animateTo(0)),
        ));
    }
  }

  Future<void> _addOwnNote() async {
    final text = TextEditingController();
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Your note', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'e.g. Their keeper is back from injury'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c, text.text.trim()), child: const Text('Save to board')),
        ]),
      ),
    );
    text.dispose();
    if (saved == null || saved.isEmpty) return;
    final firstLine = saved.split('\n').first;
    await store.addNote(board,
        category: 'My notes',
        title: firstLine.length > 40 ? '${firstLine.substring(0, 40)}…' : firstLine,
        body: saved,
        source: 'user');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchboard')),
      body: Column(children: [
        _BoardHeader(board: board, notes: _notes.length),
        TabBar(controller: _tabs, tabs: [
          Tab(text: 'Board (${_notes.length})'),
          const Tab(text: 'Chat'),
        ]),
        Expanded(
          child: TabBarView(controller: _tabs, children: [_boardTab(), _chatTab()]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ Board

  Widget _boardTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.push_pin_outlined, size: 44, color: cs.primary),
            const SizedBox(height: 12),
            Text('Nothing on the board yet', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Ask in the chat and each answer is saved here. You can add your own notes too.',
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                  onPressed: () => _tabs.animateTo(1), icon: const Icon(Icons.chat_bubble_outline), label: const Text('Ask')),
              OutlinedButton.icon(onPressed: _addOwnNote, icon: const Icon(Icons.edit_note), label: const Text('Add note')),
            ]),
          ]),
        ),
      );
    }
    final cats = ['All', ...{for (final n in _notes) n.category}];
    final shown = _filter == 'All' ? _notes : _notes.where((n) => n.category == _filter).toList();
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c),
                  avatar: c == 'All' ? null : Icon(_categoryIcons[c] ?? Icons.label_outline, size: 16),
                  selected: _filter == c,
                  onSelected: (_) => setState(() => _filter = c),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        for (final n in shown)
          _NoteCard(
            note: n,
            onPin: () async {
              await store.setNotePinned(n, !n.pinned);
              await _reload();
            },
            onDelete: () async {
              await store.deleteNote(board, n);
              await _reload();
            },
          ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'add-note',
          onPressed: _addOwnNote,
          icon: const Icon(Icons.edit_note),
          label: const Text('Add note'),
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------ Chat

  Widget _chatTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(children: [
      Expanded(
        child: _messages.isEmpty
            ? ListView(padding: const EdgeInsets.all(24), children: [
                Icon(Icons.forum_outlined, size: 44, color: cs.primary),
                const SizedBox(height: 12),
                Text('Ask about ${board.title}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  widget.assistant is ClaudeAssistant
                      ? 'Ask anything. Claude answers with the match data and searches the web for the rest. '
                          'Each answer is saved on the board.'
                      : 'Answers come from the match data: odds, form, head to head, goals, table, line-ups, stats and '
                          'news. Each answer is saved on the board. Add an AI key in Settings to ask anything.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ])
            : ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                itemCount: _messages.length + (_thinking ? 1 : 0),
                itemBuilder: (_, i) => i == _messages.length
                    ? const _Bubble(text: '…', mine: false)
                    : _Bubble(text: _messages[i].text, mine: _messages[i].role == ChatRole.user),
              ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final q in suggestedQuestions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(label: Text(q), onPressed: _thinking ? null : () => _ask(q)),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: _ask,
                decoration: const InputDecoration(hintText: 'Ask about this match', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _thinking ? null : () => _ask(_input.text),
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({required this.board, required this.notes});
  final Board board;
  final int notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = board;
    Widget team(String name, String? logo) => Expanded(
          child: Column(children: [
            TeamLogo(url: logo, name: name, size: 40),
            const SizedBox(height: 6),
            Text(name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [cs.primaryContainer, cs.surfaceContainerHigh]),
      ),
      child: Row(children: [
        team(b.home, b.homeLogo),
        Column(children: [
          Text(DateFormat.Hm().format(b.kickoff.toLocal()),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(DateFormat.MMMd().format(b.kickoff.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(b.leagueName, style: theme.textTheme.labelSmall?.copyWith(color: cs.primary)),
        ]),
        team(b.away, b.awayLogo),
      ]),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onPin, required this.onDelete});
  final BoardNote note;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = note;
    final mine = n.source == 'user';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: mine ? cs.secondary : cs.primary, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_categoryIcons[n.category] ?? Icons.label_outline, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(n.category.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: cs.primary)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: n.pinned ? 'Unpin' : 'Pin to top',
            onPressed: onPin,
            icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18,
                color: n.pinned ? cs.primary : cs.onSurfaceVariant),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete note',
            onPressed: onDelete,
            icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(n.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
            const SizedBox(height: 6),
            Text(
              '${mine ? 'Your note' : 'From chat'} · ${DateFormat.MMMd().add_Hm().format(DateTime.parse(n.created))}',
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Text(text, style: TextStyle(color: mine ? cs.onPrimary : cs.onSurface, height: 1.35)),
      ),
    );
  }
}
