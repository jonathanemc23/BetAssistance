package app.banktrack.community.push;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.ObjectMapper;

/**
 * Once a minute, reads the matches phones follow that are about to start or being played and sends each phone
 * kick-off, every score change and full time, so alerts arrive with the app closed. Runs on its own where the
 * server stays up; where it sleeps between requests (Cloud Run), POST /push/tick runs it instead.
 *
 * <p>The database is only read when a followed match is near. After a round with nothing to follow, the job stays
 * quiet until 30 minutes before the next followed kick-off (at most {@link #MAX_QUIET}), and a phone saving its
 * matches wakes it. Reading the database every minute kept Neon's compute awake around the clock and used up the
 * free plan's monthly hours, which stopped the server (Nov 2026).
 */
@Component
public class LiveAlertJob {
    /** As in the app: from shortly before kick-off until a few hours after, or longer while it was live. */
    static final Duration BEFORE = Duration.ofMinutes(30);
    static final Duration AFTER = Duration.ofHours(4);
    static final Duration LIVE_AFTER = Duration.ofHours(8);
    /** Longest quiet spell, and how often old rows are cleaned up. */
    static final Duration MAX_QUIET = Duration.ofHours(6);

    private final PushWatchRepository watches;
    private final PushDeviceRepository devices;
    private final LiveFeed feed;
    private final PushSender sender;
    private final Clock clock;
    private final PushStats stats;
    private final ObjectMapper json = new ObjectMapper();
    private final TransactionTemplate tx;
    /** No database reads before this instant, unless {@link #wake()} is called. */
    private volatile Instant quietUntil = Instant.MIN;
    private Instant lastCleanup = Instant.MIN;

    public LiveAlertJob(PushWatchRepository watches, PushDeviceRepository devices, LiveFeed feed, PushSender sender, Clock clock,
            PushStats stats, PlatformTransactionManager transactions) {
        this.watches = watches;
        this.devices = devices;
        this.feed = feed;
        this.sender = sender;
        this.clock = clock;
        this.stats = stats;
        this.tx = new TransactionTemplate(transactions);
    }

    /** The matches followed have changed: read them on the next round. */
    public void wake() {
        quietUntil = Instant.MIN;
    }

    /** One round. Returns the number of alerts sent. */
    @Scheduled(fixedDelayString = "${banktrack.push.every:PT1M}")
    public synchronized int tick() {
        Instant now = clock.instant();
        if (now.isBefore(quietUntil)) {
            stats.tick(now, 0, 0, 0);
            return 0;
        }
        Integer sent = tx.execute(status -> round(now));
        return sent == null ? 0 : sent;
    }

    private int round(Instant now) {
        if (!now.isBefore(lastCleanup.plus(MAX_QUIET))) {
            watches.deleteOld(now.minus(Duration.ofDays(2)), now.minus(Duration.ofDays(30)));
            devices.deleteStale(now.minus(Duration.ofDays(30)));
            lastCleanup = now;
        }

        Map<String, List<PushWatch>> byMatch = new LinkedHashMap<>();
        for (PushWatch w : watches.findByKickoffBetween(now.minus(LIVE_AFTER), now.plus(BEFORE))) {
            if (w.getState() == LiveAlerts.State.FINISHED) continue;
            Duration after = w.getState() == LiveAlerts.State.LIVE ? LIVE_AFTER : AFTER;
            if (now.isAfter(w.getKickoff().plus(after))) continue;
            byMatch.computeIfAbsent(w.getFeed() + "|" + w.getMatchId(), k -> new ArrayList<>()).add(w);
        }
        int sent = 0, read = 0;
        Set<Long> gone = new HashSet<>();
        for (List<PushWatch> group : byMatch.values()) {
            Optional<LiveAlerts.Game> game = feed.read(group.getFirst().getFeed(), group.getFirst().getMatchId());
            if (game.isEmpty()) continue;
            read++;
            for (PushWatch w : group) {
                PushDevice d = w.getDevice();
                if (gone.contains(d.getId())) continue;
                LiveAlerts.Alert alert = LiveAlerts.alertFor(w.getSport(), w.pickList(), d.getLang(), w.last(), game.get());
                w.record(game.get());
                if (alert == null) continue;
                PushSender.Result r = sender.send(d, payload(alert, w.getMatchId()));
                if (r == PushSender.Result.SENT) sent++;
                if (r == PushSender.Result.GONE) gone.add(d.getId());
            }
        }
        watches.flush();
        stats.tick(now, byMatch.size(), read, sent);
        if (byMatch.isEmpty()) {
            Instant next = watches.findFirstByKickoffAfterOrderByKickoffAsc(now).map(PushWatch::getKickoff).orElse(null);
            Instant until = now.plus(MAX_QUIET);
            if (next != null && next.minus(BEFORE).isBefore(until)) until = next.minus(BEFORE);
            quietUntil = until;
        }
        for (Long id : gone) {
            devices.findById(id).ifPresent(d -> {
                watches.deleteAll(watches.findByDevice(d));
                devices.delete(d);
            });
        }
        return sent;
    }

    /** What the service worker shows. tag: one notification per match, replaced as the game goes on. */
    byte[] payload(LiveAlerts.Alert alert, String matchId) {
        return json.writeValueAsString(Map.of("title", alert.title(), "body", alert.body(), "tag", "match-" + matchId))
                .getBytes(StandardCharsets.UTF_8);
    }
}
