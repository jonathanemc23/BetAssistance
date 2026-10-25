package app.banktrack.community;

import static org.assertj.core.api.Assertions.assertThat;

import app.banktrack.community.domain.Bet;
import app.banktrack.community.domain.BetKind;
import app.banktrack.community.domain.Challenge;
import app.banktrack.community.domain.ChallengeRules;
import app.banktrack.community.domain.ChallengeStatus;
import app.banktrack.community.domain.Market;
import app.banktrack.community.domain.Selection;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class ChallengeRulesTest {
    final Instant now = Instant.parse("2030-01-01T12:00:00Z");

    Selection sel(int i, double odds) {
        return new Selection("m" + i, "eng.1", "Everton", "Chelsea", Instant.parse("2030-01-02T00:00:00Z"), Market.homeWin,
                "Everton to win", null, odds);
    }

    List<Bet> play(Challenge c, int won, int lost) {
        List<Bet> bets = new ArrayList<>();
        for (int i = 0; i < won + lost; i++) {
            Bet b = new Bet("u", BetKind.CHALLENGE, c.getAttempt(), sel(i, 1.8), 0, now);
            b.settle(i < won ? 2 : 0, i < won ? 0 : 1);
            bets.add(b);
        }
        return bets;
    }

    @Test
    void onlyAnAcceptedChallengeTakesBetsOver160BeforeKickOff() {
        Challenge c = new Challenge("u");
        assertThat(ChallengeRules.refuse(c, List.of(), sel(1, 1.8), now)).isPresent();
        ChallengeRules.accept(c, now);
        assertThat(ChallengeRules.status(c, List.of(), now)).isEqualTo(ChallengeStatus.ACTIVE);
        assertThat(ChallengeRules.refuse(c, List.of(), sel(1, 1.8), now)).isEmpty();
        assertThat(ChallengeRules.refuse(c, List.of(), sel(1, 1.6), now)).hasValueSatisfying(m -> assertThat(m).contains("1.60"));
        assertThat(ChallengeRules.refuse(c, List.of(), sel(1, 1.61), now)).isEmpty();
        assertThat(ChallengeRules.refuse(c, List.of(), sel(1, 1.8), Instant.parse("2030-01-03T00:00:00Z"))).isPresent();
    }

    @Test
    void eighteenOfThirtyPassesSeventeenWaitsAWeek() {
        Challenge pass = new Challenge("u");
        ChallengeRules.accept(pass, now);
        List<Bet> won = play(pass, 18, 12);
        ChallengeRules.evaluate(pass, won, now);
        assertThat(ChallengeRules.status(pass, won, now)).isEqualTo(ChallengeStatus.PASSED);

        Challenge fail = new Challenge("u");
        ChallengeRules.accept(fail, now);
        List<Bet> lost = play(fail, 17, 13);
        ChallengeRules.evaluate(fail, lost, now);
        assertThat(ChallengeRules.status(fail, lost, now)).isEqualTo(ChallengeStatus.WAITING);
        assertThat(fail.getLastRate()).isEqualTo(17 / 30.0);
        assertThat(fail.getWaitUntil()).isEqualTo(now.plus(Duration.ofDays(7)));
        assertThat(ChallengeRules.status(fail, List.of(), now.plus(Duration.ofDays(8)))).isEqualTo(ChallengeStatus.NOT_STARTED);
    }

    @Test
    void theRestartOpensAfterTenBets() {
        Challenge c = new Challenge("u");
        ChallengeRules.accept(c, now);
        assertThat(ChallengeRules.canRestart(c, play(c, 5, 4), now)).isFalse();
        List<Bet> ten = play(c, 5, 5);
        assertThat(ChallengeRules.canRestart(c, ten, now)).isTrue();
        ChallengeRules.restart(c, ten, now);
        assertThat(ChallengeRules.status(c, List.of(), now)).isEqualTo(ChallengeStatus.WAITING);
    }

    @Test
    void marketsSettleLikeTheApp() {
        assertThat(Market.bttsYes.wins(1, 1, null)).isTrue();
        assertThat(Market.under25.wins(2, 1, null)).isFalse();
        assertThat(Market.overLine.wins(2, 1, 2.5)).isTrue();
        assertThat(Market.awayOrDraw.wins(0, 0, null)).isTrue();
    }
}
