package app.banktrack.community.domain;

import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BetRepository extends JpaRepository<Bet, Long> {
    List<Bet> findByKindAndKickoffAfterOrderByKickoffAsc(BetKind kind, Instant after);

    List<Bet> findByOwnerIdAndKindAndAttemptOrderByCreatedAtAsc(String ownerId, BetKind kind, Integer attempt);

    List<Bet> findByOwnerIdAndKindOrderByCreatedAtDesc(String ownerId, BetKind kind);

    long countByOwnerIdAndKindAndCreatedAtAfter(String ownerId, BetKind kind, Instant after);

    boolean existsByOwnerIdAndKindAndMatchIdAndMarket(String ownerId, BetKind kind, String matchId, Market market);

    /** Bets whose match should be over by now and still have no result. */
    List<Bet> findByResultIsNullAndKickoffBefore(Instant before);

    List<Bet> findByOwnerIdAndKindAndResultIsNotNull(String ownerId, BetKind kind);
}
