---
name: bron-address-book
description: |
  Manage saved addresses (the address book) on the Bron treasury platform via the
  bron CLI. Use when the user wants to list saved addresses, save a new one, delete
  one, or look up a record id to use as `toAddressBookRecordId` in a withdrawal.
  State-changing actions (create, delete) require human-in-the-loop confirmation.
license: MIT
compatibility: |
  Requires bron-cli >= 0.3.6 in PATH and an active profile with API key
  authentication.
allowed-tools: Bash(bron address-book:*) Bash(bron --schema:*) Read
metadata:
  vendor: bronlabs
  version: "0.1.0"
  bron-cli-min: "0.3.6"
---

# Bron address book

Why use this skill: a workspace's address book is the trusted recipient list. Bron validates withdrawals against it — sending to `params.toAddressBookRecordId=<id>` is safer and more readable than passing a raw `params.toAddress`.

The book is `(workspace, networkId, address)`-keyed; one record per (network, address) tuple, scoped to the workspace.

## List addresses

```bash
# Every record on every network in the workspace.
bron address-book list

# Filter by network.
bron address-book list --networkIds ETH,TRX

# Project for human review.
bron address-book list --output table \
  --columns recordId,name,networkId,address,recordType,status,memo

# Find a record id for a known recipient.
bron address-book list --networkIds ETH --output jsonl \
  | jq -r 'select(.name == "Alice") | .recordId'
```

Useful filters: `--networkIds`, `--recordType` (`address` for raw on-chain, `tag` for Bron internal routing).

## Create an entry

State-changing — surface to the user and wait for explicit OK before invoking.

```bash
bron address-book create \
  --name      "Alice (vendor)" \
  --address   "0xabcd…" \
  --networkId ETH \
  --memo      "primary payout address"
```

Optional: `--recordType tag` (with `--address <bronTag>` instead of an on-chain address) for routing within Bron.

After creation, retrieve the new `recordId` from the response — this is what you'll pass as `params.toAddressBookRecordId` in subsequent withdrawals (see the `bron-tx-send` skill).

## Delete an entry

State-changing and irreversible. Surface, confirm, run.

```bash
bron address-book delete <recordId>
```

If the record is referenced by any pending transaction, deletion fails with a `400` and a `code:` indicating the conflict; resolve those first.

## Resolving a recipient before sending

Standard pattern — the user gives you a name or address, you confirm and turn it into a `recordId`:

```bash
# User: "send 100 USDC to Alice on Ethereum"
# Step 1: find Alice.
RECORD_ID=$(bron address-book list --networkIds ETH --output jsonl \
              | jq -r 'select(.name == "Alice") | .recordId')

# Step 2: if not found, ask the user to add her or supply a raw address.
[ -z "$RECORD_ID" ] && echo "Alice not in address book — please add or supply address" && exit 1

# Step 3: use the recordId in the withdrawal (skill: bron-tx-send).
bron tx withdrawal \
  --externalId "task-$(date +%s)" \
  --accountId <a> \
  --params.amount=100 \
  --params.assetId=<usdc-on-eth> \
  --params.networkId=ETH \
  --params.toAddressBookRecordId="$RECORD_ID"
```

Multi-match ambiguity: if `--name` matches more than one record, jq picks the first. Surface all matches to the user and let them pick:

```bash
bron address-book list --networkIds ETH --output jsonl \
  | jq -r 'select(.name == "Alice")'
```

## Discovery

```bash
bron address-book --help
bron address-book list --schema      # full request + response schema
```

## Hard guardrails

- Never `create` without showing the user the exact (name, address, networkId) tuple and waiting for OK. A typo in the address creates a permanent on-chain risk.
- Never `delete` silently — confirm by surfacing the record summary and waiting for OK.
- For `recordType=address`, validate the address looks plausible for the network (EVM checksum case for `ETH`, etc.) before submitting. Bron itself validates server-side, but a pre-check saves a round trip and helps catch human error.
