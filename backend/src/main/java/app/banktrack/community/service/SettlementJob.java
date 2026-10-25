package app.banktrack.community.service;

import app.banktrack.community.domain.Bet;
import app.banktrack.community.domain.BetKind;
import app.banktrack.community.domain.BetRepository;
import java.time.Clock;
import java.time.Duration;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Settles every open bet once its match is over, then ends the challenges that have all 30 results. */
@Component
public class SettlementJob {
    /** A match is over well within this time from kick-off. */
    static final Duration MATCH_LENGTH = Duration.ofMinutes(110);

    private final BetRepository bets;
    private final ScoreProvider scores;
    private final ChallengeService challenges;
    private final Clock clock;

    public SettlementJob(BetRepository bets, ScoreProvider scores, ChallengeService challenges, Clock clock) {
        this.bets = bets;
        this.scores = scores;
        this.challenges = challenges;
        this.clock = clock;
    }

    @Scheduled(fixedDelayString = "${banktrack.settle-every:PT10M}")
    @Transactional
    public int settle() {
        List<Bet> open = bets.findByResultIsNullAndKickoffBefore(clock.instant().minus(MATCH_LENGTH));
        Map<String, List<Bet>> byMatch = open.stream().collect(Collectors.groupingBy(b -> b.getLeague() + "/" + b.getMatchId()));
        Set<String> challengers = new HashSet<>();
        int settled = 0;
        for (List<Bet> group : byMatch.values()) {
            Bet first = group.getFirst();
            var score = scores.finalScore(first.getLeague(), first.getMatchId());
            if (score.isEmpty()) continue;
            for (Bet b : group) {
                b.settle(score.get().home(), score.get().away());
                settled++;
                if (b.getKind() == BetKind.CHALLENGE) challengers.add(b.getOwnerId());
            }
        }
        bets.flush();
        challengers.forEach(challenges::evaluate);
        return settled;
    }
}
