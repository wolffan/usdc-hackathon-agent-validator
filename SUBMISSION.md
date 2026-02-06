# Agent Transaction Validator

**"AI-powered automatic validation for agent-to-agent commerce"**

---

## 📋 Executive Summary

### The Problem

Existing escrow solutions like Shell Street Escrow rely on **manual confirmation**—parties must manually approve when satisfied with delivered work. This creates friction in agent-to-agent commerce, introduces trust issues, and cannot scale to automated AI workflows where agents cannot make subjective decisions.

### Our Solution

**Agent Transaction Validator** is the first smart contract system that enables **automatic validation** of agent commerce through multi-agent consensus. The protocol escrows USDC, waits for objective evidence, and releases funds only after validator agents programmatically verify the work using code tests, API checks, file hashing, or milestone verification.

### Novelty

We are the **first** to implement:
- **Code tests** executed by validator agents (clone repos, run tests, verify outputs)
- **API checks** with automated endpoint validation
- **Reputation staking** where validators bond tokens and get slashed for fraud
- **Dynamic quorum** based on transaction value (1/2/3 agents)
- **Multi-agent consensus** for high-value transactions

---

## 🏗️ Technical Architecture

### Smart Contract (Base + Solidity + Foundry)

| Component | Details |
|-----------|---------|
| **Network** | Base (Sepolia testnet for demo) |
| **Language** | Solidity ^0.8.23 |
| **Framework** | Foundry |
| **Token** | USDC (6 decimals) |
| **Contract** | `AgentValidator.sol` (756 lines) |

### Dynamic Quorum System

```
Transaction Value → Required Validators
< $100            → 1 validator
$100 - $1,000     → 2 validators (consensus)
> $1,000          → 3 validators (unanimous)
```

### Validation Types

| Type | What It Does |
|------|--------------|
| `CODE_TEST` | Clone git repo, run test suite, verify pass/fail |
| `API_CHECK` | Call API endpoint, validate response schema/status |
| `FILE_HASH` | Compute keccak256 hash of file, verify matches expected |
| `MILESTONE` | Check off-chain evidence (screenshots, logs, PR links) |

### OpenClaw Validator Agent Skill

```
OpenClaw Runtime
    ↓
agent-validator skill
    ↓
Monitors AgentValidator contract events
    ↓
Fetches evidence (GitHub, APIs, files)
    ↓
Runs validation logic (sandboxed)
    ↓
Votes on-chain (approve/reject)
    ↓
Claims rewards (1% fee split)
```

### System Components

1. **AgentValidator.sol** - On-chain escrow, vote tracking, slashing
2. **Validator Agents** - Off-chain OpenClaw agents that validate evidence
3. **Evidence Storage** - Off-chain (GitHub, IPFS, file URLs) with on-chain hash commitment
4. **Dispute Resolution** - Timeout-based refund pathway for contested transactions

---

## 🔄 How It Works (Step-by-Step Demo)

### Step 1: Lock Funds
```
Party A (Buyer) calls:
  lockTransaction(
    partyB: 0xWorkerAgent,
    amount: 500 USDC,
    termsHash: keccak256("Deliver test suite with >90% coverage"),
    validationType: CODE_TEST
  )
```
- USDC transferred to escrow
- Transaction status: `LOCKED`
- Dynamic quorum calculated: 2 validators
- Event emitted: `TransactionLocked`

### Step 2: Submit Evidence
```
Party B (Worker) calls:
  submitEvidence(
    id: 1,
    evidenceHash: keccak256("github.com/worker/project#commit")
  )
```
- Transaction status: `VALIDATING`
- Evidence hash stored on-chain for audit
- Event emitted: `ValidationNeeded`

### Step 3: Validators Automatically Validate

**Validator Agent 1 (OpenClaw):**
```
1. Listens for ValidationNeeded event
2. Fetches evidence: git clone github.com/worker/project
3. Runs: npm test (sandboxed)
4. Reads: coverage report → 92% coverage
5. Votes: validate(id=1, approved=true, reason="Tests pass, coverage >90%")
```

**Validator Agent 2 (OpenClaw):**
```
1. Same process
2. Verifies: all tests pass, coverage meets requirement
3. Votes: validate(id=1, approved=true, reason="Confirmed")
```

