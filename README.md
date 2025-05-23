# Aptos Token Airdrop Lottery Smart Contract

## Overview

This smart contract provides a fair and transparent lottery system for selecting winners of token airdrops on the Aptos blockchain. It leverages Aptos on-chain randomness to ensure high security and reliability.

## Main Features

1. **Lottery Creation and Management**
   - Set name, description, number of winners, and deadline
   - Delete lotteries or update deadlines
2. **Participant Registration and Management**
   - Users can register themselves
   - Admins can add or remove participants
3. **Lottery Execution**
   - Fair winner selection using Aptos on-chain randomness
   - Can only be executed after the deadline
4. **Result Inquiry**
   - Retrieve lottery details
   - Get participant list
   - Get winner list

## Usage

### 1. Deploy the Contract

```bash
# Install Aptos CLI
curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3

# Initialize the project
cd airdrop_lottery
aptos init

# Compile the contract
aptos move compile

# Deploy the contract
aptos move publish
```

### 2. Create a Lottery

```bash
aptos move run \
  --function-id <your_address>::airdrop_lottery::create_lottery \
  --args string:"NFT Airdrop" string:"Win exclusive NFTs!" u64:10 u64:1717027200
```

- Lottery name
- Description
- Number of winners
- Deadline (UNIX timestamp)

### 3. Add Participants to a Lottery

```bash
aptos move run \
  --function-id <your_address>::airdrop_lottery::add_participant \
  --args u64:0 'address:["0x1", "0x2", "0x3"]'
```
- Lottery ID
- Participant addresses

### 4. Draw Winners (After Deadline)

```bash
aptos move run \
  --function-id <your_address>::airdrop_lottery::draw_winners \
  --args u64:0
```
- Lottery ID

### 5. Check Results

```bash
# Check lottery details
aptos move view \
  --function-id <your_address>::airdrop_lottery::get_lottery_details \
  --args u64:0

# Check winner list
aptos move view \
  --function-id <your_address>::airdrop_lottery::get_winners \
  --args u64:0
```

## Security Verification

- Utilizes Aptos `#[randomness]` attribute for unpredictable randomness
- Implements undergasing attack prevention with batch processing and gas limits
- Only the lottery creator can execute admin functions
- Prevents drawing before the deadline and joining after the deadline
- Prevents duplicate participant registration and duplicate winners
- Ensures proper event emission and data integrity
- Code is readable, maintainable, and well-documented with robust error handling
- No major vulnerabilities found; works as designed

## Error Codes

- `E_NOT_AUTHORIZED (1)`: Not authorized
- `E_LOTTERY_NOT_FOUND (2)`: Lottery not found
- `E_LOTTERY_ALREADY_COMPLETED (3)`: Lottery already completed
- `E_LOTTERY_NOT_COMPLETED (4)`: Lottery not yet completed
- `E_DEADLINE_NOT_REACHED (5)`: Deadline not reached
- `E_DEADLINE_PASSED (6)`: Deadline has passed
- `E_ALREADY_REGISTERED (7)`: Already registered
- `E_INVALID_WINNER_COUNT (8)`: Invalid winner count
- `E_INSUFFICIENT_PARTICIPANTS (9)`: Not enough participants

## License

This smart contract is provided under the MIT License.  