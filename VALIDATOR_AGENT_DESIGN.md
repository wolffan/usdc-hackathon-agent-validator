 # Validator Agent Design (OpenClaw Skill)

 ## Purpose
 Validator agents automatically verify evidence for transactions and submit on-chain votes with a clear audit trail. Each agent runs as an OpenClaw skill with strict sandboxing and deterministic outputs.

 ## Skill Structure
 ```
 agent-validator-hackathon/
 ├── SKILL.md
 ├── src/
 │   ├── validator.ts          # Orchestrates validation flow
 │   ├── contract.ts           # Smart contract read/write
 │   ├── reputation.ts         # Local reputation tracking
 │   └── validators/
 │       ├── codeTest.ts
 │       ├── apiCheck.ts
 │       ├── fileHash.ts
 │       └── milestone.ts
 └── tests/
     └── validator.test.ts
 ```

 ## Runtime Requirements
 - Node.js 20.x
 - Git + Docker (optional for isolation)
 - Network access for GitHub/API/file downloads
 - Strict timeouts on all external calls

 ## High-Level Workflow
 1. Listen for `ValidationNeeded` events.
 2. Fetch transaction details and evidence metadata (off-chain).
 3. Run validator based on `validationType`.
 4. Produce `approved`, `reason`, `evidenceHash`.
 5. Submit `validate(id, approved, evidenceHash, reason)` on-chain.

 ## Event Listener
 - Subscribe to `ValidationNeeded(id, quorum, validationEndsAt)`.
 - Ignore if agent already voted or is inactive.
 - Use a local lock to prevent double processing.

 ## Evidence Bundle Format (Off-Chain)
 Each evidence bundle is a JSON object stored off-chain and hashed with `keccak256`.
 ```json
 {
   "type": "CODE_TEST",
   "repoUrl": "https://github.com/user/repo",
   "branch": "feat/validator",
   "commit": "abc123",
   "commands": ["npm ci", "npm test"],
   "expected": {
     "testsPassed": true
   }
 }
 ```

 ## Validation Types
 ### 1. Code Test
 Steps:
 - Clone repo to a temp directory.
 - Checkout commit or branch.
 - Install dependencies with `npm ci`.
 - Run tests with a timeout.
 - Parse results and return verdict.

 Output:
 ```ts
 {
   approved: boolean,
   reason: string,
   evidence: {
     exitCode: number,
     stdoutHash: string,
     testsPassed: boolean
   }
 }
 ```

 ### 2. API Check
 Steps:
 - Send request to endpoint.
 - Validate status code and JSON schema.
 - Hash response body for evidence.

 Output:
 ```ts
 {
   approved: boolean,
   reason: string,
   evidence: {
     statusCode: number,
     bodyHash: string,
     headers: Record<string, string>
   }
 }
 ```

 ### 3. File Hash
 Steps:
 - Download file with size limit.
 - Compute keccak256 hash.
 - Compare to expected hash.

 Output:
 ```ts
 {
   approved: boolean,
   reason: string,
   evidence: {
     computedHash: string,
     expectedHash: string
   }
 }
 ```

 ### 4. Milestone Script
 Steps:
 - Execute predefined script in a sandbox.
 - Capture exit code and stdout hash.

 Output:
 ```ts
 {
   approved: boolean,
   reason: string,
   evidence: {
     exitCode: number,
     stdoutHash: string
   }
 }
 ```

 ## Safety and Sandboxing
 - Use a temp work dir per transaction: `/tmp/validator/<txId>/`.
 - Enforce timeouts per step (clone, install, tests).
 - Limit file size for downloads (e.g., 50 MB).
 - Block outbound requests to private IP ranges.
 - Optional Docker execution for code tests.

 ## Contract Interaction
 - `contract.ts` exposes:
   - `getTransaction(id)`
   - `submitVote(id, approved, evidenceHash, reason)`
   - `registerValidator(stakeAmount)`
 - All on-chain calls are wrapped with retries and gas limits.

 ## Evidence Hashing
 - Evidence object is normalized (sorted keys).
 - Hash with `keccak256(JSON.stringify(normalizedEvidence))`.
 - Both the transaction evidence and validator evidence are hashed.

 ## Failure Handling
 - If any step fails, return `approved: false` with reason.
 - If external service is unavailable, include `TEMP_ERROR`.
 - If input is invalid or missing, include `INVALID_EVIDENCE`.
 - Always submit a vote before `validationEndsAt`.

 ## Local Reputation Tracking (Off-Chain)
 - Track success rate for internal diagnostics.
 - This does not replace on-chain reputation.
 - Store in a local JSON file for MVP.

 ## Configuration
 ```
 VALIDATION_TIMEOUT_MS=600000
 MAX_DOWNLOAD_MB=50
 API_REQUEST_TIMEOUT_MS=10000
 ALLOWLISTED_DOMAINS=github.com,api.github.com
 ```

