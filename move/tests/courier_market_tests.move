#[test_only]
module astrologistics::courier_market_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::threat_oracle;
use astrologistics::courier_market::{Self, CourierContract, CourierBadge};

// ============ Helpers ============

/// Setup: 2 storages + oracle. Returns scenario after admin tx.
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

/// Client deposits cargo into storage with system_id=1001.
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

// ============ Tests ============

#[test]
fun test_create_contract() {
    let client = @0xC1;
    let mut scenario = setup_world();

    // Client deposits cargo
    deposit_cargo(&mut scenario, client);

    // Client creates courier contract
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let cancel_penalty = coin::mint_for_testing<SUI>(2000, scenario.ctx());

        // Ensure from != to
        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };

        let _contract_id = courier_market::create_contract(
            from,
            to,
            receipt,
            reward,
            cancel_penalty,
            8000,
            vector[1001, 2002],
            86_400_000,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };

    // Verify contract exists as shared object
    scenario.next_tx(client);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        assert!(courier_market::contract_status(&contract) == 0); // Open
        assert!(courier_market::contract_reward(&contract) == 5000);
        assert!(courier_market::contract_cargo_value(&contract) == 8000);
        assert!(courier_market::contract_min_deposit(&contract) == 8000);
        test_scenario::return_shared(contract);
    };
    scenario.end();
}

// ---- Helper: create contract and return scenario positioned after creation ----
fun setup_with_contract(): (test_scenario::Scenario, address, address) {
    let client = @0xC1;
    let courier = @0xC2;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    // Create contract
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
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
    (scenario, client, courier)
}

#[test]
fun test_accept_contract() {
    let (mut scenario, _client, courier) = setup_with_contract();

    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(10000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 1); // Accepted
        assert!(courier_market::contract_pickup_deadline(&contract) > 0);
        // Fix H7: pickup_deadline capped at deadline
        assert!(courier_market::contract_pickup_deadline(&contract) <= courier_market::contract_deadline(&contract));
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_cancel_by_client_open() {
    let (mut scenario, client, _courier) = setup_with_contract();

    scenario.next_tx(client);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let (receipt, refund) = courier_market::cancel_by_client(contract, scenario.ctx());
        // Refund = reward(5000) + penalty(2000) = 7000
        assert!(coin::value(&refund) == 7000);
        transfer::public_transfer(receipt, client);
        transfer::public_transfer(refund, client);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = courier_market::E_DEPOSIT_TOO_LOW)]
fun test_accept_deposit_too_low() {
    let (mut scenario, _client, courier) = setup_with_contract();

    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(100, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// ---- Helper: contract accepted by courier ----
fun setup_with_accepted_contract(): (test_scenario::Scenario, address, address) {
    let (mut scenario, client, courier) = setup_with_contract();

    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(10000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };
    (scenario, client, courier)
}

#[test]
fun test_pickup_and_deliver() {
    let (mut scenario, _client, courier) = setup_with_accepted_contract();

    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);

        // Identify from/to by matching contract's from_storage
        let from_id = courier_market::contract_from_storage(&contract);
        if (object::id(&s1) == from_id) {
            let mut from = s1;
            let mut to = s2;
            courier_market::pickup_and_deliver(
                &mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx(),
            );
            // Verify: cargo moved — from_storage load decreased, to_storage load increased
            assert!(storage::current_load(&from) == 0);
            assert!(storage::current_load(&to) == 200); // cargo weight=200
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        } else {
            let mut from = s2;
            let mut to = s1;
            courier_market::pickup_and_deliver(
                &mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx(),
            );
            assert!(storage::current_load(&from) == 0);
            assert!(storage::current_load(&to) == 200);
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        };

        assert!(courier_market::contract_status(&contract) == 2); // PendingConfirm
        assert!(courier_market::contract_confirm_deadline(&contract) > 0);
        test_scenario::return_shared(contract);
        transfer::public_transfer(badge, courier);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

// ---- Helper: pickup_and_deliver done, status = PendingConfirm ----
fun setup_with_delivered_contract(): (test_scenario::Scenario, address, address) {
    let (mut scenario, client, courier) = setup_with_accepted_contract();

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
            courier_market::pickup_and_deliver(
                &mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx(),
            );
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        } else {
            let mut from = s2;
            let mut to = s1;
            courier_market::pickup_and_deliver(
                &mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx(),
            );
            test_scenario::return_shared(from);
            test_scenario::return_shared(to);
        };

        test_scenario::return_shared(contract);
        transfer::public_transfer(badge, courier);
        clock::destroy_for_testing(clock);
    };
    (scenario, client, courier)
}

