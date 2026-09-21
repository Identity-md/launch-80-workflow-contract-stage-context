# Splitwise contracts

An ownerless SPLT tip pool for Sepolia. This contribution contains the token and
application implementation, Foundry tests, ABI exports, and integration guidance.
The manifest, independent reviews, source publication, attestation, admission,
deployment, and frontend are separate workflow contributions. No transactions
have been broadcast, and this repository does not contain a deployed address.

## Contracts and configuration

| Contract | Source | Constructor | Purpose |
| --- | --- | --- | --- |
| Splitwise | `src/Splitwise.sol` | `()`; nonpayable | Splitwise / SPLT, 18 decimals, exactly 1,000,000,000 tokens (`10^27` base units) minted to the constructor caller |
| TipSplitter | `src/TipSplitter.sol` | `(address token_)`; nonpayable | One permanent pool with 1–10 members; manifest argument must be `$token` |

SPLT has standard transfers, approvals, and delegated transfers. There is no mint,
burn, owner, tax, pause, upgrade, or administrative method. Zero-address recipients
and spenders are rejected. Finite allowances are reduced (with Approval events);
maximum uint256 allowance is treated as unlimited. The application constructor
checks that the token is a deployed contract. It does not authenticate its code:
the manifest reviewer and deployment service must ensure it is this SPLT token.

TipSplitter has no owner, fee, upgrade path, membership editor, or recovery method.
Its only external interactions are with its immutable token. No proxy, delegated
execution, or self-destruction is used. Neither contract accepts normal ETH
transfers, and neither constructor is payable.

## Pool lifecycle and accounting

1. A caller approves TipSplitter to spend its SPLT, then calls
   `registerMembers(address[] initialMembers, uint256 amount)` with a positive
   first tip. The 1–10 addresses must be unique, nonzero, and different from
   TipSplitter itself. The caller can include or exclude itself. Failed transfers
   roll back the entire registration, so they do not reserve a pool.
2. The first successful registration fixes the list forever. Anyone can then
   approve and call `deposit(uint256 amount)` with a positive tip. There is no
   withdrawal or refund for depositors. All amounts use SPLT base units, not
   whole-token units.
3. A member calls `claim()` to transfer its entire available share to itself.
   Nonmembers cannot claim, and no caller can redirect another member's payout.
   Claims with nothing due revert. Deposits and claims are allowed immediately,
   in the same block, and at any future time; there are no rounds or deadlines.

For `n` members and lifetime credited deposits `D`, every member has earned
`floor(D / n)`. Its claimable amount is that entitlement minus its prior claims.
Claims never change another member's entitlement. Remainders accumulate across
tips; they are not repeatedly discarded. For example, with three members, a tip
of two base units pays nobody yet; another two makes one unit available per
member; another two brings each member's lifetime entitlement to two.

At most `n - 1` base units remain as undistributable rounding dust after all
members claim. If tipping permanently stops at such a remainder, that dust stays
in the contract. With credited tips only:

```text
pool balance + totalClaimed = totalDeposited
pool balance = sum(claimable(member)) + (totalDeposited % memberCount)
```

**Use the deposit functions.** A plain ERC-20 transfer to TipSplitter does not
create claim rights. Such transfers remain uncredited and cannot be recovered;
they add a surplus to the equations above. Other tokens or forced ETH likewise
have no recovery path. The frontend must never implement tipping as a plain
`transfer` call. Direct transfers cannot register a member list or prevent a
later valid registration.

The application emits `MembersRegistered`, `TipDeposited`, and `ShareClaimed`
for changes to membership and accounting. Token movements and allowances emit
ERC-20 events. Reverted calls do not persist state changes or logs. A shared
reentrancy guard protects all mutating application calls. Claims record effects
before transferring tokens; failed token transfers roll back claim rights.
Deposits also require the exact requested increase in the pool's token balance.

## Assumptions and operational responsibilities

- **Registration is permissionless and can be front-run.** Anyone can spend as
  little as one SPLT base unit to choose the list first. There is deliberately no
  reservation for the deployer or any intended group. A coordinator should
  confirm the actual `getMembers()` result before inviting tips. A different
  desired list requires another deployment, not a membership reset.
