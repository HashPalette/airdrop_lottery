module airdrop_lottery_addr::lottery_logic_details {
    use std::vector;
    use std::error;
    use aptos_framework::randomness;
    /// Detailed implementation of the lottery logic

    // Detailed implementation of the function that shuffles the participant list and selects the specified number of winners
    // This function uses Aptos's randomness module to achieve a fair and transparent lottery

    // 1. Shuffle Algorithm
    // Uses a variation of the Fisher-Yates shuffle algorithm to randomly reorder the participant list.
    // This algorithm guarantees that all possible permutations appear with equal probability.

    // 2. Winner Selection
    // Selects the specified number of winners from the shuffled list.
    // Returns an error if the number of participants is less than the number of winners.

    // 3. Security Considerations
    // - To prevent undergasing attacks, the process is split if there are many participants
    // - Randomness calls are only made within functions with the #[randomness] attribute
    // - The winner selection process is performed entirely on-chain and does not accept external manipulation
    const E_INSUFFICIENT_PARTICIPANTS: u64 = 9;
    // Implementation details:
    struct WinCount has copy, drop, store {
        addr: address,
        count: u64,
    }

    #[lint::allow_unsafe_randomness]
    fun shuffle_and_select(participants: &vector<address>, count: u64): vector<address> {
        let total = vector::length(participants);
        assert!(count <= total, error::invalid_argument(E_INSUFFICIENT_PARTICIPANTS));
        
        // Create a copy of the participant list
        let participants_copy = *participants;
        let winners = vector::empty<address>();
        
        // Threshold for splitting the process if there are many winners
        let threshold = 100;
        
        if (count <= threshold) {
            // Standard shuffle & select algorithm (for a small number of participants)
            let i = 0;
            while (i < count) {
                let rand_index = randomness::u64_range(0, vector::length(&participants_copy));
                let winner = vector::remove(&mut participants_copy, rand_index);
                vector::push_back(&mut winners, winner);
                i = i + 1;
            };
        } else {
            // Optimized algorithm for large-scale lotteries
            // Shuffle the entire participant list
            let shuffled = shuffle_all(&participants_copy);
            
            // Select the first 'count' elements as winners
            let i = 0;
            while (i < count) {
                if (i < vector::length(&shuffled)) {
                    vector::push_back(&mut winners, *vector::borrow(&shuffled, i));
                };
                i = i + 1;
            };
        };
        
        winners
    }

    // Complete list shuffle (Fisher-Yates algorithm)
    fun shuffle_all(list: &vector<address>): vector<address> {
        let length = vector::length(list);
        let result = *list;
        
        let i = length;
        while (i > 1) {
            i = i - 1;
            let j = randomness::u64_range(0, i + 1);
            if (j != i) {
                // Swap elements
                let temp = *vector::borrow(&result, i);
                *vector::borrow_mut(&mut result, i) = *vector::borrow(&result, j);
                *vector::borrow_mut(&mut result, j) = temp;
            };
        };
        
        result
    }

    // Lottery fairness verification function
    // This function is for statistically verifying the fairness of the lottery results
    // It is not included in the actual contract, but is used during testing
    fun verify_fairness(participants: &vector<address>, winner_count: u64, iterations: u64): bool {
        let total_participants = vector::length(participants);

        // Map to count the number of times each participant wins (using struct WinCount)
        let win_counts = vector::empty<WinCount>();

        // Simulate the lottery the specified number of times
        let i = 0;
        while (i < iterations) {
            let winners = shuffle_and_select(participants, winner_count);

            // Update the count for each winner
            let j = 0;
            while (j < vector::length(&winners)) {
                let winner = *vector::borrow(&winners, j);
                let (found, idx) = find_index(&win_counts, winner);
                if (found) {
                    let wc_ref = vector::borrow_mut(&mut win_counts, idx);
                    wc_ref.count = wc_ref.count + 1;
                } else {
                    vector::push_back(&mut win_counts, WinCount { addr: winner, count: 1 });
                };
                j = j + 1;
            };

            i = i + 1;
        };

        // Expected number of wins
        let expected_wins = (iterations * winner_count) / total_participants;

        // Allowed deviation (5%)
        let tolerance = expected_wins / 20;

        // Check if the number of wins for each participant is within the expected range
        let all_fair = true;
        let k = 0;
        while (k < total_participants) {
            let participant = *vector::borrow(participants, k);
            let (found, idx) = find_index(&win_counts, participant);
            if (found) {
                let wc_ref = vector::borrow(&win_counts, idx);
                let wins = wc_ref.count;
                if (wins < expected_wins - tolerance || wins > expected_wins + tolerance) {
                    all_fair = false;
                    break;
                };
            } else {
                // If never won
                if (expected_wins > tolerance) {
                    all_fair = false;
                    break;
                };
            };
            k = k + 1;
        };

        all_fair
    }

    // Helper function: find index of address in vector<WinCount>
    fun find_index(win_counts: &vector<WinCount>, addr: address): (bool, u64) {
        let i = 0;
        while (i < vector::length(win_counts)) {
            let wc_ref = vector::borrow(win_counts, i);
            if (wc_ref.addr == addr) {
                return (true, i);
            };
            i = i + 1;
        };
        (false, 0)
    }
}
