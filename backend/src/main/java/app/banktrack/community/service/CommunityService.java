package app.banktrack.community.service;

import app.banktrack.community.domain.Bet;
import app.banktrack.community.domain.BetKind;
import app.banktrack.community.domain.BetRepository;
import app.banktrack.community.domain.Challenge;
import app.banktrack.community.domain.ChallengeRepository;
import app.banktrack.community.domain.Follow;
import app.banktrack.community.domain.FollowRepository;
import app.banktrack.community.domain.Profile;
import app.banktrack.community.domain.ProfileRepository;
import app.banktrack.community.domain.Purchase;
import app.banktrack.community.domain.PurchaseRepository;
import app.banktrack.community.domain.Selection;
import app.banktrack.community.service.Views.BetView;
import app.banktrack.community.service.Views.Bettor;
import app.banktrack.community.service.Views.Me;
import app.banktrack.community.service.Views.ProfileView;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Profiles, follows, free bets and bets for sale. */
@Service
public class CommunityService {
    /** Free bets a bettor can post in a day, as in the app. */
    public static final int MAX_FREE_PER_DAY = 3;

    private static final Pattern HANDLE = Pattern.compile("^[a-z0-9_]{3,20}$");

    private final ProfileRepository profiles;
    private final FollowRepository follows;
    private final BetRepository bets;
    private final PurchaseRepository purchases;
    private final ChallengeRepository challenges;
    private final TokenService tokens;
    private final Clock clock;

    public CommunityService(ProfileRepository profiles, FollowRepository follows, BetRepository bets, PurchaseRepository purchases,
            ChallengeRepository challenges, TokenService tokens, Clock clock) {
        this.profiles = profiles;
        this.follows = follows;
        this.bets = bets;
        this.purchases = purchases;
        this.challenges = challenges;
        this.tokens = tokens;
        this.clock = clock;
    }

    // ------------------------------------------------------------ Profiles

    /** A handle as the community keeps it, or null when it can't be one. Same rule as the app's cleanHandle. */
    public static String cleanHandle(String raw) {
        if (raw == null) return null;
        String h = raw.trim().replaceFirst("^@", "").toLowerCase();
        return HANDLE.matcher(h).matches() ? h : null;
    }

    @Transactional
    public Me createProfile(String userId, String rawHandle, String name, String bio, String avatar) {
        if (profiles.existsById(userId)) throw ApiException.conflict("You already have a community profile.");
        String handle = cleanHandle(rawHandle);
        if (handle == null) throw ApiException.refused("3 to 20 letters, digits or _");
        if (profiles.existsByHandle(handle)) throw ApiException.conflict("That username is taken.");
        String display = name == null || name.isBlank() ? handle : name.trim();
        profiles.save(new Profile(userId, handle, display, bio, avatar, clock.instant()));
        challenges.save(new Challenge(userId));
        tokens.credit(userId, TokenService.WELCOME, "WELCOME", userId);
        return me(userId);
    }

    @Transactional
    public Me updateProfile(String userId, String name, String bio, String avatar) {
        profile(userId).update(name, bio, avatar);
        return me(userId);
    }

    public Me me(String userId) {
        Profile p = profile(userId);
        return new Me(profileView(p, userId), tokens.balance(userId));
    }

    public ProfileView profileByHandle(String handle, String viewerId) {
        return profileView(profiles.findByHandle(handle).orElseThrow(() -> ApiException.notFound("No bettor with that username.")), viewerId);
    }

    @Transactional
    public ProfileView follow(String viewerId, String handle, boolean on) {
        profile(viewerId);
        Profile target = profiles.findByHandle(handle).orElseThrow(() -> ApiException.notFound("No bettor with that username."));
        if (target.getUserId().equals(viewerId)) throw ApiException.refused("You can't follow yourself.");
        Follow.Key key = new Follow.Key(viewerId, target.getUserId());
        if (on && !follows.existsById(key)) follows.save(new Follow(viewerId, target.getUserId(), clock.instant()));
        if (!on) follows.deleteById(key);
        return profileView(target, viewerId);
    }

    private ProfileView profileView(Profile p, String viewerId) {
        List<Bet> free = bets.findByOwnerIdAndKindAndResultIsNotNull(p.getUserId(), BetKind.FREE);
        long wins = free.stream().filter(Bet::isWon).count();
        return new ProfileView(p.getHandle(), p.getName(), p.getBio(), p.getAvatar(), p.getJoinedAt(), isPro(p.getUserId()),
                follows.countByIdFollowedId(p.getUserId()), follows.countByIdFollowerId(p.getUserId()),
                viewerId != null && follows.existsById(new Follow.Key(viewerId, p.getUserId())), wins, free.size() - wins);
    }

    private Profile profile(String userId) {
        return profiles.findById(userId).orElseThrow(() -> ApiException.notFound("Create your community profile first."));
    }

    private boolean isPro(String userId) {
        return challenges.findById(userId).map(c -> c.getPassedAt() != null).orElse(false);
    }

    // ---------------------------------------------------------------- Bets

