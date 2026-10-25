package app.banktrack.community.service;

import app.banktrack.community.domain.Bet;
import app.banktrack.community.domain.BetKind;
import app.banktrack.community.domain.BetRepository;
import app.banktrack.community.domain.Challenge;
import app.banktrack.community.domain.ChallengeRepository;
import app.banktrack.community.domain.ChallengeRules;
import app.banktrack.community.domain.Selection;
import app.banktrack.community.service.Views.ChallengeView;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** The pro bettor challenge, decided on the server. */
@Service
public class ChallengeService {
    private final ChallengeRepository challenges;
    private final BetRepository bets;
    private final CommunityService community;
    private final Clock clock;

    public ChallengeService(ChallengeRepository challenges, BetRepository bets, CommunityService community, Clock clock) {
        this.challenges = challenges;
        this.bets = bets;
        this.community = community;
        this.clock = clock;
    }

    public ChallengeView get(String userId) {
        return view(challenge(userId));
    }

    @Transactional
    public ChallengeView accept(String userId) {
        Challenge c = challenge(userId);
        if (!ChallengeRules.canAccept(c, current(c), clock.instant())) throw ApiException.refused("The challenge can't be started right now.");
        ChallengeRules.accept(c, clock.instant());
        return view(c);
    }

    @Transactional
    public ChallengeView place(String userId, Selection s) {
        Challenge c = challenge(userId);
        Instant now = clock.instant();
        ChallengeRules.refuse(c, current(c), s, now).ifPresent(why -> {
            throw ApiException.refused(why);
        });
        bets.save(new Bet(userId, BetKind.CHALLENGE, c.getAttempt(), s, 0, now));
        return view(c);
    }

    @Transactional
    public ChallengeView restart(String userId) {
        Challenge c = challenge(userId);
        List<Bet> placed = current(c);
        if (!ChallengeRules.canRestart(c, placed, clock.instant())) {
            throw ApiException.refused("The restart is open after 10 bets.");
        }
        ChallengeRules.restart(c, placed, clock.instant());
        return view(c);
    }

    /** Ends the attempt of [userId] once all 30 bets are settled. */
    @Transactional
    public void evaluate(String userId) {
        challenges.findById(userId).ifPresent(c -> ChallengeRules.evaluate(c, current(c), clock.instant()));
    }

    private Challenge challenge(String userId) {
        return challenges.findById(userId).orElseThrow(() -> ApiException.notFound("Create your community profile first."));
    }

    private List<Bet> current(Challenge c) {
        if (c.getAttempt() == 0) return List.of();
        return bets.findByOwnerIdAndKindAndAttemptOrderByCreatedAtAsc(c.getUserId(), BetKind.CHALLENGE, c.getAttempt());
    }

    private ChallengeView view(Challenge c) {
        Instant now = clock.instant();
        List<Bet> placed = c.getStartedAt() == null && c.getPassedAt() == null ? List.of() : current(c);
        long settled = placed.stream().filter(Bet::isSettled).count();
        return new ChallengeView(ChallengeRules.status(c, placed, now), c.getAttempt(), placed.size(),
                placed.stream().filter(Bet::isWon).count(), settled, ChallengeRules.winRate(placed),
                ChallengeRules.canRestart(c, placed, now), c.getWaitUntil(), c.getLastRate(), community.views(placed, c.getUserId()));
    }
}
