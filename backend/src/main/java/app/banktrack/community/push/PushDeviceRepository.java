package app.banktrack.community.push;

import java.time.Instant;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

public interface PushDeviceRepository extends JpaRepository<PushDevice, Long> {
    Optional<PushDevice> findByEndpoint(String endpoint);

    /** Phones that haven't synced since [before]; their watches go with them. */
    @Modifying
    @Query("delete from PushDevice d where d.updatedAt < ?1")
    int deleteStale(Instant before);
}