- Members must be able to submit `claim()` from their own address. Contract
  members need an execution method; lost keys and contracts unable to call
  cannot be rescued. An inactive member does not prevent other members claiming.
- The only supported production asset is the delivered, exact-transfer SPLT.
  Rebasing, fee tokens, missing return values, or malicious tokens are not
  supported. A malicious token can lie about balances or successful payouts;
  the guard does not make arbitrary assets trustworthy. Mock-token tests prove
  callback and failure handling, not compatibility with arbitrary ERC-20s.
- The UI should display the permanent member list, token/address/network,
  approval amount, claimable amounts, and base-unit rounding before signatures.
  Use exact approvals where practical and account for ERC-20 allowance changes
  being separately ordered transactions. Poll or refresh after receipts and
  reconcile events against current state after reorganizations.
- Reviewers must independently examine custody, first-registration control,
  accounting, constructor linkage, and final manifest arguments before release.
  These local tests are not an independent security audit. The separate final
  review also covers the eventual website and deployment configuration.

## Launch handoff

Target chain: Sepolia, chain ID **11155111**. The manifest contribution should
identify `Splitwise` as the launch token and exactly one application,
`TipSplitter`, using `src/TipSplitter.sol:TipSplitter` with the single address
constructor argument `$token`. Both identifiers are ASCII, unique, and shorter
than 32 characters. The token has no constructor arguments. Deploy the token
before TipSplitter. There are no constructor owner parameters or privileged
wallets. ProjectFactory must receive the entire token supply at token creation;
TipSplitter's constructor makes no initialization calls or token movements.

For the supplied native-ETH pool configuration: token pair zero address,
fee `3000`, tick spacing `60`, initial sqrtPriceX96 string
`"79228162514264337593543950336"`, and no hook. These parameters describe the
launch pool, not a promised market valuation; the factory seeds launch-token
liquidity only. The final manifest author records the canonical launch fields.
No `launch.json` is generated by this source contribution.

Services own policy resolution, signed artifact linkage, GitHub publication,
source attestation, admission, actual factory/address selection, deployment,
and runtime deployment data. Concrete source, constructor, authorization, or
policy conflicts must be raised in the independent manifest review. Review and
service outcomes are not prerequisites to compiling these contracts.

The later website contribution uses React, Vite, TypeScript, RainbowKit, wagmi,
and viem under `web/`, exports a relative-base static build to `dist/`, and loads
addresses and ABIs from `dist/imd-deployment.json` at runtime before IPFS
publication. It should offer register-and-tip, tip, list/claimable, and claim
flows described in [the ABI integration notes](docs/ABI.md). Production contract
addresses and the intended member list are still deployment/user choices.

## Local verification

Use Foundry and the standard Solidity **0.8.26** toolchain. The compiler is pinned
by version (not an executable path), targets Cancun, uses optimizer runs 200,
and emits no bytecode metadata hash or CBOR trailer. FFI is disabled and Solidity
tests have no filesystem permissions. All Solidity dependencies are ordinary
vendored files under `lib/forge-std/` (v1.9.7, test use only); no package download
or submodule is required. An offline runner must provide Foundry and its cached
0.8.26 compiler as its toolchain.

```sh
forge build --offline
forge test --offline
forge fmt --check
python3 scripts/export-abis.py
```

The last command rebuilds offline and refreshes the checked-in JSON ABI arrays.
In a sandbox with a read-only home directory, create a writable cache directory
and set `XDG_DATA_HOME` to it before using Foundry; the compiler must be present
there before disconnecting the network. The project configuration does not
override the verifier's compiler cache location.

Tests cover ERC-20 behavior, factory deployment and supply preservation, runtime
opcode/size limits, nonpayable constructors, registration bounds and atomicity,
invalid/duplicate actions, arbitrary depositors, unlimited claim timing,
rounding and claim ordering, unsuccessful transfers, and reentry into every
mutating application entry point from incoming and outgoing token calls.
Fuzz tests exercise transfers and distribution across 1–10 members. A stateful
invariant suite checks equal entitlements, solvency, direct-transfer isolation,
and supply conservation across deposits, claims, and donations, then proves
that every outstanding member claim can be drained. Fuzz runs are set to 512;
invariants use 128 runs of 64 actions with unexpected reverts treated as failures.
