package app.banktrack.community.service;

import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;

/** Final scores from ESPN's public match summary feed, the same one the app reads. */
@Component
public class EspnScoreProvider implements ScoreProvider {
    private static final Logger log = LoggerFactory.getLogger(EspnScoreProvider.class);

    private final RestClient http = RestClient.create("https://site.api.espn.com/apis/site/v2/sports/soccer");

    @Override
    public Optional<FinalScore> finalScore(String league, String matchId) {
        try {
            JsonNode body = http.get().uri("/{league}/summary?event={id}", league, matchId).retrieve().body(JsonNode.class);
            JsonNode comp = body == null ? null : body.path("header").path("competitions").path(0);
            if (comp == null || !comp.path("status").path("type").path("completed").asBoolean(false)) return Optional.empty();
            Integer home = null, away = null;
            for (JsonNode team : comp.path("competitors")) {
                int score = Integer.parseInt(team.path("score").asString("0"));
                if ("home".equals(team.path("homeAway").asString(""))) home = score; else away = score;
            }
            return home == null || away == null ? Optional.empty() : Optional.of(new FinalScore(home, away));
        } catch (RuntimeException e) {
            log.warn("No score for {} {}: {}", league, matchId, e.getMessage());
            return Optional.empty();
        }
    }
}
