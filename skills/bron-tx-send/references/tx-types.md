# Transaction types — body shape per `transactionType`

Reference material for `bron-tx-send`. Each `bron tx <type>` is a shortcut for `bron tx create --transactionType <type>` with `--params.<field>` flags exposing the type-specific body. Always run `bron tx <type> --help` or `bron tx <type> --schema` for the canonical, current shape — this file is a quick orientation, not the contract.

## `withdrawal`

Move funds out of a Bron account, on-chain or to another internal account.

Required:
- `accountId` — the source account.
- `params.amount` — decimal string. Decimals stay strings end-to-end; never coerce to float.
- `params.assetId` — asset identifier from `bron assets list`.
- `params.networkId` — network identifier (e.g. `ETH`, `TRX`, `BTC`).
- One of: `params.toAddress`, `params.toAddressBookRecordId`, `params.toAccountId`, `params.toBronTag`. Prefer `toAddressBookRecordId` for on-chain destinations.

Optional:
- `params.memo` — included in the on-chain transaction where the network supports it.
- `params.feeLevel` — `low` / `medium` / `high`. Defaults to a network-specific medium.
- `params.includeFee` — `true` to deduct network fee from the sent amount instead of the source account's gas budget.
- `description` — free-text string surfaced in audit logs and the UI.

## `allowance`

Grant an on-chain allowance (e.g. ERC-20 `approve`) so a contract or another address can spend a token on your behalf.

Required:
- `accountId`
- `params.assetId`, `params.networkId`
- `params.spender` — address to grant.
- `params.amount` — decimal string. Pass the literal "max" sentinel where the spec accepts it for unlimited approval.

## `bridge`

Cross-chain bridge transaction.

Required:
- `accountId`
- `params.fromAssetId`, `params.fromNetworkId`
- `params.toAssetId`, `params.toNetworkId`
- `params.amount`
- `params.toAddress` or `params.toAccountId`

Optional:
- `params.bridgeProvider` — pin a specific provider; otherwise Bron picks.
- `params.maxSlippage` — decimal string, e.g. `"0.01"` for 1%.

## `defi`

Generic DeFi interaction. Higher-risk path — use only when the user has explicitly chosen this and you've confirmed the destination contract.

Required:
- `accountId`
- `params.networkId`
- `params.contractAddress`
- `params.callData` — hex-encoded ABI call data.

## `defi-message`

Sign an arbitrary off-chain message (EIP-191 / EIP-712).

Required:
- `accountId`
- `params.networkId`
- `params.message` — UTF-8 string for EIP-191, structured object for EIP-712.

## `stake-delegation` / `stake-undelegation` / `stake-claim` / `stake-withdrawal`

Staking operations. Required fields vary per network — always run `bron tx stake-delegation --help` for the current shape. Common pattern: `accountId`, `params.assetId`, `params.networkId`, `params.validatorId`, `params.amount`.

## `address-creation` / `address-activation`

Per-account derived address operations. Most useful for receiving deposits on networks that need an explicit activation step (e.g. some Cosmos chains). Required:
- `accountId`
- `params.networkId`

## `fiat-in` / `fiat-out`

Off-ramp / on-ramp transactions through a configured fiat provider (Noah, etc.). Available only if the workspace has the relevant provider enabled.

Required (`fiat-out`):
- `accountId`
- `params.cryptoAssetId`, `params.fiatAssetId`
- `params.amount` (in the source currency)
- `params.fiatRecipientAccountId` — pre-registered fiat recipient.

`fiat-in` is symmetric (deposit fiat, receive crypto).

## `intents`

Submit a swap intent to the Bron Intents protocol — peer-to-peer swap with independent solvers and oracles. Body shape evolves; check `bron tx intents --help`.

## `deposit`

Internal record of an incoming deposit. Usually created automatically by the system when a deposit is detected on-chain; CLI can also create one manually for testing.

## Discovering what's actually available right now

The list above can drift from the live API. Always trust `bron tx --help` (lists every `transactionType` the CLI was generated for) and `bron tx <type> --schema` (machine-readable body) over this file.

```bash
# List every transaction-type subcommand.
bron tx --help

# Get the canonical body schema for one type.
bron tx withdrawal --schema | jq '.requestBody'
```

## Recipient field cheat-sheet

| Field | What it does | Use when |
|---|---|---|
| `params.toAddressBookRecordId` | Resolves to the saved on-chain address; Bron validates the destination is on the allowlist | You have a saved address-book entry. **Preferred.** |
| `params.toAccountId` | Internal transfer between two Bron accounts | Both source and destination are in the same workspace |
| `params.toBronTag` | Route to another Bron workspace by tag | The recipient is on Bron in a different workspace |
| `params.toAddress` | Raw on-chain address | You don't have a saved entry and the workspace allowlist either permits arbitrary addresses or includes this one |

Picking the wrong field type produces a `INVALID_ADDRESS` or `ADDRESS_NOT_WHITELISTED` 400 with a helpful `details` payload. Fix and retry with the same `--externalId`.
