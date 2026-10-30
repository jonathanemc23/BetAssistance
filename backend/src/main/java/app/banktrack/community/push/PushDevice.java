package app.banktrack.community.push;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/** A browser's push subscription: where to send and the keys to encrypt with. */
@Entity
@Table(name = "push_devices")
public class PushDevice {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String endpoint;
    private String p256dh;
    private String auth;
    private String lang;
    @Column(name = "updated_at")
    private Instant updatedAt;

    protected PushDevice() {}

    public PushDevice(String endpoint) {
        this.endpoint = endpoint;
    }

    public void update(String p256dh, String auth, String lang, Instant now) {
        this.p256dh = p256dh;
        this.auth = auth;
        this.lang = lang;
        this.updatedAt = now;
    }

    public Long getId() { return id; }
    public String getEndpoint() { return endpoint; }
    public String getP256dh() { return p256dh; }
    public String getAuth() { return auth; }
    public String getLang() { return lang; }
}
