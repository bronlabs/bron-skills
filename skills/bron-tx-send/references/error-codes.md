# Error codes — cause and recovery

Reference material for `bron-tx-send`. Branch on these stable codes (`code:` field in the error envelope), not on the human message. The full list is on [Bron's developer docs](https://developer.bron.org/api-reference/errors); this file calls out the ones you'll meet most.

## Auth / permissions

| `code` | Cause | Recovery |
|---|---|---|
| `INVALID_KEY` | Public JWK not registered, or `kid` was revoked | Verify the key in Settings → API keys. Generate a fresh keypair and re-register if needed. |
| `KEY_REVOKED` | The active `kid` was revoked in the UI | Run `bron auth keygen --file <path>`, register the public JWK, update the active profile. |
| `WORKSPACE_NOT_FOUND` | The active profile's `workspace_id` doesn't match what the key was registered against | Run `bron config show` to verify; correct with `bron config set workspace=<id>` or `--workspace` override. |
| `INSUFFICIENT_PERMISSIONS` | Member behind the API key doesn't have permission for this action | Reduce scope of the request, or escalate to an account that has the permission. |

## Transaction body / validation

| `code` | Cause | Recovery |
|---|---|---|
| `INSUFFICIENT_BALANCE` | `params.amount` exceeds the account's available balance for this asset | Reduce the amount, or top up the account first. `bron balances list --accountId <a> --assetId <x>` to check. |
| `AMOUNT_BELOW_MIN` | `params.amount` is below the network's documented minimum | Raise the amount above `details.min`. |
| `AMOUNT_ABOVE_MAX` | Amount above a per-asset / per-network ceiling, or a user-configured policy limit | Reduce the amount, or split into multiple transactions. |
| `INVALID_ADDRESS` | `params.toAddress` doesn't pass network-format validation | Verify the destination format (checksum case for EVM, base58 for Tron, etc.). |
| `ADDRESS_NOT_WHITELISTED` | Destination not on the workspace allowlist | Add it to the address book first (`bron address-book create`), then submit using `--params.toAddressBookRecordId`. |
| `INVALID_NETWORK` | `params.networkId` doesn't match `params.assetId` | Cross-check with `bron assets get <assetId>` — `networkIds` lists the supported networks. |
| `MISSING_FIELD` | A required `params.<x>` field wasn't passed | Add the field. `bron tx <type> --schema` lists which fields are required. |

## Idempotency / state

| `code` | Cause | Recovery |
|---|---|---|
| `EXTERNAL_ID_CONFLICT` | The `--externalId` you sent was already used in this workspace **with a different body** | Either reuse the previous body (in which case you'll get the existing tx, no error), or generate a new `--externalId`. |
| `TRANSACTION_NOT_FOUND` | `bron tx approve <id>` etc. with an id that doesn't exist | Check `bron tx list` for the correct id. |
| `INVALID_STATE_TRANSITION` | Tried to approve/cancel/sign a tx not in the right state (e.g. cancelling a `completed` tx) | Get the current state with `bron tx get <id>`, choose an action valid for that state. |
| `SIGNING_REQUEST_REQUIRED` | Tried to broadcast before a signing request was created | `bron tx create-signing-request <id>` first. |

## Rate / availability

| `code` | Cause | Recovery |
|---|---|---|
| `RATE_LIMITED` | Per-key or per-workspace rate limit hit | Back off. Respect `details.retryAfter` if present. |
| `SERVICE_UNAVAILABLE` | Upstream subsystem (signer, blockchain RPC) is down | Retry with the same `--externalId` after a short delay. Idempotency makes retry safe. |

## How to recover gracefully

1. Read the `code:` line. Don't pattern-match the human message — translations and copy-tweaks evolve.
2. Read `details` — it carries machine-readable fields (`min`, `max`, `retryAfter`, `provided`) that tell you exactly what to fix.
3. For transient codes (`SERVICE_UNAVAILABLE`, `RATE_LIMITED`) — retry with the same `--externalId`. Bron de-duplicates safely.
4. For business-logic codes (`INSUFFICIENT_BALANCE`, `ADDRESS_NOT_WHITELISTED`) — surface the situation to the user with the `details`, don't silently fix-and-retry.
5. Quote the `trace:` value when escalating to the Bron team. It joins your call across every backend service log.
