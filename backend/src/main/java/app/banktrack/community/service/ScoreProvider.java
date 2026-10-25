package app.banktrack.community.service;

import java.util.Optional;

/** Where final scores come from. */
public interface ScoreProvider {
    record FinalScore(int home, int away) {}

    /** The final score of a match, or empty while it isn't finished (or can't be read). */
    Optional<FinalScore> finalScore(String league, String matchId);
}
