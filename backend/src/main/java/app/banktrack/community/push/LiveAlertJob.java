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
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;

/**
 * Once a minute, reads the matches phones follow that are about to start or being played and sends each phone
 * kick-off, every score change and full time, so alerts arrive with the app closed. Runs on its own where the
 * server stays up; where it sleeps between requests (Cloud Run), POST /push/tick runs it instead.
 */
@Component
public class LiveAlertJob {
    /** As in the app: from shortly before kick-off until a few hours after, or longer while it was live. */
    static final Duration BEFORE = Duration.ofMinutes(30);
    static final Duration AFTER = Duration.ofHours(4);
    static final Duration LIVE_AFTER = Duration.ofHours(8);

    private final PushWatchRepository watches;
    private final PushDeviceRepository devices;
    private final LiveFeed feed;
    private final PushSender sender;
    private final Clock clock;
    private final ObjectMapper json = new ObjectMapper();

    public LiveAlertJob(PushWatchRepository watches, PushDeviceRepository devices, LiveFeed feed, PushSender sender, Clock clock) {
        this.watches = watches;
        this.devices = devices;
        this.feed = feed;
        this.sender = sender;
        this.clock = clock;
    }

    /** One round. Returns the number of alerts sent. */
    @Scheduled(fixedDelayString = "${banktrack.push.every:PT1M}")
    @Transactional
    public synchronized int tick() {
        Instant now = clock.instant();
        watches.deleteOld(now.minus(Duration.ofDays(2)), now.minus(Duration.ofDays(30)));
        devices.deleteStale(now.minus(Duration.ofDays(30)));

        Map<String, List<PushWatch>> byMatch = new LinkedHashMap<>();
        for (PushWatch w : watches.findByKickoffBetween(now.minus(LIVE_AFTER), now.plus(BEFORE))) {
            if (w.getState() == LiveAlerts.State.FINISHED) continue;
            Duration after = w.getState() == LiveAlerts.State.LIVE ? LIVE_AFTER : AFTER;
            if (now.isAfter(w.getKickoff().plus(after))) continue;
            byMatch.computeIfAbsent(w.getFeed() + "|" + w.getMatchId(), k -> new ArrayList<>()).add(w);
        }
        int sent = 0;
        Set<Long> gone = new HashSet<>();
        for (List<PushWatch> group : byMatch.values()) {
            Optional<LiveAlerts.Game> game = feed.read(group.getFirst().getFeed(), group.getFirst().getMatchId());
            if (game.isEmpty()) continue;
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
