package app.banktrack.community.push;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * The server's VAPID key pair (RFC 8292): browsers subscribe with the public key, and each push carries a token
 * signed with the private one. The pair is made on first use and kept in the database, so there is nothing to set
 * up and subscriptions survive restarts.
 */
@Component
public class VapidKeys {
    static final Base64.Encoder B64 = Base64.getUrlEncoder().withoutPadding();
    static final Base64.Decoder B64D = Base64.getUrlDecoder();

    private final PushKeyRepository keys;
    private final String subject;
    private volatile PushKey key;
    private volatile PrivateKey privateKey;

    public VapidKeys(PushKeyRepository keys, @Value("${banktrack.push.subject:https://jonathanemc23.github.io/BetAssistance/}") String subject) {
        this.keys = keys;
        this.subject = subject;
    }

    /** The public key as browsers take it (applicationServerKey): the raw P-256 point, base64url. */
    @Transactional
    public String publicKey() {
        return load().getPublicKey();
    }

    /** The Authorization header for a push to [audience] (the push service's origin), good for 12 hours. */
    @Transactional
    public String authorization(String audience, Instant now) {
        PushKey k = load();
        try {
            String header = B64.encodeToString("{\"typ\":\"JWT\",\"alg\":\"ES256\"}".getBytes(StandardCharsets.UTF_8));
            String claims = B64.encodeToString(("{\"aud\":\"" + audience + "\",\"exp\":" + now.plusSeconds(12 * 3600).getEpochSecond()
                    + ",\"sub\":\"" + subject + "\"}").getBytes(StandardCharsets.UTF_8));
            Signature es256 = Signature.getInstance("SHA256withECDSAinP1363Format");
            es256.initSign(privateKey);
            es256.update((header + "." + claims).getBytes(StandardCharsets.US_ASCII));
            String jwt = header + "." + claims + "." + B64.encodeToString(es256.sign());
            return "vapid t=" + jwt + ", k=" + k.getPublicKey();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private PushKey load() {
        if (key != null) return key;
        synchronized (this) {
            if (key != null) return key;
            PushKey k = keys.findById(1).orElseGet(() -> keys.save(generate()));
            try {
                privateKey = KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(B64D.decode(k.getPrivateKey())));
            } catch (GeneralSecurityException e) {
                throw new IllegalStateException(e);
            }
            key = k;
            return k;
        }
    }

    static PushKey generate() {
        KeyPair pair = newPair();
        return new PushKey(B64.encodeToString(raw((ECPublicKey) pair.getPublic())), B64.encodeToString(pair.getPrivate().getEncoded()));
    }

    static KeyPair newPair() {
        try {
            KeyPairGenerator gen = KeyPairGenerator.getInstance("EC");
            gen.initialize(new ECGenParameterSpec("secp256r1"));
            return gen.generateKeyPair();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The uncompressed point: 0x04, x, y (65 bytes). */
    static byte[] raw(ECPublicKey key) {
        byte[] out = new byte[65];
        out[0] = 4;
        put(key.getW().getAffineX(), out, 1);
        put(key.getW().getAffineY(), out, 33);
        return out;
    }

    private static void put(BigInteger n, byte[] out, int at) {
        byte[] b = n.toByteArray();
        int len = Math.min(b.length, 32);
        System.arraycopy(b, b.length - len, out, at + 32 - len, len);
    }
}
