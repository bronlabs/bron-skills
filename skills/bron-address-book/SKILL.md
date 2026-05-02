---
name: bron-address-book
description: |
  Manage saved addresses (the address book) on the Bron treasury platform.
  Use when the user wants to list saved addresses, save a new one, delete
  one, or look up a record id to use as `toAddressBookRecordId` in a withdrawal.
  State-changing actions (create, delete) require human-in-the-loop confirmation.
license: MIT
allowed-tools: |
  Bash(bron address-book:*) Bash(bron --schema:*) Read
  mcp__bron__bron_address_book_list mcp__bron__bron_address_book_get
  mcp__bron__bron_address_book_create mcp__bron__bron_address_book_delete
metadata:
  vendor: bronlabs
  version: "0.3.0"
  bron-cli-min: "0.3.7"
---

# Bron address book

The address book is the workspace's trusted recipient list, keyed by `(workspaceId, networkId, address)`. Bron validates withdrawals against it — passing `toAddressBookRecordId` is safer and more readable than a raw `toAddress`. Two `recordType`s: `address` (raw on-chain) and `tag` (Bron internal routing).

Two surfaces drive the same operations: MCP (`mcp__bron__bron_address_book_*`) and CLI (`bron address-book …`). Pick one and stay there. See the `bron-tx-send` skill for the full surface-picker.

## List

```text
mcp__bron__bron_address_book_list { networkIds: "ETH,TRX" }
```

```bash
bron address-book list --networkIds ETH,TRX --output jsonl \
  --columns recordId,name,networkId,address,recordType,status,memo
```

Filters and full body: `bron address-book list --help` / `bron address-book list --schema`.

## Create — state-changing, confirm first

```text
mcp__bron__bron_address_book_create {
  name: "Alice (vendor)", address: "0xabcd…", networkId: "ETH",
  memo: "primary payout address"
}
```

CLI: `bron address-book create --name "..." --address "..." --networkId ETH --memo "..."`. Pass `--recordType tag` with a Bron tag in `--address` for internal routing.

The new `recordId` comes back in the response — pass it as `params.toAddressBookRecordId` in subsequent withdrawals (see `bron-tx-send`).

## Delete — state-changing, irreversible, confirm first

```text
mcp__bron__bron_address_book_delete { recordId: "<id>" }
```

CLI: `bron address-book delete <recordId>`. If a pending transaction references the record, deletion fails with a 400 — resolve those first.

## Resolving a recipient before sending

Standard pattern: user gives a name, you turn it into a `recordId`.

```bash
RECORD_ID=$(bron address-book list --networkIds ETH --output jsonl \
              | jq -r 'select(.name == "Alice") | .recordId')
[ -z "$RECORD_ID" ] && echo "Alice not in address book — add her or supply a raw address" && exit 1
```

If the name matches multiple records, surface them all to the user and let them pick — don't blindly take the first.

## Hard rules

- Never `create` without showing the user the exact `(name, address, networkId)` tuple and waiting for explicit OK. A typo creates a permanent on-chain risk.
- Never `delete` without confirming the record summary first.
- For `recordType=address`, sanity-check the address looks right for the network (EVM checksum case for `ETH`, base58 for `TRX`, …) before submitting — server validates, but a pre-check saves a round trip.

## Discovery

```bash
bron address-book --help
bron address-book list --schema
```
