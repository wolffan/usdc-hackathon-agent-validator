// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AgentValidator
 * @dev Escrows USDC for transactions, collects validator votes, and releases funds based on dynamic quorum.
 */
contract AgentValidator is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice USDC token contract
    IERC20 public immutable usdc;
    /// @notice Token used for validator staking (can be USDC for MVP)
    IERC20 public immutable stakeToken;
    /// @notice Treasury address for slashed stake
    address public treasury;

    /// @notice Next transaction ID counter
    uint256 public nextTransactionId;
    /// @notice Minimum stake required to register as validator
    uint256 public minStake = 100 * 1e6; // 100 USDC (6 decimals)
    /// @notice Time window for validation (in seconds)
    uint256 public validationWindow = 1 hours;
    /// @notice Time window for evidence submission (in seconds)
    uint256 public evidenceWindow = 24 hours;
    /// @notice Time window for dispute resolution (in seconds)
    uint256 public disputeWindow = 24 hours;
    /// @notice Fee percentage for validators (1% = 100 basis points)
    uint256 public constant FEE_BPS = 100; // 1% = 100/10000
    /// @notice Unstake delay after request
    uint256 public constant UNSTAKE_DELAY = 7 days;

    // ==================== Enums ====================

    /// @notice Type of validation required
    enum ValidationType {
        CODE_TEST,
        API_CHECK,
        FILE_HASH,
        MILESTONE
    }

    /// @notice Transaction status
    enum Status {
        LOCKED,
        VALIDATING,
        APPROVED,
        DISPUTED,
        REFUNDED,
        VALIDATION_TIMEOUT
    }

    /// @notice Dispute resolution outcome
    enum DisputeResolution {
        NONE,
        APPROVED,
        REJECTED
    }

    // ==================== Structs ====================

    /// @notice Transaction data structure
    struct Transaction {
        uint256 id;
        address partyA; // Party who locks funds
        address partyB; // Party who submits evidence
        uint256 amount; // USDC amount (6 decimals)
        bytes32 termsHash; // Hash of agreed terms
        ValidationType validationType;
        bytes32 evidenceHash; // Hash of submitted evidence bundle
        Status status;
        DisputeResolution disputeResolution;
        uint256 createdAt;
        uint256 deadline; // Evidence deadline
        uint256 validationEndsAt; // Validation deadline
        uint256 disputeEndsAt; // Dispute resolution deadline
        uint8 quorum; // Required number of approvals (1, 2, or 3)
        uint8 approvals;
        uint8 rejections;
    }

    /// @notice Validator data structure
    struct Validator {
        address agentAddress;
        uint256 stakedAmount;
        uint256 reputationScore;
        uint256 completedValidations;
        uint256 failedValidations;
        bool active;
    }

    /// @notice Vote data structure
    struct Vote {
        bool voted;
        bool approved;
        bytes32 evidenceHash;
        bool rewardClaimed;
    }

    // ==================== Storage ====================

    /// @notice Mapping of transaction ID to transaction data (use getTransaction() to read)
    mapping(uint256 => Transaction) internal transactions;
    /// @notice Mapping of validator address to validator data
    mapping(address => Validator) public validators;
    /// @notice Mapping of transaction ID -> validator address -> vote
    mapping(uint256 => mapping(address => Vote)) public votes;
    /// @notice Mapping of transaction ID to list of validators who voted
    mapping(uint256 => address[]) public voters;
    /// @notice Tracks when a validator requested unstake
    mapping(address => uint256) public unstakeRequestedAt;
    /// @notice Tracks number of active validations/disputes a validator is involved in
    mapping(address => uint256) public activeVotes;

    // ==================== Events ====================

    event TransactionLocked(
        uint256 indexed id, address indexed partyA, address indexed partyB, uint256 amount, uint8 quorum
    );
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

    // ==================== Modifiers ====================

    /// @notice Only party A or party B can execute
    modifier onlyParty(uint256 _id) {
        require(msg.sender == transactions[_id].partyA || msg.sender == transactions[_id].partyB, "NotParty");
        _;
    }

    /// @notice Only active validators can execute
    modifier onlyValidator() {
        require(validators[msg.sender].active, "NotValidator");
        _;
    }

    // ==================== Constructor ====================

    constructor(address _usdc, address _stakeToken, address _treasury) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_stakeToken != address(0), "Invalid stake token address");
        require(_treasury != address(0), "Invalid treasury address");

        usdc = IERC20(_usdc);
        stakeToken = IERC20(_stakeToken);
        treasury = _treasury;
    }

    // ==================== Core Functions ====================

    /**
     * @notice Lock USDC for a transaction that requires validation
     * @param partyB Address of counterparty who will submit evidence
     * @param amount Amount of USDC to lock (6 decimals)
     * @param termsHash Hash of agreed terms
     * @param validationType Type of validation required
     * @return id The transaction ID
     */
    function lockTransaction(address partyB, uint256 amount, bytes32 termsHash, ValidationType validationType)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 id)
    {
        require(amount > 0, "InvalidAmount");
        require(partyB != address(0) && partyB != msg.sender, "Invalid party B address");

        id = nextTransactionId++;
        uint8 quorum = _calcQuorum(amount);

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        Transaction storage tx_ = transactions[id];
        tx_.id = id;
        tx_.partyA = msg.sender;
        tx_.partyB = partyB;
        tx_.amount = amount;
        tx_.termsHash = termsHash;
        tx_.validationType = validationType;
        tx_.evidenceHash = bytes32(0);
        tx_.status = Status.LOCKED;
        tx_.disputeResolution = DisputeResolution.NONE;
        tx_.createdAt = block.timestamp;
        tx_.deadline = block.timestamp + evidenceWindow;
        tx_.validationEndsAt = 0;
        tx_.disputeEndsAt = 0;
        tx_.quorum = uint8(quorum);
        tx_.approvals = 0;
        tx_.rejections = 0;

        emit TransactionLocked(id, msg.sender, partyB, amount, quorum);
    }

    /**
     * @notice Submit evidence for validation (only partyB)
     * @param id Transaction ID
     * @param evidenceHash Hash of evidence bundle
     */
    function submitEvidence(uint256 id, bytes32 evidenceHash) external nonReentrant whenNotPaused {
        Transaction storage tx_ = transactions[id];

        require(tx_.partyB == msg.sender, "NotParty");
        require(tx_.status == Status.LOCKED, "InvalidStatus");
        require(block.timestamp <= tx_.deadline, "DeadlinePassed");
        require(evidenceHash != bytes32(0), "EvidenceMissing");

        tx_.evidenceHash = evidenceHash;
        tx_.status = Status.VALIDATING;
        tx_.validationEndsAt = block.timestamp + validationWindow;
        tx_.disputeEndsAt = block.timestamp + validationWindow + disputeWindow;

        emit EvidenceSubmitted(id, evidenceHash);
        emit ValidationNeeded(id, tx_.quorum, tx_.validationEndsAt);
    }

    /**
     * @notice Register as a validator with stake
     * @param stakeAmount Amount to stake
     */
    function registerValidator(uint256 stakeAmount) external nonReentrant whenNotPaused {
        require(stakeAmount >= minStake, "InsufficientStake");
        require(!validators[msg.sender].active, "Already registered");

        stakeToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        Validator storage validator = validators[msg.sender];
        validator.agentAddress = msg.sender;
        validator.stakedAmount = stakeAmount;
        validator.reputationScore = 100;
        validator.completedValidations = 0;
        validator.failedValidations = 0;
        validator.active = true;

        emit ValidatorRegistered(msg.sender, stakeAmount);
    }

    /**
     * @notice Submit validation vote (active validators only)
     * @param id Transaction ID
     * @param approved True if evidence is valid, false if rejected
     * @param evidenceHash Validator's evidence hash
     */
    function validate(uint256 id, bool approved, bytes32 evidenceHash)
        external
        nonReentrant
        whenNotPaused
        onlyValidator
    {
        Transaction storage tx_ = transactions[id];

        require(tx_.status == Status.VALIDATING, "InvalidStatus");
        require(block.timestamp <= tx_.validationEndsAt, "DeadlinePassed");
        require(!votes[id][msg.sender].voted, "AlreadyVoted");

        Vote storage vote = votes[id][msg.sender];
        vote.voted = true;
        vote.approved = approved;
        vote.evidenceHash = evidenceHash;
        vote.rewardClaimed = false;
        voters[id].push(msg.sender);
        activeVotes[msg.sender] += 1;

        if (approved) {
            tx_.approvals += 1;
        } else {
            tx_.rejections += 1;
        }

        emit ValidationSubmitted(id, msg.sender, approved, evidenceHash);

        _finalize(id);
    }

    /**
     * @notice Raise a dispute for a transaction
     * @param id Transaction ID
     * @param reason Reason for dispute
     */
    function dispute(uint256 id, string calldata reason) external nonReentrant whenNotPaused onlyParty(id) {
        Transaction storage tx_ = transactions[id];

        require(tx_.status == Status.VALIDATING || tx_.status == Status.LOCKED, "InvalidStatus");

        tx_.status = Status.DISPUTED;
        tx_.disputeEndsAt = block.timestamp + disputeWindow;

        emit TransactionDisputed(id, reason);
    }

    /**
     * @notice Claim validator reward for a completed transaction
     * @dev Only validators who voted correctly receive rewards
     * @param id Transaction ID
     */
    function claimReward(uint256 id) external nonReentrant {
        Transaction storage tx_ = transactions[id];

        require(
            tx_.status == Status.APPROVED
                || (tx_.status == Status.DISPUTED && tx_.disputeResolution != DisputeResolution.NONE),
            "Not claimable - not approved or resolved"
        );
        require(votes[id][msg.sender].voted, "Did not vote");
        require(!votes[id][msg.sender].rewardClaimed, "Already claimed");

        // Only correct voters receive rewards
        (uint256 totalFee, uint256 correctVoters) = _calculateRewardMetrics(id, tx_);

        bool shouldRewardApproval =
            tx_.status == Status.APPROVED || (tx_.disputeResolution == DisputeResolution.APPROVED);
        require(_isVoteCorrect(id, msg.sender, shouldRewardApproval), "Vote was incorrect");

        uint256 reward = totalFee / correctVoters;
        require(reward > 0, "No reward available");

        votes[id][msg.sender].rewardClaimed = true;

        usdc.safeTransfer(msg.sender, reward);

        emit RewardClaimed(id, msg.sender, reward);
    }

    /**
     * @notice Refund after timeout if no evidence submitted
     * @param id Transaction ID
     */
    function refundAfterTimeout(uint256 id) external nonReentrant {
        Transaction storage tx_ = transactions[id];

        require(tx_.status == Status.LOCKED, "InvalidStatus");
        require(block.timestamp > tx_.deadline, "DeadlinePassed");

        tx_.status = Status.REFUNDED;

        usdc.safeTransfer(tx_.partyA, tx_.amount);

        emit TransactionRefunded(id);
    }

    /**
     * @notice Handle validation timeout when quorum not reached
     * @param id Transaction ID
     */
    function finalizeAfterValidationTimeout(uint256 id) external nonReentrant {
        Transaction storage tx_ = transactions[id];

        require(tx_.status == Status.VALIDATING, "InvalidStatus");
        require(block.timestamp > tx_.validationEndsAt, "Validation not ended");

        tx_.status = Status.VALIDATION_TIMEOUT;

        usdc.safeTransfer(tx_.partyA, tx_.amount);

        _releaseActiveVotes(id);
        emit TransactionTimeout(id);
    }

    /**
     * @notice Refund after dispute timeout if dispute was never resolved
     * @param id Transaction ID
     */
    function refundAfterDisputeTimeout(uint256 id) external nonReentrant {
        Transaction storage tx_ = transactions[id];

        require(tx_.status == Status.DISPUTED, "InvalidStatus");
        require(block.timestamp > tx_.disputeEndsAt, "Dispute not ended");
        require(tx_.disputeResolution == DisputeResolution.NONE, "Dispute already resolved");

        tx_.status = Status.REFUNDED;

        usdc.safeTransfer(tx_.partyA, tx_.amount);

        _releaseActiveVotes(id);
        emit TransactionRefunded(id);
    }

    // ==================== Internal Functions ====================

    /**
     * @notice Calculate required quorum based on transaction amount
     * @param amount Transaction amount
     * @return Required number of validator approvals
     */
    function _calcQuorum(uint256 amount) internal pure returns (uint8) {
        if (amount < 100 * 1e6) {
            return 1; // <$100 = 1 validator
        } else if (amount <= 1000 * 1e6) {
            return 2; // $100 - $1000 = 2 validators
        } else {
            return 3; // >$1000 = 3 validators
        }
    }

    /**
     * @notice Finalize transaction based on voting results
     * @param id Transaction ID
     */
    function _finalize(uint256 id) internal {
        Transaction storage tx_ = transactions[id];

        // Prevent double finalization
        if (tx_.status != Status.VALIDATING) {
            return;
        }

        if (tx_.approvals == tx_.quorum) {
            // Approvals reached quorum
            tx_.status = Status.APPROVED;
            _releasePayment(id);
            _applyOutcomeToValidators(id, true);
            _releaseActiveVotes(id);
            emit TransactionApproved(id);
        } else if ((tx_.rejections >= 1 && tx_.quorum == 1) || (tx_.rejections == tx_.quorum)) {
            // Rejections meet threshold
            tx_.status = Status.DISPUTED;
            tx_.disputeEndsAt = block.timestamp + disputeWindow;
            string memory reason = tx_.quorum == 1 ? "Rejected by validator" : "Quorum rejected";
            emit TransactionDisputed(id, reason);
        }
    }

    /**
     * @notice Apply final outcome to validator stats and reputation
     * @param id Transaction ID
     * @param outcomeApproved Whether the final outcome was approval
     */
    function _applyOutcomeToValidators(uint256 id, bool outcomeApproved) internal {
        address[] storage votersList = voters[id];
        for (uint256 i = 0; i < votersList.length; i++) {
            _applyValidatorOutcomeSingle(id, votersList[i], outcomeApproved);
        }
    }

    /**
     * @notice Apply outcome to a single validator
     */
    function _applyValidatorOutcomeSingle(uint256 id, address validator, bool outcomeApproved) internal {
        bool approvedVote = votes[id][validator].approved;

        if (approvedVote == outcomeApproved) {
            validators[validator].completedValidations += 1;
            _updateReputation(validator, true);
        } else {
            validators[validator].failedValidations += 1;
            _updateReputation(validator, false);
        }
    }

    /**
     * @notice Release a validator's active-vote slots for a transaction
     * @dev Voters list is bounded by quorum (max 3)
     */
    function _releaseActiveVotes(uint256 id) internal {
        address[] storage votersList = voters[id];
        for (uint256 i = 0; i < votersList.length; i++) {
            address voter = votersList[i];
            uint256 current = activeVotes[voter];
            if (current > 0) {
                activeVotes[voter] = current - 1;
            }
        }
    }

    /**
     * @notice Release payment to partyB on approval (fee stays in contract for validators)
     * @param id Transaction ID
     */
    function _releasePayment(uint256 id) internal {
        Transaction storage tx_ = transactions[id];

        uint256 fee = (tx_.amount * FEE_BPS) / 10000;
        uint256 payment = tx_.amount - fee;

        // Fee stays in contract for validator rewards (claimed via claimReward)
        usdc.safeTransfer(tx_.partyB, payment);
    }

    /**
     * @notice Update validator reputation with clamping to [0, 100]
     * @param validator Validator address
     * @param approvedCorrectly True if validator voted correctly
     */
    function _updateReputation(address validator, bool approvedCorrectly) internal {
        Validator storage v = validators[validator];
        uint256 currentScore = v.reputationScore;

        if (approvedCorrectly) {
            if (currentScore + 5 > 100) {
                v.reputationScore = 100;
            } else {
                v.reputationScore = currentScore + 5;
            }
        } else {
            if (currentScore > 10) {
                v.reputationScore = currentScore - 10;
            } else {
                v.reputationScore = 0;
            }
        }
    }

    /**
     * @notice Calculate reward metrics for fee distribution
     * @param id Transaction ID
     * @param tx_ Transaction storage reference
     * @return totalFee Total fee amount
     * @return correctVoters Number of voters who voted correctly
     */
    function _calculateRewardMetrics(uint256 id, Transaction storage tx_)
        internal
        view
        returns (uint256 totalFee, uint256 correctVoters)
    {
        totalFee = (tx_.amount * FEE_BPS) / 10000;

        bool shouldRewardApproval =
            tx_.status == Status.APPROVED || (tx_.disputeResolution == DisputeResolution.APPROVED);

        correctVoters = _countCorrectVoters(id, shouldRewardApproval);
    }

    /**
     * @notice Count voters who voted correctly
     */
    function _countCorrectVoters(uint256 id, bool shouldRewardApproval) internal view returns (uint256 count) {
        address[] storage votersList = voters[id];
        for (uint256 i = 0; i < votersList.length; i++) {
            if (_isVoteCorrect(id, votersList[i], shouldRewardApproval)) {
                count++;
            }
        }
    }

    /**
     * @notice Check if a validator's vote matches the final outcome
     */
    function _isVoteCorrect(uint256 id, address validator, bool shouldRewardApproval) internal view returns (bool) {
        bool approvedVote = votes[id][validator].approved;
        return (shouldRewardApproval && approvedVote) || (!shouldRewardApproval && !approvedVote);
    }

    /// @notice Pause the contract (owner only)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract (owner only)
    function unpause() external onlyOwner {
        _unpause();
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Slash a validator: 50% to treasury, 50% returned
     * @dev Returns remaining stake before deactivating to prevent trapping
     * @param validator Validator address
     */
    function slashValidator(address validator) external onlyOwner {
        require(validators[validator].active, "NotValidator");

        uint256 slashAmount = validators[validator].stakedAmount / 2;
        uint256 remaining = validators[validator].stakedAmount - slashAmount;

        // Transfer remaining stake first (if this fails, validator stays active)
        if (remaining > 0) {
            stakeToken.safeTransfer(validator, remaining);
        }

        validators[validator].stakedAmount = 0;
        validators[validator].reputationScore = 0;
        validators[validator].active = false;

        stakeToken.safeTransfer(treasury, slashAmount);

        emit ValidatorSlashed(validator, slashAmount);
    }

    /**
     * @notice Resolve a disputed transaction (owner only)
     * @param id Transaction ID
     * @param resolution APPROVED (pay partyB) or REJECTED (refund partyA)
     */
    function resolveDispute(uint256 id, DisputeResolution resolution) external onlyOwner {
        Transaction storage tx_ = transactions[id];
        require(tx_.status == Status.DISPUTED, "Transaction not disputed");
        require(resolution != DisputeResolution.NONE, "Invalid resolution");
        require(tx_.disputeResolution == DisputeResolution.NONE, "Already resolved");

        tx_.disputeResolution = resolution;

        if (resolution == DisputeResolution.APPROVED) {
            tx_.status = Status.APPROVED;
            _releasePayment(id);
            emit TransactionApproved(id);
        } else {
            tx_.status = Status.REFUNDED;
            usdc.safeTransfer(tx_.partyA, tx_.amount);
            emit TransactionRefunded(id);
        }

        _applyOutcomeToValidators(id, resolution == DisputeResolution.APPROVED);
        _releaseActiveVotes(id);
        emit DisputeResolved(id, resolution);
    }

    /**
     * @notice Request unstake (starts 7-day cooldown)
     */
    function requestUnstake() external onlyValidator {
        Validator storage v = validators[msg.sender];
        require(v.stakedAmount > 0, "No stake");
        unstakeRequestedAt[msg.sender] = block.timestamp;
        emit UnstakeRequested(msg.sender, block.timestamp);
    }

    /**
     * @notice Unstake after cooldown if no active validations/disputes
     */
    function unstake() external nonReentrant onlyValidator {
        uint256 requestedAt = unstakeRequestedAt[msg.sender];
        require(requestedAt > 0, "No unstake request");
        require(block.timestamp >= requestedAt + UNSTAKE_DELAY, "Unstake period not met");
        require(activeVotes[msg.sender] == 0, "Active validation/dispute pending");

        Validator storage v = validators[msg.sender];
        uint256 amount = v.stakedAmount;
        require(amount > 0, "No stake");

        v.stakedAmount = 0;
        v.active = false;
        unstakeRequestedAt[msg.sender] = 0;

        stakeToken.safeTransfer(msg.sender, amount);
        emit ValidatorUnstaked(msg.sender, amount);
    }

    /**
     * @notice Update treasury address (owner only)
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    /**
     * @notice Update time windows (owner only)
     */
    function setWindows(uint256 _validationWindow, uint256 _evidenceWindow, uint256 _disputeWindow) external onlyOwner {
        validationWindow = _validationWindow;
        evidenceWindow = _evidenceWindow;
        disputeWindow = _disputeWindow;
        emit WindowsUpdated(_validationWindow, _evidenceWindow, _disputeWindow);
    }

    /**
     * @notice Update minimum stake (owner only)
     * @param newMinStake New minimum stake amount
     */
    function setMinStake(uint256 newMinStake) external onlyOwner {
        require(newMinStake > 0, "Invalid min stake");
        minStake = newMinStake;
        emit MinStakeUpdated(newMinStake);
    }

    // ==================== View Functions ====================

    function getTransaction(uint256 id) external view returns (Transaction memory) {
        return transactions[id];
    }

    function getValidator(address validator) external view returns (Validator memory) {
        return validators[validator];
    }

    function getVoters(uint256 id) external view returns (address[] memory) {
        return voters[id];
    }

    function getVote(uint256 id, address validator) external view returns (Vote memory) {
        return votes[id][validator];
    }

    function getQuorum(uint256 amount) external pure returns (uint8) {
        return _calcQuorum(amount);
    }
}
