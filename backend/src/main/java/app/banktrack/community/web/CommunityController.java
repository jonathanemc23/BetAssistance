package app.banktrack.community.web;

import app.banktrack.community.domain.Selection;
import app.banktrack.community.service.ChallengeService;
import app.banktrack.community.service.CommunityService;
import app.banktrack.community.service.TokenService;
import app.banktrack.community.service.Views.BetView;
import app.banktrack.community.service.Views.ChallengeView;
import app.banktrack.community.service.Views.Me;
import app.banktrack.community.service.Views.ProfileView;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.security.Principal;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** The community API the app calls. The signed-in user is the Principal. */
@RestController
@RequestMapping("/api")
public class CommunityController {
    public record NewProfile(@NotBlank String handle, @Size(max = 80) String name, @Size(max = 120) String bio, @Size(max = 200) String avatar) {}

    public record ProfileChange(@Size(max = 80) String name, @Size(max = 120) String bio, @Size(max = 200) String avatar) {}

    private final CommunityService community;
    private final ChallengeService challenge;
    private final TokenService tokens;

    public CommunityController(CommunityService community, ChallengeService challenge, TokenService tokens) {
        this.community = community;
        this.challenge = challenge;
        this.tokens = tokens;
    }

    // Profiles and follows

    @GetMapping("/me")
    public Me me(Principal user) {
        return community.me(user.getName());
    }

    @PostMapping("/profiles")
    @ResponseStatus(HttpStatus.CREATED)
    public Me createProfile(Principal user, @Valid @RequestBody NewProfile p) {
        return community.createProfile(user.getName(), p.handle(), p.name(), p.bio(), p.avatar());
    }

    @PatchMapping("/me")
    public Me updateProfile(Principal user, @Valid @RequestBody ProfileChange p) {
        return community.updateProfile(user.getName(), p.name(), p.bio(), p.avatar());
    }

    @GetMapping("/profiles/{handle}")
    public ProfileView profile(Principal user, @PathVariable String handle) {
        return community.profileByHandle(handle, user.getName());
    }

    @PutMapping("/profiles/{handle}/follow")
    public ProfileView follow(Principal user, @PathVariable String handle) {
        return community.follow(user.getName(), handle, true);
    }

    @DeleteMapping("/profiles/{handle}/follow")
    public ProfileView unfollow(Principal user, @PathVariable String handle) {
        return community.follow(user.getName(), handle, false);
    }

    // The community page: hottest bets to buy, then free bets

    @GetMapping("/feed/hot")
    public List<BetView> hot(Principal user, @RequestParam(defaultValue = "3") int limit) {
        return community.forSale(user.getName(), Math.min(limit, 50));
    }

    @GetMapping("/feed/sale")
    public List<BetView> forSale(Principal user) {
        return community.forSale(user.getName(), 100);
    }

    @GetMapping("/feed/free")
    public List<BetView> free(Principal user, @RequestParam(defaultValue = "30") int limit) {
        return community.free(user.getName(), Math.min(limit, 100));
    }

    @PostMapping("/bets/free")
    @ResponseStatus(HttpStatus.CREATED)
    public BetView postFree(Principal user, @Valid @RequestBody Selection s) {
        return community.postFree(user.getName(), s);
    }

    @PostMapping("/bets/sale")
    @ResponseStatus(HttpStatus.CREATED)
    public BetView sell(Principal user, @Valid @RequestBody Selection s) {
        return community.sell(user.getName(), s);
    }

    @PostMapping("/bets/{id}/buy")
    public BetView buy(Principal user, @PathVariable Long id) {
        return community.buy(user.getName(), id);
    }

    // The pro bettor challenge

    @GetMapping("/challenge")
    public ChallengeView challenge(Principal user) {
        return challenge.get(user.getName());
    }

    @PostMapping("/challenge/accept")
    public ChallengeView accept(Principal user) {
        return challenge.accept(user.getName());
    }

    @PostMapping("/challenge/bets")
    public ChallengeView place(Principal user, @Valid @RequestBody Selection s) {
        return challenge.place(user.getName(), s);
    }

    @PostMapping("/challenge/restart")
    public ChallengeView restart(Principal user) {
        return challenge.restart(user.getName());
    }

    // Tokens

    @GetMapping("/tokens")
    public Map<String, Integer> tokens(Principal user) {
        return Map.of("tokens", tokens.balance(user.getName()));
    }
}
