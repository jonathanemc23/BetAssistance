package app.banktrack.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/** Where a user stands in the pro bettor challenge; its bets are the CHALLENGE bets of the current attempt. */
@Entity
@Table(name = "challenges")
public class Challenge {
    @Id
    @Column(name = "user_id")
    private String userId;
    private int attempt;
    @Column(name = "started_at")
    private Instant startedAt;
    @Column(name = "wait_until")
    private Instant waitUntil;
    @Column(name = "passed_at")
    private Instant passedAt;
    @Column(name = "last_rate")
    private Double lastRate;

    protected Challenge() {}

    public Challenge(String userId) {
        this.userId = userId;
    }

    public String getUserId() { return userId; }
    public int getAttempt() { return attempt; }
    public Instant getStartedAt() { return startedAt; }
    public Instant getWaitUntil() { return waitUntil; }
    public Instant getPassedAt() { return passedAt; }
    public Double getLastRate() { return lastRate; }

    void accept(Instant now) {
        attempt++;
        startedAt = now;
        waitUntil = null;
    }

    void end(Instant now, Double rate) {
        startedAt = null;
        waitUntil = now.plus(ChallengeRules.WAIT);
        lastRate = rate;
    }

    void pass(Instant now) {
        passedAt = now;
    }
}
