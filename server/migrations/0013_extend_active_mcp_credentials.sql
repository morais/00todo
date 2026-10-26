-- Preserve existing MCP connections when increasing their lifetime from
-- 30 to 365 days. Never revive an expired or revoked credential, and never
-- shorten a credential that already has a later expiry.
UPDATE credentials
SET expires_at = strftime('%Y-%m-%dT%H:%M:%fZ', created_at, '+365 days')
WHERE kind = 'mcp'
  AND revoked_at IS NULL
  AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
  AND expires_at < strftime('%Y-%m-%dT%H:%M:%fZ', created_at, '+365 days');
