#[test_only]
module airdrop_lottery_addr::airdrop_lottery_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use airdrop_lottery_addr::airdrop_lottery;

    // Test account addresses
    const ADMIN: address = @0xABCD;
    const USER1: address = @0x1234;
    const USER2: address = @0x5678;
    const USER3: address = @0x9ABC;

    // Test lottery ID
    const LOTTERY_ID: u64 = 0;

    // Test initialization function
    fun setup_test(aptos_framework: &signer, admin: &signer) {
        // Initialize timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create account
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize module
        airdrop_lottery::init_module_for_test(admin);
    }

    // Basic lottery creation test
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr)]
    fun test_create_lottery(aptos_framework: &signer, admin: &signer) {
        // Set up test environment
        setup_test(aptos_framework, admin);
        
        // Create lottery
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600; // 1 hour later
        
        airdrop_lottery::create_lottery(admin, name, description, winner_count, deadline);
        
        // Check if the lottery was created correctly
        let (returned_name, returned_description, returned_winner_count, participant_count, is_completed, creator, created_at, returned_deadline) = 
            airdrop_lottery::get_lottery_details(LOTTERY_ID);
        
        assert!(returned_name == name, 0);
        assert!(returned_description == description, 1);
        assert!(returned_winner_count == winner_count, 2);
        assert!(participant_count == 0, 3);
        assert!(!is_completed, 4);
        assert!(creator == signer::address_of(admin), 5);
        assert!(created_at >= current_time, 6);
        assert!(returned_deadline == deadline, 7);
    }

    // Participant registration test
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678)]
    fun test_register_participant(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer) {
        // Set up test environment
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        
        // Create lottery
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600; // 1 hour later
        
        airdrop_lottery::create_lottery(admin, name, description, winner_count, deadline);
        
        // Register participants
        airdrop_lottery::register_participant(user1, LOTTERY_ID);
        airdrop_lottery::register_participant(user2, LOTTERY_ID);
        
        // Check if participants were registered correctly
        let participants = airdrop_lottery::get_participants(LOTTERY_ID);
        assert!(vector::length(&participants) == 2, 0);
        assert!(*vector::borrow(&participants, 0) == signer::address_of(user1), 1);
        assert!(*vector::borrow(&participants, 1) == signer::address_of(user2), 2);
    }

    // Lottery execution test
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678, user3 = @0x9ABC)]
    fun test_draw_winners(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer, user3: &signer) {
        // Set up test environment
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(user3));
        
        // Create lottery
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600; // 1 hour later
        
        airdrop_lottery::create_lottery(admin, name, description, winner_count, deadline);
        
        // Register participants
        airdrop_lottery::register_participant(user1, LOTTERY_ID);
        airdrop_lottery::register_participant(user2, LOTTERY_ID);
        airdrop_lottery::register_participant(user3, LOTTERY_ID);
        
        // Advance time (to pass the deadline)
        timestamp::update_global_time_for_test_secs(current_time + 3601);
        
        // Execute lottery
        airdrop_lottery::draw_winners(admin, LOTTERY_ID);
        
        // Check if the lottery is completed
        let (_, _, _, _, is_completed, _, _, _) = airdrop_lottery::get_lottery_details(LOTTERY_ID);
        assert!(is_completed, 0);
        
        // Check if winners are selected correctly
        let winners = airdrop_lottery::get_winners(LOTTERY_ID);
        assert!(vector::length(&winners) == winner_count, 1);
        
        // Check if winners are in the participant list
        let participants = airdrop_lottery::get_participants(LOTTERY_ID);
        let winner1 = *vector::borrow(&winners, 0);
        let winner2 = *vector::borrow(&winners, 1);
        
        let (is_participant1, _) = vector::index_of(&participants, &winner1);
        let (is_participant2, _) = vector::index_of(&participants, &winner2);
        
        assert!(is_participant1, 2);
        assert!(is_participant2, 3);
        
        // Check that winners are not duplicated
        assert!(winner1 != winner2, 4);
    }

    // Error case test: Drawing before deadline
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234)]
    #[expected_failure(abort_code = 5)]
    fun test_draw_winners_before_deadline(aptos_framework: &signer, admin: &signer, user1: &signer) {
        // Set up test environment
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        
        // Create lottery
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 1;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600; // 1 hour later
        
        airdrop_lottery::create_lottery(admin, name, description, winner_count, deadline);
        
        // Register participant
        airdrop_lottery::register_participant(user1, LOTTERY_ID);
        
        // Execute lottery before deadline (should error)
        airdrop_lottery::draw_winners(admin, LOTTERY_ID);
    }

    // Error case test: Insufficient participants
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234)]
    #[expected_failure(abort_code = 9)]
    fun test_insufficient_participants(aptos_framework: &signer, admin: &signer, user1: &signer) {
        // Set up test environment
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        
        // Create lottery (winner count 2)
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 2;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600; // 1 hour later
        
        airdrop_lottery::create_lottery(admin, name, description, winner_count, deadline);
        
        // Register participant (only one)
        airdrop_lottery::register_participant(user1, LOTTERY_ID);
        
        // Advance time
        timestamp::update_global_time_for_test_secs(current_time + 3601);
        
        // Execute lottery with insufficient participants (should error)
        airdrop_lottery::draw_winners(admin, LOTTERY_ID);
    }

    // Error case test: Unauthorized user drawing
    #[test(aptos_framework = @aptos_framework, admin = @airdrop_lottery_addr, user1 = @0x1234, user2 = @0x5678)]
    #[expected_failure(abort_code = 1)]
    fun test_unauthorized_draw(aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer) {
        // Set up test environment
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        
        // Create lottery
        let name = string::utf8(b"Test Lottery");
        let description = string::utf8(b"This is a test lottery");
        let winner_count = 1;
        let current_time = timestamp::now_seconds();
        let deadline = current_time + 3600; // 1 hour later
        
        airdrop_lottery::create_lottery(admin, name, description, winner_count, deadline);
        
        // Register participant
        airdrop_lottery::register_participant(user1, LOTTERY_ID);
        
        // Advance time
        timestamp::update_global_time_for_test_secs(current_time + 3601);
        
        // Unauthorized user executes lottery (should error)
        airdrop_lottery::draw_winners(user2, LOTTERY_ID);
    }
}
