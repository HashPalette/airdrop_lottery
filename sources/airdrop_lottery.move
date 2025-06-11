module airdrop_lottery_addr::airdrop_lottery {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::randomness;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

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
        /// Table to store all lotteries by ID
        lotteries_table: Table<u64, AirdropLottery>,
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
            lotteries_table: table::new(),
            lottery_creation_events: account::new_event_handle<LotteryCreationEvent>(account),
            lottery_completion_events: account::new_event_handle<LotteryCompletionEvent>(account),
        });
        
        // Initialize AccountLotteries
        move_to(account, AccountLotteries {
            created_lotteries: vector::empty<u64>(),
        });
    }

    public(friend) fun init_module_for_test(account: &signer) {
        init_module(account);
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
        table::add(&mut module_data.lotteries_table, lottery_id, lottery);
        
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

    /// Add participant(s) (creator only)
    public entry fun add_participant(
        account: &signer,
        lottery_id: u64,
        participants: vector<address>
    ) acquires ModuleData {
        let account_addr = signer::address_of(account);
        
        // Get module data and check if lottery exists
        let module_data = borrow_global_mut<ModuleData>(@airdrop_lottery_addr);
        assert!(table::contains(&module_data.lotteries_table, lottery_id), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = table::borrow_mut(&mut module_data.lotteries_table, lottery_id);
        
        // Only the creator can execute
        assert!(account_addr == lottery.creator, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Check if the lottery is not completed
        assert!(!lottery.is_completed, error::invalid_state(E_LOTTERY_ALREADY_COMPLETED));
        
        // Add participants
        let i = 0;
        let participants_count = vector::length(&participants);
        while (i < participants_count) {
            let participant = *vector::borrow(&participants, i);
            // Check if not already registered
            let (is_registered, _) = vector::index_of(&lottery.participants, &participant);
            if (!is_registered) {
                vector::push_back(&mut lottery.participants, participant);
            };
            i = i + 1;
        };
    }

    /// Remove participant(s) (creator only)
    public entry fun remove_participant(
        account: &signer,
        lottery_id: u64,
        participants: vector<address>
    ) acquires ModuleData {
        let account_addr = signer::address_of(account);
        
        // Get module data and check if lottery exists
        let module_data = borrow_global_mut<ModuleData>(@airdrop_lottery_addr);
        assert!(table::contains(&module_data.lotteries_table, lottery_id), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = table::borrow_mut(&mut module_data.lotteries_table, lottery_id);
        
        // Only the creator can execute
        assert!(account_addr == lottery.creator, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Check if the lottery is not completed
        assert!(!lottery.is_completed, error::invalid_state(E_LOTTERY_ALREADY_COMPLETED));
        
        // Remove participants
        let i = 0;
        let participants_count = vector::length(&participants);
        while (i < participants_count) {
            let participant = *vector::borrow(&participants, i);
            // Check if the participant exists
            let (is_registered, index) = vector::index_of(&lottery.participants, &participant);
            if (is_registered) {
                vector::remove(&mut lottery.participants, index);
            };
            i = i + 1;
        };
    }

    /// Execute the lottery and select winners (creator only)
    #[lint::allow_unsafe_randomness]
    public entry fun draw_winners(
        account: &signer,
        lottery_id: u64
    ) acquires ModuleData {
        let account_addr = signer::address_of(account);
        
        // Get module data and check if lottery exists
        let module_data = borrow_global_mut<ModuleData>(@airdrop_lottery_addr);
        assert!(table::contains(&module_data.lotteries_table, lottery_id), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = table::borrow_mut(&mut module_data.lotteries_table, lottery_id);
        
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
    public fun get_lottery_details(lottery_id: u64): (String, String, u64, u64, bool, address, u64, u64) acquires ModuleData {
        let module_data = borrow_global<ModuleData>(@airdrop_lottery_addr);
        assert!(table::contains(&module_data.lotteries_table, lottery_id), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = table::borrow(&module_data.lotteries_table, lottery_id);
        
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
    public fun get_participants(lottery_id: u64): vector<address> acquires ModuleData {
        let module_data = borrow_global<ModuleData>(@airdrop_lottery_addr);
        assert!(table::contains(&module_data.lotteries_table, lottery_id), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = table::borrow(&module_data.lotteries_table, lottery_id);
        *&lottery.participants
    }

    /// Get the winner list of the lottery
    #[view]
    public fun get_winners(lottery_id: u64): vector<address> acquires ModuleData {
        let module_data = borrow_global<ModuleData>(@airdrop_lottery_addr);
        assert!(table::contains(&module_data.lotteries_table, lottery_id), error::not_found(E_LOTTERY_NOT_FOUND));
        
        let lottery = table::borrow(&module_data.lotteries_table, lottery_id);
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

    // =====================
    // Test code (from airdrop_lottery_tests.move)
    // =====================
    #[test_only]
    const ADMIN: address = @0xABCD;
    #[test_only]
    const USER1: address = @0x1234;
    #[test_only]
    const USER2: address = @0x5678;
    #[test_only]
    const USER3: address = @0x9ABC;
    #[test_only]
    const LOTTERY_ID: u64 = 0;

    #[test_only]
    fun setup_test(aptos_framework: &signer, admin: &signer) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        account::create_account_for_test(signer::address_of(admin));
        init_module_for_test(admin);
    }

    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr)]
    public fun test_create_lottery(aptos_framework: &signer, admin: &signer) acquires AccountLotteries, ModuleData {
        setup_test(aptos_framework, admin);
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        let (returned_name, returned_description, returned_winner_count, participant_count, is_completed, creator, created_at, returned_deadline) = get_lottery_details(LOTTERY_ID);
        assert!(returned_name == name, 0);
        assert!(returned_description == description, 1);
        assert!(returned_winner_count == winner_count, 2);
        assert!(participant_count == 0, 3);
        assert!(!is_completed, 4);
        assert!(creator == signer::address_of(admin), 5);
        assert!(created_at >= current_time, 6);
        assert!(returned_deadline == deadline, 7);
    }

    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678)]
    public fun test_register_participant(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer) acquires AccountLotteries, ModuleData {
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user1)));
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user2)));
        let participants = get_participants(LOTTERY_ID);
        assert!(vector::length(&participants) == 2, 0);
        assert!(*vector::borrow(&participants, 0) == signer::address_of(user1), 1);
        assert!(*vector::borrow(&participants, 1) == signer::address_of(user2), 2);
    }

    #[lint::allow_unsafe_randomness]
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678, user3 = @0x9ABC)]
    public fun test_draw_winners(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer, user3: &signer) acquires AccountLotteries, ModuleData {
        randomness::initialize_for_testing(aptos_framework);
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(user3));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user1)));
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user2)));
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user3)));
        timestamp::update_global_time_for_test_secs(current_time + 3601);
        draw_winners(admin, LOTTERY_ID);
        let (_, _, _, _, is_completed, _, _, _) = get_lottery_details(LOTTERY_ID);
        assert!(is_completed, 0);
        let winners = get_winners(LOTTERY_ID);
        assert!(vector::length(&winners) == winner_count, 1);
        let participants = get_participants(LOTTERY_ID);
        let winner1 = *vector::borrow(&winners, 0);
        let winner2 = *vector::borrow(&winners, 1);
        let (is_participant1, _) = vector::index_of(&participants, &winner1);
        let (is_participant2, _) = vector::index_of(&participants, &winner2);
        assert!(is_participant1, 2);
        assert!(is_participant2, 3);
        assert!(winner1 != winner2, 4);
    }

    #[lint::allow_unsafe_randomness]
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234)]
    #[expected_failure(abort_code = 196613, location = airdrop_lottery_addr::airdrop_lottery)]
    public fun test_draw_winners_before_deadline(aptos_framework: &signer, admin: &signer, user1: &signer) acquires AccountLotteries, ModuleData {
        randomness::initialize_for_testing(aptos_framework);
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 1;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user1)));
        draw_winners(admin, LOTTERY_ID);
    }

    #[lint::allow_unsafe_randomness]
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234)]
    #[expected_failure(abort_code = 65545, location = airdrop_lottery_addr::airdrop_lottery)]
    public fun test_insufficient_participants(aptos_framework: &signer, admin: &signer, user1: &signer) acquires AccountLotteries, ModuleData {
        randomness::initialize_for_testing(aptos_framework);
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user1)));
        timestamp::update_global_time_for_test_secs(current_time + 3601);
        draw_winners(admin, LOTTERY_ID);
    }

    #[lint::allow_unsafe_randomness]
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678)]
    #[expected_failure(abort_code = 327681, location = airdrop_lottery_addr::airdrop_lottery)]
    public fun test_unauthorized_draw(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer) acquires AccountLotteries, ModuleData {
        randomness::initialize_for_testing(aptos_framework);
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 1;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user1)));
        timestamp::update_global_time_for_test_secs(current_time + 3601);
        draw_winners(user2, LOTTERY_ID);
    }

    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678, user3 = @0x9ABC)]
    public fun test_add_multiple_participants(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer, user3: &signer) acquires AccountLotteries, ModuleData {
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(user3));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        
        // Create a vector with multiple addresses
        let participants = vector::empty<address>();
        vector::push_back(&mut participants, signer::address_of(user1));
        vector::push_back(&mut participants, signer::address_of(user2));
        vector::push_back(&mut participants, signer::address_of(user3));
        
        // Add multiple participants in a single call
        add_participant(admin, LOTTERY_ID, participants);
        
        // Verify all participants were added
        let registered_participants = get_participants(LOTTERY_ID);
        assert!(vector::length(&registered_participants) == 3, 0);
        assert!(*vector::borrow(&registered_participants, 0) == signer::address_of(user1), 1);
        assert!(*vector::borrow(&registered_participants, 1) == signer::address_of(user2), 2);
        assert!(*vector::borrow(&registered_participants, 2) == signer::address_of(user3), 3);
    }

    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678, user3 = @0x9ABC)]
    public fun test_remove_multiple_participants(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer, user3: &signer) acquires AccountLotteries, ModuleData {
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(user3));
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600;
        create_lottery(admin, name, description, winner_count, deadline);
        
        // First add all participants individually
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user1)));
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user2)));
        add_participant(admin, LOTTERY_ID, vector::singleton(signer::address_of(user3)));
        
        // Verify all participants were added
        let registered_participants = get_participants(LOTTERY_ID);
        assert!(vector::length(&registered_participants) == 3, 0);
        
        // Create a vector with multiple addresses to remove
        let participants_to_remove = vector::empty<address>();
        vector::push_back(&mut participants_to_remove, signer::address_of(user1));
        vector::push_back(&mut participants_to_remove, signer::address_of(user3));
        
        // Remove multiple participants in a single call
        remove_participant(admin, LOTTERY_ID, participants_to_remove);
        
        // Verify only user2 remains in the participants list
        let remaining_participants = get_participants(LOTTERY_ID);
        assert!(vector::length(&remaining_participants) == 1, 1);
        assert!(*vector::borrow(&remaining_participants, 0) == signer::address_of(user2), 2);
    }
}
