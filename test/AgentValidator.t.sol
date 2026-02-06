// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {AgentValidator} from "../src/AgentValidator.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract AgentValidatorTest is Test {
    AgentValidator public agentValidator;
    ERC20Mock public usdc;
    ERC20Mock public stakeToken;

    address public owner = address(0x1);
    address public partyA = address(0x2);
    address public partyB = address(0x3);
    address public validator1 = address(0x4);
    address public validator2 = address(0x5);
    address public validator3 = address(0x6);
    address public treasury = address(0x7);

    uint256 public constant IERC20_AMOUNT = 1000 * 1e6; // 1000 IERC20
    uint256 public constant MIN_STAKE = 100 * 1e6; // 100 IERC20

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        usdc = new ERC20Mock("USD Coin", "IERC20", 6);
        stakeToken = new ERC20Mock("Stake Token", "STAKE", 6);

        // Deploy contract
        agentValidator = new AgentValidator(address(usdc), address(stakeToken), treasury);

        vm.stopPrank();

        // Fund parties with IERC20
        deal(address(usdc), partyA, 10000 * 1e6);
        deal(address(usdc), partyB, 10000 * 1e6);

        // Fund validators with stake tokens
        deal(address(stakeToken), validator1, 1000 * 1e6);
        deal(address(stakeToken), validator2, 1000 * 1e6);
        deal(address(stakeToken), validator3, 1000 * 1e6);

        // Register validators
        vm.startPrank(validator1);
        stakeToken.approve(address(agentValidator), MIN_STAKE);
        agentValidator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(validator2);
        stakeToken.approve(address(agentValidator), MIN_STAKE);
        agentValidator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(validator3);
        stakeToken.approve(address(agentValidator), MIN_STAKE);
        agentValidator.registerValidator(MIN_STAKE);
        vm.stopPrank();
    }

    // ==================== Lock Transaction Tests ====================

    function test_LockTransaction() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);

        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );

        vm.stopPrank();

        // Verify transaction is locked
        AgentValidator.Transaction memory txData = agentValidator.getTransaction(txId);

        assertEq(txData.partyA, partyA);
        assertEq(txData.partyB, partyB);
        assertEq(txData.amount, IERC20_AMOUNT);
        assertEq(txData.termsHash, keccak256("terms"));
        assertEq(uint8(txData.validationType), uint8(AgentValidator.ValidationType.CODE_TEST));
        assertEq(txData.evidenceHash, bytes32(0));
        assertEq(uint8(txData.status), uint8(AgentValidator.Status.LOCKED));
        assertGt(txData.createdAt, 0);
        assertGt(txData.deadline, txData.createdAt);
        assertEq(txData.quorum, 2); // $100-$1000 requires 2 validators
        assertEq(txData.approvals, 0);
        assertEq(txData.rejections, 0);
    }

    function test_DynamicQuorum() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6); // <$100

        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);

        vm.stopPrank();

        // Verify quorum = 1 for <$100
        assertEq(agentValidator.getTransaction(txId).quorum, 1);

        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 500 * 1e6); // $500-$1000

        txId = agentValidator.lockTransaction(
            partyB, 500 * 1e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );

        vm.stopPrank();

        // Verify quorum = 2 for $500-$1000
        assertEq(agentValidator.getTransaction(txId).quorum, 2);

        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 1500 * 1e6); // >$1000

        txId = agentValidator.lockTransaction(
            partyB, 1500 * 1e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );

        vm.stopPrank();

        // Verify quorum = 3 for >$1000
        assertEq(agentValidator.getTransaction(txId).quorum, 3);
    }

    function test_LockTransaction_InvalidAmount() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);

        vm.expectRevert(bytes("InvalidAmount"));
        agentValidator.lockTransaction(
            partyB,
            0, // Invalid: 0 amount
            keccak256("terms"),
            AgentValidator.ValidationType.CODE_TEST
        );
    }

    function test_LockTransaction_InvalidParty() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);

        vm.expectRevert(bytes("Invalid party B address"));
        agentValidator.lockTransaction(
            address(0), // Invalid: zero address
            IERC20_AMOUNT,
            keccak256("terms"),
            AgentValidator.ValidationType.CODE_TEST
        );
    }

    // ==================== Submit Evidence Tests ====================

    function test_SubmitEvidence() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Verify status changed to VALIDATING
        AgentValidator.Transaction memory txData = agentValidator.getTransaction(txId);
        assertEq(uint8(txData.status), uint8(AgentValidator.Status.VALIDATING));
        assertEq(txData.evidenceHash, keccak256("evidence"));
        assertGt(txData.validationEndsAt, 0);
    }

    function test_SubmitEvidence_NotParty() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("NotParty"));
        vm.startPrank(validator1);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
    }

    function test_SubmitEvidence_NotLocked() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Try to submit evidence again
        vm.expectRevert(bytes("InvalidStatus"));
        agentValidator.submitEvidence(txId, keccak256("evidence2"));
    }

    function test_SubmitEvidence_DeadlinePassed() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        // Warp past evidence deadline (without submitting evidence first)
        vm.warp(agentValidator.getTransaction(txId).deadline + 1);

        vm.startPrank(partyB);
        vm.expectRevert(bytes("DeadlinePassed"));
        agentValidator.submitEvidence(txId, keccak256("evidence"));
    }

    function test_SubmitEvidence_EvidenceMissing() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("EvidenceMissing"));
        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, bytes32(0));
    }

    // ==================== Register Validator Tests ====================

    function test_RegisterValidator() public {
        address newValidator = address(0x100);
        vm.startPrank(owner);
        deal(address(stakeToken), newValidator, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(newValidator);
        stakeToken.approve(address(agentValidator), MIN_STAKE);

        agentValidator.registerValidator(MIN_STAKE);

        // Verify validator is registered
        AgentValidator.Validator memory valData = agentValidator.getValidator(newValidator);
        assertEq(valData.agentAddress, newValidator);
        assertEq(valData.stakedAmount, MIN_STAKE);
        assertEq(valData.reputationScore, 100); // Starting score
        assert(valData.active);
    }

    function test_RegisterValidator_InsufficientStake() public {
        address newValidator = address(0x100);
        vm.startPrank(owner);
        deal(address(stakeToken), newValidator, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(newValidator);
        stakeToken.approve(address(agentValidator), MIN_STAKE - 1);

        vm.expectRevert(bytes("InsufficientStake"));
        agentValidator.registerValidator(MIN_STAKE - 1);
    }

    function test_RegisterValidator_AlreadyRegistered() public {
        vm.startPrank(validator1);
        stakeToken.approve(address(agentValidator), MIN_STAKE);
        vm.expectRevert(bytes("Already registered"));
        agentValidator.registerValidator(MIN_STAKE);
    }

    // ==================== Validate Tests ====================

    function test_Validate_Approve() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // First validator approves
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // Verify transaction status is still VALIDATING (quorum not met)
        AgentValidator.Transaction memory txData = agentValidator.getTransaction(txId);
        assertEq(uint8(txData.status), uint8(AgentValidator.Status.VALIDATING));
        assertEq(txData.approvals, 1);
        assertEq(txData.rejections, 0);
    }

    function test_Validate_Reject() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // First validator rejects
        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));

        // Verify transaction status is still VALIDATING (quorum not met)
        AgentValidator.Transaction memory txData = agentValidator.getTransaction(txId);
        assertEq(uint8(txData.status), uint8(AgentValidator.Status.VALIDATING));
        assertEq(txData.approvals, 0);
        assertEq(txData.rejections, 1);
    }

    function test_Validate_NotValidator() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        vm.expectRevert(bytes("NotValidator"));
        vm.startPrank(address(0x999));
        agentValidator.validate(txId, true, keccak256("evidence"));
    }

    function test_Validate_NotVoting() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("InvalidStatus"));
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));
    }

    function test_Validate_DeadlinePassed() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Warp past validation deadline
        vm.warp(agentValidator.getTransaction(txId).validationEndsAt + 1);

        vm.expectRevert(bytes("DeadlinePassed"));
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));
    }

    function test_Validate_AlreadyVoted() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // Try to vote again
        vm.expectRevert(bytes("AlreadyVoted"));
        agentValidator.validate(txId, true, keccak256("evidence"));
    }

    function test_Finalize_Approved() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // First validator approves
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // Second validator approves (quorum met)
        vm.startPrank(validator2);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // Verify transaction is approved
        AgentValidator.Transaction memory txData = agentValidator.getTransaction(txId);
        assertEq(uint8(txData.status), uint8(AgentValidator.Status.APPROVED));
        assertEq(txData.approvals, 2);
        assertEq(txData.rejections, 0);
    }

    function test_Finalize_Rejected() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Both validators reject (quorum met)
        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));

        vm.startPrank(validator2);
        agentValidator.validate(txId, false, keccak256("evidence"));

        // Verify transaction is disputed
        AgentValidator.Transaction memory txData = agentValidator.getTransaction(txId);
        assertEq(uint8(txData.status), uint8(AgentValidator.Status.DISPUTED));
        assertEq(txData.approvals, 0);
        assertEq(txData.rejections, 2);
    }

    // ==================== Claim Reward Tests ====================

    function test_ClaimReward_SingleValidator() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6); // <$100 = quorum 1
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Single validator approves (quorum = 1 for <$100)
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // Verify validator can claim reward
        uint256 balBefore = usdc.balanceOf(validator1);
        agentValidator.claimReward(txId);
        uint256 balAfter = usdc.balanceOf(validator1);

        // Single correct voter gets full 1% fee
        uint256 expectedReward = 10e6 * agentValidator.FEE_BPS() / 10000;
        assertEq(balAfter - balBefore, expectedReward);
    }

    function test_ClaimReward_MultipleValidators() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 500 * 1e6); // $500 - requires 2 validators
        uint256 txId = agentValidator.lockTransaction(
            partyB, 500 * 1e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Both validators approve (quorum met)
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        vm.startPrank(validator2);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // Each correct validator claims their share (1% fee / 2)
        uint256 expectedReward = (500 * 1e6 * agentValidator.FEE_BPS() / 10000) / 2;

        // Validator 1 claims
        uint256 bal1Before = usdc.balanceOf(validator1);
        vm.startPrank(validator1);
        agentValidator.claimReward(txId);
        uint256 bal1After = usdc.balanceOf(validator1);
        assertEq(bal1After - bal1Before, expectedReward);

        // Validator 2 claims
        uint256 bal2Before = usdc.balanceOf(validator2);
        vm.startPrank(validator2);
        agentValidator.claimReward(txId);
        uint256 bal2After = usdc.balanceOf(validator2);
        assertEq(bal2After - bal2Before, expectedReward);
    }

    function test_ClaimReward_AlreadyClaimed() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6); // <$100 = quorum 1
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        // First claim
        agentValidator.claimReward(txId);

        // Try to claim again (should fail)
        vm.expectRevert(bytes("Already claimed"));
        agentValidator.claimReward(txId);
    }

    function test_ClaimReward_NotVoted() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6); // <$100 = quorum 1
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        // Approve with validator1 (quorum=1, so transaction becomes APPROVED)
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));
        vm.stopPrank();

        // validator2 did NOT vote, so claiming should fail
        vm.startPrank(validator2);
        vm.expectRevert(bytes("Did not vote"));
        agentValidator.claimReward(txId);
    }

    function test_ClaimReward_WrongStatus() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("Not claimable - not approved or resolved"));
        vm.startPrank(validator1);
        agentValidator.claimReward(txId);
    }

    // ==================== Timeout Tests ====================

    function test_RefundAfterTimeout() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        // Warp past deadline
        vm.warp(agentValidator.getTransaction(txId).deadline + 1);

        uint256 balBefore = usdc.balanceOf(partyA);
        vm.startPrank(partyA);
        agentValidator.refundAfterTimeout(txId);
        uint256 balAfter = usdc.balanceOf(partyA);

        // Verify refund
        assertEq(balAfter - balBefore, IERC20_AMOUNT);
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.REFUNDED));
    }

    function test_RefundAfterTimeout_NotLocked() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        vm.expectRevert(bytes("InvalidStatus"));
        vm.startPrank(partyA);
        agentValidator.refundAfterTimeout(txId);
    }

    function test_FinalizeAfterValidationTimeout() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        // Warp past validation deadline (quorum not reached)
        vm.warp(agentValidator.getTransaction(txId).validationEndsAt + 1);

        uint256 balBefore = usdc.balanceOf(partyA);
        vm.startPrank(partyA);
        agentValidator.finalizeAfterValidationTimeout(txId);
        uint256 balAfter = usdc.balanceOf(partyA);

        // Verify refund when validation times out
        assertEq(balAfter - balBefore, IERC20_AMOUNT);
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.VALIDATION_TIMEOUT));
    }

    function test_FinalizeAfterValidationTimeout_NotValidating() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("InvalidStatus"));
        vm.startPrank(partyA);
        agentValidator.finalizeAfterValidationTimeout(txId);
    }

    function test_FinalizeAfterValidationTimeout_NotEnded() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        vm.expectRevert(bytes("Validation not ended"));
        vm.startPrank(partyA);
        agentValidator.finalizeAfterValidationTimeout(txId);
    }

    // ==================== Dispute Tests ====================

    function test_Dispute_Locked() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        // Can dispute while locked
        vm.startPrank(partyA);
        agentValidator.dispute(txId, "Test dispute");

        // Verify disputed
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.DISPUTED));
    }

    function test_Dispute_Validating() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Can dispute while validating
        vm.startPrank(partyA);
        agentValidator.dispute(txId, "Test dispute");

        // Verify disputed
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.DISPUTED));
        assertGt(agentValidator.getTransaction(txId).disputeEndsAt, 0);
    }

    function test_Dispute_NotParty() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("NotParty"));
        vm.startPrank(validator1);
        agentValidator.dispute(txId, "Test");
    }

    function test_Dispute_NotValidatingOrLocked() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6); // <$100 = quorum 1
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Approve transaction (quorum met)
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));

        vm.expectRevert(bytes("InvalidStatus"));
        vm.startPrank(partyA);
        agentValidator.dispute(txId, "Test");
    }

    function test_RefundAfterDisputeTimeout() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Dispute the transaction
        vm.startPrank(partyA);
        agentValidator.dispute(txId, "Test dispute");

        // Warp past dispute deadline
        vm.warp(agentValidator.getTransaction(txId).disputeEndsAt + 1);

        uint256 balBefore = usdc.balanceOf(partyA);
        vm.startPrank(partyA);
        agentValidator.refundAfterDisputeTimeout(txId);
        uint256 balAfter = usdc.balanceOf(partyA);

        // Verify refund after dispute timeout
        assertEq(balAfter - balBefore, IERC20_AMOUNT);
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.REFUNDED));
    }

    function test_RefundAfterDisputeTimeout_NotDisputed() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.expectRevert(bytes("InvalidStatus"));
        vm.startPrank(partyA);
        agentValidator.refundAfterDisputeTimeout(txId);
    }

    function test_RefundAfterDisputeTimeout_NotEnded() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));

        // Dispute the transaction
        vm.startPrank(partyA);
        agentValidator.dispute(txId, "Test dispute");

        vm.expectRevert(bytes("Dispute not ended"));
        agentValidator.refundAfterDisputeTimeout(txId);
    }

    // ==================== Reputation Tests ====================

    function test_Reputation_CorrectVoteKeepsCap() public {
        // Score starts at 100 (the cap). Correct vote adds +5 but is capped at 100.
        assertEq(agentValidator.getValidator(validator1).reputationScore, 100);

        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6); // <$100 = quorum 1
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        // Validator1 votes correctly (approve) -> quorum met -> finalized with outcome=approved
        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));
        vm.stopPrank();

        // Reputation stays at 100 (capped) after correct vote
        assertEq(agentValidator.getValidator(validator1).reputationScore, 100);
        assertEq(agentValidator.getValidator(validator1).completedValidations, 1);
    }

    function test_Reputation_IncorrectVoteDecreases() public {
        assertEq(agentValidator.getValidator(validator1).reputationScore, 100);

        // Use $500 = quorum 2 so we can have one correct + one incorrect voter
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 500 * 1e6);
        uint256 txId = agentValidator.lockTransaction(
            partyB, 500 * 1e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        // Validator1 rejects (incorrect - outcome will be approved)
        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));
        vm.stopPrank();

        // Validator2 approves
        vm.startPrank(validator2);
        agentValidator.validate(txId, true, keccak256("evidence"));
        vm.stopPrank();

        // Quorum not yet met for approval (need 2 approvals), but rejections=1 < quorum=2
        // So status is still VALIDATING. Let validator3 approve to reach quorum.
        vm.startPrank(validator3);
        agentValidator.validate(txId, true, keccak256("evidence"));
        vm.stopPrank();

        // Now 2 approvals = quorum met -> APPROVED
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.APPROVED));

        // Validator1 voted incorrectly (rejected when outcome was approved) -> reputation -10
        assertEq(agentValidator.getValidator(validator1).reputationScore, 90);
        assertEq(agentValidator.getValidator(validator1).failedValidations, 1);

        // Validator2 voted correctly -> reputation stays 100 (capped)
        assertEq(agentValidator.getValidator(validator2).reputationScore, 100);
        assertEq(agentValidator.getValidator(validator2).completedValidations, 1);
    }

    // ==================== Pause/Unpause Tests ====================

    function test_Pause() public {
        vm.startPrank(owner);
        agentValidator.pause();
        vm.stopPrank();

        // Verify paused by trying to lock transaction (should fail)
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        vm.expectRevert();
        agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
    }

    function test_Unpause() public {
        vm.startPrank(owner);
        agentValidator.pause();
        agentValidator.unpause();
        vm.stopPrank();

        // Verify unpaused by locking a transaction
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        // Will fail due to no approval error, but different from Pausable error
        agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
    }

    function test_Pause_NotOwner() public {
        vm.expectRevert();
        vm.startPrank(validator1);
        agentValidator.pause();
    }

    function test_Unpause_NotOwner() public {
        vm.expectRevert();
        vm.startPrank(validator1);
        agentValidator.unpause();
    }

    // ==================== Slash Tests ====================

    function test_SlashValidator() public {
        uint256 expectedSlashed = MIN_STAKE / 2; // 50% slash
        uint256 expectedReturned = MIN_STAKE - expectedSlashed;

        uint256 stakeBefore = stakeToken.balanceOf(validator1);
        uint256 treasuryBefore = stakeToken.balanceOf(treasury);

        vm.startPrank(owner);
        agentValidator.slashValidator(validator1);

        uint256 stakeAfter = stakeToken.balanceOf(validator1);
        uint256 treasuryAfter = stakeToken.balanceOf(treasury);

        // Verify slash
        assertEq(stakeAfter - stakeBefore, expectedReturned);
        assertEq(treasuryAfter - treasuryBefore, expectedSlashed);
        assertEq(stakeToken.balanceOf(validator1) - stakeBefore, expectedReturned);

        // Verify validator deactivated
        AgentValidator.Validator memory valData = agentValidator.getValidator(validator1);
        assertEq(valData.stakedAmount, 0);
        assertEq(valData.reputationScore, 0);
        assert(!valData.active);
    }

    function test_SlashValidator_NotValidator() public {
        vm.expectRevert(bytes("NotValidator"));
        vm.startPrank(owner);
        agentValidator.slashValidator(address(0x999));
    }

    // ==================== Resolve Dispute Tests ====================

    function test_ResolveDispute_Approved() public {
        // Lock + evidence + reject to get DISPUTED status
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6);
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        // Single validator rejects (quorum=1 -> DISPUTED)
        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));
        vm.stopPrank();

        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.DISPUTED));

        // Owner resolves dispute in favor of partyB (APPROVED)
        uint256 balBefore = usdc.balanceOf(partyB);
        vm.startPrank(owner);
        agentValidator.resolveDispute(txId, AgentValidator.DisputeResolution.APPROVED);
        vm.stopPrank();

        uint256 balAfter = usdc.balanceOf(partyB);
        uint256 expectedPayment = 10e6 - (10e6 * 100 / 10000); // amount - 1% fee
        assertEq(balAfter - balBefore, expectedPayment);
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.APPROVED));
    }

    function test_ResolveDispute_Rejected() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6);
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));
        vm.stopPrank();

        // Owner resolves dispute in favor of partyA (REJECTED = refund)
        uint256 balBefore = usdc.balanceOf(partyA);
        vm.startPrank(owner);
        agentValidator.resolveDispute(txId, AgentValidator.DisputeResolution.REJECTED);
        vm.stopPrank();

        uint256 balAfter = usdc.balanceOf(partyA);
        assertEq(balAfter - balBefore, 10e6);
        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.REFUNDED));
    }

    function test_ResolveDispute_NotDisputed() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(bytes("Transaction not disputed"));
        agentValidator.resolveDispute(txId, AgentValidator.DisputeResolution.APPROVED);
    }

    function test_ResolveDispute_AlreadyResolved() public {
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 10e6);
        uint256 txId =
            agentValidator.lockTransaction(partyB, 10e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST);
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));
        vm.stopPrank();

        vm.startPrank(owner);
        agentValidator.resolveDispute(txId, AgentValidator.DisputeResolution.REJECTED);

        // Try to resolve again
        vm.expectRevert(bytes("Transaction not disputed"));
        agentValidator.resolveDispute(txId, AgentValidator.DisputeResolution.APPROVED);
    }

    // ==================== Claim Reward (Incorrect Vote) Tests ====================

    function test_ClaimReward_IncorrectVoteRejected() public {
        // Use $500 = quorum 2 so we can have one correct + one incorrect voter
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), 500 * 1e6);
        uint256 txId = agentValidator.lockTransaction(
            partyB, 500 * 1e6, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        // Validator1 rejects (will be incorrect when transaction is approved)
        vm.startPrank(validator1);
        agentValidator.validate(txId, false, keccak256("evidence"));
        vm.stopPrank();

        // Validator2 and validator3 approve (quorum met)
        vm.startPrank(validator2);
        agentValidator.validate(txId, true, keccak256("evidence"));
        vm.stopPrank();

        vm.startPrank(validator3);
        agentValidator.validate(txId, true, keccak256("evidence"));
        vm.stopPrank();

        assertEq(uint8(agentValidator.getTransaction(txId).status), uint8(AgentValidator.Status.APPROVED));

        // Incorrect voter cannot claim
        vm.startPrank(validator1);
        vm.expectRevert(bytes("Vote was incorrect"));
        agentValidator.claimReward(txId);
    }

    // ==================== Unstake Tests ====================

    function test_RequestUnstake() public {
        vm.startPrank(validator1);
        agentValidator.requestUnstake();
        vm.stopPrank();

        assertGt(agentValidator.unstakeRequestedAt(validator1), 0);
    }

    function test_Unstake_Success() public {
        vm.startPrank(validator1);
        agentValidator.requestUnstake();
        vm.stopPrank();

        // Warp past the 7-day cooldown
        vm.warp(block.timestamp + 7 days + 1);

        uint256 balBefore = stakeToken.balanceOf(validator1);
        vm.startPrank(validator1);
        agentValidator.unstake();
        uint256 balAfter = stakeToken.balanceOf(validator1);

        assertEq(balAfter - balBefore, MIN_STAKE);
        assertEq(agentValidator.getValidator(validator1).active, false);
        assertEq(agentValidator.getValidator(validator1).stakedAmount, 0);
    }

    function test_Unstake_TooEarly() public {
        vm.startPrank(validator1);
        agentValidator.requestUnstake();

        // Try unstaking before cooldown
        vm.expectRevert(bytes("Unstake period not met"));
        agentValidator.unstake();
    }

    function test_Unstake_NoRequest() public {
        vm.startPrank(validator1);
        vm.expectRevert(bytes("No unstake request"));
        agentValidator.unstake();
    }

    function test_Unstake_ActiveVotesPending() public {
        // Create a transaction and have validator1 vote (creates activeVotes)
        vm.startPrank(partyA);
        usdc.approve(address(agentValidator), IERC20_AMOUNT);
        uint256 txId = agentValidator.lockTransaction(
            partyB, IERC20_AMOUNT, keccak256("terms"), AgentValidator.ValidationType.CODE_TEST
        );
        vm.stopPrank();

        vm.startPrank(partyB);
        agentValidator.submitEvidence(txId, keccak256("evidence"));
        vm.stopPrank();

        vm.startPrank(validator1);
        agentValidator.validate(txId, true, keccak256("evidence"));
        agentValidator.requestUnstake();
        vm.stopPrank();

        // Warp past cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Should fail because active validation pending (quorum not yet met)
        vm.startPrank(validator1);
        vm.expectRevert(bytes("Active validation/dispute pending"));
        agentValidator.unstake();
    }

    // ==================== Admin Setter Tests ====================

    function test_SetTreasury() public {
        address newTreasury = address(0x99);
        vm.startPrank(owner);
        agentValidator.setTreasury(newTreasury);
        vm.stopPrank();

        assertEq(agentValidator.treasury(), newTreasury);
    }

    function test_SetTreasury_ZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("Invalid treasury address"));
        agentValidator.setTreasury(address(0));
    }

    function test_SetTreasury_NotOwner() public {
        vm.startPrank(validator1);
        vm.expectRevert();
        agentValidator.setTreasury(address(0x99));
    }

    function test_SetWindows() public {
        vm.startPrank(owner);
        agentValidator.setWindows(2 hours, 48 hours, 48 hours);
        vm.stopPrank();

        assertEq(agentValidator.validationWindow(), 2 hours);
        assertEq(agentValidator.evidenceWindow(), 48 hours);
        assertEq(agentValidator.disputeWindow(), 48 hours);
    }

    function test_SetWindows_NotOwner() public {
        vm.startPrank(validator1);
        vm.expectRevert();
        agentValidator.setWindows(2 hours, 48 hours, 48 hours);
    }

    function test_SetMinStake() public {
        vm.startPrank(owner);
        agentValidator.setMinStake(200 * 1e6);
        vm.stopPrank();

        assertEq(agentValidator.minStake(), 200 * 1e6);
    }

    function test_SetMinStake_Zero() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("Invalid min stake"));
        agentValidator.setMinStake(0);
    }

    function test_SetMinStake_NotOwner() public {
        vm.startPrank(validator1);
        vm.expectRevert();
        agentValidator.setMinStake(200 * 1e6);
    }
}