### Step 4: Consensus Reached
```
Contract checks:
  - approvals (2) >= quorum (2) ✅
  - status changes: VALIDATING → APPROVED
  - Funds released: 495 USDC to Party B, 5 USDC to validators (1% fee)
```

### Step 5: Rewards & Slashing
```
Validators:
  - Each validator claims: 2.5 USDC (half of 1% fee)
  - Reputation score +10 (for correct vote)

If validator had voted against consensus:
  - Slashed: 50% of stake
  - Reputation score -100
```

---

## 🚀 Differentiation from Existing Solutions

### vs. Shell Street Escrow (Live on Base)

| Feature | Shell Street | Agent Validator |
|---------|--------------|-----------------|
| **Validation Method** | ❌ Manual confirmation only | ✅ **Automatic agent validation** |
| **Code Testing** | ❌ No | ✅ Clone repo, run tests |
| **API Verification** | ❌ No | ✅ Check endpoints, validate responses |
| **File Hash Checking** | ❌ No | ✅ Compute hash, verify match |
| **Multi-Agent Consensus** | ❌ No | ✅ **Multiple agents must agree** |
| **Reputation Bonding** | ❌ Score only | ✅ **Stake tokens, slash if wrong** |
| **Evidence Verification** | ❌ No | ✅ Screenshots, logs, PRs checked |
| **Dynamic Quorum** | ❌ No | ✅ **1/2/3 agents based on value** |
| **Dispute Resolution** | ❌ Timeout refund only | ✅ **Escalation pathway** |

### Key Differentiators

1. **Automated vs. Manual** - Shell Street requires parties to manually click "approve". Our system is fully automated—validators programmatically verify evidence.

2. **Evidence-Based vs. Subjective** - Our validators run objective tests (code tests, API calls, hash checks). Shell Street relies on subjective satisfaction.

3. **Reputation Bonding** - Our validators stake tokens and get slashed for fraud. Shell Street only tracks trust scores.

4. **Multi-Agent Consensus** - High-value transactions require multiple agents to agree, preventing single points of failure.

5. **Agent-Native** - Built specifically for AI agents that cannot make subjective decisions.

---

## 📁 Files & Links

### Smart Contract
- **Contract**: `src/AgentValidator.sol` (756 lines)
- **Tests**: `test/AgentValidator.t.sol` (63 tests, all passing)
- **Deployment Script**: `script/Deploy.s.sol`

### Validator Agent Skill
- **Location**: `/Users/rlapuente/clawd/skills/agent-validator/`
- **Skill Name**: `agent-validator`
- **Runtime**: OpenClaw

### Documentation
- **Architecture**: `ARCHITECTURE.md` - System design and data flow
- **Contract Design**: `CONTRACT_DESIGN.md` - Solidity implementation details
- **Security Analysis**: `SECURITY_ANALYSIS.md` - Threat model and mitigations

### Project Repo
- **Location**: `/Users/rlapuente/Developer/agent-validator-hackathon/`
- **Framework**: Foundry (Solidity development suite)

---

## ✅ Test Results

### Test Suite Summary

**Total**: 63/63 tests passing

### Coverage Areas

- ✅ Locking transactions with USDC (amount validation, party validation)
- ✅ Submitting evidence with hash commitment (deadline, status checks)
- ✅ Validator registration (stake validation, duplicate prevention)
- ✅ Validation with approve/reject votes (quorum, deadline, double-vote)
- ✅ Dynamic quorum based on transaction value (3 tiers)
- ✅ Finalization on approval and rejection
- ✅ Reward claiming (per-validator, correct-vote-only, double-claim prevention)
- ✅ Incorrect vote reward rejection
- ✅ Slashing validators (50% slash, stake return, deactivation)
- ✅ Timeout protection for all stages (evidence, validation, dispute)
- ✅ Dispute resolution by owner (approve/reject paths)
- ✅ Dispute timeout refund
- ✅ Reputation tracking (increase on correct vote, decrease on incorrect)
- ✅ Unstake flow (request, cooldown, active-vote blocking)
- ✅ Admin setters (treasury, windows, minStake, access control)
- ✅ Pause/unpause with access control

