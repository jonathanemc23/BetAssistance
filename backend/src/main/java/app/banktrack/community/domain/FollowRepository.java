package app.banktrack.community.domain;

import org.springframework.data.jpa.repository.JpaRepository;

public interface FollowRepository extends JpaRepository<Follow, Follow.Key> {
    long countByIdFollowedId(String followedId);

    long countByIdFollowerId(String followerId);
}
