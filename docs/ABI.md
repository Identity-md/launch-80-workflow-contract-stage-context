# ABI integration

The generated JSON arrays are [Splitwise.json](abi/Splitwise.json) and
[TipSplitter.json](abi/TipSplitter.json). Regenerate with
`python3 scripts/export-abis.py` after source changes. They include all functions,
constructors, events, and custom errors. The deployment service incorporates
these ABIs and actual addresses into the frontend's runtime deployment file;
the frontend must use that file instead of hard-coded addresses.

## Splitwise

| Method | Behavior |
| --- | --- |
| `name()`, `symbol()`, `decimals()`, `totalSupply()` | `Splitwise`, `SPLT`, 18, `10^27` |
| `balanceOf(address)` | Balance in base units |
| `allowance(address,address)` | Owner's spending allowance for the spender |
| `approve(address,uint256)` | Set spender's allowance; returns true; zero revokes |
| `transfer(address,uint256)` | Send the caller's tokens; returns true |
| `transferFrom(address,address,uint256)` | Spend allowance and send tokens; returns true |

Transfer and Approval are the standard indexed ERC-20 events. Custom errors:
`InvalidRecipient`, `InvalidSpender`, `InsufficientBalance`, and
`InsufficientAllowance`. Approval uses replacement semantics. The unlimited
uint256 allowance is not decremented. SPLT has no permit extension.

## TipSplitter

| Method | Behavior |
| --- | --- |
| `token()` | Immutable SPLT address |
| `MAX_MEMBERS()` | 10 |
| `memberCount()`, `getMembers()` | Current length and ordered permanent member list; initially empty |
| `isMember(address)` | Whether the address may claim |
| `registerMembers(address[],uint256)` | Register once and transfer a positive first tip from caller; approve first |
| `deposit(uint256)` | Transfer a positive tip from caller after registration; approve first |
| `claim()` | Member receives its entire currently available share; returns the amount |
| `claimable(address)` | Base units currently due; zero for nonmembers or an unregistered pool |
| `claimed(address)` | Lifetime amount paid to a member |
| `totalDeposited()`, `totalClaimed()` | Lifetime credited tips and payouts |

Writes send no native value. Suggested flow: validate chain/address configuration,
read memberCount and getMembers, read balance and allowance, approve if needed,
wait for the approval receipt, then register-and-tip or deposit. The permanent
list may change from empty to populated between simulation and confirmation;
handle `AlreadyRegistered` by refreshing it, never automatically tip an
unexpected list. To claim, check isMember and claimable, simulate, send claim,
then refresh balances and totals after confirmation. Repeat claims may revert
if another pending transaction already paid the same wallet.

| Event | Indexed fields | Other data |
| --- | --- | --- |
| `MembersRegistered` | depositor | members address array |
| `TipDeposited` | depositor | amount |
| `ShareClaimed` | member | amount |

Registration emits MembersRegistered and TipDeposited in the same successful
transaction. Token Transfer events accompany deposits and claims. When replaying
logs, use block/transaction/log ordering and remove events from reorganized blocks.

| Error | Meaning |
| --- | --- |
| `InvalidToken` | Constructor token is zero or has no deployed code |
| `AlreadyRegistered` | The permanent member list is already fixed |
| `NotRegistered` | A normal deposit needs initial registration first |
| `InvalidMemberCount` | The list must contain 1–10 members |
| `InvalidMember(address)` | Zero address or TipSplitter itself was supplied |
| `DuplicateMember(address)` | The same member was supplied twice |
| `ZeroAmount` | First or later tip must be positive |
| `NotMember` | Caller has no claim rights |
| `NothingToClaim` | No whole base units are currently due |
| `TransferFailed` | The token returned false |
| `UnexpectedTokenAmount` | Incoming token balance did not increase by the exact tip |
| `Reentrancy` | A token callback attempted another mutating application call |

Token reverts and malformed return data also revert the application operation;
show the token's insufficient balance/allowance errors where available. All
failed writes leave membership, credited deposits, and prior claim rights intact.
There is no address argument on claim and no refund, member editor, admin,
upgrade, sweep, or native-currency flow.
