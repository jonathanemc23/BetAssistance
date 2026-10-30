package app.banktrack.community.push;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;

/** A match a phone follows because it has an open bet on it, and what the last reading of it saw. */
@Entity
@Table(name = "push_watches")
public class PushWatch {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "device_id")
    private PushDevice device;
    @Column(name = "match_id")
    private String matchId;
    /** ESPN's sport and league, e.g. soccer/eng.1. */
    private String feed;
    private String sport;
    private Instant kickoff;
    private String home;
    private String away;
    /** The picks riding on the match, one per line, in the phone's language. */
    private String picks;
    @Enumerated(EnumType.STRING)
    private LiveAlerts.State state;
    @Column(name = "home_score")
    private String homeScore;
    @Column(name = "away_score")
    private String awayScore;

    protected PushWatch() {}

    public PushWatch(PushDevice device, String matchId) {
        this.device = device;
        this.matchId = matchId;
    }

    public void update(String feed, String sport, Instant kickoff, String home, String away, List<String> picks) {
        this.feed = feed;
        this.sport = sport;
        this.kickoff = kickoff;
        this.home = home;
        this.away = away;
        this.picks = String.join("\n", picks);
    }

    /** What the last reading saw, null before the first. */
    public LiveAlerts.Snapshot last() {
        return state == null ? null : new LiveAlerts.Snapshot(state, homeScore, awayScore);
    }

    public void record(LiveAlerts.Game game) {
        this.state = game.state();
        this.homeScore = game.homeScore();
        this.awayScore = game.awayScore();
    }

    public List<String> pickList() {
        return picks == null || picks.isEmpty() ? List.of() : Arrays.asList(picks.split("\n"));
    }

    public PushDevice getDevice() { return device; }
    public String getMatchId() { return matchId; }
    public String getFeed() { return feed; }
    public String getSport() { return sport; }
    public Instant getKickoff() { return kickoff; }
    public LiveAlerts.State getState() { return state; }
}
