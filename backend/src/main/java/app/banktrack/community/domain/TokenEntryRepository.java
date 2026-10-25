package app.banktrack.community.domain;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface TokenEntryRepository extends JpaRepository<TokenEntry, Long> {
    @Query("select coalesce(sum(t.amount), 0) from TokenEntry t where t.userId = ?1")
    int balance(String userId);

    boolean existsByReasonAndReference(String reason, String reference);
}
