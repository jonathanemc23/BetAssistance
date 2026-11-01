package app.banktrack.community.push;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import org.springframework.stereotype.Component;

/** What the last rounds did, kept in memory for GET /push/status. No endpoints or other personal data. */
@Component
public class PushStats {
    private static final int KEEP = 20;

    private Instant lastTick;
    private int lastFollowed, lastRead, lastSent;
    private final Deque<String> pushes = new ArrayDeque<>();
    private final Deque<String> feedErrors = new ArrayDeque<>();

    synchronized void tick(Instant at, int followed, int read, int sent) {
        lastTick = at;
        lastFollowed = followed;
        lastRead = read;
        lastSent = sent;
    }

    /** One push: the push service's host and its answer (an HTTP status, or the error). */
    synchronized void push(Instant at, String host, String answer) {
        add(pushes, at + " " + host + " " + answer);
    }

    synchronized void feedError(Instant at, String feed, String matchId, String error) {
        add(feedErrors, at + " " + feed + " " + matchId + ": " + error);
    }

    private static void add(Deque<String> list, String line) {
        list.addFirst(line);
        while (list.size() > KEEP) list.removeLast();
    }

    record Snapshot(Instant lastTick, int followed, int read, int sent, List<String> pushes, List<String> feedErrors) {}

    synchronized Snapshot snapshot() {
        return new Snapshot(lastTick, lastFollowed, lastRead, lastSent, new ArrayList<>(pushes), new ArrayList<>(feedErrors));
    }
}
