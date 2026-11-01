import 'l10n.dart';

/// A selection as the app writes it ("Arsenal to win", "Over 2.5 goals")
/// in the app's language. Selections are saved in English so the app can
/// keep reading them; this only changes how they are shown. Text the user
/// typed that matches no pattern is shown as it is.
String trPick(String s) {
  if (!L10n.spanish || s.isEmpty) return s;
  if (s.contains(' & ')) return s.split(' & ').map(trPick).join(' & ');
  final t = s.trim();
  RegExpMatch? m(String p) => RegExp('^$p\$', caseSensitive: false).firstMatch(t);

  switch (t.toLowerCase()) {
    case 'draw':
      return 'Empate';
    case 'over':
      return 'Más';
    case 'under':
      return 'Menos';
    case 'yes':
      return 'Sí';
    case 'no':
      return 'No';
    case 'both teams to score':
      return 'Ambos equipos marcan';
    case 'not both teams to score':
      return 'No marcan ambos';
  }
  if (m(r'(\d+)-leg parlay') case final x?) return 'Combinada de ${x[1]} selecciones';
  if (m(r'both teams to score: (.+)') case final x?) return 'Ambos marcan: ${trPick(x[1]!)}';
  if (m(r'half-time: (.+)') case final x?) return 'Descanso: ${trPick(x[1]!)}';
  if (m(r'correct score (.+)') case final x?) return 'Resultado exacto ${x[1]}';
  if (m(r'double chance (.+)') case final x?) return 'Doble oportunidad ${x[1]}';
  if (m(r'(over|under) ([\d.,]+) (goals?|corners?|cards?|points?|runs?|shots?|shots on target|fouls?)') case final x?) {
    final unit = switch (x[3]!.toLowerCase()) {
      'goal' || 'goals' => 'goles',
      'corner' || 'corners' => 'córners',
      'card' || 'cards' => 'tarjetas',
      'point' || 'points' => 'puntos',
      'run' || 'runs' => 'carreras',
      'shots on target' => 'tiros a puerta',
      'shot' || 'shots' => 'tiros',
      _ => 'faltas',
    };
    return '${x[1]!.toLowerCase() == 'over' ? 'Más de' : 'Menos de'} ${x[2]} $unit';
  }
  if (m(r'(over|under) ([\d.,]+)') case final x?) return '${x[1]!.toLowerCase() == 'over' ? 'Más de' : 'Menos de'} ${x[2]}';
  if (m(r'(.+) to win to nil') case final x?) return 'Gana ${x[1]} sin encajar';
  if (m(r'(.+) (over|under) ([\d.,]+) (goals?|points?|runs?)') case final x?) {
    return '${x[1]}: ${trPick('${x[2]} ${x[3]} ${x[4]}')}';
  }
  if (m(r'(.+) to win') case final x?) return 'Gana ${x[1]}';
  if (m(r'(.+) or draw') case final x?) return '${x[1]} o empate';
  if (m(r'(.+) draw no bet') case final x?) return '${x[1]} (empate no válido)';
  if (m(r'(.+) to score') case final x?) return 'Marca ${x[1]}';
  if (m(r'(.+) or (.+)') case final x?) return '${x[1]} o ${x[2]}';
  return s;
}

/// A sport's own word for its score ("goals", "points", "runs") in the
/// app's language.
String trUnit(String unit) => switch (unit) {
      'goals' => tr('goals'),
      'points' => tr('points'),
      'runs' => tr('runs'),
      _ => unit,
    };

/// A form letter (W, D, L) in the app's language: G, E, P in Spanish.
String trForm(String r) => !L10n.spanish
    ? r
    : switch (r) {
        'W' => 'G',
        'D' => 'E',
        'L' => 'P',
        _ => r,
      };

/// A league table column heading in the app's language.
String trTableHead(String h) => !L10n.spanish
    ? h
    : switch (h) {
        'P' => 'PJ',
        'W' => 'G',
        'D' => 'E',
        'L' => 'P',
        'GD' => 'DG',
        'GB' => 'JD',
        _ => h,
      };

/// A stat name from the match feed ("Corner Kicks") in the app's language.
String trStat(String label) => L10n.spanish ? (_esStats[label.toLowerCase()] ?? label) : label;

const _esStats = {
  'fouls': 'Faltas',
  'yellow cards': 'Tarjetas amarillas',
  'red cards': 'Tarjetas rojas',
  'offsides': 'Fueras de juego',
  'corner kicks': 'Córners',
  'corners': 'Córners',
  'saves': 'Paradas',
  'possession': 'Posesión',
  'shots': 'Tiros',
  'on goal': 'A puerta',
  'on target': 'A puerta',
  '3-point %': '% de triples',
  'shots on target': 'Tiros a puerta',
  'on target %': '% a puerta',
  'penalty goals': 'Goles de penalti',
  'penalty kicks taken': 'Penaltis lanzados',
  'accurate passes': 'Pases precisos',
  'passes': 'Pases',
  'pass completion %': '% de pases completados',
  'accurate crosses': 'Centros precisos',
  'crosses': 'Centros',
  'cross %': '% de centros',
  'long balls': 'Balones largos',
  'accurate long balls': 'Balones largos precisos',
  'long balls %': '% de balones largos',
  'blocked shots': 'Tiros bloqueados',
  'effective tackles': 'Entradas efectivas',
  'tackles': 'Entradas',
  'tackle %': '% de entradas',
  'interceptions': 'Intercepciones',
  'effective clearances': 'Despejes efectivos',
  'clearances': 'Despejes',
  'goals': 'Goles',
  'assists': 'Asistencias',
  'goal difference': 'Diferencia de goles',
  'goals conceded': 'Goles en contra',
  'total goals': 'Goles totales',
  'rebounds': 'Rebotes',
  'field goal %': '% de tiros de campo',
  'three point %': '% de triples',
  'free throw %': '% de tiros libres',
  'turnovers': 'Pérdidas',
  'steals': 'Robos',
  'blocks': 'Tapones',
  'hits': 'Hits',
  'runs': 'Carreras',
  'errors': 'Errores',
};
