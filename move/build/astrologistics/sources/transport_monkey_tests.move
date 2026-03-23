#[test_only]
module astrologistics::transport_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::fuel::{Self, FuelTreasuryCap};
use astrologistics::transport;

// ============ Helper ============

fun setup_with_cargo(admin: address, user: address, scenario: &mut test_scenario::Scenario) {
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let c1 = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        let c2 = storage::create_storage(2, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(c1, admin);
        transfer::public_transfer(c2, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };
}

/// Monkey: fuel_cost below minimum should fail
#[test]
#[expected_failure(abort_code = transport::E_FUEL_COST_TOO_LOW)]
fun test_fuel_cost_below_minimum() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);
    setup_with_cargo(admin, user, &mut scenario);

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // fuel_cost = 1 (way below min = 10 * 100 = 1000)
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 1, 0, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey: fuel_cost above maximum should fail
#[test]
#[expected_failure(abort_code = transport::E_FUEL_COST_TOO_HIGH)]
fun test_fuel_cost_above_maximum() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);
    setup_with_cargo(admin, user, &mut scenario);

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // fuel_cost = 100_000_000 (above max = 100_000 * 100 = 10_000_000)
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 100_000_000, 0, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey: invalid tier (3) should fail
#[test]
#[expected_failure(abort_code = transport::E_INVALID_TIER)]
fun test_invalid_tier() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);
    setup_with_cargo(admin, user, &mut scenario);

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 5000, 0, 3, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey: wrong storage mismatch — receipt from s1 but pass s2 as from_storage
#[test]
#[expected_failure(abort_code = transport::E_STORAGE_MISMATCH)]
fun test_receipt_storage_mismatch() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);
    setup_with_cargo(admin, user, &mut scenario);

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Pass s2 as from_storage but receipt is from s1
        let order = transport::create_order(
            &s2, &s1, receipt, vector[2, 1], 5000, 0, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey: non-owner cannot cancel
#[test]
#[expected_failure(abort_code = transport::E_NOT_OWNER)]
fun test_non_owner_cancel_fails() {
    let admin = @0xAD;
    let user = @0xA1;
    let attacker = @0xBAD;
    let mut scenario = test_scenario::begin(admin);
    setup_with_cargo(admin, user, &mut scenario);

    // User creates order
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 5000, 0, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, attacker); // send to attacker for them to try cancel
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };

    // Attacker tries to cancel
    scenario.next_tx(attacker);
    {
        let order = test_scenario::take_from_sender<transport::TransportOrder>(&scenario);
        let returned = transport::cancel_order(order, scenario.ctx());
        transfer::public_transfer(returned, attacker);
    };
    scenario.end();
}

/// Monkey: complete with wrong to_storage
#[test]
#[expected_failure(abort_code = transport::E_STORAGE_MISMATCH)]
fun test_complete_wrong_destination() {
    let admin = @0xAD;
    let user = @0xA1;
    let mut scenario = test_scenario::begin(admin);
    setup_with_cargo(admin, user, &mut scenario);

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let mut order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 5000, 0, 0, &clock, scenario.ctx(),
        );

        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 5000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());

        // Try complete with swapped storages (s2 as from, s1 as to)
        // Order expects from=s1, to=s2 — passing from=s2 triggers E_STORAGE_MISMATCH
        let new_receipt = transport::complete_transport(
            order, &mut s2, &mut s1, &clock, scenario.ctx(),
        );
        transfer::public_transfer(new_receipt, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
