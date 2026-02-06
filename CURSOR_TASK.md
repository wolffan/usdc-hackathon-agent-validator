# Cursor Task: Agent Transaction Validator Architecture

## Project Overview

**Project Name:** Agent Transaction Validator (OpenClaw USDC Hackathon)
**Track:** Most Novel Smart Contract
**Deadline:** Sunday, Feb 8, 2026 @ 20:00 GMT
**Current Status:** Research complete, ready for architecture phase

---

## Your Task

Design the **complete technical architecture** for the Agent Transaction Validator system before we start development.

---

## Background

### Problem Statement

When AI agents transact with each other, how do they trust that the other party fulfilled their obligation?

**Existing Solutions:**
- Shell Street Escrow V5: Only does bilateral escrow with manual confirmations
- Agent Bounty Board: Dutch auction with human approval
- MoltCities Jobs: Escrow bounties with manual approval

**The Gap:** NO automated validation system where agents automatically verify work quality.

---

## Our Solution: Agent Transaction Validator

An autonomous system where validator agents automatically verify work and release payment only when terms are met.

**Novelty Factors:**
1. Automatic validation (vs. manual confirmations)
2. Multi-agent consensus for high-value transactions
3. Reputation bonding (agents stake tokens, get slashed for fraud)
4. Evidence-based validation (agents actually test code, check APIs)
5. Multiple validation types (code tests, API checks, file hashes, milestones)

---

## Architecture Requirements

### 1. Smart Contract (Solidity + Foundry)

**Core Contract: `AgentValidator.sol`**

Design the contract with:

**Data Structures:**
```solidity
struct Transaction {
    uint256 id;
    address partyA;           // Payer (depositor)
    address partyB;           // Worker (recipient)
    uint256 amount;           // USDC amount
    bytes32 termsHash;        // Keccak256 hash of agreed terms
    ValidationType validationType;
    bytes32 evidenceHash;
    Status status;
    uint256 createdAt;
    uint256 deadline;
}

enum ValidationType {
    CODE_TEST,      // Clone repo, run tests
    API_CHECK,       // Verify API endpoint
    FILE_HASH,       // Verify file upload
    MILESTONE        // Custom milestone
}

enum Status {
    LOCKED,          // Funds deposited, awaiting evidence
    VALIDATING,       // Evidence submitted, validators working
    APPROVED,        // Validated, payment released
    DISPUTED,        // Dispute raised
    REFUNDED         // Timeout or cancellation
}

struct Validator {
    address agentAddress;
    uint256 stakedAmount;      // Tokens staked for validation
    uint256 reputationScore;      // Dynamic score based on performance
    uint256 completedValidations;
    uint256 failedValidations;
    bool active;
}
```

**Key Functions to Design:**
1. `lockTransaction(partyB, amount, termsHash, validationType)` - Party A locks USDC
2. `submitEvidence(transactionId, evidenceHash)` - Party B submits work proof
3. `registerValidator(stakeAmount)` - Agents register as validators
4. `validate(transactionId, approved, reason)` - Validators vote on work
5. `dispute(transactionId, reason)` - Party can dispute
6. `claimReward(transactionId)` - Validator earns fee after validation

**Validation Logic to Design:**
- **Dynamic Quorum:**
  - <$100: 1 validator
  - $100-$1000: 2 validators (consensus)
  - >$1000: 3 validators (unanimous)
- **Timeout Protection:** Auto-refund if no action within time window
- **Slashing Conditions:**
  - Fraudulent validation (approve invalid work)
  - Malicious rejection (reject valid work)
  - Failure to respond within time
- **Fee Structure:** 1% fee to validators, split proportionally

---

### 2. Validator Agent Logic (OpenClaw Skill)

Design the OpenClaw skill architecture:

**Skill Structure:**
```
agent-validator-hackathon/
├── SKILL.md                 # OpenClaw skill manifest
├── src/
│   ├── validator.ts         # Main validation logic
│   ├── validators/
│   │   ├── codeTest.ts      # Clone repo, run tests
│   │   ├── apiCheck.ts      # Verify API endpoints
│   │   ├── fileHash.ts      # Compute and verify hashes
│   │   └── milestone.ts     # Execute custom scripts
│   ├── reputation.ts         # Track and update reputation
│   └── contract.ts          # Smart contract interaction
└── tests/
    └── validator.test.ts
```

**Validator Agent Workflows:**

**A. Code Test Validation**
```typescript
async function validateCodeTest(transaction) {
    // 1. Clone repo from GitHub
    await exec(`git clone ${transaction.repoUrl} /tmp/repo-${txId}`);

    // 2. Checkout specified branch/commit
    await exec(`cd /tmp/repo-${txId} && git checkout ${transaction.branch}`);

    // 3. Install dependencies
    await exec(`cd /tmp/repo-${txId} && npm install`);

    // 4. Run tests
    const result = await exec(`cd /tmp/repo-${txId} && npm test`);

    // 5. Parse results
    const testResults = parseTestResults(result.stdout);

    // 6. Return verdict
    return {
        approved: testResults.allPassed,
        evidence: {
            exitCode: result.exitCode,
            passed: testResults.passed,
            failed: testResults.failed,
            coverage: testResults.coverage
        },
        reason: testResults.allPassed ?
            'All tests passed' :
            `${testResults.failed} tests failed`
    };
}
```