#[test]
fun test_confirm_and_settle() {
    let admin = @0xAD;
    let (mut scenario, client, courier) = setup_with_delivered_contract();

    // Client confirms delivery
    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        courier_market::confirm_delivery(&mut contract, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 3); // Delivered
        test_scenario::return_shared(contract);
    };

    // Settle
    scenario.next_tx(courier);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let oracle_cap = test_scenario::take_from_address<threat_oracle::OracleCap>(&scenario, admin);
        courier_market::settle(contract, badge, &oracle_cap, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };

    // Verify courier received ReporterCap
    scenario.next_tx(courier);
    {
        let reporter_cap = test_scenario::take_from_address<threat_oracle::ReporterCap>(&scenario, courier);
        threat_oracle::transfer_reporter_cap(reporter_cap, courier);
    };
    scenario.end();
}

#[test]
fun test_raise_dispute_and_resolve_client_wins() {
    let admin = @0xAD;
    let (mut scenario, client, courier) = setup_with_delivered_contract();

    // Client raises dispute
    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 5000);
        courier_market::raise_dispute(&mut contract, &clock, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 4); // Disputed
        assert!(courier_market::contract_dispute_deadline(&contract) > 0);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Oracle resolves: client wins (ruling=0)
    scenario.next_tx(admin);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_address<CourierBadge>(&scenario, courier);
        let oracle_cap = test_scenario::take_from_sender<threat_oracle::OracleCap>(&scenario);
        courier_market::resolve_dispute(contract, badge, &oracle_cap, 0, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.end();
}

#[test]
fun test_raise_dispute_and_resolve_split() {
    let admin = @0xAD;
    let (mut scenario, client, courier) = setup_with_delivered_contract();

    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        courier_market::raise_dispute(&mut contract, &clock, scenario.ctx());
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Oracle resolves: split (ruling=2)
    scenario.next_tx(admin);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_address<CourierBadge>(&scenario, courier);
        let oracle_cap = test_scenario::take_from_sender<threat_oracle::OracleCap>(&scenario);
        courier_market::resolve_dispute(contract, badge, &oracle_cap, 2, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.end();
}

#[test]
fun test_timeout_open() {
    let keeper = @0xBB;
    let client = @0xC1;
    let (mut scenario, _client, _courier) = setup_with_contract();

    // Fast-forward past deadline (1000 + 86_400_000)
    scenario.next_tx(keeper);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_001); // past deadline
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        assert!(coin::value(&bounty) == 0); // no keeper bounty for Open timeout
        transfer::public_transfer(bounty, keeper);
        clock::destroy_for_testing(clock);
    };

    // Verify client got receipt back
    scenario.next_tx(client);
    {
        let receipt = test_scenario::take_from_address<DepositReceipt>(&scenario, client);
        transfer::public_transfer(receipt, client);
    };
    scenario.end();
}

#[test]
fun test_timeout_accepted_no_pickup() {
    let keeper = @0xBB;
    let (mut scenario, _client, _courier) = setup_with_accepted_contract();

    // Fast-forward past pickup_deadline
    scenario.next_tx(keeper);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let pickup_dl = courier_market::contract_pickup_deadline(&contract);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, pickup_dl + 1);
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        // Keeper bounty = 0.5% of courier deposit (10000) = 50
        assert!(coin::value(&bounty) == 50);
        transfer::public_transfer(bounty, keeper);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_timeout_pending_confirm_auto_settle() {
    let keeper = @0xBB;
    let (mut scenario, _client, _courier) = setup_with_delivered_contract();

    // Fast-forward past confirm_deadline
    scenario.next_tx(keeper);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let confirm_dl = courier_market::contract_confirm_deadline(&contract);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, confirm_dl + 1);
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        assert!(coin::value(&bounty) == 0); // no bounty for auto-confirm
        transfer::public_transfer(bounty, keeper);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_timeout_disputed_auto_courier_wins() {
    let keeper = @0xBB;
    let (mut scenario, client, _courier) = setup_with_delivered_contract();

    // Client raises dispute
    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 5000);
        courier_market::raise_dispute(&mut contract, &clock, scenario.ctx());
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Fast-forward past dispute_deadline (72 hours)
    scenario.next_tx(keeper);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let dispute_dl = courier_market::contract_dispute_deadline(&contract);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, dispute_dl + 1);
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        assert!(coin::value(&bounty) == 0);
        transfer::public_transfer(bounty, keeper);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
