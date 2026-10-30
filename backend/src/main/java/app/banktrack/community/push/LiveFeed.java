package app.banktrack.community.push;

import java.util.Optional;

/** Where live scores come from. */
public interface LiveFeed {
    /** [matchId] in [feed] (ESPN's sport/league, e.g. soccer/eng.1) as it is now, or empty when it can't be read. */
    Optional<LiveAlerts.Game> read(String feed, String matchId);
}
