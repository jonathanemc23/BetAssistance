package app.banktrack.community.push;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.time.Instant;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

class WebPushTest {
    /** Decrypts as a browser does (RFC 8291) with its private key and auth secret. */
    static byte[] decrypt(byte[] body, KeyPair browser, byte[] auth) throws Exception {
        ByteBuffer in = ByteBuffer.wrap(body);
        byte[] salt = new byte[16];
        in.get(salt);
        assertThat(in.getInt()).isEqualTo(4096);
        byte[] asPublic = new byte[in.get()];
        in.get(asPublic);
        byte[] sealed = new byte[in.remaining()];
        in.get(sealed);

        byte[] uaPublic = VapidKeys.raw((ECPublicKey) browser.getPublic());
        KeyAgreement ecdh = KeyAgreement.getInstance("ECDH");
        ecdh.init(browser.getPrivate());
        ecdh.doPhase(WebPush.publicKey(asPublic, (ECPublicKey) browser.getPublic()), true);
        byte[] ikm = WebPush.expand(WebPush.hmac(auth, ecdh.generateSecret()),
                WebPush.concat("WebPush: info\0".getBytes(StandardCharsets.US_ASCII), uaPublic, asPublic), 32);
        byte[] prk = WebPush.hmac(salt, ikm);
        Cipher aes = Cipher.getInstance("AES/GCM/NoPadding");
        aes.init(Cipher.DECRYPT_MODE,
                new SecretKeySpec(WebPush.expand(prk, "Content-Encoding: aes128gcm\0".getBytes(StandardCharsets.US_ASCII), 16), "AES"),
                new GCMParameterSpec(128, WebPush.expand(prk, "Content-Encoding: nonce\0".getBytes(StandardCharsets.US_ASCII), 12)));
        byte[] plain = aes.doFinal(sealed);
        assertThat(plain[plain.length - 1]).isEqualTo((byte) 2);
        return Arrays.copyOf(plain, plain.length - 1);
    }

    @Test
    void encryptsForTheBrowser() throws Exception {
        KeyPair browser = VapidKeys.newPair();
        byte[] auth = new byte[16];
        Arrays.fill(auth, (byte) 7);
        byte[] msg = "{\"title\":\"Goal! Everton 1-0 Chelsea\"}".getBytes(StandardCharsets.UTF_8);

        byte[] body = WebPush.encrypt(msg, VapidKeys.raw((ECPublicKey) browser.getPublic()), auth);

        assertThat(body.length).isEqualTo(16 + 4 + 1 + 65 + msg.length + 1 + 16);
        assertThat(decrypt(body, browser, auth)).isEqualTo(msg);
    }

    @Test
    void signsTheVapidToken() throws Exception {
        PushKeyRepository repo = Mockito.mock(PushKeyRepository.class);
        PushKey key = VapidKeys.generate();
        Mockito.when(repo.findById(1)).thenReturn(java.util.Optional.of(key));
        VapidKeys vapid = new VapidKeys(repo, "https://example.com/");

        String header = vapid.authorization("https://web.push.apple.com", Instant.parse("2030-01-01T10:00:00Z"));

        assertThat(header).startsWith("vapid t=").endsWith(", k=" + key.getPublicKey());
        String jwt = header.substring(8, header.indexOf(','));
        String[] parts = jwt.split("\\.");
        assertThat(new String(VapidKeys.B64D.decode(parts[1]), StandardCharsets.UTF_8))
                .isEqualTo("{\"aud\":\"https://web.push.apple.com\",\"exp\":1893535200,\"sub\":\"https://example.com/\"}");
        Signature es256 = Signature.getInstance("SHA256withECDSAinP1363Format");
        ECPublicKey like = (ECPublicKey) VapidKeys.newPair().getPublic();
        es256.initVerify(WebPush.publicKey(VapidKeys.B64D.decode(key.getPublicKey()), like));
        es256.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
        assertThat(es256.verify(VapidKeys.B64D.decode(parts[2]))).isTrue();
    }
}
