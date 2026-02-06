// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/AgentValidator.sol";

/**
 * @title DeployScript
 * @dev Deployment script for AgentValidator contract on Base Sepolia testnet
 */
contract DeployScript is Script {
    function run() external {
        // Deployer private key (set via env variable PRIVATE_KEY)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying AgentValidator contract...");
        console.log("Deployer address:", deployer);
        console.log("Network: Base Sepolia");
        console.log("Chain ID:", block.chainid);

        // Constructor parameters
        // USDC on Base Sepolia
        address usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        // Using same USDC as stake token for MVP
        address stakeTokenAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        // Treasury set to deployer address
        address treasuryAddress = deployer;

        console.log("USDC address:", usdcAddress);
        console.log("Stake token address:", stakeTokenAddress);
        console.log("Treasury address:", treasuryAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AgentValidator contract
        AgentValidator validator = new AgentValidator(usdcAddress, stakeTokenAddress, treasuryAddress);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("[SUCCESS] Deployment Successful!");
        console.log("========================================");
        console.log("Contract address:", address(validator));
        console.log("Deployer:", deployer);
        console.log("Transaction hash: (Check explorer)");
        console.log("Explorer: https://sepolia.basescan.org");
        console.log("========================================");

        // Verify deployment
        _verifyDeployment(address(validator), usdcAddress, stakeTokenAddress, treasuryAddress);
    }

    function _verifyDeployment(address contractAddress, address usdc, address stakeToken, address treasury)
        internal
        view
    {
        console.log("\nVerifying deployment...");

        AgentValidator validator = AgentValidator(contractAddress);

        // Check USDC address
        address deployedUsdc = address(validator.usdc());
        require(deployedUsdc == usdc, "USDC address mismatch");
        console.log("[OK] USDC address verified:", deployedUsdc);

        // Check stake token address
        address deployedStakeToken = address(validator.stakeToken());
        require(deployedStakeToken == stakeToken, "Stake token address mismatch");
        console.log("[OK] Stake token address verified:", deployedStakeToken);

        // Check treasury address
        address deployedTreasury = validator.treasury();
        require(deployedTreasury == treasury, "Treasury address mismatch");
        console.log("[OK] Treasury address verified:", deployedTreasury);

        // Check minimum stake
        uint256 minStake = validator.minStake();
        console.log("[OK] Minimum stake:", minStake / 1e6, "USDC");

        // Check validation window
        uint256 validationWindow = validator.validationWindow();
        console.log("[OK] Validation window:", validationWindow / 3600, "hours");

        // Check evidence window
        uint256 evidenceWindow = validator.evidenceWindow();
        console.log("[OK] Evidence window:", evidenceWindow / 3600, "hours");

        // Check dispute window
        uint256 disputeWindow = validator.disputeWindow();
        console.log("[OK] Dispute window:", disputeWindow / 3600, "hours");

        console.log("\n[SUCCESS] All verifications passed!");
    }
}
