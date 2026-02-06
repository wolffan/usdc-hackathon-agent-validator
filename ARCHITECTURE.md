 # Agent Transaction Validator - Architecture

 ## Purpose
 Enable autonomous agent-to-agent transactions where payment is released only after objective validation of work. The system combines on-chain escrow and validator voting with off-chain evidence checks performed by validator agents.

 ## Goals
 - Automatic validation for code, API, file hash, and milestone workflows.
 - Dynamic quorum based on transaction value.
 - Reputation bonding with staking and slashing.
 - Clear audit trail of evidence and validator decisions.
 - Simple, reliable, and implementable within 3 days.

 ## Non-Goals (MVP)
 - General purpose oracle network.
 - Cross-chain payments.
 - Fully decentralized validator selection marketplace.

 ## High-Level Components
 1. **AgentValidator.sol (Smart Contract)**
    - Holds USDC in escrow.
    - Tracks transactions, evidence hash, and validator votes.
    - Releases or refunds funds based on consensus.
    - Manages validator registration, stake, reputation, and slashing.
 2. **Validator Agents (OpenClaw Skill)**
    - Observe on-chain events.
    - Fetch evidence and run validation logic per type.
    - Submit votes and reasoning to contract.
    - Store off-chain evidence artifacts and hash on-chain.
 3. **Evidence Storage (Off-chain)**
    - GitHub repos, API endpoints, file URLs, or IPFS/Arweave.
    - Validator agents compute evidence hash to pin to chain.
 4. **Client/Orchestrator (Optional)**
    - UI or agent that helps parties submit terms and evidence.
    - Not required for core validation flow.

 ## System Diagram
 ```
 ┌─────────────────────────────────────────────────────────────┐
 │                 Agent Transaction Validator                 │
 └─────────────────────────────────────────────────────────────┘
                 │                          │
     lockTransaction()                 registerValidator()
                 │                          │
                 ▼                          ▼
 ┌────────────────────────────┐    ┌───────────────────────────┐
 │     AgentValidator.sol     │    │     Validator Agents      │
 │ - escrow USDC              │    │ - listen to events        │
 │ - track votes + status     │◄───┤ - validate evidence       │
 │ - enforce quorum + timeouts│    │ - vote approve/reject     │
 └────────────────────────────┘    └───────────────────────────┘
                 │                          │
         submitEvidence()            validate() + claimReward()
                 │                          │
                 ▼                          ▼
           Party B (Worker)            Validator Rewards
 ```

 ## Core Data Flow
 1. **Lock**
    - Party A calls `lockTransaction(...)`, USDC moved into escrow.
    - Contract emits `TransactionLocked(id, quorum, deadline)`.
 2. **Evidence**
    - Party B calls `submitEvidence(id, evidenceHash)` with off-chain details.
    - Contract sets status to `VALIDATING` and emits `ValidationNeeded`.
 3. **Validation**
    - Validators pick up `ValidationNeeded` event.
    - Each validator runs checks and calls `validate(id, approved, reason, evidenceHash)`.
    - Contract records vote and updates reputation after final outcome.
 4. **Resolution**
    - If quorum approves, release payment to Party B.
    - If quorum rejects, refund Party A or mark disputed.
    - If conflicting votes, move to `DISPUTED` and allow escalation path.
 5. **Rewards**
    - Validators claim their share of the 1% fee after finalization.

 ## State Machine
 ```
 LOCKED → VALIDATING → APPROVED → (final)
         ↘
          DISPUTED → REFUNDED (or ESCALATED external)
 ```
 - `LOCKED`: funds in escrow, waiting for evidence.
 - `VALIDATING`: evidence submitted, validators working.
 - `APPROVED`: consensus approval, funds released to Party B.
 - `DISPUTED`: rejection, split votes, or timeout.
 - `REFUNDED`: funds returned to Party A after dispute or timeout.

 ## Dynamic Quorum
 - `< $100`: 1 validator.
 - `$100 - $1000`: 2 validators (consensus).
 - `> $1000`: 3 validators (unanimous).

 ## On-Chain vs Off-Chain Boundary
 - **On-chain**: escrow, vote tracking, validator staking, final state.
 - **Off-chain**: running tests, calling APIs, downloading files, hashing.
 - Evidence hash bridges both worlds for auditability.

 ## Escalation Model (MVP)
 - If validators disagree or time out, transaction is marked `DISPUTED`.
 - Funds can be refunded by Party A after a dispute timeout.
 - Optional future: external oracle or human arbitration.

 ## Reliability Considerations
 - Explicit timeouts on evidence submission and validation.
 - Circuit breaker pause for emergencies.
 - Simple, deterministic quorum rules.
 - Minimal on-chain logic to reduce attack surface.

 ## Dependencies
 - USDC ERC-20 (6 decimals).
 - Stake token (can be the same as USDC for MVP).
 - Foundry for contract testing.
 - OpenClaw runtime for validator agents.

