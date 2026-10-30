package app.banktrack.community.push;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.banktrack.community.push.LiveAlerts.Game;
import app.banktrack.community.push.LiveAlerts.State;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
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

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class PushApiTest {
    /** Match 701 is Everton v Chelsea, kicking off now (the clock is the real one). */
    static class FakeFeed implements LiveFeed {
        final Map<String, Game> games = new HashMap<>();

        @Override
        public Optional<Game> read(String feed, String matchId) {
            return Optional.ofNullable(games.get(feed + "|" + matchId));
        }
    }

    static class FakeSender implements PushSender {
        final List<String> sent = new ArrayList<>();
        Result answer = Result.SENT;

        @Override
        public Result send(PushDevice device, byte[] payload) {
            sent.add(device.getEndpoint() + " " + new String(payload, StandardCharsets.UTF_8));
            return answer;
        }
    }

    @TestConfiguration
    static class Config {
        @Bean @Primary FakeFeed fakeFeed() { return new FakeFeed(); }
        @Bean @Primary FakeSender fakeSender() { return new FakeSender(); }
    }

    static final String ENDPOINT = "https://web.push.apple.com/QGuQyavXutnMJmo";

    @Autowired MockMvc mvc;
    @Autowired FakeFeed feed;
    @Autowired FakeSender sender;
    @Autowired PushDeviceRepository devices;
    @Autowired PushWatchRepository watches;

    @BeforeEach
    void reset() {
        watches.deleteAll();
        devices.deleteAll();
        feed.games.clear();
        sender.sent.clear();
        sender.answer = PushSender.Result.SENT;
    }

    void sync(String endpoint, String matches) throws Exception {
        mvc.perform(put("/push/devices").contentType(MediaType.APPLICATION_JSON).content("""
                {"subscription": {"endpoint": "%s", "keys": {"p256dh": "BNcRdreALRFX", "auth": "tBHItJI5svbpez7KI4CCXg"}},
                 "lang": "en", "matches": %s}""".formatted(endpoint, matches)))
                .andExpect(status().isNoContent());
    }

    static String everton(String kickoff) {
        return """
                [{"id": "701", "feed": "soccer/eng.1", "sport": "Soccer", "kickoff": "%s",
                  "home": "Everton", "away": "Chelsea", "picks": ["Everton to win"]}]""".formatted(kickoff);
    }

    int tick() throws Exception {
        String body = mvc.perform(post("/push/tick").header("X-Tick-Key", "test-tick"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return Integer.parseInt(body.replaceAll("\\D", ""));
    }

    void score(State s, String h, String a) {
        feed.games.put("soccer/eng.1|701", new Game(s, "Everton", "Chelsea", h, a, "", "Premier League"));
    }

    @Test
    void sendsKickOffGoalsAndFullTime() throws Exception {
        mvc.perform(get("/push/key")).andExpect(status().isOk()).andExpect(jsonPath("$.key").isString());
        sync(ENDPOINT, everton(java.time.Instant.now().plusSeconds(600).toString()));

        score(State.SCHEDULED, null, null);
        assertThat(tick()).isZero();
        score(State.LIVE, "0", "0");
        assertThat(tick()).isEqualTo(1);
        assertThat(sender.sent.getLast()).contains(ENDPOINT, "Kick-off: Everton vs Chelsea", "match-701");
        assertThat(tick()).isZero();
        score(State.LIVE, "1", "0");
        assertThat(tick()).isEqualTo(1);
        assertThat(sender.sent.getLast()).contains("Goal! Everton 1-0 Chelsea", "Your pick: Everton to win");

        // The app syncs again: what was read is kept, so nothing repeats.
        sync(ENDPOINT, everton(java.time.Instant.now().plusSeconds(600).toString()));
        assertThat(tick()).isZero();
        score(State.FINISHED, "1", "0");
        assertThat(tick()).isEqualTo(1);
        assertThat(sender.sent.getLast()).contains("Full time: Everton 1-0 Chelsea");
        assertThat(tick()).isZero();
    }

    @Test
    void followsOnlyMatchesAboutToStartOrUnderWay() throws Exception {
        sync(ENDPOINT, everton(java.time.Instant.now().plusSeconds(3 * 3600).toString()));
        score(State.LIVE, "0", "0");
        tick();
        tick();
        assertThat(sender.sent).isEmpty();
    }

    @Test
    void dropsSubscriptionsThePushServiceForgot() throws Exception {
        sync(ENDPOINT, everton(java.time.Instant.now().minusSeconds(60).toString()));
        score(State.FINISHED, "2", "2");
        sender.answer = PushSender.Result.GONE;
        assertThat(tick()).isZero();
        assertThat(devices.count()).isZero();
        assertThat(watches.count()).isZero();
    }

    @Test
    void switchingAlertsOffForgetsThePhone() throws Exception {
        sync(ENDPOINT, everton(java.time.Instant.now().toString()));
        mvc.perform(delete("/push/devices").contentType(MediaType.APPLICATION_JSON).content("{\"endpoint\": \"" + ENDPOINT + "\"}"))
                .andExpect(status().isNoContent());
        assertThat(devices.count()).isZero();
    }

    @Test
    void refusesOtherEndpointsAndTicksWithoutTheKey() throws Exception {
        mvc.perform(put("/push/devices").contentType(MediaType.APPLICATION_JSON).content("""
                {"subscription": {"endpoint": "https://example.com/x", "keys": {"p256dh": "a", "auth": "b"}}, "matches": []}"""))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/push/tick")).andExpect(status().isForbidden());
        mvc.perform(post("/push/tick").header("X-Tick-Key", "wrong")).andExpect(status().isForbidden());
    }

    @Test
    void theWebAppMayCall() throws Exception {
        mvc.perform(options("/push/devices").header("Origin", "https://jonathanemc23.github.io")
                        .header("Access-Control-Request-Method", "PUT"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "https://jonathanemc23.github.io"));
    }
}
