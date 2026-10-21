import type { Pool, PoolClient } from "pg";
import {
  HttpError,
  type Entity,
  type Operation,
  type Result,
} from "./protocol.js";

export class SyncStore {
  constructor(private pool: Pool) {}
  async push(
    accountId: string,
    operations: Operation[],
  ): Promise<{ results: Result[] }> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        "INSERT INTO sync_accounts(account_id) VALUES ($1) ON CONFLICT DO NOTHING",
        [accountId],
      );
      const account = await client.query(
        "SELECT disabled FROM sync_accounts WHERE account_id=$1 FOR UPDATE",
        [accountId],
      );
      if (account.rows[0].disabled)
        throw new HttpError(403, "Account disabled");
      const results: Result[] = [];
      for (const operation of operations)
        results.push(await this.apply(client, accountId, operation));
      await client.query("COMMIT");
      return { results };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
  private async apply(
    client: PoolClient,
    accountId: string,
    op: Operation,
  ): Promise<Result> {
    const receipt = await client.query(
      "SELECT result, operation = $3::jsonb AS same FROM sync_receipts WHERE account_id=$1 AND operation_id=$2",
      [accountId, op.operationId, JSON.stringify(op)],
    );
    if (receipt.rowCount) {
      if (!receipt.rows[0].same)
        throw new HttpError(409, "Operation ID reused with different content");
      return receipt.rows[0].result;
    }
    const existing = await client.query(
      'SELECT entity_type AS "entityType", entity_id AS "entityId", revision, deleted, payload, cursor FROM sync_entities WHERE account_id=$1 AND entity_type=$2 AND entity_id=$3',
      [accountId, op.entityType, op.entityId],
    );
    const row = existing.rows[0];
    let entity: Entity;
    let status: Result["status"];
    if (row && Number(row.revision) !== op.baseRevision) {
      entity = { ...row, revision: Number(row.revision) };
      status = "conflict";
    } else {
      // v1 cannot represent a nonexistent current entity in a conflict response.
      if (!row && op.baseRevision !== 0)
        throw new HttpError(400, "Missing entity requires baseRevision zero");
      if (op.baseRevision === Number.MAX_SAFE_INTEGER)
        throw new HttpError(409, "Revision exhausted");
      const counter = await client.query(
        "UPDATE sync_accounts SET cursor=cursor+1 WHERE account_id=$1 RETURNING cursor",
        [accountId],
      );
      entity = {
        entityType: op.entityType,
        entityId: op.entityId,
        revision: op.baseRevision + 1,
        deleted: op.deleted,
        payload: op.payload,
        cursor: counter.rows[0].cursor,
      };
      await client.query(
        "INSERT INTO sync_entities(account_id,entity_type,entity_id,revision,deleted,payload,cursor) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(account_id,entity_type,entity_id) DO UPDATE SET revision=EXCLUDED.revision,deleted=EXCLUDED.deleted,payload=EXCLUDED.payload,cursor=EXCLUDED.cursor",
        [
          accountId,
          entity.entityType,
          entity.entityId,
          entity.revision,
          entity.deleted,
          entity.payload,
          entity.cursor,
        ],
      );
      await client.query(
        "INSERT INTO sync_changes(account_id,cursor,entity) VALUES($1,$2,$3)",
        [accountId, entity.cursor, entity],
      );
      status = "accepted";
    }
    const result: Result = { operationId: op.operationId, status, entity };
    await client.query(
      "INSERT INTO sync_receipts(account_id,operation_id,operation,result) VALUES($1,$2,$3,$4)",
      [accountId, op.operationId, op, result],
    );
    return result;
  }
  async pull(accountId: string, cursor: string, limit: number) {
    const result = await this.pool.query(
      "SELECT entity FROM sync_changes WHERE account_id=$1 AND cursor>$2 ORDER BY cursor LIMIT $3",
      [accountId, cursor, limit + 1],
    );
    const entities: Entity[] = result.rows
      .slice(0, limit)
      .map((row) => row.entity);
    return {
      entities,
      nextCursor: entities.at(-1)?.cursor ?? cursor,
      hasMore: result.rows.length > limit,
    };
  }
}
