package app.banktrack.community.service;

import app.banktrack.community.domain.BetKind;
import app.banktrack.community.domain.ChallengeStatus;
import app.banktrack.community.domain.Market;
import java.time.Instant;
import java.util.List;

/** What the API returns. */
public final class Views {
    private Views() {}

    public record Bettor(String handle, String name, String avatar, boolean pro, long wins, long losses, long followers) {}

    /** A bet as a viewer sees it: the pick, line and odds are null on a bet for sale they haven't bought. */
    public record BetView(
            Long id,
            BetKind kind,
            Bettor bettor,
            String matchId,
            String league,
            String home,
            String away,
            Instant kickoff,
            Market market,
            String pick,
            Double line,
            Double odds,
            int price,
            long buyers,
            boolean mine,
            boolean bought,
            String result) {}

    public record ProfileView(
            String handle, String name, String bio, String avatar, Instant joinedAt, boolean pro,
            long followers, long following, boolean followedByMe, long freeWins, long freeLosses) {}

    public record Me(ProfileView profile, int tokens) {}

    public record ChallengeView(
            ChallengeStatus status, int attempt, int placed, long wins, long settled, Double winRate,
            boolean canRestart, Instant waitUntil, Double lastRate, List<BetView> bets) {}
}
