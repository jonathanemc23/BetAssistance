package app.banktrack.community;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.banktrack.community.domain.Challenge;
import app.banktrack.community.domain.ChallengeRepository;
import app.banktrack.community.service.ScoreProvider;
import app.banktrack.community.service.SettlementJob;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class CommunityApiTest {
    static final Instant NOW = Instant.parse("2030-01-01T10:00:00Z");

    /** A clock tests can move. */
    static class TestClock extends Clock {
        Instant now = NOW;

        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }

    @TestConfiguration
    static class Config {
        @Bean @Primary TestClock testClock() { return new TestClock(); }

        /** Everton 2, Chelsea 1 for every match. */
        @Bean @Primary ScoreProvider scores() { return (league, id) -> Optional.of(new ScoreProvider.FinalScore(2, 1)); }
    }

    @Autowired MockMvc mvc;
    @Autowired TestClock clock;
    @Autowired SettlementJob settlement;
    @Autowired ChallengeRepository challenges;

    MockHttpServletRequestBuilder as(String user, MockHttpServletRequestBuilder req) {
        return req.header("X-Dev-User", user).contentType(MediaType.APPLICATION_JSON);
    }

    static String bet(String match, String market, String pick, double odds) {
        return """
            {"matchId":"%s","league":"eng.1","home":"Everton","away":"Chelsea","kickoff":"2030-01-01T19:00:00Z",
             "market":"%s","pick":"%s","odds":%s}""".formatted(match, market, pick, odds);
    }

    @Test
    void profileFreeBetsFollowsBuyingAndTheChallenge() throws Exception {
        clock.now = NOW;
        mvc.perform(get("/api/me")).andExpect(status().isUnauthorized());
        mvc.perform(as("laura", get("/api/me"))).andExpect(status().isNotFound());

        // A community profile first; the username is cleaned like the app does.
        mvc.perform(as("laura", post("/api/profiles")).content("{\"handle\":\"a\"}")).andExpect(status().isUnprocessableContent());
        mvc.perform(as("laura", post("/api/profiles")).content("{\"handle\":\"@Laura_Bets\",\"name\":\"Laura\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.profile.handle").value("laura_bets"))
                .andExpect(jsonPath("$.tokens").value(10));
        mvc.perform(as("diego", post("/api/profiles")).content("{\"handle\":\"laura_bets\"}")).andExpect(status().isConflict());
        mvc.perform(as("diego", post("/api/profiles")).content("{\"handle\":\"goalmachine\",\"name\":\"Diego\"}")).andExpect(status().isCreated());

        // Free bets: open to everyone, 3 a day, and followers.
        mvc.perform(as("diego", post("/api/bets/free")).content(bet("1", "homeWin", "Everton to win", 1.9)))
                .andExpect(status().isCreated());
        mvc.perform(as("diego", post("/api/bets/free")).content(bet("1", "homeWin", "Everton to win", 1.9)))
                .andExpect(status().isUnprocessableContent());
        mvc.perform(as("laura", get("/api/feed/free")))
                .andExpect(jsonPath("$[0].pick").value("Everton to win"))
                .andExpect(jsonPath("$[0].bettor.handle").value("goalmachine"));
        mvc.perform(as("laura", put("/api/profiles/goalmachine/follow")))
                .andExpect(jsonPath("$.followers").value(1))
                .andExpect(jsonPath("$.followedByMe").value(true));

        // Only pros sell; a bought bet shows its pick and pays the seller.
        mvc.perform(as("diego", post("/api/bets/sale")).content(bet("2", "over25", "Over 2.5 goals", 2.3)))
                .andExpect(status().isUnprocessableContent());
        Challenge c = challenges.findById("diego").orElseThrow();
        var passed = Challenge.class.getDeclaredField("passedAt");
        passed.setAccessible(true);
        passed.set(c, NOW);
        challenges.save(c);
        String sale = mvc.perform(as("diego", post("/api/bets/sale")).content(bet("2", "over25", "Over 2.5 goals", 2.3)))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.price").value(3))
                .andReturn().getResponse().getContentAsString();
        String id = sale.replaceAll(".*\"id\":(\\d+).*", "$1");
        mvc.perform(as("laura", get("/api/feed/hot")))
                .andExpect(jsonPath("$[0].pick").doesNotExist())
                .andExpect(jsonPath("$[0].bettor.pro").value(true));
        mvc.perform(as("laura", post("/api/bets/" + id + "/buy")))
                .andExpect(jsonPath("$.pick").value("Over 2.5 goals"))
                .andExpect(jsonPath("$.bought").value(true))
                .andExpect(jsonPath("$.buyers").value(1));
        mvc.perform(as("laura", get("/api/tokens"))).andExpect(jsonPath("$.tokens").value(7));
        mvc.perform(as("diego", get("/api/tokens"))).andExpect(jsonPath("$.tokens").value(13));

        // The challenge: accept, odds over 1.60, settled from the final score.
        mvc.perform(as("laura", post("/api/challenge/bets")).content(bet("3", "homeWin", "Everton to win", 1.8)))
                .andExpect(status().isUnprocessableContent());
        mvc.perform(as("laura", post("/api/challenge/accept"))).andExpect(jsonPath("$.status").value("ACTIVE"));
        mvc.perform(as("laura", post("/api/challenge/bets")).content(bet("3", "homeWin", "Everton to win", 1.6)))
                .andExpect(status().isUnprocessableContent());
        mvc.perform(as("laura", post("/api/challenge/bets")).content(bet("3", "homeWin", "Everton to win", 1.8)))
                .andExpect(jsonPath("$.placed").value(1));

        clock.now = Instant.parse("2030-01-01T22:00:00Z");
        assertThat(settlement.settle()).isEqualTo(3);
        mvc.perform(as("laura", get("/api/challenge")))
                .andExpect(jsonPath("$.wins").value(1))
                .andExpect(jsonPath("$.bets[0].result").value("WON"));
        mvc.perform(as("laura", get("/api/profiles/goalmachine")))
                .andExpect(jsonPath("$.freeWins").value(1));
    }
}
