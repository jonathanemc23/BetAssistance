package app.banktrack.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import java.io.Serializable;
import java.time.Instant;

/** One user following another. */
@Entity
@Table(name = "follows")
public class Follow {
    @Embeddable
    public record Key(@Column(name = "follower_id") String followerId, @Column(name = "followed_id") String followedId)
            implements Serializable {}

    @EmbeddedId
    private Key id;
    @Column(name = "created_at")
    private Instant createdAt;

    protected Follow() {}

    public Follow(String followerId, String followedId, Instant createdAt) {
        this.id = new Key(followerId, followedId);
        this.createdAt = createdAt;
    }

    public Key getId() { return id; }
}
