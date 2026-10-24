import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/fixtures.dart';

/// Pitch colours: the same in every theme, like a real pitch.
const _grass = Color(0xFF2F7A45);
const _grassDark = Color(0xFF2A6E3E);
const _lines = Color(0xD9FFFFFF);

/// Shots on target are red, as on TV graphics.
const shotRed = Color(0xFFE53935);

// ---------------------------------------------------------------- Stat tiles

/// A stat worth a tile of its own: ESPN's name, a label and an icon.
class _TileSpec {
  const _TileSpec(this.key, this.label, this.icon);
  final String key;
  final String label;
  final Widget Function(BuildContext context) icon;
}

Widget Function(BuildContext) _icon(IconData i) =>
    (c) => Icon(i, size: 20, color: Theme.of(c).colorScheme.primary);

Widget Function(BuildContext) _card(Color color) =>
    (c) => Container(
      width: 13,
      height: 18,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );

final _tiles = [
  _TileSpec('wonCorners', 'Corners', _icon(Icons.flag_rounded)),
  _TileSpec('totalShots', 'Shots', _icon(Icons.sports_soccer)),
  _TileSpec('shotsOnTarget', 'On target', _icon(Icons.gps_fixed)),
  _TileSpec('saves', 'Saves', _icon(Icons.back_hand_outlined)),
  _TileSpec('foulsCommitted', 'Fouls', _icon(Icons.sports)),
  _TileSpec('offsides', 'Offsides', _icon(Icons.outlined_flag)),
  _TileSpec('yellowCards', 'Yellow cards', _card(const Color(0xFFF2C230))),
  _TileSpec('redCards', 'Red cards', _card(const Color(0xFFD9372B))),
  // Basketball
  _TileSpec('totalRebounds', 'Rebounds', _icon(Icons.sports_basketball)),
  _TileSpec('assists', 'Assists', _icon(Icons.handshake_outlined)),
  _TileSpec('steals', 'Steals', _icon(Icons.pan_tool_alt_outlined)),
  _TileSpec('blocks', 'Blocks', _icon(Icons.block)),
  _TileSpec('turnovers', 'Turnovers', _icon(Icons.swap_horiz)),
  _TileSpec('fouls', 'Fouls', _icon(Icons.sports)),
  _TileSpec('fieldGoalPct', 'Field goal %', _icon(Icons.percent)),
  _TileSpec('threePointFieldGoalPct', '3-point %', _icon(Icons.looks_3_outlined)),
];

/// ESPN names shown as tiles, so the stat list below can leave them out.
final Set<String> tileStatKeys = {for (final t in _tiles) t.key};

/// Corners, shots, cards and the like as tiles: an icon, both teams' counts
/// with the leader highlighted, and a split bar.
class StatTiles extends StatelessWidget {
  const StatTiles({super.key, required this.values, this.max});
  final Map<String, (String, String)> values;

  /// Show at most this many tiles (the overview shows the first six).
  final int? max;

  static bool any(Map<String, (String, String)> values) => _tiles.any((t) => values.containsKey(t.key));