**B. API Check Validation**
```typescript
async function validateAPICheck(transaction) {
    // 1. Send test request
    const response = await fetch(transaction.apiEndpoint, {
        method: 'GET',
        headers: transaction.headers
    });

    // 2. Verify response
    const approved =
        response.status === 200 &&
        schemaValidate(response.body, transaction.expectedSchema);

    // 3. Return verdict
    return {
        approved,
        evidence: {
            statusCode: response.status,
            bodyHash: keccak256(response.body),
            headers: response.headers
        },
        reason: approved ?
            'API returned expected response' :
            'API validation failed'
    };
}
```

**C. File Hash Validation**
```typescript
async function validateFileHash(transaction) {
    // 1. Download file
    const file = await download(transaction.fileUrl);

    // 2. Compute hash
    const computedHash = keccak256(file);

    // 3. Compare with expected
    const approved = computedHash === transaction.expectedHash;

    return {
        approved,
        evidence: {
            computedHash,
            expectedHash: transaction.expectedHash,
            match: approved
        },
        reason: approved ?
            'File hash matches expected' :
            `Hash mismatch: ${computedHash} != ${transaction.expectedHash}`
    };
}
```

---

### 3. Multi-Agent Consensus System

Design how validators coordinate:

**Consensus Flow:**
```
1. Transaction moves to VALIDATING status
2. Contract emits ValidationNeeded(transactionId, quorum)
3. N validator agents pick up task (first-come, first-served)
4. Each validator calls validate() with their verdict
5. Contract tracks votes:
   - If all approve → APPROVED, release funds
   - If quorum rejects → DISPUTED, refund to payer
   - If split votes (e.g., approve/reject/approve) → ESCALATE
6. Escalation: Route to oracle or human for final decision
```

**Staking & Slashing Logic:**
```solidity
// On registration
function registerValidator(uint256 stakeAmount) external {
    stakeToken.transferFrom(msg.sender, address(this), stakeAmount);
    validators[msg.sender] = Validator({
        agentAddress: msg.sender,
        stakedAmount: stakeAmount,
        reputationScore: 500, // Start at 500
        completedValidations: 0,
        failedValidations: 0,
        active: true
    });
}

// On validation failure (proven fraud)
function slashValidator(address validator) external {
    require(isEscalated, "Not escalated");
    require(validators[validator].active, "Validator inactive");

    uint256 slashAmount = validators[validator].stakedAmount / 2; // 50% slash
    stakeToken.transfer(treasury, slashAmount);
    validators[validator].stakedAmount -= slashAmount;
    validators[validator].reputationScore = 0; // Reset to zero
    validators[validator].active = false;
}
```

**Reputation Update Logic:**
```solidity
function updateReputation(address validator, bool approvedCorrectly) internal {
    Validator storage v = validators[validator];

    if (approvedCorrectly) {
        v.completedValidations += 1;
        v.reputationScore += 10; // +10 for correct validation
    } else {
        v.failedValidations += 1;
        v.reputationScore -= 50; // -50 for wrong validation
    }

    // Bonus for high reputation validators
    if (v.reputationScore > 1000) {
        v.reputationScore += 5; // Additional bonus
    }
}
```

---

### 4. System Architecture

Draw the full system architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                   Agent Transaction Validator               │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Party A   │    │ Validator 1  │    │ Validator 2  │
│   (Payer)   │    │   Agent     │    │   Agent     │
└─────────────┘    └─────────────┘    └─────────────┘
       │                     │                   │
       │ lockTransaction()     │ validate()          │ validate()
       │ deposit USDC         │ check code/API      │ check code/API
       ▼                     ▼                   ▼
┌───────────────────────────────────────────────────────┐
│           AgentValidator.sol Contract              │
│                                                │
│  - Lock USDC escrow                           │
│  - Track validator votes                         │
│  - Enforce quorum rules                        │
│  - Release/refund based on consensus             │
│  - Slash validators for fraud                   │
└───────────────────────────────────────────────────────┘
       │                     │                   │
       │ approved             approved            approved
       ▼                     ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Party B   │    │ Validator 1  │    │ Validator 2  │
