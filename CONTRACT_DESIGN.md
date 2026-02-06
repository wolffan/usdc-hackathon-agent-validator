 # AgentValidator.sol - Contract Design

 ## Overview
 `AgentValidator` escrows USDC for a transaction, waits for evidence, collects validator votes, and releases or refunds funds based on dynamic quorum. Validators stake tokens, earn fees, and are slashed for malicious or negligent behavior.

 ## External Dependencies
 - `IERC20` for USDC.
 - `IERC20` for stake token (can be USDC for MVP).
 - `Ownable` + `Pausable` + `ReentrancyGuard`.
 - Solidity `^0.8.23`.

 ## Core Data Types
 ```solidity
 enum ValidationType { CODE_TEST, API_CHECK, FILE_HASH, MILESTONE }
 enum Status { LOCKED, VALIDATING, APPROVED, DISPUTED, REFUNDED, VALIDATION_TIMEOUT }
 enum DisputeResolution { NONE, APPROVED, REJECTED }

 struct Transaction {
     uint256 id;
     address partyA;
     address partyB;
     uint256 amount;               // USDC, 6 decimals
     bytes32 termsHash;            // hash of agreed terms
     ValidationType validationType;
     bytes32 evidenceHash;         // hash of submitted evidence bundle
     Status status;
     DisputeResolution disputeResolution;
     uint256 createdAt;
     uint256 deadline;             // evidence deadline
     uint256 validationEndsAt;
     uint256 disputeEndsAt;        // dispute resolution deadline
     uint8 quorum;                 // 1, 2, or 3
     uint8 approvals;
     uint8 rejections;
 }

 struct Validator {
     address agentAddress;
     uint256 stakedAmount;
     uint256 reputationScore;
     uint256 completedValidations;
     uint256 failedValidations;
     bool active;
 }

 struct Vote {
     bool voted;
     bool approved;
     bytes32 evidenceHash;
     bool rewardClaimed;
 }
 ```

 ## Storage Layout
 ```solidity
 IERC20 public immutable usdc;
 IERC20 public immutable stakeToken;
 address public treasury;

 uint256 public nextTransactionId;
 uint256 public minStake;
 uint256 public validationWindow;   // default: 1 hours
 uint256 public evidenceWindow;     // default: 24 hours
 uint256 public disputeWindow;      // default: 24 hours
 uint256 public constant FEE_BPS = 100;       // 1%
 uint256 public constant UNSTAKE_DELAY = 7 days;

 mapping(uint256 => Transaction) internal transactions;
 mapping(address => Validator) public validators;
 mapping(uint256 => mapping(address => Vote)) public votes;
 mapping(uint256 => address[]) public voters;
 mapping(address => uint256) public unstakeRequestedAt;
 mapping(address => uint256) public activeVotes;
 ```

 ## Events
 ```solidity
 event TransactionLocked(uint256 indexed id, address indexed partyA, address indexed partyB, uint256 amount, uint8 quorum);
 event EvidenceSubmitted(uint256 indexed id, bytes32 evidenceHash);
 event ValidationNeeded(uint256 indexed id, uint8 quorum, uint256 validationEndsAt);
 event ValidatorRegistered(address indexed validator, uint256 stakeAmount);
 event ValidationSubmitted(uint256 indexed id, address indexed validator, bool approved, bytes32 evidenceHash);
 event TransactionApproved(uint256 indexed id);
 event TransactionDisputed(uint256 indexed id, string reason);
 event DisputeResolved(uint256 indexed id, DisputeResolution resolution);
 event TransactionRefunded(uint256 indexed id);
 event TransactionTimeout(uint256 indexed id);
 event ValidatorSlashed(address indexed validator, uint256 slashAmount);
 event UnstakeRequested(address indexed validator, uint256 requestTime);
 event ValidatorUnstaked(address indexed validator, uint256 amount);
 event RewardClaimed(uint256 indexed id, address indexed validator, uint256 amount);
 event TreasuryUpdated(address indexed newTreasury);
 event WindowsUpdated(uint256 validationWindow, uint256 evidenceWindow, uint256 disputeWindow);
 event MinStakeUpdated(uint256 newMinStake);
 ```

 ## Key Functions (External)
 ```solidity
 function lockTransaction(address partyB, uint256 amount, bytes32 termsHash, ValidationType validationType)
     external nonReentrant whenNotPaused returns (uint256 id);

 function submitEvidence(uint256 id, bytes32 evidenceHash)
     external nonReentrant whenNotPaused;

 function registerValidator(uint256 stakeAmount)
     external nonReentrant whenNotPaused;

 function validate(uint256 id, bool approved, bytes32 evidenceHash)
     external nonReentrant whenNotPaused onlyValidator;

 function dispute(uint256 id, string calldata reason)
     external nonReentrant whenNotPaused onlyParty;

 function claimReward(uint256 id) external nonReentrant;
 function refundAfterTimeout(uint256 id) external nonReentrant;
 function finalizeAfterValidationTimeout(uint256 id) external nonReentrant;
 function refundAfterDisputeTimeout(uint256 id) external nonReentrant;
 ```

 ## Admin Functions
 ```solidity
 function slashValidator(address validator) external onlyOwner;
 function resolveDispute(uint256 id, DisputeResolution resolution) external onlyOwner;
 function requestUnstake() external onlyValidator;
 function unstake() external nonReentrant onlyValidator;
 function setTreasury(address newTreasury) external onlyOwner;
 function setWindows(uint256, uint256, uint256) external onlyOwner;
 function setMinStake(uint256 newMinStake) external onlyOwner;
 function pause() external onlyOwner;
 function unpause() external onlyOwner;
 ```

 ## Internal Functions
 ```solidity
 function _calcQuorum(uint256 amount) internal pure returns (uint8);
 function _finalize(uint256 id) internal;
 function _applyOutcomeToValidators(uint256 id, bool outcomeApproved) internal;
 function _applyValidatorOutcomeSingle(uint256 id, address validator, bool outcomeApproved) internal;
 function _releaseActiveVotes(uint256 id) internal;
 function _releasePayment(uint256 id) internal;
 function _updateReputation(address validator, bool approvedCorrectly) internal;
 function _calculateRewardMetrics(uint256 id, Transaction storage tx_) internal view;
 function _countCorrectVoters(uint256 id, bool shouldRewardApproval) internal view;
 function _isVoteCorrect(uint256 id, address validator, bool shouldRewardApproval) internal view;
 ```

 ## Reward and Fee Model
 - 1% fee from transaction amount stays in the contract on approval.
 - Only validators who voted **correctly** (matching the final outcome) can claim rewards.
 - Reward per correct voter = `totalFee / correctVoters`.
 - Incorrect voters receive nothing.
 - Each validator claims individually via `claimReward()`.

 ## Slashing Rules (MVP)
 - `slashValidator()` slashes 50% of stake to treasury.
 - Remaining 50% is returned to the validator before deactivation.
 - Reputation is set to 0 and validator is deactivated.

 ## Timeouts
 - `evidenceWindow`: time for Party B to submit evidence (default 24h).
 - `validationWindow`: time for validators to vote after evidence (default 1h).
 - `disputeWindow`: time for dispute resolution (default 24h).
 - `UNSTAKE_DELAY`: cooldown before validators can withdraw stake (7 days).

 ## Access Control
 - `onlyOwner` can set `treasury`, windows, `minStake`, pause/unpause, slash, resolve disputes.
 - `onlyValidator` modifier checks `validators[msg.sender].active`.
 - `onlyParty` modifier checks `partyA` or `partyB`.

 ## State Transitions
 - `LOCKED` -> `VALIDATING` after `submitEvidence`.
 - `VALIDATING` -> `APPROVED` when approvals reach quorum.
 - `VALIDATING` -> `DISPUTED` when rejections meet threshold.
 - `VALIDATING` -> `VALIDATION_TIMEOUT` when validation window expires without quorum.
 - `DISPUTED` -> `APPROVED` or `REFUNDED` via `resolveDispute`.
 - `DISPUTED` -> `REFUNDED` via `refundAfterDisputeTimeout`.
 - `LOCKED` -> `REFUNDED` via `refundAfterTimeout`.

 ## Edge Cases
 - Double voting blocked by `votes[id][validator].voted`.
 - No evidence submission triggers `refundAfterTimeout`.
 - Reentrancy guarded on all token transfers.
 - Incorrect voters cannot claim rewards (checked in `claimReward`).
 - Full accounting via events for all transitions.
 - Unstaking blocked while validator has active votes.
