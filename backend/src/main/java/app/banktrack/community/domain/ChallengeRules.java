package app.banktrack.community.domain;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * The pro bettor challenge, enforced on the server so nobody can fake a pass: 30 bets that can't be removed
 * or changed, each with odds over 1.60, won at 60% or more. Under 60% after 30, or a restart after 10 or
 * more, means a week's wait before starting again. The same rules as lib/logic/community.dart in the app.
 */
public final class ChallengeRules {
    public static final int TARGET = 30;
    public static final int RESTART_AFTER = 10;
    public static final double PASS_RATE = 0.6;
    public static final double MIN_ODDS = 1.6;
    public static final Duration WAIT = Duration.ofDays(7);

    private ChallengeRules() {}

    public static ChallengeStatus status(Challenge c, List<Bet> bets, Instant now) {
        if (c.getPassedAt() != null) return ChallengeStatus.PASSED;
        if (c.getWaitUntil() != null && now.isBefore(c.getWaitUntil())) return ChallengeStatus.WAITING;
        if (c.getStartedAt() == null) return ChallengeStatus.NOT_STARTED;
        if (bets.size() >= TARGET) return ChallengeStatus.AWAITING_RESULTS;
        return ChallengeStatus.ACTIVE;
    }

    /** Why the bet can't be placed now, or empty when it can. */
    public static Optional<String> refuse(Challenge c, List<Bet> bets, Selection s, Instant now) {
        if (status(c, bets, now) != ChallengeStatus.ACTIVE) return Optional.of("The challenge isn't open for bets right now.");
        if (!s.kickoff().isAfter(now)) return Optional.of("This match has started: pick one that hasn't.");
        if (s.odds() <= MIN_ODDS) return Optional.of("Challenge bets need odds over 1.60.");
        if (bets.stream().anyMatch(b -> b.getMatchId().equals(s.matchId()) && b.getMarket() == s.market())) {
            return Optional.of("You already have this bet in the challenge.");
        }
        return Optional.empty();
    }

    public static boolean canAccept(Challenge c, List<Bet> bets, Instant now) {
        return status(c, bets, now) == ChallengeStatus.NOT_STARTED;
    }

    public static boolean canRestart(Challenge c, List<Bet> bets, Instant now) {
        return status(c, bets, now) == ChallengeStatus.ACTIVE && bets.size() >= RESTART_AFTER;
    }

    public static void accept(Challenge c, Instant now) {
        c.accept(now);
    }

    public static void restart(Challenge c, List<Bet> bets, Instant now) {
        c.end(now, winRate(bets));
    }

    /** Passed at 60% or more once all 30 bets are settled; else a week's wait. */
    public static void evaluate(Challenge c, List<Bet> bets, Instant now) {
        if (c.getPassedAt() != null || c.getStartedAt() == null || bets.size() < TARGET) return;
        if (bets.stream().anyMatch(b -> !b.isSettled())) return;
        double rate = winRate(bets);
        if (rate >= PASS_RATE) {
            c.pass(now);
        } else {
            c.end(now, rate);
        }
    }

    /** Won out of settled, 0 to 1; null before the first result. */
    public static Double winRate(List<Bet> bets) {
        long settled = bets.stream().filter(Bet::isSettled).count();
        if (settled == 0) return null;
        return (double) bets.stream().filter(Bet::isWon).count() / settled;
    }
}