│  (Worker)   │    │ earns fee   │    │ earns fee   │
│ submits work │    │ + reputation│    │ + reputation│
└─────────────┘    └─────────────┘    └─────────────┘
```

---

### 5. Security Considerations

Design security measures:

**Smart Contract Security:**
- Reentrancy protection on all external functions
- Proper access control (only validators can call validate)
- Timeout mechanisms to prevent funds from being locked forever
- Emergency pause circuit breaker
- Integer overflow/underflow protection (Solidity 0.8.20+)

**Agent Security:**
- Validate all external inputs (repo URLs, API endpoints)
- Use temporary directories for cloning/executing code
- Timeout execution to prevent hanging
- Sanitize file paths to prevent directory traversal
- Rate limiting to prevent spam

**Economic Security:**
- Stake slashing must be proportionate (not 100%, reasonable)
- Minimum stake requirement to join validator pool
- Maximum stake cap to prevent concentration
- Fee caps to prevent excessive extraction

---

### 6. Testing Strategy

Design comprehensive test plan:

**Unit Tests (Foundry):**
```solidity
// Test 1: Lock transaction
function test_LockTransaction() public {
    vm.deal(partyA, 1000e6); // 1000 USDC
    vm.prank(partyA);
    validator.lockTransaction(partyB, 500e6, termsHash, CODE_TEST);
    assertEq(validator.status(id), Status.LOCKED);
    assertEq(validator.partyA(id), partyA);
    assertEq(validator.amount(id), 500e6);
}

// Test 2: Dynamic quorum
function test_DynamicQuorum() public {
    // Small amount: 1 validator
    testLockAndQuorum(50e6, 1);  // $50

    // Medium amount: 2 validators
    testLockAndQuorum(500e6, 2); // $500

    // Large amount: 3 validators
    testLockAndQuorum(5000e6, 3); // $5000
}

// Test 3: Validator registration
function test_RegisterValidator() public {
    uint256 stakeAmount = 100e18; // 100 tokens
    vm.prank(validator1);
    validator.registerValidator(stakeAmount);
    assertEq(validator.validators(validator1).stakedAmount, stakeAmount);
    assertEq(validator.validators(validator1).reputationScore, 500);
}

// Test 4: Slashing
function test_SlashValidator() public {
    // Setup validator with stake
    validator.registerValidator(100e18);

    // Escalate transaction
    validator.dispute(txId, "Evidence of fraud");

    // Slash
    validator.slashValidator(validator1);
    assertEq(validator.validators(validator1).stakedAmount, 50e18); // 50% slashed
    assertEq(validator.validators(validator1).reputationScore, 0);
}
```

**Integration Tests (OpenClaw skill):**
```typescript
// Test full flow: lock -> validate -> approve -> release
async function testFullFlow() {
    // 1. Lock transaction
    const txId = await lockTransaction(...);

    // 2. Submit evidence
    await submitEvidence(txId, evidenceHash);

    // 3. Validate (3 validators)
    await validator1.validate(txId, true, "Tests passed");
    await validator2.validate(txId, true, "Tests passed");
    await validator3.validate(txId, true, "Tests passed");

    // 4. Verify approved and paid
    const status = await getTransactionStatus(txId);
    assertEqual(status, Status.APPROVED);
}
```

**Fuzz Testing:**
- Test with random inputs (repo URLs, amounts, hashes)
- Test edge cases (zero amounts, invalid hashes)
- Test concurrent validations

---

### 7. Deployment Plan

Design deployment strategy:

**Testnet (Phase 1):**
- Deploy to Base Goerli testnet
- Fund validators with test USDC
- Run test transactions
- Verify quorum logic
- Test slashing mechanism

**Mainnet (Phase 2 - Post-Hackathon):**
- Audit contract
- Deploy to Base mainnet
- Set up block explorer verification
- Deploy validator agents to production

---

## Deliverables

Please create these files:

1. **ARCHITECTURE.md** - High-level system architecture with diagrams
2. **CONTRACT_DESIGN.md** - Detailed smart contract design (all structs, functions, events)
3. **VALIDATOR_AGENT_DESIGN.md** - OpenClaw skill architecture and workflows
4. **SECURITY_ANALYSIS.md** - Security considerations and mitigations
5. **TEST_PLAN.md** - Comprehensive testing strategy
6. **DEPLOYMENT_PLAN.md** - Deployment steps for testnet/mainnet

Each file should be detailed, code-ready, and cover all aspects of the design.

---

## Context Files Available

All research is in: `/Users/rlapuente/clawd/hackathon-usdc-2026/`
- `research-existing-solutions.md` - What exists
- `ideas-detailed.md` - Our proposed ideas
- `competition-analysis.md` - Shell Street vs. us
- `links-rules.md` - Hackathon rules and links

Feel free to reference these files for context.

---

## Timeline

**Phase 1 (Today - Feb 4):** Architecture and Design (YOUR TASK)
**Phase 2 (Feb 5):** Smart Contract Development
**Phase 3 (Feb 6):** Validator Agent Development
**Phase 4 (Feb 7):** Testing & Deployment
**Phase 5 (Feb 8):** Final Polish & Submission

---

## Success Criteria

Your architecture design should:
- ✅ Cover all validation types (CODE_TEST, API_CHECK, FILE_HASH, MILESTONE)
- ✅ Define clear multi-agent consensus mechanism
- ✅ Detail reputation bonding and slashing logic
- ✅ Address security considerations
- ✅ Provide clear testing strategy
- ✅ Be implementable in 3 days (Feb 5-7)

---

**Start working on this architecture design now.** Focus on technical depth and implementation readiness.