  @override
  Widget build(BuildContext context) {
    var specs = [
      for (final t in _tiles)
        if (values.containsKey(t.key)) t,
    ];
    if (max != null && specs.length > max!) specs = specs.sublist(0, max);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final w = (box.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in specs)
              SizedBox(
                width: w,
                child: _StatTile(spec: t, value: values[t.key]!),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.spec, required this.value});
  final _TileSpec spec;
  final (String, String) value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = statNumber(value.$1) ?? 0, a = statNumber(value.$2) ?? 0;
    Widget number(String v, bool lead, Color color) => Text(
      v,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: lead ? color : cs.onSurface.withValues(alpha: 0.75),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: spec.icon(context),
          ),
          const SizedBox(height: 6),
          Text(
            spec.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 28,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  number(value.$1, h > a, cs.primary),
                  const SizedBox(width: 14),
                  number(value.$2, a > h, cs.tertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: h + a == 0
                  ? ColoredBox(color: cs.surfaceContainerHighest, child: const SizedBox.expand())
                  : Row(
                      children: [
                        if (h > 0)
                          Expanded(
                            flex: (h * 100).round(),
                            child: ColoredBox(color: cs.primary, child: const SizedBox.expand()),
                          ),
                        if (h > 0 && a > 0) const SizedBox(width: 2),
                        if (a > 0)
                          Expanded(
                            flex: (a * 100).round(),
                            child: ColoredBox(color: cs.tertiary, child: const SizedBox.expand()),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "59.9%" -> 59.9, "+3" -> 3.
double? statNumber(String v) => double.tryParse(v.replaceAll('%', '').replaceAll('+', '').trim());

// ---------------------------------------------------------------- Shot map

/// Every attempt on a full pitch: the home team shoots to the right, the away
/// team to the left. Filled red circles were on target, a red circle with a
/// white ring went in, hollow circles missed and faded ones were blocked.
/// Tap a circle to see who took it.
class ShotMap extends StatefulWidget {
  const ShotMap({super.key, required this.shots, required this.home, required this.away, this.compact = false});
  final List<Shot> shots;
  final Team home, away;

  /// Just the pitch and legend, for the overview.
  final bool compact;

  @override
  State<ShotMap> createState() => _ShotMapState();
}

class _ShotMapState extends State<ShotMap> {
  String? _side; // null: both
  Shot? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shots = [
      for (final s in widget.shots)
        if (_side == null || s.side == _side) s,
    ];
    String count(String side) {
      final mine = widget.shots.where((s) => s.side == side);
      final on = mine.where((s) => s.kind == ShotKind.onTarget || s.kind == ShotKind.goal).length;
      return '${mine.length} shots · $on on target';
    }

    final compact = widget.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              const ButtonSegment(value: '', label: Text('Both')),
              ButtonSegment(
                value: 'home',
                label: Text(widget.home.shortName, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: 'away',
                label: Text(widget.away.shortName, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {_side ?? ''},
            onSelectionChanged: (s) => setState(() {
              _side = s.first.isEmpty ? null : s.first;
              _selected = null;
            }),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                '◀ ${widget.away.shortName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                '${widget.home.shortName} ▶',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 105 / 68,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                onTapUp: (d) {
                  Shot? best;
                  var bestDist = 24.0;
                  for (final s in shots) {
                    final dist = (_onPitch(s, size) - d.localPosition).distance;
                    if (dist < bestDist) {
                      best = s;
                      bestDist = dist;
                    }
                  }
                  setState(() => _selected = best == _selected ? null : best);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CustomPaint(
                    size: size,
                    painter: _ShotPainter(shots: shots, selected: _selected),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (compact)
          const SizedBox.shrink()
        else if (_selected case final s?)
          _ShotCaption(shot: s, team: s.side == 'home' ? widget.home : widget.away)
        else
          Text(
            'Tap a circle to see who took the shot.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        const SizedBox(height: 10),
        const ShotLegend(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                count('home'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              count('away'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 14),
          Text(
            'WHERE THE SHOTS WENT',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          GoalMouth(shots: shots, selected: _selected),
          const SizedBox(height: 6),
          Text(
            "Across the goal is from the feed; the height isn't, so shots are spread up and down.",
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Where [s] was taken from on a pitch of [size].
Offset _onPitch(Shot s, Size size) => s.side == 'home'
    ? Offset(s.x / 100 * size.width, (100 - s.y) / 100 * size.height)
    : Offset((100 - s.x) / 100 * size.width, s.y / 100 * size.height);

Offset? _endOnPitch(Shot s, Size size) {
  if (s.endX == null || s.endY == null) return null;
  return _onPitch(Shot(side: s.side, kind: s.kind, x: s.endX!, y: s.endY!), size);
}

class _ShotCaption extends StatelessWidget {
  const _ShotCaption({required this.shot, required this.team});
  final Shot shot;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final what = switch (shot.kind) {
      ShotKind.goal => 'Goal',
      ShotKind.onTarget => 'Saved',
      ShotKind.offTarget => 'Missed',
      ShotKind.blocked => 'Blocked',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _ShotDot(kind: shot.kind, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${shot.clock} ${shot.player.isEmpty ? team.shortName : shot.player} · $what',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (shot.text.isNotEmpty)
                  Text(
                    shot.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the circles mean.
class ShotLegend extends StatelessWidget {
  const ShotLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    Widget item(ShotKind k, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShotDot(kind: k, size: 12),
        const SizedBox(width: 4),
        Text(text, style: style),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        item(ShotKind.goal, 'Goal'),
        item(ShotKind.onTarget, 'On target'),
        item(ShotKind.offTarget, 'Off target'),
        item(ShotKind.blocked, 'Blocked'),
      ],
    );
  }
}

/// One legend marker, drawn on a scrap of grass so hollow circles show.
class _ShotDot extends StatelessWidget {
  const _ShotDot({required this.kind, required this.size});
  final ShotKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size + 6,
    height: size + 6,
    decoration: const BoxDecoration(color: _grass, shape: BoxShape.circle),
    child: CustomPaint(painter: _DotPainter(kind, size / 2)),
  );
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.kind, this.r);
  final ShotKind kind;
  final double r;
  @override
  void paint(Canvas canvas, Size size) => _paintShot(canvas, size.center(Offset.zero), kind, r);
  @override
  bool shouldRepaint(_DotPainter old) => old.kind != kind || old.r != r;
}

void _paintShot(Canvas canvas, Offset c, ShotKind kind, double r, {bool selected = false}) {
  final rr = selected ? r * 1.4 : r;
  switch (kind) {
    case ShotKind.goal:
      canvas.drawCircle(c, rr * 1.15, Paint()..color = shotRed);
      canvas.drawCircle(
        c,
        rr * 1.15,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Colors.white,
      );
      canvas.drawCircle(c, rr * 0.38, Paint()..color = Colors.white);
    case ShotKind.onTarget:
      canvas.drawCircle(c, rr, Paint()..color = shotRed);
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.8),
      );
    case ShotKind.offTarget:
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    case ShotKind.blocked:
      canvas.drawCircle(
        c,
        rr * 0.85,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.5),
      );
  }
}

class _ShotPainter extends CustomPainter {
  _ShotPainter({required this.shots, required this.selected});
  final List<Shot> shots;
  final Shot? selected;

  @override
  void paint(Canvas canvas, Size size) {
    paintPitch(canvas, size, horizontal: true);
    final r = size.width / 70;
    // Misses and blocks first, so the shots on target sit on top.
    final order = [...shots]..sort((a, b) => _rank(a.kind).compareTo(_rank(b.kind)));
    for (final s in order) {
      final c = _onPitch(s, size);
      if (identical(s, selected)) {
        final end = _endOnPitch(s, size);
        if (end != null) {
          canvas.drawLine(
            c,
            end,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      _paintShot(canvas, c, s.kind, r, selected: identical(s, selected));
    }
  }

  static int _rank(ShotKind k) => switch (k) {
    ShotKind.blocked => 0,
    ShotKind.offTarget => 1,
    ShotKind.onTarget => 2,
    ShotKind.goal => 3,
  };

  @override
  bool shouldRepaint(_ShotPainter old) => old.shots != shots || old.selected != selected;
}

/// A football pitch with its markings: lengthways left to right when
/// [horizontal], else bottom to top.
void paintPitch(Canvas canvas, Size size, {required bool horizontal}) {
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = _grass);
  // Mowing stripes.
  const stripes = 10;
  for (var i = 0; i < stripes; i += 2) {
    final r = horizontal
        ? Rect.fromLTWH(size.width / stripes * i, 0, size.width / stripes, size.height)
        : Rect.fromLTWH(0, size.height / stripes * i, size.width, size.height / stripes);
    canvas.drawRect(r, Paint()..color = _grassDark);
  }
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = _lines;
  // Work in a lengthways frame of 105 x 68 metres.
  canvas.save();
  if (horizontal) {
    canvas.scale(size.width / 105, size.height / 68);
  } else {
    canvas.translate(0, size.height);
    canvas.rotate(-math.pi / 2);
    canvas.scale(size.height / 105, size.width / 68);
  }
  line.strokeWidth = 1.5 / (horizontal ? size.width / 105 : size.height / 105);
  final dot = Paint()..color = _lines;
  canvas.drawRect(const Rect.fromLTWH(0.6, 0.6, 103.8, 66.8), line);
  canvas.drawLine(const Offset(52.5, 0), const Offset(52.5, 68), line);
  canvas.drawCircle(const Offset(52.5, 34), 9.15, line);
  canvas.drawCircle(const Offset(52.5, 34), 0.6, dot);
  for (final left in [true, false]) {
    double x(double v) => left ? v : 105 - v;
    canvas.drawRect(Rect.fromLTRB(math.min(x(0), x(16.5)), 13.85, math.max(x(0), x(16.5)), 54.15), line);
    canvas.drawRect(Rect.fromLTRB(math.min(x(0), x(5.5)), 24.85, math.max(x(0), x(5.5)), 43.15), line);
    canvas.drawCircle(Offset(x(11), 34), 0.6, dot);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(x(11), 34), radius: 9.15),
      left ? -0.93 : math.pi - 0.93,
      1.86,
      false,
      line,
    );
    // The goal, just behind the line.
    canvas.drawRect(
      Rect.fromLTRB(math.min(x(0), x(-1.2)), 30.34, math.max(x(0), x(-1.2)), 37.66),
      line..strokeWidth = line.strokeWidth * 1.6,
    );
    line.strokeWidth = line.strokeWidth / 1.6;
  }
  canvas.restore();
}

// ---------------------------------------------------------------- Goal mouth

/// The goal seen from the pitch: shots on target inside the frame, misses
/// outside it (wide, or over the bar when they were straight).
class GoalMouth extends StatelessWidget {
  const GoalMouth({super.key, required this.shots, this.selected, this.onTarget, this.offTarget});
  final List<Shot> shots;
  final Shot? selected;

  /// Counts to show when there are no shot positions: [onTarget] filled
  /// circles in the goal and [offTarget] hollow ones around it.
  final int? onTarget, offTarget;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3.2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _GoalPainter(
            shots: shots.isNotEmpty || onTarget == null
                ? [
                    for (final s in shots)
                      if (s.kind != ShotKind.blocked) s,
                  ]
                : [
                    for (var i = 0; i < onTarget!; i++)
                      Shot(side: '', kind: ShotKind.onTarget, x: 0, y: 0, clock: 'n$i'),
                    for (var i = 0; i < (offTarget ?? 0); i++)
                      Shot(side: '', kind: ShotKind.offTarget, x: 0, y: 0, clock: 'f$i'),
                  ],
            selected: selected,
          ),
        ),
      ),
    );
  }
}

class _GoalPainter extends CustomPainter {
  _GoalPainter({required this.shots, required this.selected});
  final List<Shot> shots;
  final Shot? selected;

  // The strip shows 32 units across (about 22 m) around the goal.
  static const _span = 32.0, _postL = 50 + 5.38, _postR = 50 - 5.38;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _grassDark);
    final ground = size.height * 0.86;
    double sx(double gy) => (50 + _span / 2 - gy) / _span * size.width;
    final left = sx(_postL), right = sx(_postR);
    final bar = ground - (right - left) / 3; // 2.44 m of 7.32 m
    // Net
    final net = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var x = left; x <= right; x += 8) {
      canvas.drawLine(Offset(x, bar), Offset(x, ground), net);
    }
    for (var y = bar; y <= ground; y += 8) {
      canvas.drawLine(Offset(left, y), Offset(right, y), net);
    }
    canvas.drawLine(
      Offset(0, ground),
      Offset(size.width, ground),
      Paint()
        ..color = _lines
        ..strokeWidth = 1.5,
    );
    final frame = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(left, ground)
        ..lineTo(left, bar)
        ..lineTo(right, bar)
        ..lineTo(right, ground),
      frame,
    );

    final r = size.height / 16;
    final noPositions = shots.every((s) => s.goalY == null);
    final ins = [
      for (final s in shots)
        if (s.kind == ShotKind.goal || s.kind == ShotKind.onTarget) s,
    ];
    final outs = [
      for (final s in shots)
        if (s.kind == ShotKind.offTarget) s,
    ];
    final order = [...outs, ...ins];
    for (final (i, s) in order.indexed) {
      final inside = s.kind != ShotKind.offTarget;
      final jitter = _unit(s, i);
      double x;
      double y;
      if (noPositions) {
        // Spread evenly: inside the goal, or in an arc around it.
        final list = inside ? ins : outs;
        final k = list.indexOf(s), n = list.length;
        if (inside) {
          x = left + (right - left) * (k + 1) / (n + 1);
          y = bar + (ground - bar) * (0.3 + 0.45 * jitter);
        } else {
          final t = n == 1 ? 0.5 : k / (n - 1);
          final a = math.pi * (1 - t);
          x = (left + right) / 2 + math.cos(a) * (right - left) * 0.8;
          y = ground - 2 * r - math.sin(a) * (ground - bar + 2 * r);
        }
      } else {
        x = sx(s.goalY ?? 50).clamp(r, size.width - r);
        if (inside) {
          x = x.clamp(left + r, right - r);
          y = bar + r + (ground - bar - 2 * r) * jitter;
        } else if (x > left && x < right) {
          // Straight but missed: over the bar.
          y = bar - r * 1.6 - (bar - r * 2.6).clamp(0, double.infinity) * jitter * 0.6;
        } else {
          y = ground - r - (ground - r * 2) * jitter * 0.8;
        }
      }
      _paintShot(canvas, Offset(x, y), s.kind, r, selected: identical(s, selected));
    }
  }

  /// A steady pseudo-random 0..1 per shot, so dots don't jump on rebuild.
  static double _unit(Shot s, int i) {
    final h = Object.hash(s.clock, s.player, s.x, s.y, i) & 0x7fffffff;
    return (h % 1000) / 1000;
  }

  @override
  bool shouldRepaint(_GoalPainter old) => old.shots != shots || old.selected != selected;
}

// ---------------------------------------------------------------- Line-up pitch

/// Both starting elevens on one pitch: home in the bottom half attacking up,
/// away in the top half attacking down. Rows come from the formation
/// ("4-2-3-1"); players are put in rows by their listed position, back to
/// front, and left to right within a row.
class LineupPitch extends StatelessWidget {
  const LineupPitch({super.key, required this.home, required this.away});
  final TeamInfo home, away;

  static bool canDraw(TeamInfo t) => t.starters.length == 11 && _rows(t.formation) != null;

  static List<int>? _rows(String? formation) {
    final parts = (formation ?? '').split('-').map(int.tryParse).toList();
    if (parts.length < 2 || parts.any((p) => p == null)) return null;
    final rows = parts.cast<int>();
    return rows.fold<int>(0, (a, b) => a + b) == 10 ? rows : null;
  }

  /// Back (0) to front (6) from ESPN's position code.
  static double _depth(String p) {
    final s = p.toUpperCase();
    if (s == 'G' || s == 'GK') return 0;
    if (s.startsWith('CD') || s == 'LB' || s == 'RB' || s == 'D' || s == 'SW' || s.endsWith('WB')) return 1;
    if (s.startsWith('DM')) return 2;
    if (s.startsWith('CM') || s == 'LM' || s == 'RM' || s == 'M') return 3;
    if (s.startsWith('AM')) return 4;
    if (s == 'LW' || s == 'RW' || s.contains('CF')) return 5;
    if (s == 'F' || s == 'ST') return 5.5;
    return 3;
  }

  /// Left (-2) to right (2) from the player's own point of view.
  static int _lateral(String p) {
    final s = p.toUpperCase();
    if (s.endsWith('-L')) return -1;
    if (s.endsWith('-R')) return 1;
    if (s.startsWith('L')) return -2;
    if (s.startsWith('R')) return 2;
    return 0;
  }

  /// The eleven in rows, goalkeeper first, each row left to right.
  static List<List<Player>> lines(TeamInfo t) {
    final rows = _rows(t.formation)!;
    final indexed = t.starters.indexed.toList();
    final gk = indexed.where((e) => _depth(e.$2.position) == 0).firstOrNull ?? indexed.first;
    final rest =
        [
          for (final e in indexed)
            if (!identical(e, gk)) e,
        ]..sort((a, b) {
          final d = _depth(a.$2.position).compareTo(_depth(b.$2.position));
          return d != 0 ? d : a.$1.compareTo(b.$1);
        });
    final out = [
      [gk.$2],
    ];
    var at = 0;
    for (final n in rows) {
      final row = rest.sublist(at, math.min(at + n, rest.length)).map((e) => e.$2).toList()
        ..sort((a, b) => _lateral(a.position).compareTo(_lateral(b.position)));
      out.add(row);
      at += n;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 68 / 105,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          final children = <Widget>[];
          void place(TeamInfo t, bool bottom, Color color, Color onColor) {
            final ls = lines(t);
            for (final (r, row) in ls.indexed) {
              // Goalkeeper near the goal line, the front line near halfway.
              final depth = 0.05 + 0.38 * r / (ls.length - 1);
              final y = bottom ? size.height * (1 - depth) : size.height * depth;
              for (final (i, p) in row.indexed) {
                // Home looks up the pitch, so its left is the screen's left;
                // away looks down, so its left is the screen's right.
                final f = (i + 1) / (row.length + 1);
                final x = size.width * (bottom ? f : 1 - f);
                children.add(
                  Positioned(
                    left: x - 36,
                    top: y - 17,
                    width: 72,
                    child: _PlayerMarker(player: p, color: color, onColor: onColor),
                  ),
                );
              }
            }
          }

          // Club colours when the feed has them and they tell the sides apart.
          var homeColor = home.color == null ? cs.primary : Color(0xFF000000 | home.color!);
          var awayColor = away.color == null ? cs.tertiary : Color(0xFF000000 | away.color!);
          if (_close(homeColor, awayColor)) {
            homeColor = cs.primary;
            awayColor = homeColor.computeLuminance() > 0.5 ? const Color(0xFF263238) : Colors.white;
          }
          place(away, false, awayColor, _onColor(awayColor));
          place(home, true, homeColor, _onColor(homeColor));
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                CustomPaint(size: size, painter: _PitchPainter()),
                ...children,
              ],
            ),
          );
        },
      ),
    );
  }
}

bool _close(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs() < 0.35;

Color _onColor(Color c) => c.computeLuminance() > 0.5 ? const Color(0xFF1B1B1B) : Colors.white;

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintPitch(canvas, size, horizontal: false);
  @override
  bool shouldRepaint(_PitchPainter old) => false;
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({required this.player, required this.color, required this.onColor});
  final Player player;
  final Color color, onColor;

  @override
  Widget build(BuildContext context) {
    final name = player.shortName.isNotEmpty ? player.shortName : player.name;
    // "S. Ichazo" -> "Ichazo"
    final last = name.contains('. ') ? name.substring(name.indexOf('. ') + 2) : name.split(' ').last;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Text(
                player.jersey,
                style: TextStyle(color: onColor, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            if (player.subbedOut)
              const Positioned(
                right: -8,
                top: -4,
                child: Icon(Icons.arrow_circle_down, size: 13, color: Color(0xFFFF8A80)),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Color(0x99000000), blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}
