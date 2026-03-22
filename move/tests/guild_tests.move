#[test_only]
module astrologistics::guild_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::guild::{Self, Guild, GuildMemberCap};

#[test]
fun test_create_guild() {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"StarHaulers".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        assert!(test_scenario::has_most_recent_for_sender<GuildMemberCap>(&scenario));
        let guild = test_scenario::take_shared<Guild>(&scenario);
        assert!(guild::guild_leader(&guild) == leader);
        assert!(guild::guild_member_count(&guild) == 1);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        assert!(guild::member_cap_guild_id(&cap) == object::id(&guild));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_add_member() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"StarHaulers".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(member);
    {
        assert!(test_scenario::has_most_recent_for_sender<GuildMemberCap>(&scenario));
        let guild = test_scenario::take_shared<Guild>(&scenario);
        assert!(guild::guild_member_count(&guild) == 2);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        assert!(guild::verify_membership(&guild, &cap));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_remove_member() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"StarHaulers".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, member);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(member);
    {
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        assert!(!guild::verify_membership(&guild, &cap));
        guild::destroy_stale_cap(cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_leave_guild() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"StarHaulers".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(member);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::leave_guild(&mut guild, cap);
        assert!(guild::guild_member_count(&guild) == 1);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_verify_membership() {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"StarHaulers".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        assert!(guild::verify_membership(&guild, &cap));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}
