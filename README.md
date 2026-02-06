# AgentValidator - Agent-Native Escrow with USDC

## 📖 Description

**AgentValidator** is a smart contract that enables AI agents to secure transactions with escrow, validator staking, and dynamic quorum-based validation. Agents can lock USDC funds for services to be delivered, request validation from staked validators, and have funds released automatically when consensus is reached.

The contract solves the fundamental trust problem in agent-to-agent commerce: how can agents safely pay each other when neither party knows the other? By requiring validators to stake USDC (minimum 100) and vote on transaction outcomes, the system ensures economic accountability. Validators are rewarded for correct votes and slashed for bad ones, creating alignment incentives.

## 🎯 Hackathon Track
- **Track:** Most Novel Smart Contract
- **Hackathon:** USDC Hackathon (Moltbook m/usdc)
- **Submission:** #USDCHackathon ProjectSubmission MostNovelSmartContract - AgentValidator

## 🚀 Features
- **Escrow Locking:** Secure USDC funds in escrow for transactions
- **Validator Staking:** Agents stake 100+ USDC to become validators
- **Dynamic Quorum:** Automatic quorum calculation based on transaction amount
  - <$100: 1 validator
  - $100-$1,000: 2 validators
  - >$1,000: 3 validators
- **Multi-Validator Voting:** Multiple validators vote on transaction outcomes
- **Evidence Submission:** Parties submit evidence for validation
- **Auto-Finalization:** Funds release automatically when quorum reached
- **Dispute Resolution:** Built-in dispute mechanism with time windows
- **Reward Distribution:** Validators earn 1% fee for correct validation
- **Reputation System:** Track validator performance over time
- **Slashing:** Bad validators lose stake on disputes
- **Time Windows:** Configurable windows for evidence, validation, disputes

## 🏗️ Architecture
- **Smart Contract:** Solidity ^0.8.23
- **Framework:** Foundry
- **Dependencies:** OpenZeppelin v4.0.0
- **Network:** Base Sepolia (testnet)
- **Token:** USDC (6 decimals)

## ✅ Test Results
- **Unit Tests:** 12/12 passing
- **Integration Tests:** 14/14 scenarios passing
- **Gas Optimization:** Optimized for <600K gas on all functions
- **Code Review:** Completed with Cursor GPT-5.2

### Test Coverage
- ✅ Escrow locking with USDC
- ✅ Validator registration (100 USDC minimum)
- ✅ Dynamic quorum based on amount
- ✅ Multi-validator voting system
- ✅ Evidence submission
- ✅ Auto-finalization on quorum
- ✅ Reward distribution (1% fee)
- ✅ Dispute mechanism
- ✅ Validator reputation tracking
- ✅ Multiple wallet scenarios (6 wallets)
- ✅ Time window enforcement
- ✅ Fee calculation accuracy

## 🔐 Security Features
- ReentrancyGuard on critical functions
- OnlyOwner for admin functions
- OnlyParty for transaction participants
- Pausable for emergency stops
- Time windows for all actions (evidence, validation, dispute)
- Validator staking (economic security)
- Slashing for bad validators

## 🛠️ How to Run Tests

### Unit Tests
```bash
cd ~/Developer/agent-validator-hackathon
forge test -vv
```

### Integration Tests
```bash
forge script script/IntegrationTest.s.sol --rpc-url https://sepolia.base.org --via-ir -vv
```

### Deploy to Base Sepolia
```bash
forge script script/Deploy.s.sol --rpc-url https://sepolia.base.org --broadcast --via-ir
```

## 📝 License
MIT License - See LICENSE file

## 👥 Authors
- Raimon Lapuente
- Echo (OpenClaw Assistant)

## 📚 Usage Example

```solidity
// Party A locks funds for Party B
contract.lockTransaction(
    partyBAddress,           // Receiver's wallet
    1000 * 1e6,            // 1,000 USDC
    keccak256(terms),       // Hash of agreed terms
    ValidationType.CODE_TEST  // Type of validation needed
);

// Party B submits evidence
contract.submitEvidence(txnId, evidenceHash);

// Validators vote
contract.validate(txnId, true, validatorEvidenceHash);

// Validators claim rewards
contract.claimReward(txnId);
```

## 🔗 Links
- **Testnet:** [Deployment address to be added]
- **Integration Tests:** ~/clawd/AGENT_VALIDATOR_INTEGRATION_TESTS_REPORT.md

## 💡 Novelty
AgentValidator introduces **agent-native escrow** - a validation mechanism designed specifically for AI agent commerce where:
- Neither party knows each other
- No human intervention is possible
- Economic incentives align all participants
- Validators are staked AI agents, not humans
- Quorum scales automatically with transaction size
- Reputation is tracked onchain

This is fundamentally different from traditional escrow systems that require human intermediaries or trusted third parties.
