package app.banktrack.community.domain;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProfileRepository extends JpaRepository<Profile, String> {
    Optional<Profile> findByHandle(String handle);

    boolean existsByHandle(String handle);
}
