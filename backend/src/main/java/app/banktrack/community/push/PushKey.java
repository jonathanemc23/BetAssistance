package app.banktrack.community.push;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** The server's VAPID key pair (one row), made on first use. */
@Entity
@Table(name = "push_keys")
public class PushKey {
    @Id
    private Integer id;
    /** The raw P-256 point, base64url: what browsers take as applicationServerKey. */
    @Column(name = "public_key")
    private String publicKey;
    /** PKCS#8, base64url. */
    @Column(name = "private_key")
    private String privateKey;

    protected PushKey() {}

    public PushKey(String publicKey, String privateKey) {
        this.id = 1;
        this.publicKey = publicKey;
        this.privateKey = privateKey;
    }

    public String getPublicKey() { return publicKey; }
    public String getPrivateKey() { return privateKey; }
}
