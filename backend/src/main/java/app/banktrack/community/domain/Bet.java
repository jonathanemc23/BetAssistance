package app.banktrack.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/** A selection on a match, settled from the final score: a free bet, a bet for sale or a challenge bet. */
@Entity
@Table(name = "bets")
public class Bet {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "owner_id")
    private String ownerId;
    @Enumerated(EnumType.STRING)
    private BetKind kind;
    private Integer attempt;
    @Column(name = "match_id")
    private String matchId;
    private String league;
    private String home;
    private String away;
    private Instant kickoff;
    @Enumerated(EnumType.STRING)
    private Market market;
    private String pick;
    private Double line;
    private double odds;
    private int price;
    /** WON, LOST, or null until the match is over. */
    private String result;
    @Column(name = "created_at")
    private Instant createdAt;

    protected Bet() {}

    public Bet(String ownerId, BetKind kind, Integer attempt, Selection s, int price, Instant createdAt) {
        this.ownerId = ownerId;
        this.kind = kind;
        this.attempt = attempt;
        this.matchId = s.matchId();
        this.league = s.league();
        this.home = s.home();
        this.away = s.away();
        this.kickoff = s.kickoff();
        this.market = s.market();
        this.pick = s.pick();
        this.line = s.line();
        this.odds = s.odds();
        this.price = price;
        this.createdAt = createdAt;
    }

    public void settle(int h, int a) {
        result = market.wins(h, a, line) ? "WON" : "LOST";
    }

    public Long getId() { return id; }
    public String getOwnerId() { return ownerId; }
    public BetKind getKind() { return kind; }
    public Integer getAttempt() { return attempt; }
    public String getMatchId() { return matchId; }
    public String getLeague() { return league; }
    public String getHome() { return home; }
    public String getAway() { return away; }
    public Instant getKickoff() { return kickoff; }
    public Market getMarket() { return market; }
    public String getPick() { return pick; }
    public Double getLine() { return line; }
    public double getOdds() { return odds; }
    public int getPrice() { return price; }
    public String getResult() { return result; }
    public Instant getCreatedAt() { return createdAt; }
    public boolean isSettled() { return result != null; }
    public boolean isWon() { return "WON".equals(result); }
}
