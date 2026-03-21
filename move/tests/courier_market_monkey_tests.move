#[test_only]
module astrologistics::courier_market_monkey_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::threat_oracle;
use astrologistics::courier_market::{Self, CourierContract, CourierBadge};

// ============ Shared setup ============

fun setup_world(): test_scenario::Scenario {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario
}

fun deposit_cargo(scenario: &mut test_scenario::Scenario, client: address) {
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(scenario);
        let s2 = test_scenario::take_shared<Storage>(scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        if (storage::system_id(&s1) == 1001) {
            let mut s = s1;
            let receipt = storage::deposit(&mut s, b"ore", 200, 8000, &clock, scenario.ctx());
            transfer::public_transfer(receipt, client);
            test_scenario::return_shared(s);
            test_scenario::return_shared(s2);
        } else {
            let mut s = s2;
            let receipt = storage::deposit(&mut s, b"ore", 200, 8000, &clock, scenario.ctx());
            transfer::public_transfer(receipt, client);
            test_scenario::return_shared(s1);
            test_scenario::return_shared(s);
        };
        clock::destroy_for_testing(clock);
    };
}

fun create_contract(scenario: &mut test_scenario::Scenario, client: address) {
    deposit_cargo(scenario, client);
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(scenario);
        let s2 = test_scenario::take_shared<Storage>(scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        let _id = courier_market::create_contract(
            from, to, receipt, reward, penalty, 8000,
            vector[1001, 2002], 86_400_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
}

fun accept_contract(scenario: &mut test_scenario::Scenario, courier: address) {
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(10000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
}

// ============ Monkey Tests ============

// 1. Courier deposit exactly at minimum (boundary)
#[test]
fun test_accept_exact_min_deposit() {
    let client = @0xC1;
    let courier = @0xC2;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);

    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Exact minimum = 8000 (cargo_value)
        let deposit = coin::mint_for_testing<SUI>(8000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 1);
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 2. Deadline = minimum (1 hour = 3_600_000 ms)
#[test]
fun test_min_deadline() {
    let client = @0xC1;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        let _id = courier_market::create_contract(
            from, to, receipt, reward, penalty, 8000,
            vector[1001, 2002], 3_600_000, &clock, scenario.ctx(), // MIN deadline
        );
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 3. Cancel after accept (should fail — wrong status)
#[test]
#[expected_failure(abort_code = courier_market::E_WRONG_STATUS)]
fun test_cancel_after_accept_fails() {
    let client = @0xC1;
    let courier = @0xC2;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);
    accept_contract(&mut scenario, courier);

    scenario.next_tx(client);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let (_receipt, _refund) = courier_market::cancel_by_client(contract, scenario.ctx());
        abort 0 // unreachable
    };
}

// 4. Double accept (should fail — wrong status)
#[test]
#[expected_failure(abort_code = courier_market::E_WRONG_STATUS)]
fun test_double_accept_fails() {
    let client = @0xC1;
    let courier = @0xC2;
    let courier2 = @0xC3;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);
    accept_contract(&mut scenario, courier);

    scenario.next_tx(courier2);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(10000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, courier2);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 5. Confirm by non-client (should fail)
#[test]
#[expected_failure(abort_code = courier_market::E_NOT_CLIENT)]
fun test_confirm_by_non_client_fails() {
    let client = @0xC1;
    let courier = @0xC2;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);
    accept_contract(&mut scenario, courier);

    // Pickup and deliver
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);
        let from_id = courier_market::contract_from_storage(&contract);
        if (object::id(&s1) == from_id) {
            let mut from = s1;
            let mut to = s2;
            courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        } else {
            let mut from = s2;
            let mut to = s1;
            courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        };
        test_scenario::return_shared(contract);
        transfer::public_transfer(badge, courier);
        clock::destroy_for_testing(clock);
    };

    // Courier tries to confirm (not client) — should fail
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        courier_market::confirm_delivery(&mut contract, scenario.ctx());
        test_scenario::return_shared(contract);
    };
    scenario.end();
}