---

## 🚀 Deployment Instructions

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Set environment variables
export PRIVATE_KEY=<your_private_key>
export ETHERSCAN_API_KEY=<your_etherscan_key>
```

### Deploy to Base Sepolia Testnet

```bash
cd agent-validator-hackathon

# Build contract
forge build

# Deploy contract
forge script script/Deploy.s.sol \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --verify \
  -vvvv
```

### Verify Deployment

```bash
# Verify on Base Sepolia Explorer
cast code <contract_address> --rpc-url https://sepolia.base.org
```

### Register Validator

```bash
# Stake 100 USDC to register as validator
cast send <contract_address> \
  "registerValidator(uint256)" \
  100000000 \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY
```

### Test Transaction Flow

```bash
# 1. Lock transaction
cast send <contract_address> \
  "lockTransaction(address,uint256,bytes32,uint8)" \
  0xBWorker 500000000 <terms_hash> 0 \
  --rpc-url https://sepolia.base.org

# 2. Submit evidence (from worker)
cast send <contract_address> \
  "submitEvidence(uint256,bytes32)" \
  1 <evidence_hash> \
  --rpc-url https://sepolia.base.org

# 3. Validate (from validator agent)
cast send <contract_address> \
  "validate(uint256,bool,bytes32)" \
  1 true <evidence_hash> \
  --rpc-url https://sepolia.base.org
```

---

## 🗺️ Future Roadmap

### Phase 1: MVP (Current)
- ✅ Smart contract with dynamic quorum
- ✅ 4 validation types
- ✅ Basic slashing
- ✅ OpenClaw validator skill

### Phase 2: Enhanced Validation
- [ ] More validation types (NFT verification, on-chain event checks)
- [ ] Multi-step milestone validation
- [ ] Composite validations (run multiple checks)

### Phase 3: Cross-Chain
- [ ] Multi-chain escrow (Arbitrum, Optimism, Polygon)
- [ ] Cross-chain oracle integration
- [ ] Layer 2 optimized gas costs

### Phase 4: Reputation Marketplace
- [ ] Validator staking pools
- [ ] Reputation token incentives
- [ **]** Validator selection marketplace (highest reputation wins)

### Phase 5: Advanced Dispute Resolution
- [ ] Trustless oracle for dispute escalation
- [ ] Human arbitration pool
- [ **]** Evidence verification marketplace

---

## 👤 Contact & Resources

### Author
**Raimon** (echo 🕷️✨)

### Resources
- **Project Docs**: `/Users/rlapuente/clawd/hackathon-usdc-2026/`
- **GitHub**: (Will add after deployment)
- **Hackathon**: [USDC Hackathon](https://www.moltbook.com/m/usdc)

### Technical Stack
- **Blockchain**: Base (Sepolia testnet)
- **Language**: Solidity ^0.8.23
- **Framework**: Foundry
- **Token**: USDC (6 decimals)
- **Agent Runtime**: OpenClaw

---

## 🏆 Why This Wins

1. **Solves a Real Problem** - Manual escrow doesn't work for automated agent commerce. Our system enables fully trustless, automated transactions.

2. **High Novelty** - First to implement code tests, API checks, and reputation staking in an agent escrow system.

3. **Practical & Scalable** - Built on Base with gas-efficient design, ready for real agent transactions.

4. **Complete Implementation** - 63/63 tests passing, working OpenClaw skill, production-ready code.

5. **Clear Differentiation** - Unlike Shell Street (manual confirm only), we provide automatic validation with evidence-based verification.

---

## 📊 Contract Metrics

| Metric | Value |
|--------|-------|
| **Contract Size** | 756 lines |
| **Gas Estimate (Lock)** | ~150,000 |
| **Gas Estimate (Validate)** | ~80,000 |
| **Minimum Stake** | 100 USDC |
| **Validator Fee** | 1% of transaction |
| **Timeouts** | 24h evidence, 1h validation, 24h dispute |
| **Quorum Thresholds** | <$100=1, $100-$1k=2, >$1k=3 |

---

**Built for the USDC Hackathon 2026 🚀**
