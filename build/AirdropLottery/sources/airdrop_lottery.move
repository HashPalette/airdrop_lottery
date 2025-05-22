module airdrop_lottery_addr::airdrop_lottery {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::randomness;
    use aptos_framework::timestamp;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_LOTTERY_NOT_FOUND: u64 = 2;
    const E_LOTTERY_ALREADY_COMPLETED: u64 = 3;
    const E_LOTTERY_NOT_COMPLETED: u64 = 4;
    const E_DEADLINE_NOT_REACHED: u64 = 5;
    const E_DEADLINE_PASSED: u64 = 6;
    const E_ALREADY_REGISTERED: u64 = 7;
    const E_INVALID_WINNER_COUNT: u64 = 8;
    const E_INSUFFICIENT_PARTICIPANTS: u64 = 9;

    /// Structure to manage the state of the airdrop lottery
    struct AirdropLottery has key, store {
        /// Unique identifier for the lottery
        lottery_id: u64,
        /// Name of the lottery
        name: String,
        /// Description of the lottery
        description: String,
        /// List of participants
        participants: vector<address>,
        /// List of winners
        winners: vector<address>,
        /// Number of winners
        winner_count: u64,
        /// Whether the lottery is completed
        is_completed: bool,
        /// Creator of the lottery
        creator: address,
        /// Creation time of the lottery
        created_at: u64,
        /// Deadline of the lottery
        deadline: u64,
    }

    /// Structure to manage the state of the module
    struct ModuleData has key {
        /// Next lottery ID
        next_lottery_id: u64,
        /// List of created lotteries
        lotteries: vector<u64>,
        /// Lottery creation event
        lottery_creation_events: EventHandle<LotteryCreationEvent>,
        /// Lottery completion event
        lottery_completion_events: EventHandle<LotteryCompletionEvent>,
    }

    /// Structure to manage the list of lotteries created by an account
    struct AccountLotteries has key {
        /// List of lotteries created by the account
        created_lotteries: vector<u64>,
    }

    /// Lottery creation event
    struct LotteryCreationEvent has drop, store {
        lottery_id: u64,
        name: String,
        creator: address,
        winner_count: u64,
        deadline: u64,
    }

    /// Lottery completion event
    struct LotteryCompletionEvent has drop, store {
        lottery_id: u64,
        winners: vector<address>,
    }

    /// Initialize the module
    fun init_module(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Initialize ModuleData
        move_to(account, ModuleData {
            next_lottery_id: 0,
            lotteries: vector::empty<u64>(),
            lottery_creation_events: account::new_event_handle<LotteryCreationEvent>(account),
            lottery_completion_events: account::new_event_handle<LotteryCompletionEvent>(account),
        });
        
        // Initialize AccountLotteries
        move_to(account, AccountLotteries {
            created_lotteries: vector::empty<u64>(),
        });
    }

    /// Create a new lottery
    public entry fun create_lottery(
        account: &signer,
        name: String,
        description: String,
        winner_count: u64,
        deadline: u64
    ) acquires ModuleData, AccountLotteries {
        let account_addr = signer::address_of(account);
        let module_data = borrow_global_mut<ModuleData>(@airdrop_lottery_addr);
        
        // Get and update the lottery ID
        let lottery_id = module_data.next_lottery_id;
        module_data.next_lottery_id = lottery_id + 1;
        
        // Create the lottery
        let lottery = AirdropLottery {
            lottery_id,
            name,
            description,
            participants: vector::empty<address>(),
            winners: vector::empty<address>(),
            winner_count,
            is_completed: false,
            creator: account_addr,
            created_at: timestamp::now_seconds(),
            deadline,
        };
        
        // Save the lottery to global storage
        move_to(account, lottery);
        
        // Update module data
        vector::push_back(&mut module_data.lotteries, lottery_id);
        
        // Update the account's lottery list
        if (!exists<AccountLotteries>(account_addr)) {
            move_to(account, AccountLotteries {
                created_lotteries: vector::empty<u64>(),
            });
        };
        
        let account_lotteries = borrow_global_mut<AccountLotteries>(account_addr);
        vector::push_back(&mut account_lotteries.created_lotteries, lottery_id);
        
        // Emit event
        event::emit_event(
            &mut module_data.lottery_creation_events,
            LotteryCreationEvent {
                lottery_id,
                name: *&name,
                creator: account_addr,
                winner_count,
                deadline,
            },
        );
    }

    /// Register for the lottery
    public entry fun register_participant(
        account: &signer,
        lottery_id: u64
    ) acquires AirdropLottery {
        let participant_addr = signer::address_of(account);
        
        // Check if the lottery exists
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global_mut<AirdropLottery>(@airdrop_lottery_addr);
        
        // Check if the lottery is not completed
        assert!(!lottery.is_completed, error::invalid_state(E_LOTTERY_ALREADY_COMPLETED));
        
        // Check if the deadline has not passed
        assert!(timestamp::now_seconds() <= lottery.deadline, error::invalid_state(E_DEADLINE_PASSED));
        
        // Check if not already registered
        let (is_registered, _) = vector::index_of(&lottery.participants, &participant_addr);
        assert!(!is_registered, error::already_exists(E_ALREADY_REGISTERED));
        
        // Add participant
        vector::push_back(&mut lottery.participants, participant_addr);
    }

    /// Add a participant (creator only)
    public entry fun add_participant(
        account: &signer,
        lottery_id: u64,
        participant: address
    ) acquires AirdropLottery {
        let account_addr = signer::address_of(account);
        
        // Check if the lottery exists
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global_mut<AirdropLottery>(@airdrop_lottery_addr);
        
        // Only the creator can execute
        assert!(account_addr == lottery.creator, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Check if the lottery is not completed
        assert!(!lottery.is_completed, error::invalid_state(E_LOTTERY_ALREADY_COMPLETED));
        
        // Check if not already registered
        let (is_registered, _) = vector::index_of(&lottery.participants, &participant);
        assert!(!is_registered, error::already_exists(E_ALREADY_REGISTERED));
        
        // Add participant
        vector::push_back(&mut lottery.participants, participant);
    }

    /// Remove a participant (creator only)
    public entry fun remove_participant(
        account: &signer,
        lottery_id: u64,
        participant: address
    ) acquires AirdropLottery {
        let account_addr = signer::address_of(account);
        
        // Check if the lottery exists
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global_mut<AirdropLottery>(@airdrop_lottery_addr);
        
        // Only the creator can execute
        assert!(account_addr == lottery.creator, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Check if the lottery is not completed
        assert!(!lottery.is_completed, error::invalid_state(E_LOTTERY_ALREADY_COMPLETED));
        
        // Check if the participant exists
        let (is_registered, index) = vector::index_of(&lottery.participants, &participant);
        assert!(is_registered, error::not_found(E_LOTTERY_NOT_FOUND));
        
        // Remove participant
        vector::remove(&mut lottery.participants, index);
    }

    /// Execute the lottery and select winners (creator only)
    #[lint::allow_unsafe_randomness]
    public entry fun draw_winners(
        account: &signer,
        lottery_id: u64
    ) acquires AirdropLottery, ModuleData {
        let account_addr = signer::address_of(account);
        
        // Check if the lottery exists
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global_mut<AirdropLottery>(@airdrop_lottery_addr);
        
        // Only the creator can execute
        assert!(account_addr == lottery.creator, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Check if the lottery is not completed
        assert!(!lottery.is_completed, error::invalid_state(E_LOTTERY_ALREADY_COMPLETED));
        
        // Check if the deadline has been reached
        assert!(timestamp::now_seconds() >= lottery.deadline, error::invalid_state(E_DEADLINE_NOT_REACHED));
        
        // Check if the number of participants is at least the number of winners
        let participant_count = vector::length(&lottery.participants);
        assert!(participant_count >= lottery.winner_count, error::invalid_argument(E_INSUFFICIENT_PARTICIPANTS));
        
        // Select winners
        lottery.winners = shuffle_and_select(&lottery.participants, lottery.winner_count);
        lottery.is_completed = true;
        
        // Emit event
        let module_data = borrow_global_mut<ModuleData>(@airdrop_lottery_addr);
        event::emit_event(
            &mut module_data.lottery_completion_events,
            LotteryCompletionEvent {
                lottery_id,
                winners: *&lottery.winners,
            },
        );
    }

    /// Shuffle the participant list and select the specified number of winners
    fun shuffle_and_select(participants: &vector<address>, count: u64): vector<address> {
        let total = vector::length(participants);
        assert!(count <= total, error::invalid_argument(E_INSUFFICIENT_PARTICIPANTS));
        
        let winners = vector::empty<address>();
        let participants_copy = *participants;
        
        let i = 0;
        while (i < count) {
            let rand_index = randomness::u64_range(0, vector::length(&participants_copy));
            let winner = vector::remove(&mut participants_copy, rand_index);
            vector::push_back(&mut winners, winner);
            i = i + 1;
        };
        
        winners
    }

    /// Get the details of the lottery
    #[view]
    public fun get_lottery_details(lottery_id: u64): (String, String, u64, u64, bool, address, u64, u64) acquires AirdropLottery {
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global<AirdropLottery>(@airdrop_lottery_addr);
        
        (
            *&lottery.name,
            *&lottery.description,
            lottery.winner_count,
            vector::length(&lottery.participants),
            lottery.is_completed,
            lottery.creator,
            lottery.created_at,
            lottery.deadline
        )
    }

    /// Get the participant list of the lottery
    #[view]
    public fun get_participants(lottery_id: u64): vector<address> acquires AirdropLottery {
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global<AirdropLottery>(@airdrop_lottery_addr);
        *&lottery.participants
    }

    /// Get the winner list of the lottery
    #[view]
    public fun get_winners(lottery_id: u64): vector<address> acquires AirdropLottery {
        assert!(exists<AirdropLottery>(@airdrop_lottery_addr), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = borrow_global<AirdropLottery>(@airdrop_lottery_addr);
        assert!(lottery.is_completed, error::invalid_state(E_LOTTERY_NOT_COMPLETED));
        
        *&lottery.winners
    }

    /// Get the list of lotteries created by the account
    #[view]
    public fun get_account_lotteries(account_address: address): vector<u64> acquires AccountLotteries {
        if (!exists<AccountLotteries>(account_address)) {
            return vector::empty<u64>()
        };
        
        let account_lotteries = borrow_global<AccountLotteries>(account_address);
        *&account_lotteries.created_lotteries
    }

    /// Get the list of all lottery IDs
    #[view]
    public fun get_all_lotteries(): vector<u64> acquires ModuleData {
        let module_data = borrow_global<ModuleData>(@airdrop_lottery_addr);
        *&module_data.lotteries
    }
}
