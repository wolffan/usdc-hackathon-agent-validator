// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {AgentValidator} from "../src/AgentValidator.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract SlashSecurityTest is Test {
    AgentValidator public validator;
    ERC20Mock public usdc;
    ERC20Mock public stakeToken;
    address public treasury = address(0x123);
    address public owner = address(this);

    address public partyA = address(0xA);
    address public partyB = address(0xB);
    address public validator1 = address(0x1);
    address public validator2 = address(0x2);
    address public validator3 = address(0x3);

    uint256 constant INITIAL_MINT = 1_000_000 * 1e6; // 1M USDC
    uint256 constant MIN_STAKE = 100 * 1e6; // 100 USDC
    uint256 constant TEST_AMOUNT = 500 * 1e6; // 500 USDC

    bytes32 constant TERMS_HASH = keccak256("test terms");
    bytes32 constant EVIDENCE_HASH = keccak256("test evidence");

    function setUp() public {
        // Deploy mock tokens
        usdc = new ERC20Mock("USD Coin", "USDC", 6);
        stakeToken = new ERC20Mock("Stake Token", "STAKE", 6);

        // Deploy contract
        validator = new AgentValidator(address(usdc), address(stakeToken), treasury);

        // Mint tokens
        usdc.mint(partyA, INITIAL_MINT);
        usdc.mint(partyB, INITIAL_MINT);
        stakeToken.mint(validator1, INITIAL_MINT);
        stakeToken.mint(validator2, INITIAL_MINT);
        stakeToken.mint(validator3, INITIAL_MINT);

        // Approve spending
        vm.startPrank(partyA);
        usdc.approve(address(validator), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(partyB);
        usdc.approve(address(validator), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(validator1);
        stakeToken.approve(address(validator), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(validator2);
        stakeToken.approve(address(validator), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(validator3);
        stakeToken.approve(address(validator), type(uint256).max);
        vm.stopPrank();
    }

    function test_SlashValidator_WithActiveVotes_Reverts() public {
        // Register validators
        vm.startPrank(validator1);
        validator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(validator2);
        validator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        // Lock transaction (requires 2 validators for $500)
        vm.startPrank(partyA);
        uint256 txId = validator.lockTransaction(partyB, TEST_AMOUNT, TERMS_HASH, AgentValidator.ValidationType.MILESTONE);
        vm.stopPrank();

        // Submit evidence
        vm.startPrank(partyB);
        validator.submitEvidence(txId, EVIDENCE_HASH);
        vm.stopPrank();

        // Validator1 votes (now has active vote)
        vm.startPrank(validator1);
        validator.validate(txId, true, keccak256("evidence1"));
        vm.stopPrank();

        // Try to slash validator1 while they have active votes
        vm.expectRevert("Validator has active votes");
        validator.slashValidator(validator1);
    }

    function test_SlashValidator_NoActiveVotes_Success() public {
        // Register validator
        vm.startPrank(validator1);
        validator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        // Lock transaction
        vm.startPrank(partyA);
        uint256 txId = validator.lockTransaction(partyB, TEST_AMOUNT, TERMS_HASH, AgentValidator.ValidationType.MILESTONE);
        vm.stopPrank();

        // Submit evidence
        vm.startPrank(partyB);
        validator.submitEvidence(txId, EVIDENCE_HASH);
        vm.stopPrank();

        // Register and vote with validator2
        vm.startPrank(validator2);
        stakeToken.mint(validator2, MIN_STAKE);
        validator.registerValidator(MIN_STAKE);
        validator.validate(txId, true, keccak256("evidence2"));
        vm.stopPrank();

        // Finalize transaction
        vm.warp(block.timestamp + 2 hours);
        validator.finalizeAfterValidationTimeout(txId);

        // Now validator1 has no active votes (transaction finalized)
        uint256 balanceBefore = stakeToken.balanceOf(validator1);
        uint256 treasuryBefore = stakeToken.balanceOf(treasury);

        // Slash validator1
        validator.slashValidator(validator1);

        // Check slashing worked correctly
        uint256 expectedSlash = MIN_STAKE / 2;
        uint256 expectedReturn = MIN_STAKE - expectedSlash;

        assertEq(stakeToken.balanceOf(validator1), balanceBefore + expectedReturn);
        assertEq(stakeToken.balanceOf(treasury), treasuryBefore + expectedSlash);

        // Check validator is deactivated
        AgentValidator.Validator memory val = validator.getValidator(validator1);
        assertEq(val.stakedAmount, 0);
        assertEq(val.reputationScore, 0);
        assertTrue(!val.active);
    }

    function test_SlashValidator_MultipleActiveVotes_Reverts() public {
        // Register all validators
        vm.startPrank(validator1);
        validator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(validator2);
        validator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(validator3);
        validator.registerValidator(MIN_STAKE);
        vm.stopPrank();

        // Lock first transaction (needs 2 validators)
        vm.startPrank(partyA);
        uint256 txId1 = validator.lockTransaction(partyB, TEST_AMOUNT, TERMS_HASH, AgentValidator.ValidationType.MILESTONE);
        vm.stopPrank();

        vm.startPrank(partyB);
        validator.submitEvidence(txId1, EVIDENCE_HASH);
        vm.stopPrank();

        // Lock second transaction
        vm.startPrank(partyA);
        uint256 txId2 = validator.lockTransaction(partyB, TEST_AMOUNT, TERMS_HASH, AgentValidator.ValidationType.MILESTONE);
        vm.stopPrank();

        vm.startPrank(partyB);
        validator.submitEvidence(txId2, EVIDENCE_HASH);
        vm.stopPrank();

        // Validator1 votes on both transactions
        vm.startPrank(validator1);
        validator.validate(txId1, true, keccak256("evidence1"));
        validator.validate(txId2, true, keccak256("evidence2"));
        vm.stopPrank();

        // Try to slash validator1 (has 2 active votes)
        vm.expectRevert("Validator has active votes");
        validator.slashValidator(validator1);
    }
}
