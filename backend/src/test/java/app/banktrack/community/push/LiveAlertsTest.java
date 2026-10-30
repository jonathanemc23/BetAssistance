package app.banktrack.community.push;

import static org.assertj.core.api.Assertions.assertThat;

import app.banktrack.community.push.LiveAlerts.Alert;
import app.banktrack.community.push.LiveAlerts.Game;
import app.banktrack.community.push.LiveAlerts.Snapshot;
import app.banktrack.community.push.LiveAlerts.State;
import java.util.List;
import org.junit.jupiter.api.Test;

class LiveAlertsTest {
    static Game game(State s, String h, String a, String detail) {
        return new Game(s, "Everton", "Chelsea", h, a, detail, "Premier League");
    }

    static Alert alert(Snapshot last, Game now) {
        return LiveAlerts.alertFor("Soccer", List.of("Everton to win"), "en", last, now);
    }

    @Test
    void kickOffGoalsAndFullTime() {
        Snapshot pre = new Snapshot(State.SCHEDULED, null, null);
        assertThat(alert(pre, game(State.LIVE, "0", "0", "1'")))
                .isEqualTo(new Alert("Kick-off: Everton vs Chelsea", "1' · Premier League\nYour pick: Everton to win"));
        Snapshot live = new Snapshot(State.LIVE, "0", "0");
        assertThat(alert(live, game(State.LIVE, "0", "0", "30'"))).isNull();
        assertThat(alert(live, game(State.LIVE, "1", "0", "31'")))
                .isEqualTo(new Alert("Goal! Everton 1-0 Chelsea", "31'\nYour pick: Everton to win"));
        assertThat(alert(new Snapshot(State.LIVE, "2", "0"), game(State.LIVE, "1", "0", "33'")).title())
                .isEqualTo("Score corrected: Everton 1-0 Chelsea");
        assertThat(alert(live, game(State.FINISHED, "2", "1", "FT")))
                .isEqualTo(new Alert("Full time: Everton 2-1 Chelsea", "Your pick: Everton to win"));
        assertThat(alert(new Snapshot(State.FINISHED, "2", "1"), game(State.FINISHED, "2", "1", "FT"))).isNull();
    }

    @Test
    void aFirstReadingOnlyRecordsUnlessItIsOver() {
        assertThat(alert(null, game(State.LIVE, "1", "0", "50'"))).isNull();
        assertThat(alert(null, game(State.FINISHED, "1", "0", "FT")).title()).isEqualTo("Full time: Everton 1-0 Chelsea");
    }

    @Test
    void speaksThePhonesLanguage() {
        Alert a = LiveAlerts.alertFor("Basketball", List.of("Lakers -4.5", "Más de 220.5"), "es",
                new Snapshot(State.LIVE, "50", "48"), game(State.LIVE, "52", "48", "Q3"));
        assertThat(a).isEqualTo(new Alert("Actualización: Everton 52-48 Chelsea", "Q3\nTus apuestas: Lakers -4.5, Más de 220.5"));
        assertThat(LiveAlerts.alertFor("Soccer", List.of(), "es", new Snapshot(State.SCHEDULED, null, null),
                game(State.LIVE, "1", "0", "")).title()).isEqualTo("En juego: Everton 1-0 Chelsea");
    }
}
