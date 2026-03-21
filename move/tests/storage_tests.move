#[test_only]
module astrologistics::storage_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, AdminCap};

#[test]
fun test_create_storage() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(
            1001,
            10000,
            100,
            &clock,
            scenario.ctx(),
        );
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario));
        let storage = test_scenario::take_shared<Storage>(&scenario);
        assert!(storage::system_id(&storage) == 1001);
        assert!(storage::available_capacity(&storage) == 10000);
        assert!(storage::fee_rate(&storage) == 100);
        test_scenario::return_shared(storage);
    };
    scenario.end();
}

#[test]
fun test_deposit_and_withdraw() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    // Create storage with 1% daily fee
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };

    // Deposit
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let receipt = storage::deposit(
            &mut s, b"ore", 500, 10000, &clock, scenario.ctx(),
        );

        assert!(storage::available_capacity(&s) == 9500);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };

    // Withdraw ~1 day later — fee = 10000 * 100 / 10000 * 1 = 100
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000); // ~1 day later

        // Pay 200 SUI (more than fee=100, excess returned)
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(200, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());

        assert!(storage::available_capacity(&s) == 10000);
        assert!(storage::cargo_weight(&cargo) == 500);

        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_withdraw_zero_fee() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Withdraw immediately — 0 days = 0 fee
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(0, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_CAPACITY_EXCEEDED)]
fun test_deposit_exceeds_capacity() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 100, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 200, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_INSUFFICIENT_FEE)]
fun test_withdraw_insufficient_fee() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Withdraw after 1 day — fee=100, pay only 10
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_400_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(10, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
