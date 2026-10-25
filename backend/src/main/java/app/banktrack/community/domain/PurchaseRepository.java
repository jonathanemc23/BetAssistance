package app.banktrack.community.domain;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PurchaseRepository extends JpaRepository<Purchase, Purchase.Key> {
    long countByIdBetId(Long betId);

    List<Purchase> findByIdBuyerIdAndIdBetIdIn(String buyerId, Collection<Long> betIds);
}