// 6. Settle without confirming (should fail — wrong status: PendingConfirm != Delivered)
#[test]
#[expected_failure(abort_code = courier_market::E_WRONG_STATUS)]
fun test_settle_without_confirm_fails() {
    let admin = @0xAD;
    let client = @0xC1;
    let courier = @0xC2;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);
    accept_contract(&mut scenario, courier);

    // Pickup and deliver
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);
        let from_id = courier_market::contract_from_storage(&contract);
        if (object::id(&s1) == from_id) {
            let mut from = s1;
            let mut to = s2;
            courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        } else {
            let mut from = s2;
            let mut to = s1;
            courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        };
        test_scenario::return_shared(contract);
        transfer::public_transfer(badge, courier);
        clock::destroy_for_testing(clock);
    };

    // Try settle without confirm
    scenario.next_tx(courier);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let oracle_cap = test_scenario::take_from_address<threat_oracle::OracleCap>(&scenario, admin);
        courier_market::settle(contract, badge, &oracle_cap, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.end();
}

// 7. claim_timeout before deadline (should fail)
#[test]
#[expected_failure(abort_code = courier_market::E_NOT_TIMED_OUT)]
fun test_timeout_before_deadline_fails() {
    let keeper = @0xBB;
    let client = @0xC1;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);

    scenario.next_tx(keeper);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000); // way before deadline
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        transfer::public_transfer(bounty, keeper);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 8. Deadline too short (< 1 hour)
#[test]
#[expected_failure(abort_code = courier_market::E_DEADLINE_TOO_SHORT)]
fun test_deadline_too_short_fails() {
    let client = @0xC1;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        let _id = courier_market::create_contract(
            from, to, receipt, reward, penalty, 8000,
            vector[1001, 2002], 1000, &clock, scenario.ctx(), // 1 second — too short!
        );
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 9. Same storage (from == to, Fix Low)
#[test]
#[expected_failure(abort_code = courier_market::E_SAME_STORAGE)]
fun test_same_storage_fails() {
    let client = @0xC1;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        // Use s1 as both from and to
        let (from, _to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        let _id = courier_market::create_contract(
            from, from, receipt, reward, penalty, 8000,  // same storage!
            vector[1001], 86_400_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 10. Reward too low (Fix H8)
#[test]
#[expected_failure(abort_code = courier_market::E_REWARD_TOO_LOW)]
fun test_reward_too_low_fails() {
    let client = @0xC1;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let reward = coin::mint_for_testing<SUI>(100, scenario.ctx()); // < MIN_CONTRACT_REWARD (1000)
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        let _id = courier_market::create_contract(
            from, to, receipt, reward, penalty, 8000,
            vector[1001, 2002], 86_400_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 11. Dispute on wrong status (Open — should fail)
#[test]
#[expected_failure(abort_code = courier_market::E_WRONG_STATUS)]
fun test_dispute_on_open_fails() {
    let client = @0xC1;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);

    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        courier_market::raise_dispute(&mut contract, &clock, scenario.ctx());
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// 12. Wrong courier tries pickup (badge mismatch)
#[test]
#[expected_failure(abort_code = courier_market::E_NOT_COURIER)]
fun test_wrong_courier_pickup_fails() {
    let client = @0xC1;
    let courier = @0xC2;
    let imposter = @0xC3;
    let mut scenario = setup_world();
    create_contract(&mut scenario, client);
    accept_contract(&mut scenario, courier);

    // Imposter tries to use the badge (but sender != badge.courier)
    scenario.next_tx(imposter);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_address<CourierBadge>(&scenario, courier);
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let from_id = courier_market::contract_from_storage(&contract);
        if (object::id(&s1) == from_id) {
            let mut from = s1;
            let mut to = s2;
            courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        } else {
            let mut from = s2;
            let mut to = s1;
            courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        };
        test_scenario::return_shared(contract);
        transfer::public_transfer(badge, courier);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
