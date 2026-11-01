package app.banktrack.community.push;

import java.util.List;
import java.util.Map;

/**
 * What to say about a match with money on it: kick-off, every score change and full time. The same rules as
 * alertFor in the app's lib/logic/live_alerts.dart, in the phone's language.
 */
public final class LiveAlerts {
    private LiveAlerts() {}

    public enum State { SCHEDULED, LIVE, FINISHED, OTHER }

    /** A match as the feed has it now. Scores are null before kick-off. */
    public record Game(State state, String home, String away, String homeScore, String awayScore, String detail,
            String league) {}

    /** What the last reading saw. */
    public record Snapshot(State state, String homeScore, String awayScore) {}

    public record Alert(String title, String body) {}

    private static final Map<String, String> SPANISH = Map.of(
            "Full time: {}", "Final: {}",
            "Kick-off: {}", "Inicio: {}",
            "Under way: {}", "En juego: {}",
            "Score corrected: {}", "Marcador corregido: {}",
            "Goal! {}", "¡Gol! {}",
            "Score update: {}", "Actualización: {}",
            "Your pick: {}", "Tu apuesta: {}",
            "Your picks: {}", "Tus apuestas: {}");

    static String tr(String lang, String text, String arg) {
        String t = "es".equals(lang) ? SPANISH.getOrDefault(text, text) : text;
        return t.replace("{}", arg);
    }

    /**
     * The alert for [now] given the last reading ([last], null on the first). A first reading only records the
     * match, so a phone that syncs halfway through a game doesn't get it replayed; one already finished still
     * reports the result.
     */
    public static Alert alertFor(String sport, List<String> picks, String lang, Snapshot last, Game now) {
        String pickLine = picks.isEmpty() ? ""
                : tr(lang, picks.size() == 1 ? "Your pick: {}" : "Your picks: {}", String.join(", ", picks));
        String score = now.home() + " " + orZero(now.homeScore()) + "-" + orZero(now.awayScore()) + " " + now.away();

        if (now.state() == State.FINISHED) {
            if (last != null && last.state() == State.FINISHED) return null;
            return new Alert(tr(lang, "Full time: {}", score), lines("", pickLine));
        }
        if (now.state() != State.LIVE || last == null) return null;
        if (last.state() != State.LIVE) {
            boolean started = "0".equals(orZero(now.homeScore())) && "0".equals(orZero(now.awayScore()));
            String title = started ? tr(lang, "Kick-off: {}", now.home() + " vs " + now.away()) : tr(lang, "Under way: {}", score);
            String where = now.detail().isEmpty() ? now.league() : now.detail() + " · " + now.league();
            return new Alert(title, lines(where, pickLine));
        }
        if (same(last.homeScore(), now.homeScore()) && same(last.awayScore(), now.awayScore())) return null;
        int before = total(last.homeScore(), last.awayScore()), after = total(now.homeScore(), now.awayScore());
        String title = after < before ? tr(lang, "Score corrected: {}", score)
                : "Soccer".equals(sport) ? tr(lang, "Goal! {}", score)
                : tr(lang, "Score update: {}", score);
        return new Alert(title, lines(now.detail(), pickLine));
    }

    private static String orZero(String s) {
        return s == null ? "0" : s;
    }

    private static boolean same(String a, String b) {
        return a == null ? b == null : a.equals(b);
    }

    private static String lines(String a, String b) {
        if (a.isEmpty()) return b;
        return b.isEmpty() ? a : a + "\n" + b;
    }

    private static int total(String a, String b) {
        return parse(a) + parse(b);
    }

    private static int parse(String s) {
        try {
            return s == null ? 0 : Integer.parseInt(s.trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
