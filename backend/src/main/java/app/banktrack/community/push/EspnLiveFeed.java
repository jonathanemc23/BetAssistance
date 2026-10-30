package app.banktrack.community.push;

import java.util.Optional;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;

/** Live scores from ESPN's public match summary feed, the same one the app reads. */
@Component
public class EspnLiveFeed implements LiveFeed {
    private static final Logger log = LoggerFactory.getLogger(EspnLiveFeed.class);

    /** sport/league, as the app sends it. */
    static final Pattern FEED = Pattern.compile("[a-z]+/[a-z0-9._-]+");

    private final RestClient http = RestClient.create("https://site.api.espn.com/apis/site/v2/sports");

    @Override
    public Optional<LiveAlerts.Game> read(String feed, String matchId) {
        if (!FEED.matcher(feed).matches()) return Optional.empty();
        String[] parts = feed.split("/");
        try {
            JsonNode body = http.get().uri("/{sport}/{league}/summary?event={id}", parts[0], parts[1], matchId)
                    .retrieve().body(JsonNode.class);
            return body == null ? Optional.empty() : parse(body);
        } catch (RuntimeException e) {
            log.warn("No live score for {} {}: {}", feed, matchId, e.getMessage());
            return Optional.empty();
        }
    }

    static Optional<LiveAlerts.Game> parse(JsonNode body) {
        JsonNode comp = body.path("header").path("competitions").path(0);
        JsonNode type = comp.path("status").path("type");
        LiveAlerts.State state = switch (type.path("state").asString("")) {
            case "pre" -> LiveAlerts.State.SCHEDULED;
            case "in" -> LiveAlerts.State.LIVE;
            case "post" -> type.path("completed").asBoolean(false) ? LiveAlerts.State.FINISHED : LiveAlerts.State.OTHER;
            default -> LiveAlerts.State.OTHER;
        };
        String home = null, away = null, homeScore = null, awayScore = null;
        for (JsonNode c : comp.path("competitors")) {
            JsonNode team = c.path("team");
            String name = team.path("displayName").asString(team.path("name").asString("?"));
            String score = c.path("score").isMissingNode() || c.path("score").isNull() ? null : c.path("score").asString();
            if ("home".equals(c.path("homeAway").asString(""))) {
                home = name;
                homeScore = score;
            } else {
                away = name;
                awayScore = score;
            }
        }
        if (home == null || away == null) return Optional.empty();
        if (state == LiveAlerts.State.SCHEDULED) homeScore = awayScore = null;
        return Optional.of(new LiveAlerts.Game(state, home, away, homeScore, awayScore,
                type.path("shortDetail").asString(""), body.path("header").path("league").path("name").asString("")));
    }
}
