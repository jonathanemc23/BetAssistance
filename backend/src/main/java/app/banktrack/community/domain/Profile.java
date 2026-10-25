package app.banktrack.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/** A community profile, one per signed-in user. */
@Entity
@Table(name = "profiles")
public class Profile {
    @Id
    @Column(name = "user_id")
    private String userId;
    private String handle;
    private String name;
    private String bio = "";
    private String avatar = "";
    @Column(name = "joined_at")
    private Instant joinedAt;

    protected Profile() {}

    public Profile(String userId, String handle, String name, String bio, String avatar, Instant joinedAt) {
        this.userId = userId;
        this.handle = handle;
        this.name = name;
        this.bio = bio == null ? "" : bio;
        this.avatar = avatar == null ? "" : avatar;
        this.joinedAt = joinedAt;
    }

    public String getUserId() { return userId; }
    public String getHandle() { return handle; }
    public String getName() { return name; }
    public String getBio() { return bio; }
    public String getAvatar() { return avatar; }
    public Instant getJoinedAt() { return joinedAt; }

    public void update(String name, String bio, String avatar) {
        if (name != null && !name.isBlank()) this.name = name.trim();
        if (bio != null) this.bio = bio.trim();
        if (avatar != null) this.avatar = avatar;
    }
}
