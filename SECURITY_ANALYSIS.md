 # Security Analysis

 ## Threat Model
 - Malicious party submits invalid work or evidence.
 - Validators collude to approve or reject incorrectly.
 - Validators fail to respond or attempt to grief.
 - External data sources are unreliable or compromised.
 - Smart contract is attacked via reentrancy, spoofing, or overflow.

 ## Smart Contract Risks and Mitigations
 1. **Reentrancy on token transfers**
    - Use `ReentrancyGuard`.
    - Perform state updates before external calls.
 2. **Unauthorized access**
    - Restrict validator-only functions with `onlyValidator`.
    - Only parties can call dispute/refund for their transaction.
 3. **Locked funds due to inactivity**
    - Evidence and validation timeouts with `refundAfterTimeout`.
    - Dispute window to prevent permanent lock.
 4. **Vote manipulation**
    - One vote per validator per transaction enforced by `Vote` mapping.
    - Only active validators with minimum stake can vote.
 5. **Integer overflow**
    - Solidity 0.8.20 built-in overflow checks.
 6. **Pause for emergencies**
    - `Pausable` allows contract owner to halt in emergencies.

 ## Validator Agent Risks and Mitigations
 1. **Malicious repositories or scripts**
    - Run code in a sandbox (Docker or restricted process).
    - Set strict CPU and time limits.
    - No secret environment variables.
 2. **SSRF / internal network access**
    - Block private IP ranges.
    - Allowlist domains for API checks.
 3. **Large file downloads**
    - Enforce maximum size and timeout.
 4. **Directory traversal**
    - Use isolated temp directories.
    - Sanitize all paths before filesystem access.
 5. **Non-deterministic results**
    - Normalize evidence data before hashing.
    - Record command outputs and versions.

 ## Economic Security
 1. **Validator collusion**
    - Dynamic quorum increases cost of collusion.
    - Slashing based on dispute resolution (future phase).
 2. **Sybil attacks**
    - Minimum stake requirement.
    - Cap maximum stake to avoid centralization.
 3. **Griefing by non-response**
    - Validation window and reputation penalties.
 4. **Fee manipulation**
    - Fixed fee percentage (1%).
    - Fee cap enforced on-chain.

 ## Evidence Integrity
 - All evidence bundles hashed with keccak256.
 - On-chain only stores hash, not sensitive data.
 - Validators store evidence artifacts for auditability.

 ## Data Privacy
 - Avoid storing sensitive data on-chain.
 - Evidence references should point to redacted artifacts when needed.
 - Testnet-only per hackathon rules.

 ## Operational Security
 - Rotate agent keys and keep private keys isolated.
 - Use separate wallets for validator stake and operations.
 - Monitor for unusual validation patterns.

 ## Residual Risks (Accepted for MVP)
 - Dispute resolution is minimal (refund-only).
 - No trust-minimized oracle for escalations.
 - Validator selection is first-come, not randomized.

