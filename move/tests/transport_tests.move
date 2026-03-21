#[test_only]
module astrologistics::transport_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::fuel::{Self, FuelTreasuryCap};
use astrologistics::transport;

#[test]
fun test_create_order_instant() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    // Setup: create two storages
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo in storage 1
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 500, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    // Create transport order (Instant tier)
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let order = transport::create_order(
            &s1,
            &s2,
            receipt,
            vector[1001, 1500, 2002],  // route
            15000,                      // fuel_cost (within min/max bounds for weight 500)
            800,                        // danger_snapshot
            0,                          // tier: Instant
            &clock,
            scenario.ctx(),
        );

        assert!(transport::order_tier(&order) == 0);
        assert!(transport::order_fuel_cost(&order) == 15000);
        assert!(transport::order_status(&order) == 0); // Created
        // Instant tier: earliest_complete_at = created_at (no delay)
        assert!(transport::order_earliest_complete_at(&order) == 1000);

        transfer::public_transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_create_order_standard_has_delay() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 5000);

        let order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002],
            5000,   // fuel_cost
            500,    // danger
            2,      // tier: Standard
            &clock,
            scenario.ctx(),
        );

        // Standard tier: earliest_complete_at = 5000 + 900_000 = 905_000
        assert!(transport::order_earliest_complete_at(&order) == 905_000);
        transfer::public_transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_full_transport_lifecycle_instant() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    // Setup storages + fuel treasury
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    // Create order + pay fuel + complete (Instant = no delay)
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let mut order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 0, // tier=Instant
            &clock, scenario.ctx(),
        );

        // Pay fuel
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 5000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());
        assert!(transport::order_status(&order) == 1); // FuelPaid

        // Complete immediately (Instant tier, no delay)
        let new_receipt = transport::complete_transport(
            order, &mut s1, &mut s2, &clock, scenario.ctx(),
        );

        // Verify: cargo deposited in s2 (s1 freed, s2 loaded)
        assert!(storage::available_capacity(&s1) == 10000); // cargo removed from s1
        assert!(storage::available_capacity(&s2) < 10000);  // cargo deposited in s2

        transfer::public_transfer(new_receipt, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = transport::E_TOO_EARLY)]
fun test_complete_before_delay_fails() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let mut order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 2, // tier=Standard (15min delay)
            &clock, scenario.ctx(),
        );

        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 5000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());

        // Try complete at t=2000 (too early, need t=901_000)
        clock::set_for_testing(&mut clock, 2000);
        let new_receipt = transport::complete_transport(
            order, &mut s1, &mut s2, &clock, scenario.ctx(),
        );

        transfer::public_transfer(new_receipt, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_cancel_order_before_payment() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 0,
            &clock, scenario.ctx(),
        );

        // Cancel before paying fuel
        let returned_receipt = transport::cancel_order(order, scenario.ctx());
        transfer::public_transfer(returned_receipt, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = transport::E_WRONG_STATUS)]
fun test_cancel_after_pay_fails() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let mut order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 0,
            &clock, scenario.ctx(),
        );

        // Pay fuel first
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 5000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());

        // Try cancel after payment — should fail
        let returned_receipt = transport::cancel_order(order, scenario.ctx());
        transfer::public_transfer(returned_receipt, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_pay_fuel_returns_excess() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let mut order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 0,
            &clock, scenario.ctx(),
        );

        // Pay with 8000 FUEL (5000 needed, 3000 excess)
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 8000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());
        assert!(transport::order_status(&order) == 1);

        transfer::public_transfer(order, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };

    // Verify user received excess FUEL back
    scenario.next_tx(user);
    {
        let excess_fuel = test_scenario::take_from_sender<coin::Coin<fuel::FUEL>>(&scenario);
        assert!(coin::value(&excess_fuel) == 3000);
        coin::burn_for_testing(excess_fuel);
    };
    scenario.end();
}
