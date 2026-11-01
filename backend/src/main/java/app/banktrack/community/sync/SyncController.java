package app.banktrack.community.sync;

import app.banktrack.community.service.ApiException;
import java.security.Principal;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * The signed-in user's own data, saved on their account so it follows them to any phone. The server keeps the
 * app's snapshot as it comes (a JSON text) and never reads inside it; only its owner can fetch it.
 *
 * <p>Saves are optimistic: the app sends the version it last saw as baseVersion, and if another phone saved in
 * between the answer is 409 with the current version, so the app can ask before anything is overwritten.
 */
@RestController
@RequestMapping("/api/sync")
public class SyncController {
    /** About 5 MB of text: years of bets with room to spare. */
    static final int MAX_CHARS = 5_000_000;

    public record Snapshot(long version, Instant updatedAt, String data) {}

    public record Save(long baseVersion, String data) {}

    public record Saved(long version, Instant updatedAt) {}

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public SyncController(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    /** The account's data, or version 0 and no data for an account that never saved. */
    @GetMapping
    public Snapshot get(Principal user) {
        List<Snapshot> rows = jdbc.query("select version, updated_at, data from user_data where user_id = ?",
                (rs, i) -> new Snapshot(rs.getLong(1), rs.getTimestamp(2).toInstant(), rs.getString(3)), user.getName());
        return rows.isEmpty() ? new Snapshot(0, null, null) : rows.get(0);
    }

    @PutMapping
    @Transactional
    public ResponseEntity<?> save(Principal user, @RequestBody Save save) {
        if (save.data() == null || save.data().isBlank()) throw new ApiException(HttpStatus.BAD_REQUEST, "Nothing to save.");
        if (save.data().length() > MAX_CHARS) throw new ApiException(HttpStatus.CONTENT_TOO_LARGE, "Too much data to save.");
        Instant now = clock.instant();
        long next = save.baseVersion() + 1;
        int changed = jdbc.update("update user_data set version = ?, data = ?, updated_at = ? where user_id = ? and version = ?",
                next, save.data(), Timestamp.from(now), user.getName(), save.baseVersion());
        if (changed == 0 && save.baseVersion() == 0) {
            try {
                jdbc.update("insert into user_data (user_id, version, data, updated_at) values (?, ?, ?, ?)",
                        user.getName(), next, save.data(), Timestamp.from(now));
                changed = 1;
            } catch (DuplicateKeyException e) {
                // Another phone saved first; fall through to the conflict.
            }
        }
        if (changed == 0) {
            Long current = jdbc.query("select version from user_data where user_id = ?",
                    rs -> rs.next() ? rs.getLong(1) : 0L, user.getName());
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "Your account changed on another device.", "version", current));
        }
        return ResponseEntity.ok(new Saved(next, now));
    }

    /** Removes the data kept on the account. The phone keeps its own copy. */
    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(Principal user) {
        jdbc.update("delete from user_data where user_id = ?", user.getName());
    }
}
