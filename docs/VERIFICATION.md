# Local verification record

Checked with Forge 1.5.1 and standard Solc 0.8.26. These are contributor-run
checks, not an independent review or deployment attestation.

| Check | Result |
| --- | --- |
| `forge build --offline` | Passed |
| `forge test --offline` | 45 passed, 0 failed, 0 skipped |
| `forge fmt --check` | Passed |
| Supplied `Token.protected.t.sol` | 6 passed, 0 failed, 0 skipped |
| Supplied `Project.protected.t.sol` | 2 passed, 0 failed, 0 skipped |
| Exported ABIs compared to compiler artifacts | Exact matches for both contracts |

The project suite includes two fuzz tests with 512 runs each and a stateful
invariant test with 128 runs of 64 actions (8,192 calls, zero unexpected reverts).
The invariant includes final draining of all outstanding claims.

The supplied protected suites were run unchanged using actual compiled creation
code, a local simulated CREATE2 factory, chain ID 11155111, expected supply
`10^27`, 18 decimals, and one TipSplitter whose constructor was encoded with the
predicted token address. No live RPC, deployed production address, signed
manifest, or wallet was used. Those read-only input suites are not deliverables.

Compiled deployed runtime sizes with the committed configuration:

| Contract | Bytes |
| --- | --- |
| Splitwise | 1,385 |
| TipSplitter | 2,842 |

Both constructors are nonpayable. Splitwise takes no arguments; TipSplitter
takes exactly one address. Runtime opcode scans passed for both contracts.

The local sandbox used `XDG_DATA_HOME=/tmp/splitwise-toolchain` for its standard
compiler cache because the user home directory is read-only. Solidity imports
resolve exclusively from the repository's source and vendored forge-std files.
The offline verification environment supplies the Foundry/Solc toolchain.
