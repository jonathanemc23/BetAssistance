package app.banktrack.community.push;

import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Keeps each phone's subscription and the matches it follows, as the app sends them. */
@Service
public class PushService {
    /** Push services browsers use; endpoints anywhere else are refused so the server only posts to them. */
    static final List<String> PUSH_HOSTS = List.of(
            "push.apple.com", "fcm.googleapis.com", "push.services.mozilla.com", "notify.windows.com");
    static final int MAX_MATCHES = 100;

    public record Keys(String p256dh, String auth) {}

    public record Subscription(String endpoint, Keys keys) {}

    /** A match with an open bet on it. feed is ESPN's sport/league, kickoff ISO 8601. */
    public record Match(String id, String feed, String sport, String kickoff, String home, String away, List<String> picks) {}

    public record Sync(Subscription subscription, String lang, List<Match> matches) {}

    private final PushDeviceRepository devices;
    private final PushWatchRepository watches;
    private final Clock clock;

    public PushService(PushDeviceRepository devices, PushWatchRepository watches, Clock clock) {
        this.devices = devices;
        this.watches = watches;
        this.clock = clock;
    }

    /** Saves the phone's subscription and replaces the matches it follows, keeping what was already read of each. */
    @Transactional
    public void sync(Sync s) {
        Subscription sub = s.subscription();
        if (sub == null || sub.keys() == null || blank(sub.keys().p256dh()) || blank(sub.keys().auth())) {
            throw new IllegalArgumentException("Missing subscription");
        }
        checkEndpoint(sub.endpoint());
        List<Match> matches = s.matches() == null ? List.of() : s.matches();
        if (matches.size() > MAX_MATCHES) throw new IllegalArgumentException("Too many matches");
        Instant now = clock.instant();
        PushDevice device = devices.findByEndpoint(sub.endpoint()).orElseGet(() -> new PushDevice(sub.endpoint()));
        device.update(cut(sub.keys().p256dh(), 200), cut(sub.keys().auth(), 100), "es".equals(s.lang()) ? "es" : "en", now);
        device = devices.save(device);

        Map<String, PushWatch> have = new HashMap<>();
        for (PushWatch w : watches.findByDevice(device)) have.put(w.getMatchId(), w);
        Set<String> keep = new HashSet<>();
        for (Match m : matches) {
            if (blank(m.id()) || m.id().length() > 64 || m.feed() == null || !EspnLiveFeed.FEED.matcher(m.feed()).matches()
                    || m.feed().length() > 80 || !keep.add(m.id())) {
                continue;
            }
            Instant kickoff;
            try {
                kickoff = Instant.parse(m.kickoff());
            } catch (RuntimeException e) {
                continue;
            }
            PushWatch w = have.get(m.id());
            if (w == null) w = new PushWatch(device, m.id());
            List<String> picks = m.picks() == null ? List.of()
                    : m.picks().stream().filter(p -> p != null && !p.isBlank()).map(p -> cut(p.replace('\n', ' '), 120)).limit(8).toList();
            w.update(m.feed(), cut(nz(m.sport()), 20), kickoff, cut(nz(m.home()), 80), cut(nz(m.away()), 80), picks);
            watches.save(w);
        }
        for (PushWatch w : have.values()) {
            if (!keep.contains(w.getMatchId())) watches.delete(w);
        }
    }

    @Transactional
    public void remove(String endpoint) {
        devices.findByEndpoint(endpoint).ifPresent(d -> {
            watches.deleteAll(watches.findByDevice(d));
            devices.delete(d);
        });
    }

    static void checkEndpoint(String endpoint) {
        URI uri;
        try {
            uri = URI.create(endpoint);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("Bad endpoint");
        }
        String host = uri.getHost();
        if (!"https".equals(uri.getScheme()) || host == null || endpoint.length() > 1000
                || PUSH_HOSTS.stream().noneMatch(h -> host.equals(h) || host.endsWith("." + h))) {
            throw new IllegalArgumentException("Bad endpoint");
        }
    }

    private static boolean blank(String s) {
        return s == null || s.isBlank();
    }

    private static String nz(String s) {
        return s == null ? "" : s;
    }

    private static String cut(String s, int max) {
        return s.length() <= max ? s : s.substring(0, max);
    }
}
