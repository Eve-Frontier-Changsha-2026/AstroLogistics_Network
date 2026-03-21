#[test_only]
module astrologistics::courier_market_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::threat_oracle;
use astrologistics::courier_market::{Self, CourierContract};

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
