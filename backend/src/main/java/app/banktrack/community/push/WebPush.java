package app.banktrack.community.push;

import java.io.ByteArrayOutputStream;
import java.math.BigInteger;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.SecureRandom;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Sends Web Push messages: the payload encrypted for the browser (RFC 8291, aes128gcm) and signed for the push
 * service with the server's VAPID key (RFC 8292). Apple's push service delivers these to home-screen web apps on
 * iPhone (iOS 16.4 and later), as Google's and Mozilla's do for their browsers.
 */
@Component
public class WebPush implements PushSender {
    private static final Logger log = LoggerFactory.getLogger(WebPush.class);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final VapidKeys vapid;
    private final Clock clock;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    public WebPush(VapidKeys vapid, Clock clock) {
        this.vapid = vapid;
        this.clock = clock;
    }

    @Override
    public Result send(PushDevice device, byte[] payload) {
        try {
            URI endpoint = URI.create(device.getEndpoint());
            byte[] body = encrypt(payload, VapidKeys.B64D.decode(device.getP256dh()), VapidKeys.B64D.decode(device.getAuth()));
            HttpRequest req = HttpRequest.newBuilder(endpoint)
                    .timeout(Duration.ofSeconds(15))
                    .header("Authorization", vapid.authorization(endpoint.getScheme() + "://" + endpoint.getHost(), clock.instant()))
                    .header("Content-Encoding", "aes128gcm")
                    .header("Content-Type", "application/octet-stream")
                    // A goal alert is old news after an hour.
                    .header("TTL", "3600")
                    .header("Urgency", "high")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(body))
                    .build();
            int status = http.send(req, HttpResponse.BodyHandlers.discarding()).statusCode();
            if (status == 404 || status == 410) return Result.GONE;
            if (status >= 200 && status < 300) return Result.SENT;
            log.warn("Push to {} refused: {}", endpoint.getHost(), status);
            return Result.FAILED;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return Result.FAILED;
        } catch (Exception e) {
            log.warn("Push failed: {}", e.getMessage());
            return Result.FAILED;
        }
    }

    /** One aes128gcm record for the browser with public key [uaPublic] (65 bytes) and [authSecret] (16 bytes). */
    static byte[] encrypt(byte[] plaintext, byte[] uaPublic, byte[] authSecret) throws GeneralSecurityException {
        byte[] salt = new byte[16];
        RANDOM.nextBytes(salt);
        return encrypt(plaintext, uaPublic, authSecret, VapidKeys.newPair(), salt);
    }

    static byte[] encrypt(byte[] plaintext, byte[] uaPublic, byte[] authSecret, KeyPair server, byte[] salt)
            throws GeneralSecurityException {
        byte[] asPublic = VapidKeys.raw((ECPublicKey) server.getPublic());
        KeyAgreement ecdh = KeyAgreement.getInstance("ECDH");
        ecdh.init(server.getPrivate());
        ecdh.doPhase(publicKey(uaPublic, (ECPublicKey) server.getPublic()), true);
        byte[] secret = ecdh.generateSecret();

        byte[] keyInfo = concat("WebPush: info\0".getBytes(StandardCharsets.US_ASCII), uaPublic, asPublic);
        byte[] ikm = expand(hmac(authSecret, secret), keyInfo, 32);
        byte[] prk = hmac(salt, ikm);
        byte[] cek = expand(prk, "Content-Encoding: aes128gcm\0".getBytes(StandardCharsets.US_ASCII), 16);
        byte[] nonce = expand(prk, "Content-Encoding: nonce\0".getBytes(StandardCharsets.US_ASCII), 12);

        Cipher aes = Cipher.getInstance("AES/GCM/NoPadding");
        aes.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(cek, "AES"), new GCMParameterSpec(128, nonce));
        // 0x02: the last (and only) record, no padding.
        byte[] sealed = aes.doFinal(concat(plaintext, new byte[] {2}));

        ByteBuffer header = ByteBuffer.allocate(16 + 4 + 1 + asPublic.length);
        header.put(salt).putInt(4096).put((byte) asPublic.length).put(asPublic);
        return concat(header.array(), sealed);
    }

    /** A browser's raw public key as a Java key on the same curve as [like]. */
    static ECPublicKey publicKey(byte[] raw, ECPublicKey like) throws GeneralSecurityException {
        if (raw.length != 65 || raw[0] != 4) throw new GeneralSecurityException("Not an uncompressed P-256 key");
        ECPoint point = new ECPoint(new BigInteger(1, Arrays.copyOfRange(raw, 1, 33)), new BigInteger(1, Arrays.copyOfRange(raw, 33, 65)));
        return (ECPublicKey) KeyFactory.getInstance("EC").generatePublic(new ECPublicKeySpec(point, like.getParams()));
    }

    static byte[] hmac(byte[] key, byte[] data) throws GeneralSecurityException {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return mac.doFinal(data);
    }

    /** HKDF-Expand for one block (length up to 32). */
    static byte[] expand(byte[] prk, byte[] info, int length) throws GeneralSecurityException {
        return Arrays.copyOf(hmac(prk, concat(info, new byte[] {1})), length);
    }

    static byte[] concat(byte[]... parts) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (byte[] p : parts) out.writeBytes(p);
        return out.toByteArray();
    }
}
