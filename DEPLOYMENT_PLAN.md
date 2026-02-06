 # Deployment Plan

 ## Environments
 - **Local:** Anvil (Foundry) for fast iteration.
 - **Testnet:** Base Goerli (per hackathon instructions).
 - **Mainnet (Post-Hackathon):** Base mainnet after audit.

 ## Prerequisites
 - Funded deployer wallet (testnet ETH).
 - Testnet USDC contract address.
 - Stake token address (use test USDC for MVP).
 - OpenClaw validator agents configured with RPC URL.

 ## Phase 1: Local Deployment
 1. Deploy mock USDC and stake token.
 2. Deploy `AgentValidator` with:
    - USDC address
    - stake token address
    - treasury address
    - min stake, windows, fee
 3. Run Foundry test suite.
 4. Start 1-3 validator agents against local RPC.

 ## Phase 2: Testnet Deployment (Hackathon)
 1. Verify testnet-only compliance.
 2. Deploy `AgentValidator` with real test USDC.
 3. Verify contract on block explorer.
 4. Register 2-3 validator agents with minimum stake.
 5. Run test transactions for each validation type.
 6. Capture logs and screenshots for demo.

 ## Phase 3: Mainnet Preparation (Post-Hackathon)
 1. Audit contract (external + internal review).
 2. Add randomized validator selection and stronger slashing.
 3. Harden agent sandboxing and monitoring.
 4. Deploy to Base mainnet.

 ## Rollback and Emergency Plan
 - Use `pause()` to stop new locks and validations.
 - Allow refunds after timeout if paused.
 - Hotfix with new deployment if critical bug found.

 ## Operational Checklist
 - RPC endpoints configured.
 - Validator agents have sufficient stake and gas.
 - Monitoring alerts for failed validations.
 - Backups of evidence artifacts and hashes.

