-- Each account's own data (bets, bankroll, parlays, Matchboard, settings),
-- kept as the app's snapshot so a phone that signs in gets it back. version
-- goes up by one on every save; a phone saves only on top of the version it
-- last saw, so two phones can't overwrite each other unnoticed.
create table user_data (
    user_id    varchar(128) primary key,
    version    bigint not null,
    data       text   not null,
    updated_at timestamp with time zone not null
);
