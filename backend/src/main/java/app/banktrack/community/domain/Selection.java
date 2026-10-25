package app.banktrack.community.domain;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.Instant;

/** What the app sends for a bet: the match and the market at its price. */
public record Selection(
        @NotBlank String matchId,
        @NotBlank String league,
        @NotBlank String home,
        @NotBlank String away,
        @NotNull Instant kickoff,
        @NotNull Market market,
        @NotBlank String pick,
        Double line,
        @Positive double odds) {}
