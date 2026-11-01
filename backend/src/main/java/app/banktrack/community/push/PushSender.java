package app.banktrack.community.push;

/** Delivers a push message to a browser. */
public interface PushSender {
    enum Result { SENT, GONE, FAILED }

    /** GONE when the push service says the subscription no longer exists. */
    Result send(PushDevice device, byte[] payload);
}