    /** Posts a free bet: before kick-off, once per match and market, 3 a day. */
    @Transactional
    public BetView postFree(String userId, Selection s) {
        profile(userId);
        Instant now = clock.instant();
        if (!s.kickoff().isAfter(now)) throw ApiException.refused("This match has started: pick one that hasn't.");
        if (bets.existsByOwnerIdAndKindAndMatchIdAndMarket(userId, BetKind.FREE, s.matchId(), s.market())) {
            throw ApiException.refused("You already posted this bet.");
        }
        Instant dayStart = now.atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant();
        if (bets.countByOwnerIdAndKindAndCreatedAtAfter(userId, BetKind.FREE, dayStart) >= MAX_FREE_PER_DAY) {
            throw ApiException.refused("You can post up to 3 free bets a day.");
        }
        Bet b = bets.save(new Bet(userId, BetKind.FREE, null, s, 0, now));
        return views(List.of(b), userId).getFirst();
    }

    /** Puts a bet up for sale, priced by its odds. Only pro bettors can sell. */
    @Transactional
    public BetView sell(String userId, Selection s) {
        profile(userId);
        if (!isPro(userId)) throw ApiException.refused("Only those who pass the challenge can sell bets in the community for tokens.");
        Instant now = clock.instant();
        if (!s.kickoff().isAfter(now)) throw ApiException.refused("This match has started: pick one that hasn't.");
        if (bets.existsByOwnerIdAndKindAndMatchIdAndMarket(userId, BetKind.SALE, s.matchId(), s.market())) {
            throw ApiException.refused("This bet is already for sale.");
        }
        Bet b = bets.save(new Bet(userId, BetKind.SALE, null, s, price(s.odds()), now));
        return views(List.of(b), userId).getFirst();
    }

    /** The token price of a bet for sale, by its odds, as the app's listingPrice. */
    public static int price(double odds) {
        return odds >= 2.2 ? 3 : (odds >= 1.8 ? 2 : 1);
    }

    /** Spends the bet's tokens to see its pick; the seller gets them. */
    @Transactional
    public BetView buy(String userId, Long betId) {
        profile(userId);
        Bet b = bets.findById(betId).filter(x -> x.getKind() == BetKind.SALE).orElseThrow(() -> ApiException.notFound("No bet for sale with that id."));
        if (b.getOwnerId().equals(userId)) throw ApiException.refused("This is your own bet.");
        Purchase.Key key = new Purchase.Key(userId, betId);
        if (!purchases.existsById(key)) {
            if (!b.getKickoff().isAfter(clock.instant())) throw ApiException.refused("This match has started: the bet is no longer for sale.");
            tokens.debit(userId, b.getPrice(), "BUY_BET", userId + ":" + betId);
            tokens.credit(b.getOwnerId(), b.getPrice(), "SALE", userId + ":" + betId);
            purchases.save(new Purchase(userId, betId, b.getPrice(), clock.instant()));
        }
        return views(List.of(b), userId).getFirst();
    }

    /** The bets for sale whose matches are still to start, the most bought first. */
    public List<BetView> forSale(String viewerId, int limit) {
        List<BetView> all = views(bets.findByKindAndKickoffAfterOrderByKickoffAsc(BetKind.SALE, clock.instant()), viewerId);
        return all.stream().sorted(Comparator.comparingLong(BetView::buyers).reversed()).limit(limit).toList();
    }

    /** Free bets on matches from the last couple of hours on, those from bettors the viewer follows first. */
    public List<BetView> free(String viewerId, int limit) {
        Set<String> followed = viewerId == null ? Set.of() : follows.findAll().stream()
                .filter(f -> f.getId().followerId().equals(viewerId)).map(f -> f.getId().followedId()).collect(Collectors.toSet());
        List<Bet> list = bets.findByKindAndKickoffAfterOrderByKickoffAsc(BetKind.FREE, clock.instant().minus(Duration.ofHours(2)));
        List<Bet> sorted = list.stream()
                .sorted(Comparator.comparing((Bet b) -> !followed.contains(b.getOwnerId())).thenComparing(Bet::getKickoff))
                .limit(limit).toList();
        return views(sorted, viewerId);
    }

    public List<BetView> views(List<Bet> list, String viewerId) {
        Map<String, Bettor> bettors = new HashMap<>();
        Set<Long> bought = viewerId == null || list.isEmpty() ? Set.of()
                : purchases.findByIdBuyerIdAndIdBetIdIn(viewerId, list.stream().map(Bet::getId).toList()).stream()
                        .map(p -> p.getId().betId()).collect(Collectors.toSet());
        return list.stream().map(b -> {
            Bettor who = bettors.computeIfAbsent(b.getOwnerId(), this::bettor);
            boolean mine = b.getOwnerId().equals(viewerId);
            boolean has = bought.contains(b.getId());
            boolean open = b.getKind() != BetKind.SALE || mine || has;
            return new BetView(b.getId(), b.getKind(), who, b.getMatchId(), b.getLeague(), b.getHome(), b.getAway(), b.getKickoff(),
                    b.getMarket(), open ? b.getPick() : null, open ? b.getLine() : null, open ? b.getOdds() : null, b.getPrice(),
                    b.getKind() == BetKind.SALE ? purchases.countByIdBetId(b.getId()) : 0, mine, has, b.getResult());
        }).toList();
    }

    private Bettor bettor(String userId) {
        Profile p = profile(userId);
        List<Bet> settled = new java.util.ArrayList<>(bets.findByOwnerIdAndKindAndResultIsNotNull(userId, BetKind.SALE));
        settled.addAll(bets.findByOwnerIdAndKindAndResultIsNotNull(userId, BetKind.CHALLENGE));
        long wins = settled.stream().filter(Bet::isWon).count();
        return new Bettor(p.getHandle(), p.getName(), p.getAvatar(), isPro(userId), wins, settled.size() - wins,
                follows.countByIdFollowedId(userId));
    }
}
