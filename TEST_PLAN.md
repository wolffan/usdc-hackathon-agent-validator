 # Test Plan

 ## Goals
 - Verify escrow safety and correct fund flow.
 - Validate dynamic quorum and voting logic.
 - Ensure timeouts and refunds work reliably.
 - Confirm validator agent behavior for each validation type.

 ## Smart Contract Unit Tests (Foundry)
 1. **Lock Transaction**
    - Locks USDC and records transaction fields.
    - Emits `TransactionLocked`.
 2. **Evidence Submission**
    - Only Party B can submit.
    - Moves status to `VALIDATING`.
 3. **Dynamic Quorum**
    - `< $100`: quorum 1.
    - `$100 - $1000`: quorum 2.
    - `> $1000`: quorum 3.
 4. **Validation Voting**
    - Only active validators can vote.
    - Prevent double voting.
    - Approvals reach quorum → `APPROVED`.
    - Rejections reach threshold → `DISPUTED`.
 5. **Timeouts**
    - Evidence timeout → refund.
    - Validation timeout → dispute/refund.
 6. **Rewards**
    - 1% fee split across validators.
    - Reward claim only after finalization.
 7. **Slashing (If Enabled)**
    - Slash only after dispute outcome is known.
    - Validator stake decreases correctly.
 8. **Pause/Unpause**
    - All state-changing actions blocked when paused.

 ## Invariant Tests
 - Escrowed USDC equals sum of locked amounts minus paid/refunded amounts.
 - A transaction cannot move from `APPROVED` to any other state.
 - No validator can vote twice for same transaction.

 ## Fuzz Tests
 - Random transaction amounts, deadlines, and validators.
 - Random order of votes and timing.
 - Invalid evidence hashes and invalid states.

 ## Agent Unit Tests (TypeScript)
 1. **Code Test Validation**
    - Passing tests returns approved.
    - Failing tests returns rejected.
 2. **API Check**
    - 200 with schema match approves.
    - Non-200 or schema mismatch rejects.
 3. **File Hash**
    - Correct hash approves.
    - Incorrect hash rejects.
 4. **Milestone**
    - Script exit code 0 approves.
    - Non-zero rejects.
 5. **Evidence Hashing**
    - Deterministic hashing for same input.

 ## Integration Tests
 - Full flow: lock → submit evidence → validate → approve → release.
 - Dispute flow: lock → submit evidence → reject → dispute → refund.
 - Timeout flow: lock → no evidence → refund.
 - Multi-validator flow: 3 validators for high value.

 ## End-to-End Tests
 - Start local chain + deploy contract.
 - Run 2-3 validator agents in parallel.
 - Simulate real evidence in a temp Git repo and API stub.

 ## Manual QA Checklist
 - Events emitted at each step.
 - USDC balances change as expected.
 - Validator rewards are claimable and accurate.
 - Evidence hashes match expected values.

