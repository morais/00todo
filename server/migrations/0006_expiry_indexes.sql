-- Let the expired-auth sweep seek rows instead of scanning each table.
CREATE INDEX oauth_flows_expires ON oauth_flows(expires_at);
CREATE INDEX oauth_codes_expires ON oauth_codes(expires_at);
CREATE INDEX credentials_expires ON credentials(expires_at);
