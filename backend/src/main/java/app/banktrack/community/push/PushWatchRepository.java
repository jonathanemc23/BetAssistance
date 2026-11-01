package app.banktrack.community.push;

import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

public interface PushWatchRepository extends JpaRepository<PushWatch, Long> {
    List<PushWatch> findByDevice(PushDevice device);

    List<PushWatch> findByKickoffBetween(Instant from, Instant to);

    @Modifying
    @Query("delete from PushWatch w where w.kickoff < ?1 or w.device.id in (select d.id from PushDevice d where d.updatedAt < ?2)")
    int deleteOld(Instant kickoffBefore, Instant deviceBefore);
}
