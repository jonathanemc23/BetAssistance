package app.banktrack.community.service;

import app.banktrack.community.domain.TokenEntry;
import app.banktrack.community.domain.TokenEntryRepository;
import java.time.Clock;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Token balances, kept as a ledger on the server so they can't be changed on the phone. */
@Service
public class TokenService {
    /** What a new profile starts with, as the app gives today. */
    public static final int WELCOME = 10;

    private final TokenEntryRepository entries;
    private final Clock clock;

    public TokenService(TokenEntryRepository entries, Clock clock) {
        this.entries = entries;
        this.clock = clock;
    }

    public int balance(String userId) {
        return entries.balance(userId);
    }

    @Transactional
    public void credit(String userId, int amount, String reason, String reference) {
        if (reference != null && entries.existsByReasonAndReference(reason, reference)) return;
        entries.save(new TokenEntry(userId, amount, reason, reference, clock.instant()));
    }

    /** Takes [amount] tokens, or refuses when the balance is short. */
    @Transactional
    public void debit(String userId, int amount, String reason, String reference) {
        if (balance(userId) < amount) throw new ApiException(HttpStatus.PAYMENT_REQUIRED, "Not enough tokens.");
        entries.save(new TokenEntry(userId, -amount, reason, reference, clock.instant()));
    }
}
