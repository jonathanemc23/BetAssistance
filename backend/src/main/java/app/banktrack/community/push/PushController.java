package app.banktrack.community.push;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Live alerts with the app closed. No sign-in: a phone is known by its push subscription, whose endpoint only that
 * browser and its push service know.
 *
 * <pre>
 * GET    /push/key       the server's public key, to subscribe with
 * PUT    /push/devices   {subscription, lang, matches}: save the subscription and the matches it follows
 * DELETE /push/devices   {endpoint}: alerts switched off
 * POST   /push/tick      run a round now (header X-Tick-Key), for hosts that sleep between requests
 * </pre>
 */
@RestController
@RequestMapping("/push")
public class PushController {
    private final VapidKeys keys;
    private final PushService service;
    private final LiveAlertJob job;
    private final String tickKey;

    public PushController(VapidKeys keys, PushService service, LiveAlertJob job,
            @Value("${banktrack.push.tick-key:}") String tickKey) {
        this.keys = keys;
        this.service = service;
        this.job = job;
        this.tickKey = tickKey;
    }

    public record Removal(String endpoint) {}

    @GetMapping("/key")
    public Map<String, String> key() {
        return Map.of("key", keys.publicKey());
    }

    @PutMapping("/devices")
    public ResponseEntity<Void> sync(@RequestBody PushService.Sync sync) {
        service.sync(sync);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/devices")
    public ResponseEntity<Void> remove(@RequestBody Removal removal) {
        if (removal.endpoint() != null) service.remove(removal.endpoint());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/tick")
    public ResponseEntity<Map<String, Integer>> tick(@RequestHeader(value = "X-Tick-Key", required = false) String key) {
        if (tickKey.isBlank() || key == null
                || !MessageDigest.isEqual(tickKey.getBytes(StandardCharsets.UTF_8), key.getBytes(StandardCharsets.UTF_8))) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(Map.of("sent", job.tick()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> refused(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}
