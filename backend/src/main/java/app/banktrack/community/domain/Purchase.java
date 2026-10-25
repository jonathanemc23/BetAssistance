package app.banktrack.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import java.io.Serializable;
import java.time.Instant;

/** A bet for sale that a user bought: they can see its pick. */
@Entity
@Table(name = "purchases")
public class Purchase {
    @Embeddable
    public record Key(@Column(name = "buyer_id") String buyerId, @Column(name = "bet_id") Long betId) implements Serializable {}

    @EmbeddedId
    private Key id;
    private int price;
    @Column(name = "created_at")
    private Instant createdAt;

    protected Purchase() {}

    public Purchase(String buyerId, Long betId, int price, Instant createdAt) {
        this.id = new Key(buyerId, betId);
        this.price = price;
        this.createdAt = createdAt;
    }

    public Key getId() { return id; }
}
