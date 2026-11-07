-- Native app credentials have only been issued after verified Apple native
-- sign-in. Web OAuth/dashboard sign-ins and review codes are not evidence.
-- Include retained expired/revoked credentials: they still prove sign-in.
-- Swept credentials cannot be reconstructed; leave those accounts unknown.
ALTER TABLE tenants ADD COLUMN native_first_signed_in_at TEXT;

UPDATE tenants
SET native_first_signed_in_at = (
  SELECT created_at FROM credentials
  WHERE credentials.tenant_id = tenants.id AND kind = 'app'
    AND julianday(created_at) IS NOT NULL
  ORDER BY julianday(created_at) ASC LIMIT 1
)
WHERE EXISTS (
  SELECT 1 FROM credentials
  WHERE credentials.tenant_id = tenants.id AND kind = 'app'
    AND julianday(created_at) IS NOT NULL
);
