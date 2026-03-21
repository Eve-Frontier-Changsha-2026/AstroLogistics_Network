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
