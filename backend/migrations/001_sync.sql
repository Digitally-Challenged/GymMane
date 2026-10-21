CREATE TABLE sync_accounts (
  account_id uuid PRIMARY KEY,
  cursor bigint NOT NULL DEFAULT 0 CHECK (cursor >= 0),
  disabled boolean NOT NULL DEFAULT false,
  tokens_valid_after bigint NOT NULL DEFAULT 0
);
CREATE TABLE sync_entities (
  account_id uuid NOT NULL REFERENCES sync_accounts,
  entity_type text NOT NULL CHECK (entity_type IN ('workout', 'routine')),
  entity_id uuid NOT NULL,
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  deleted boolean NOT NULL,
  payload jsonb,
  cursor bigint NOT NULL,
  PRIMARY KEY (account_id, entity_type, entity_id),
  CHECK ((deleted AND payload IS NULL) OR (NOT deleted AND jsonb_typeof(payload) = 'object'))
);
CREATE TABLE sync_changes (
  account_id uuid NOT NULL REFERENCES sync_accounts,
  cursor bigint NOT NULL,
  entity jsonb NOT NULL,
  PRIMARY KEY (account_id, cursor)
);
CREATE TABLE sync_receipts (
  account_id uuid NOT NULL REFERENCES sync_accounts,
  operation_id uuid NOT NULL,
  operation jsonb NOT NULL,
  result jsonb NOT NULL,
  PRIMARY KEY (account_id, operation_id)
);
-- No client grants: only the trusted backend database role accesses these tables.
REVOKE ALL ON sync_accounts, sync_entities, sync_changes, sync_receipts FROM PUBLIC;
