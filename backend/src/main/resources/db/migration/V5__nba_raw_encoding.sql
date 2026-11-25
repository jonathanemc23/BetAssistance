-- NBA raw payloads are stored compressed to fit a free database (500 MB):
-- body holds base64 of gzip when body_encoding = 'gzip+base64', the text itself
-- when 'identity'. sha256 is always of the uncompressed text.
alter table nba.raw_payloads add column body_encoding varchar(20) not null default 'identity';
