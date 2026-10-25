package app.banktrack.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/** One token movement. A balance is the sum of a user's entries, so tokens can't be edited on the phone. */
@Entity
@Table(name = "token_entries")
public class TokenEntry {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "user_id")
    private String userId;
    private int amount;
    private String reason;
    /** What the entry is for (a bet id, a Play Store order); unique per reason so nothing is paid twice. */
    private String reference;
    @Column(name = "created_at")
    private Instant createdAt;

    protected TokenEntry() {}

    public TokenEntry(String userId, int amount, String reason, String reference, Instant createdAt) {
        this.userId = userId;
        this.amount = amount;
        this.reason = reason;
        this.reference = reference;
        this.createdAt = createdAt;
    }

    public int getAmount() { return amount; }
    public String getReason() { return reason; }
}
