# Contract v3: Guild + Seal + Bounty Differential — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **SUI Move skills required:** Invoke `sui-developer` for contract development, `sui-tester` for testing, `sui-seal` for Task 5 Seal integration. All Move changes must pass `sui move test` before commit.

**Goal:** Add guild system, owned/private storage, guild-based courier reward differential, and SUI Seal encrypted coordinates to enable "Dark Forest" gameplay.

**Architecture:** New `guild.move` module provides Guild shared objects and non-transferable GuildMemberCap tokens. Existing structs (`Storage`, `CourierContract`) are extended via `dynamic_field` (upgrade-safe, no struct layout changes). New `seal_policy.move` defines decryption policies for encrypted Storage coordinates. All changes are compatible upgrade safe.

**Tech Stack:** SUI Move 2024.beta, `dynamic_field` pattern, SUI Seal framework

**Dependency graph (post-v3):**
```
guild         → constants
storage       → constants, guild
courier_market → storage, threat_oracle, guild, constants
seal_policy   → guild, storage, courier_market
transport     → storage, threat_oracle, fuel (unchanged)
fuel_station  → storage, fuel, constants (unchanged)
```

**Upgrade Constraints:**
- ❌ Cannot modify existing struct layouts (Storage, CourierContract, etc.)
- ❌ Cannot modify existing public function signatures
- ✅ CAN add new modules, functions, struct types
- ✅ Use `dynamic_field` to extend existing objects
- ✅ Modify function bodies (add checks, clean up dynamic_fields)
- ✅ Disable replaced functions with `abort E_DISABLED`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `move/sources/guild.move` | Guild shared object + GuildMemberCap management |
| Create | `move/sources/seal_policy.move` | SUI Seal decryption policies for encrypted coords |
| Modify | `move/sources/constants.move` | Guild discount BPS, max guild members |
| Modify | `move/sources/storage.move` | guild_id dynamic_field, owned storage, encrypted coords, guild withdraw |
| Modify | `move/sources/courier_market.move` | Guild bonus create/settle, dynamic_field cleanup |
| Create | `move/tests/guild_tests.move` | Guild unit + monkey tests |
| Create | `move/tests/guild_monkey_tests.move` | Guild edge case / adversarial tests |
| Create | `move/tests/seal_policy_tests.move` | Seal policy approval tests |
| Modify | `move/tests/storage_tests.move` | Guild storage + owned storage tests |
| Modify | `move/tests/storage_monkey_tests.move` | Guild storage edge cases |
| Modify | `move/tests/courier_market_tests.move` | Guild bonus settle tests |
| Modify | `move/tests/courier_market_monkey_tests.move` | Guild bonus edge cases |
| Modify | `move/tests/integration_tests.move` | Cross-module guild + seal flows |

---

## Task 1: Constants + Guild Module Foundation

**Files:**
- Modify: `move/sources/constants.move`
- Create: `move/sources/guild.move`
- Create: `move/tests/guild_tests.move`
- Create: `move/tests/guild_monkey_tests.move`

### Step 1: Add constants

- [ ] **Add guild constants to `move/sources/constants.move`**

```move
/// Guild member fee discount: 3000 = 30% off storage fees
public fun guild_fee_discount_bps(): u64 { 3000 }

/// Max members per guild
public fun max_guild_members(): u64 { 100 }

/// Max guild name length in bytes (Red Team Fix: input fuzzing)
public fun max_guild_name_length(): u64 { 128 }
```

### Step 2: Write guild unit tests (failing)

- [ ] **Create `move/tests/guild_tests.move` with all unit tests**

```move
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
        let leader_cap = guild::create_guild(b"StarHaulers".to_string(), &clock, scenario.ctx());
        transfer::transfer(leader_cap, leader); // key only — use transfer in test module? No!
        // GuildMemberCap is key-only → need guild::transfer_guild_member_cap
        // Actually, in the test module we can't call transfer::transfer for key-only.
        // The create_guild function should transfer the cap internally.
        // Revised: create_guild transfers leader cap internally, returns nothing.
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
    // Leader adds member
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    // Verify member received cap
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
    // Leader removes member
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, member);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    // Member's cap is now stale
    scenario.next_tx(member);
    {
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        assert!(!guild::verify_membership(&guild, &cap));
        // Member can destroy stale cap
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
    // Member leaves
    scenario.next_tx(member);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::leave_guild(&mut guild, cap);
        assert!(guild::guild_member_count(&guild) == 1); // only leader remains
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
```

### Step 3: Run tests to verify they fail

- [ ] **Run: `sui move test guild_tests`**

Expected: FAIL — module `guild` not found.

### Step 4: Implement guild module

- [ ] **Create `move/sources/guild.move`**

```move
module astrologistics::guild;

use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;
use astrologistics::constants;

// ============ Error codes ============
const E_NOT_LEADER: u64 = 0;
const E_ALREADY_MEMBER: u64 = 1;
const E_NOT_MEMBER: u64 = 2;
const E_GUILD_FULL: u64 = 3;
const E_LEADER_CANNOT_LEAVE: u64 = 4;
const E_CAP_GUILD_MISMATCH: u64 = 5;
const E_NAME_TOO_LONG: u64 = 6;  // Red Team Fix: input fuzzing

// ============ Structs ============

public struct Guild has key {
    id: UID,
    name: std::string::String,
    leader: address,
    members: Table<address, bool>,
    member_count: u64,
    created_at: u64,
}

/// Non-transferable guild membership token.
/// Validity is checked against Guild.members table (can become stale if removed).
public struct GuildMemberCap has key {
    id: UID,
    guild_id: ID,
    member: address,
}

// ============ Events ============

public struct GuildCreated has copy, drop {
    guild_id: ID,
    leader: address,
    name: std::string::String,
}

public struct MemberAdded has copy, drop {
    guild_id: ID,
    member: address,
}

public struct MemberRemoved has copy, drop {
    guild_id: ID,
    member: address,
}

public struct MemberLeft has copy, drop {
    guild_id: ID,
    member: address,
}

// ============ Public functions ============

/// Create a new guild. Caller becomes leader and auto-enrolled member.
/// GuildMemberCap is transferred to leader internally (key-only, no public_transfer).
public fun create_guild(
    name: std::string::String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Red Team Fix: prevent storage bloat via oversized guild names
    assert!(name.length() <= constants::max_guild_name_length(), E_NAME_TOO_LONG);

    let leader = ctx.sender();
    let mut members = table::new<address, bool>(ctx);
    table::add(&mut members, leader, true);

    let guild = Guild {
        id: object::new(ctx),
        name,
        leader,
        members,
        member_count: 1,
        created_at: clock::timestamp_ms(clock),
    };

    let guild_id = object::id(&guild);

    let leader_cap = GuildMemberCap {
        id: object::new(ctx),
        guild_id,
        member: leader,
    };

    event::emit(GuildCreated { guild_id, leader, name: guild.name });

    transfer::share_object(guild);
    transfer::transfer(leader_cap, leader);
}

/// Leader adds a member. GuildMemberCap transferred to member internally.
public fun add_member(
    guild: &mut Guild,
    leader_cap: &GuildMemberCap,
    member_addr: address,
    ctx: &mut TxContext,
) {
    assert!(leader_cap.guild_id == object::id(guild), E_CAP_GUILD_MISMATCH);
    assert!(leader_cap.member == guild.leader, E_NOT_LEADER);
    assert!(!table::contains(&guild.members, member_addr), E_ALREADY_MEMBER);
    assert!(guild.member_count < constants::max_guild_members(), E_GUILD_FULL);

    table::add(&mut guild.members, member_addr, true);
    guild.member_count = guild.member_count + 1;

    let cap = GuildMemberCap {
        id: object::new(ctx),
        guild_id: object::id(guild),
        member: member_addr,
    };

    event::emit(MemberAdded { guild_id: object::id(guild), member: member_addr });
    transfer::transfer(cap, member_addr);
}

/// Leader removes a member from the guild table.
/// The member's GuildMemberCap still exists but verify_membership will return false.
public fun remove_member(
    guild: &mut Guild,
    leader_cap: &GuildMemberCap,
    member_addr: address,
) {
    assert!(leader_cap.guild_id == object::id(guild), E_CAP_GUILD_MISMATCH);
    assert!(leader_cap.member == guild.leader, E_NOT_LEADER);
    assert!(table::contains(&guild.members, member_addr), E_NOT_MEMBER);
    assert!(member_addr != guild.leader, E_LEADER_CANNOT_LEAVE); // leader can't remove self

    table::remove(&mut guild.members, member_addr);
    guild.member_count = guild.member_count - 1;

    event::emit(MemberRemoved { guild_id: object::id(guild), member: member_addr });
}

/// Member voluntarily leaves the guild and destroys their cap.
public fun leave_guild(
    guild: &mut Guild,
    cap: GuildMemberCap,
) {
    let GuildMemberCap { id, guild_id, member } = cap;
    assert!(guild_id == object::id(guild), E_CAP_GUILD_MISMATCH);
    assert!(member != guild.leader, E_LEADER_CANNOT_LEAVE);

    if (table::contains(&guild.members, member)) {
        table::remove(&mut guild.members, member);
        guild.member_count = guild.member_count - 1;
    };

    event::emit(MemberLeft { guild_id: object::id(guild), member });
    object::delete(id);
}

/// Destroy a stale cap (member was removed by leader, cap is no longer valid).
public fun destroy_stale_cap(cap: GuildMemberCap) {
    let GuildMemberCap { id, guild_id: _, member: _ } = cap;
    object::delete(id);
}

/// Check if a cap holder is currently a valid member of the guild.
public fun verify_membership(guild: &Guild, cap: &GuildMemberCap): bool {
    cap.guild_id == object::id(guild) &&
    table::contains(&guild.members, cap.member)
}

// ============ Getters ============

public fun guild_leader(guild: &Guild): address { guild.leader }
public fun guild_member_count(guild: &Guild): u64 { guild.member_count }
public fun guild_name(guild: &Guild): &std::string::String { &guild.name }
public fun member_cap_guild_id(cap: &GuildMemberCap): ID { cap.guild_id }
public fun member_cap_member(cap: &GuildMemberCap): address { cap.member }
public fun is_member(guild: &Guild, addr: address): bool {
    table::contains(&guild.members, addr)
}
```

### Step 5: Run tests to verify they pass

- [ ] **Run: `sui move test guild_tests`**

Expected: All 5 tests PASS.

### Step 6: Write monkey tests (failing)

- [ ] **Create `move/tests/guild_monkey_tests.move`**

```move
#[test_only]
module astrologistics::guild_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::guild::{Self, Guild, GuildMemberCap};

// ---- Helpers ----

fun setup_guild(): test_scenario::Scenario {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario
}

fun setup_guild_with_member(): test_scenario::Scenario {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario
}

// ---- Monkey Tests ----

#[test]
#[expected_failure(abort_code = astrologistics::guild::E_ALREADY_MEMBER)]
fun test_double_add_member() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = setup_guild_with_member();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx()); // double add
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::E_NOT_LEADER)]
fun test_non_leader_adds_member() {
    let member = @0xA2;
    let outsider = @0xA3;
    let mut scenario = setup_guild_with_member();
    // Member (not leader) tries to add someone
    scenario.next_tx(member);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let member_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &member_cap, outsider, scenario.ctx());
        test_scenario::return_to_sender(&scenario, member_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::E_NOT_MEMBER)]
fun test_remove_non_member() {
    let leader = @0xA1;
    let outsider = @0xA3;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, outsider);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::E_LEADER_CANNOT_LEAVE)]
fun test_leader_cannot_leave() {
    let leader = @0xA1;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::leave_guild(&mut guild, cap); // leader can't leave
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::E_LEADER_CANNOT_LEAVE)]
fun test_leader_cannot_remove_self() {
    let leader = @0xA1;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, leader); // can't self-remove
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_stale_cap_after_removal() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = setup_guild_with_member();
    // Remove member
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, member);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    // Member's cap exists but is stale
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
#[expected_failure(abort_code = astrologistics::guild::E_CAP_GUILD_MISMATCH)]
fun test_wrong_guild_cap() {
    // leader1 creates guild1, leader2 creates guild2
    // leader1 tries to add member to guild2 using guild1's cap → E_CAP_GUILD_MISMATCH
    let leader1 = @0xA1;
    let leader2 = @0xA2;
    let outsider = @0xA3;
    let mut scenario = test_scenario::begin(leader1);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"Guild1".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader2);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"Guild2".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    // leader1 takes their cap (guild1), tries to add to guild2
    scenario.next_tx(leader1);
    {
        let g1 = test_scenario::take_shared<Guild>(&scenario);
        let g2 = test_scenario::take_shared<Guild>(&scenario);
        let cap1 = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        // Identify which shared guild is guild2 (leader2's)
        let (mut target, other) = if (guild::guild_leader(&g1) == leader2) {
            (g1, g2)
        } else {
            (g2, g1)
        };
        guild::add_member(&mut target, &cap1, outsider, scenario.ctx()); // wrong cap!
        test_scenario::return_to_sender(&scenario, cap1);
        test_scenario::return_shared(target);
        test_scenario::return_shared(other);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::E_GUILD_FULL)]
fun test_guild_full() {
    // Fill guild to max_guild_members, then try to add one more
    let leader = @0xA1;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        // Add max_guild_members - 1 members (leader already counts as 1)
        let mut i = 1u64;
        while (i < 100) { // constants::max_guild_members() = 100
            let member_addr = @0x1000 + i; // pseudo — use address arithmetic or hardcode
            guild::add_member(&mut guild, &leader_cap, member_addr, scenario.ctx());
            i = i + 1;
        };
        // Now guild is full (100 members). Try one more.
        guild::add_member(&mut guild, &leader_cap, @0xFFFF, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}
```

> **Implementation note for `test_guild_full`:** Move test addresses can be constructed via hex literals (`@0x1001`, `@0x1002`, ...). The loop creates 99 members + leader = 100. The 101st add should abort with `E_GUILD_FULL`. If `address + u64` arithmetic doesn't compile, use a lookup table of addresses or hardcode a subset.

Add this test to the same file:

```move
#[test]
#[expected_failure(abort_code = astrologistics::guild::E_NAME_TOO_LONG)]
fun test_guild_name_too_long() {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        // 200 bytes > max 128
        let long_name = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".to_string();
        guild::create_guild(long_name, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

### Step 7: Run monkey tests

- [ ] **Run: `sui move test guild_monkey`**

Expected: All monkey tests PASS (expected_failure tests abort correctly).

### Step 8: Commit

- [ ] **Commit**

```bash
git add move/sources/constants.move move/sources/guild.move move/tests/guild_tests.move move/tests/guild_monkey_tests.move
git commit -m "feat(v3): add guild module — Guild shared object + GuildMemberCap"
```

---

## Task 2: Storage Guild Integration

**Files:**
- Modify: `move/sources/storage.move`
- Modify: `move/tests/storage_tests.move`
- Modify: `move/tests/storage_monkey_tests.move`

### Step 1: Write guild storage tests (failing)

- [ ] **Add tests to `move/tests/storage_tests.move`**

```move
// Add imports at top:
// use astrologistics::guild::{Self, Guild, GuildMemberCap};

#[test]
fun test_set_storage_guild() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let guild_id = object::id(&guild);

        // Set guild
        storage::set_storage_guild(&mut s, &cap, guild_id);
        let guild_opt = storage::storage_guild_id(&s);
        assert!(option::is_some(&guild_opt));
        assert!(*option::borrow(&guild_opt) == guild_id);

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_remove_storage_guild() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);

        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        storage::remove_storage_guild(&mut s, &cap);
        assert!(option::is_none(&storage::storage_guild_id(&s)));

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_withdraw_as_guild_member() {
    let admin = @0xAD;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(admin);
    // Setup: storage + guild + add member
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 500, &clock, scenario.ctx()); // 5% fee
        transfer::public_transfer(admin_cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);

        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    // Member deposits cargo
    scenario.next_tx(member);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let receipt = storage::deposit(&mut s, b"ore", 500, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, member);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Member withdraws with guild discount (1 day later)
    // Normal fee: 10000 * 500 / 10000 * 1 = 500
    // Guild discount: 500 * (10000 - 3000) / 10000 = 350
    scenario.next_tx(member);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let guild_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(500, scenario.ctx());

        let cargo = storage::withdraw_as_guild_member(
            &mut s, receipt, payment, &guild, &guild_cap, &clock, scenario.ctx()
        );
        // Fee should be 350 (30% discount on 500)
        transfer::public_transfer(cargo, member);
        test_scenario::return_to_sender(&scenario, guild_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

### Step 2: Run tests to verify they fail

- [ ] **Run: `sui move test test_set_storage_guild`**

Expected: FAIL — `set_storage_guild` not found.

### Step 3: Implement storage guild integration

- [ ] **Add to `move/sources/storage.move`**

Add imports:
```move
use sui::dynamic_field;
use astrologistics::guild::{Self, Guild, GuildMemberCap};
```

Add error codes:
```move
const E_NOT_GUILD_MEMBER: u64 = 11;
const E_NO_GUILD: u64 = 12;
const E_GUILD_MISMATCH: u64 = 13;
```

Add dynamic_field key struct:
```move
/// Marker key for guild_id dynamic_field on Storage
public struct GuildIdKey has copy, drop, store {}
```

Add functions:
```move
/// Set guild_id on a storage (AdminCap gated). Uses dynamic_field (upgrade-safe).
public fun set_storage_guild(storage: &mut Storage, cap: &AdminCap, guild_id: ID) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    if (dynamic_field::exists_(&storage.id, GuildIdKey {})) {
        *dynamic_field::borrow_mut(&mut storage.id, GuildIdKey {}) = guild_id;
    } else {
        dynamic_field::add(&mut storage.id, GuildIdKey {}, guild_id);
    };
}

/// Remove guild_id from a storage (AdminCap gated).
public fun remove_storage_guild(storage: &mut Storage, cap: &AdminCap) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    if (dynamic_field::exists_(&storage.id, GuildIdKey {})) {
        let _: ID = dynamic_field::remove(&mut storage.id, GuildIdKey {});
    };
}

/// Get guild_id of a storage. Returns None if not set.
public fun storage_guild_id(storage: &Storage): Option<ID> {
    if (dynamic_field::exists_(&storage.id, GuildIdKey {})) {
        option::some(*dynamic_field::borrow(&storage.id, GuildIdKey {}))
    } else {
        option::none()
    }
}

/// Withdraw with guild member fee discount.
/// Discount: fee * (BPS_SCALE - guild_fee_discount_bps) / BPS_SCALE
#[allow(lint(self_transfer))]
public fun withdraw_as_guild_member(
    storage: &mut Storage,
    receipt: DepositReceipt,
    payment: Coin<SUI>,
    guild: &Guild,
    guild_cap: &GuildMemberCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Cargo {
    // Verify guild membership
    assert!(guild::verify_membership(guild, guild_cap), E_NOT_GUILD_MEMBER);
    // Verify storage has a guild and it matches
    let storage_guild = storage_guild_id(storage);
    assert!(option::is_some(&storage_guild), E_NO_GUILD);
    assert!(*option::borrow(&storage_guild) == object::id(guild), E_GUILD_MISMATCH);

    let DepositReceipt { id, storage_id, cargo_id, depositor: _ } = receipt;
    assert!(storage_id == object::id(storage), E_RECEIPT_MISMATCH);
    assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);
    object::delete(id);

    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };

    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;

    // Calculate fee with guild discount
    let now = clock::timestamp_ms(clock);
    let duration_ms = if (now > cargo.deposited_at) { now - cargo.deposited_at } else { 0 };
    let days_stored = duration_ms / 86_400_000;
    let base_fee = if (days_stored == 0) { 0 } else {
        (((cargo.value as u128) * (storage.fee_rate_bps as u128) * (days_stored as u128)
          / (constants::bps_scale() as u128)) as u64)
    };
    // Apply guild discount
    let fee = ((base_fee as u128)
        * ((constants::bps_scale() - constants::guild_fee_discount_bps()) as u128)
        / (constants::bps_scale() as u128)) as u64;

    assert!(coin::value(&payment) >= fee, E_INSUFFICIENT_FEE);
    if (fee > 0) {
        let mut payment_balance = coin::into_balance(payment);
        let fee_balance = balance::split(&mut payment_balance, fee);
        balance::join(&mut storage.accumulated_fees, fee_balance);
        if (balance::value(&payment_balance) > 0) {
            transfer::public_transfer(coin::from_balance(payment_balance, ctx), ctx.sender());
        } else {
            balance::destroy_zero(payment_balance);
        };
    } else {
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, ctx.sender());
        } else {
            coin::destroy_zero(payment);
        };
    };

    event::emit(CargoWithdrawn {
        storage_id: object::id(storage),
        cargo_id,
        withdrawer: ctx.sender(),
        storage_fee: fee,
    });

    cargo
}
```

### Step 4: Run tests

- [ ] **Run: `sui move test storage_tests`**

Expected: All tests PASS (old + new).

### Step 5: Add monkey tests for guild storage

- [ ] **Add to `move/tests/storage_monkey_tests.move`**

```move
// Add at end of file:

#[test]
#[expected_failure(abort_code = astrologistics::storage::E_CAP_MISMATCH)]
fun test_set_guild_wrong_cap() {
    // Admin of storage1 tries to set guild on storage2
    let admin1 = @0xA1;
    let admin2 = @0xA2;
    let mut scenario = test_scenario::begin(admin1);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin1);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin2);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap2, admin2);
        clock::destroy_for_testing(clock);
    };
    // admin2 tries to set guild on storage1 using cap2
    scenario.next_tx(admin2);
    {
        // Take the storage with system_id 1001 (admin1's)
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let cap2 = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let (mut target, other) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let fake_guild_id = object::id_from_address(@0xDEAD);
        storage::set_storage_guild(&mut target, &cap2, fake_guild_id); // wrong cap
        test_scenario::return_to_sender(&scenario, cap2);
        test_scenario::return_shared(target);
        test_scenario::return_shared(other);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::storage::E_NOT_GUILD_MEMBER)]
fun test_withdraw_guild_non_member() {
    // Non-member tries withdraw_as_guild_member — should fail
    // Setup: storage with guild, user is NOT a member
    let admin = @0xAD;
    let outsider = @0xA3;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 500, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    // Set guild on storage
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    // Outsider creates their own guild (to get a GuildMemberCap from a DIFFERENT guild)
    scenario.next_tx(outsider);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"FakeGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    // Outsider deposits
    scenario.next_tx(outsider);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, outsider);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Outsider tries guild withdraw with wrong guild cap
    scenario.next_tx(outsider);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        // Take the admin's guild (the one associated with storage)
        let g1 = test_scenario::take_shared<Guild>(&scenario);
        let g2 = test_scenario::take_shared<Guild>(&scenario);
        let fake_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(500, scenario.ctx());

        // fake_cap is from FakeGuild, but storage is associated with TestGuild
        // verify_membership will return false → E_NOT_GUILD_MEMBER (if we pass the right guild)
        // OR E_GUILD_MISMATCH (if cap's guild != storage's guild)
        // Either way, it should fail
        let target_guild = if (guild::guild_leader(&g1) == admin) { &g1 } else { &g2 };
        let cargo = storage::withdraw_as_guild_member(
            &mut s, receipt, payment, target_guild, &fake_cap, &clock, scenario.ctx()
        );
        transfer::public_transfer(cargo, outsider);
        test_scenario::return_to_sender(&scenario, fake_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(g1);
        test_scenario::return_shared(g2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

### Step 6: Run all storage tests

- [ ] **Run: `sui move test storage`**

Expected: All PASS.

### Step 7: Commit

- [ ] **Commit**

```bash
git add move/sources/storage.move move/tests/storage_tests.move move/tests/storage_monkey_tests.move
git commit -m "feat(v3): storage guild integration — dynamic_field guild_id + guild member discount withdraw"
```

---

## Task 3: Owned/Private Storage

**Files:**
- Modify: `move/sources/storage.move`
- Modify: `move/tests/storage_tests.move`

### Step 1: Write tests (failing)

- [ ] **Add tests to `move/tests/storage_tests.move`**

```move
#[test]
fun test_create_private_storage() {
    let owner = @0xB1;
    let mut scenario = test_scenario::begin(owner);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_private_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, owner);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(owner);
    {
        // Private storage is owned, not shared
        assert!(test_scenario::has_most_recent_for_sender<Storage>(&scenario));
        assert!(test_scenario::has_most_recent_for_sender<storage::AdminCap>(&scenario));
        let storage = test_scenario::take_from_sender<Storage>(&scenario);
        assert!(storage::system_id(&storage) == 1001);
        test_scenario::return_to_sender(&scenario, storage);
    };
    scenario.end();
}

#[test]
fun test_share_storage() {
    let owner = @0xB1;
    let other = @0xB2;
    let mut scenario = test_scenario::begin(owner);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_private_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, owner);
        clock::destroy_for_testing(clock);
    };
    // Owner shares the storage
    scenario.next_tx(owner);
    {
        let storage = test_scenario::take_from_sender<Storage>(&scenario);
        storage::share_storage(storage);
    };
    // Now other users can access it as shared
    scenario.next_tx(other);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        assert!(storage::system_id(&s) == 1001);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
fun test_private_storage_owner_deposit_withdraw() {
    let owner = @0xB1;
    let mut scenario = test_scenario::begin(owner);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_private_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, owner);
        clock::destroy_for_testing(clock);
    };
    // Owner deposits into their own private storage
    scenario.next_tx(owner);
    {
        let mut s = test_scenario::take_from_sender<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 300, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, owner);
        test_scenario::return_to_sender(&scenario, s);
        clock::destroy_for_testing(clock);
    };
    // Owner withdraws
    scenario.next_tx(owner);
    {
        let mut s = test_scenario::take_from_sender<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(0, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());
        transfer::public_transfer(cargo, owner);
        test_scenario::return_to_sender(&scenario, s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

### Step 2: Run tests to verify failure

- [ ] **Run: `sui move test test_create_private_storage`**

Expected: FAIL — `create_private_storage` not found.

### Step 3: Implement owned storage functions

- [ ] **Add to `move/sources/storage.move`**

Add event:
```move
public struct StorageShared has copy, drop {
    storage_id: ID,
    owner: address,
}
```

Add functions:
```move
/// Create a private (owned) storage. NOT shared — only owner can interact.
/// Call share_storage() later to permanently convert to shared.
public fun create_private_storage(
    system_id: u64,
    max_capacity: u64,
    fee_rate_bps: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): AdminCap {
    assert!(fee_rate_bps <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);

    let storage = Storage {
        id: object::new(ctx),
        owner: ctx.sender(),
        system_id,
        max_capacity,
        current_load: 0,
        fee_rate_bps,
        cargo_bag: object_bag::new(ctx),
        live_receipts: table::new(ctx),
        accumulated_fees: balance::zero(),
        created_at: clock::timestamp_ms(clock),
    };
    let storage_id = object::id(&storage);

    event::emit(StorageCreated {
        storage_id,
        owner: ctx.sender(),
        system_id,
        max_capacity,
    });

    // Transfer to owner (owned object, not shared)
    transfer::transfer(storage, ctx.sender());

    AdminCap {
        id: object::new(ctx),
        storage_id,
    }
}

/// Permanently convert an owned storage to shared. Irreversible (SUI limitation).
/// This enables other players to deposit/withdraw and interact with the storage.
public fun share_storage(storage: Storage) {
    let storage_id = object::id(&storage);
    let owner = storage.owner;
    event::emit(StorageShared { storage_id, owner });
    transfer::share_object(storage);
}
```

### Step 4: Run tests

- [ ] **Run: `sui move test storage_tests`**

Expected: All PASS.

### Step 5: Commit

- [ ] **Commit**

```bash
git add move/sources/storage.move move/tests/storage_tests.move
git commit -m "feat(v3): owned/private storage — create_private_storage + share_storage (one-way)"
```

---

## Task 4: Courier Guild Bonus Differential

**Files:**
- Modify: `move/sources/courier_market.move`
- Modify: `move/tests/courier_market_tests.move`
- Modify: `move/tests/courier_market_monkey_tests.move`

### Key Design Decision

**Old `settle` naturally handles non-guild case on guild contracts:**
- `client_deposit` = reward + cancel_penalty + guild_bonus
- `settle` pays `reward` to courier, returns rest (cancel_penalty + guild_bonus) to client
- This IS the correct "outsider" behavior — no code change needed for non-guild path

**Only need:**
1. `create_contract_with_guild_bonus` — stores GuildBonusInfo via dynamic_field
2. `settle_as_guild_member` — verifies guild, gives reward + bonus to courier
3. All functions that delete CourierContract UID must clean up dynamic_fields first

### Step 1: Write tests (failing)

- [ ] **Add tests to `move/tests/courier_market_tests.move`**

```move
// Add import: use astrologistics::guild::{Self, Guild, GuildMemberCap};

#[test]
fun test_create_contract_with_guild_bonus() {
    let client = @0xC1;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    // Create guild
    scenario.next_tx(client);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"ClientGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    // Create contract with guild bonus
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let cancel_penalty = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        let guild_bonus = coin::mint_for_testing<SUI>(1000, scenario.ctx());

        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        let _contract_id = courier_market::create_contract_with_guild_bonus(
            from, to, receipt, reward, cancel_penalty, guild_bonus,
            8000, vector[1001, 2002], 7_200_000,
            object::id(&guild),
            &clock, scenario.ctx()
        );

        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        test_scenario::return_shared(guild);
        clock::destroy_for_testing(clock);
    };

    // Verify contract exists
    scenario.next_tx(client);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        assert!(courier_market::contract_reward(&contract) == 5000);
        // client_deposit should be 5000 + 2000 + 1000 = 8000
        test_scenario::return_shared(contract);
    };
    scenario.end();
}

#[test]
fun test_settle_as_guild_member() {
    let client = @0xC1;
    let courier = @0xC2;
    let admin = @0xAD;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    // Create guild, add courier as member
    scenario.next_tx(client);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"ClientGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(client);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, courier, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };

    // Create contract with guild bonus
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let cancel_penalty = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        let guild_bonus = coin::mint_for_testing<SUI>(1000, scenario.ctx());

        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        courier_market::create_contract_with_guild_bonus(
            from, to, receipt, reward, cancel_penalty, guild_bonus,
            8000, vector[1001, 2002], 7_200_000,
            object::id(&guild),
            &clock, scenario.ctx()
        );

        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        test_scenario::return_shared(guild);
        clock::destroy_for_testing(clock);
    };

    // Courier accepts
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(8000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Courier picks up and delivers
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);

        let (from, to) = if (storage::system_id(&s1) == 1001) {
            (&mut s1, &mut s2)
        } else {
            (&mut s2, &mut s1)
        };
        courier_market::pickup_and_deliver(&mut contract, &badge, from, to, &clock, scenario.ctx());
        test_scenario::return_to_sender(&scenario, badge);
        test_scenario::return_shared(contract);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };

    // Client confirms
    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        courier_market::confirm_delivery(&mut contract, scenario.ctx());
        test_scenario::return_shared(contract);
    };

    // Courier settles AS GUILD MEMBER — should get reward + guild_bonus
    scenario.next_tx(courier);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let oracle_cap = test_scenario::take_from_address<threat_oracle::OracleCap>(&scenario, admin);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let guild_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);

        courier_market::settle_as_guild_member(
            contract, badge, &oracle_cap, &guild, &guild_cap, scenario.ctx()
        );
        // Courier should receive: reward (5000) + guild_bonus (1000) = 6000
        // Client should receive: cancel_penalty (2000)

        test_scenario::return_to_sender(&scenario, guild_cap);
        transfer::public_transfer(oracle_cap, admin);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_settle_non_guild_on_guild_contract() {
    // Non-guild courier uses old settle() on a guild contract
    // Courier gets reward (5000), client gets cancel_penalty + guild_bonus (3000)
    let client = @0xC1;
    let courier = @0xC2;
    let admin = @0xAD;
    let mut scenario = setup_world();
    deposit_cargo(&mut scenario, client);

    // Create guild (courier is NOT a member)
    scenario.next_tx(client);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"ClientGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    // Create contract with guild bonus
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let cancel_penalty = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        let guild_bonus = coin::mint_for_testing<SUI>(1000, scenario.ctx());

        let (from, to) = if (storage::system_id(&s1) == 1001) { (&s1, &s2) } else { (&s2, &s1) };
        courier_market::create_contract_with_guild_bonus(
            from, to, receipt, reward, cancel_penalty, guild_bonus,
            8000, vector[1001, 2002], 7_200_000,
            object::id(&guild),
            &clock, scenario.ctx()
        );

        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        test_scenario::return_shared(guild);
        clock::destroy_for_testing(clock);
    };

    // Courier accepts
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(8000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, courier);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Courier picks up and delivers
    scenario.next_tx(courier);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);
        let (from, to) = if (storage::system_id(&s1) == 1001) {
            (&mut s1, &mut s2)
        } else {
            (&mut s2, &mut s1)
        };
        courier_market::pickup_and_deliver(&mut contract, &badge, from, to, &clock, scenario.ctx());
        test_scenario::return_to_sender(&scenario, badge);
        test_scenario::return_shared(contract);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };

    // Client confirms
    scenario.next_tx(client);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        courier_market::confirm_delivery(&mut contract, scenario.ctx());
        test_scenario::return_shared(contract);
    };

    // Courier uses OLD settle() — gets reward only, guild_bonus returns to client
    scenario.next_tx(courier);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let oracle_cap = test_scenario::take_from_address<threat_oracle::OracleCap>(&scenario, admin);

        courier_market::settle(contract, badge, &oracle_cap, scenario.ctx());
        // Courier gets: reward (5000) + courier_deposit (8000)
        // Client gets: cancel_penalty + guild_bonus (2000 + 1000 = 3000)

        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.end();
}
```

### Step 2: Run tests to verify failure

- [ ] **Run: `sui move test test_create_contract_with_guild_bonus`**

Expected: FAIL — `create_contract_with_guild_bonus` not found.

> **IMPORTANT: Steps 3–5 must be implemented atomically before running any tests.** Creating `create_contract_with_guild_bonus` (Step 3) without the dynamic_field cleanup in Step 5 means old `settle`/`resolve_dispute`/`claim_timeout`/`cancel_by_client` will crash on `object::delete` for guild contracts (dangling dynamic_field). Implement all three steps, THEN run tests.

### Step 3: Implement guild bonus types and create function

- [ ] **Add to `move/sources/courier_market.move`**

Add imports:
```move
use sui::dynamic_field;
use astrologistics::guild::{Self, Guild, GuildMemberCap};
```

Add types:
```move
/// Dynamic field key for guild bonus info on CourierContract
public struct GuildBonusKey has copy, drop, store {}

/// Guild bonus metadata stored on CourierContract via dynamic_field
public struct GuildBonusInfo has copy, drop, store {
    amount: u64,
    guild_id: ID,
}
```

Add error code:
```move
const E_NOT_GUILD_MEMBER_SETTLE: u64 = 12;
const E_GUILD_MISMATCH_SETTLE: u64 = 13;
```

Add function:
```move
/// Create a courier contract with guild bonus.
/// Guild courier gets reward + guild_bonus. Non-guild courier gets reward only.
/// guild_bonus coins are merged into client_deposit.
/// GuildBonusInfo stored via dynamic_field.
public fun create_contract_with_guild_bonus(
    from_storage: &Storage,
    to_storage: &Storage,
    receipt: DepositReceipt,
    reward: Coin<SUI>,
    cancel_penalty: Coin<SUI>,
    guild_bonus: Coin<SUI>,
    min_courier_deposit: u64,
    route: vector<u64>,
    deadline_duration: u64,
    required_guild_id: ID,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let now = clock::timestamp_ms(clock);
    assert!(deadline_duration >= MIN_DEADLINE_MS, E_DEADLINE_TOO_SHORT);
    assert!(object::id(from_storage) != object::id(to_storage), E_SAME_STORAGE);
    assert!(coin::value(&reward) >= constants::min_contract_reward(), E_REWARD_TOO_LOW);

    let cargo_id = storage::receipt_cargo_id(&receipt);
    let cargo_value = storage::cargo_value_by_id(from_storage, cargo_id);
    let effective_min_deposit = if (min_courier_deposit > cargo_value) {
        min_courier_deposit
    } else {
        cargo_value
    };

    let reward_amount = coin::value(&reward);
    let guild_bonus_amount = coin::value(&guild_bonus);
    let mut client_balance = coin::into_balance(reward);
    balance::join(&mut client_balance, coin::into_balance(cancel_penalty));
    balance::join(&mut client_balance, coin::into_balance(guild_bonus));

    let mut contract = CourierContract {
        id: object::new(ctx),
        client: ctx.sender(),
        courier: option::none(),
        from_storage: object::id(from_storage),
        to_storage: object::id(to_storage),
        cargo_receipt: option::some(receipt),
        reward: reward_amount,
        client_deposit: client_balance,
        courier_deposit: balance::zero(),
        min_courier_deposit: effective_min_deposit,
        cargo_value,
        route,
        status: STATUS_OPEN,
        deadline: now + deadline_duration,
        pickup_deadline: 0,
        confirm_deadline: 0,
        dispute_deadline: 0,
        created_at: now,
    };

    // Store guild bonus info as dynamic_field
    if (guild_bonus_amount > 0) {
        dynamic_field::add(
            &mut contract.id,
            GuildBonusKey {},
            GuildBonusInfo { amount: guild_bonus_amount, guild_id: required_guild_id },
        );
    };

    let contract_id = object::id(&contract);

    event::emit(ContractCreated {
        contract_id,
        client: ctx.sender(),
        from_storage: object::id(from_storage),
        to_storage: object::id(to_storage),
        reward: reward_amount,
        deadline: now + deadline_duration,
    });

    transfer::share_object(contract);
    contract_id
}
```

### Step 4: Implement settle_as_guild_member

- [ ] **Add to `move/sources/courier_market.move`**

```move
/// Settle a guild contract. Guild courier gets reward + guild_bonus.
/// Verifies courier is in the required guild via GuildMemberCap.
#[allow(lint(self_transfer))]
public fun settle_as_guild_member(
    mut contract: CourierContract,
    badge: CourierBadge,
    oracle_cap: &OracleCap,
    guild: &Guild,
    guild_cap: &GuildMemberCap,
    ctx: &mut TxContext,
) {
    assert!(contract.status == STATUS_DELIVERED, E_WRONG_STATUS);
    assert!(badge.contract_id == object::id(&contract), E_BADGE_MISMATCH);

    // Extract guild bonus info (must exist for this function)
    let guild_bonus_amount = if (dynamic_field::exists_with_type<GuildBonusKey, GuildBonusInfo>(
        &contract.id, GuildBonusKey {}
    )) {
        let info: GuildBonusInfo = dynamic_field::remove(&mut contract.id, GuildBonusKey {});
        // Verify guild membership
        assert!(guild::verify_membership(guild, guild_cap), E_NOT_GUILD_MEMBER_SETTLE);
        assert!(info.guild_id == object::id(guild), E_GUILD_MISMATCH_SETTLE);
        info.amount
    } else {
        0 // No guild bonus — same as regular settle
    };

    let courier_addr = badge.courier;
    let CourierBadge { id: badge_id, contract_id: _, courier: _ } = badge;
    object::delete(badge_id);

    let contract_id = object::id(&contract);
    let CourierContract {
        id, client, courier: _, from_storage: _, to_storage: _,
        cargo_receipt, reward, client_deposit, courier_deposit,
        min_courier_deposit: _, cargo_value: _, route: _, status: _,
        deadline: _, pickup_deadline: _, confirm_deadline: _,
        dispute_deadline: _, created_at: _,
    } = contract;

    // Return receipt to client
    if (option::is_some(&cargo_receipt)) {
        let r = option::destroy_some(cargo_receipt);
        transfer::public_transfer(r, client);
    } else {
        option::destroy_none(cargo_receipt);
    };

    // Pay courier: reward + guild_bonus
    let mut client_bal = client_deposit;
    let total_courier_payout = reward + guild_bonus_amount;
    let reward_payout = balance::split(&mut client_bal, total_courier_payout);
    transfer::public_transfer(coin::from_balance(reward_payout, ctx), courier_addr);

    // Return remaining to client
    if (balance::value(&client_bal) > 0) {
        transfer::public_transfer(coin::from_balance(client_bal, ctx), client);
    } else {
        balance::destroy_zero(client_bal);
    };

    // Return courier deposit
    transfer::public_transfer(coin::from_balance(courier_deposit, ctx), courier_addr);

    // Issue ReporterCap
    let reporter_cap = threat_oracle::issue_reporter_cap(oracle_cap, courier_addr, 1, ctx);
    let reporter_cap_id = object::id(&reporter_cap);
    threat_oracle::transfer_reporter_cap(reporter_cap, courier_addr);

    event::emit(ContractSettled {
        contract_id,
        courier_reward: total_courier_payout,
        reporter_cap_id,
    });

    object::delete(id);
}
```

### Step 5: Modify existing functions to clean up dynamic_fields

- [ ] **Modify `settle`, `resolve_dispute`, `claim_timeout`, `cancel_by_client` in `courier_market.move`**

For each function that destructures CourierContract and calls `object::delete(id)`, add dynamic_field cleanup **before** destructuring (when we still have `&mut contract.id`).

**Pattern** — add this block before `let CourierContract { ... } = contract;` in each function:

```move
// Clean up guild bonus dynamic_field if present
if (dynamic_field::exists_with_type<GuildBonusKey, GuildBonusInfo>(
    &contract.id, GuildBonusKey {}
)) {
    let _: GuildBonusInfo = dynamic_field::remove(&mut contract.id, GuildBonusKey {});
};
```

**Functions to modify:**
1. `settle` — add cleanup before `let contract_id = object::id(&contract);`
   - Change `contract` param to `mut contract`
2. `resolve_dispute` — same pattern, change param to `mut contract`
3. `claim_timeout` — already has `mut` via destructure; add cleanup before destructure
4. `cancel_by_client` — same pattern, change param to `mut contract`

> **Note:** `settle` on a guild contract: courier gets `reward` only (the guild_bonus stays in client_deposit which is returned to client). The dynamic_field is just cleaned up to allow UID deletion. This is the correct "non-guild" behavior.

### Step 6: Run tests

- [ ] **Run: `sui move test courier_market`**

Expected: All tests PASS (old + new).

### Step 7: Run full test suite

- [ ] **Run: `sui move test`**

Expected: All tests PASS (97 old + new guild/courier tests).

### Step 8: Commit

- [ ] **Commit**

```bash
git add move/sources/courier_market.move move/tests/courier_market_tests.move move/tests/courier_market_monkey_tests.move
git commit -m "feat(v3): courier guild bonus — create_contract_with_guild_bonus + settle_as_guild_member"
```

---

## Task 5: Seal Policy Module

> **IMPORTANT:** Invoke `sui-seal` skill before implementing this task to verify the exact SUI Seal framework API (package address, `seal::approve` signature, dependency setup). The code below is based on best-known Seal patterns and may need adjustment.

**Files:**
- Modify: `move/Move.toml` (add Seal dependency)
- Create: `move/sources/seal_policy.move`
- Modify: `move/sources/storage.move` (encrypted coords helpers)
- Create: `move/tests/seal_policy_tests.move`

### Step 1: Add Seal dependency

- [ ] **Invoke `sui-seal` skill and update `move/Move.toml`**

```toml
[dependencies]
# Add SUI Seal dependency — verify exact address with sui-seal skill
# Sui = { git = "...", subdir = "crates/sui-framework/packages/sui-framework", rev = "..." }
# SuiSeal = { ... }
```

### Step 2: Add encrypted coords storage to storage.move

- [ ] **Add to `move/sources/storage.move`**

```move
/// Marker key for encrypted coordinates dynamic_field on Storage
public struct EncryptedCoordsKey has copy, drop, store {}

/// Store encrypted coordinates on a storage (AdminCap gated).
/// Coordinates are encrypted client-side using SUI Seal SDK.
public fun set_encrypted_coords(
    storage: &mut Storage,
    cap: &AdminCap,
    encrypted_data: vector<u8>,
) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    if (dynamic_field::exists_(&storage.id, EncryptedCoordsKey {})) {
        *dynamic_field::borrow_mut(&mut storage.id, EncryptedCoordsKey {}) = encrypted_data;
    } else {
        dynamic_field::add(&mut storage.id, EncryptedCoordsKey {}, encrypted_data);
    };
}

/// Get encrypted coordinates. Returns empty vector if not set.
public fun get_encrypted_coords(storage: &Storage): vector<u8> {
    if (dynamic_field::exists_(&storage.id, EncryptedCoordsKey {})) {
        *dynamic_field::borrow(&storage.id, EncryptedCoordsKey {})
    } else {
        vector[]
    }
}
```

### Step 3: Create seal policy module

- [ ] **Create `move/sources/seal_policy.move`**

```move
module astrologistics::seal_policy;

use astrologistics::guild::{Self, Guild, GuildMemberCap};
use astrologistics::storage::{Self, Storage};
use astrologistics::courier_market::{Self, CourierContract, CourierBadge};

// ============ Error codes ============
const E_NOT_GUILD_MEMBER: u64 = 0;
const E_GUILD_MISMATCH: u64 = 1;
const E_BADGE_MISMATCH: u64 = 2;
const E_CONTRACT_STORAGE_MISMATCH: u64 = 3;
const E_CONTRACT_NOT_ACTIVE: u64 = 4;

// ============ Seal Policy Functions ============

/// Seal approval for guild members.
/// Guild members can decrypt coordinates of any storage in their guild.
///
/// The `id` parameter is the Seal encryption ID — passed by the Seal SDK.
/// This function verifies conditions, then calls the Seal framework approve.
///
/// NOTE: Exact Seal API (seal::approve call) must be verified with sui-seal skill.
/// The function signature may need adjustment for the Seal framework's requirements.
entry fun seal_approve_guild_member(
    guild: &Guild,
    guild_cap: &GuildMemberCap,
    storage: &Storage,
    // id: vector<u8>, // Seal ID — uncomment after verifying Seal API
) {
    // Verify guild membership
    assert!(guild::verify_membership(guild, guild_cap), E_NOT_GUILD_MEMBER);

    // Verify storage belongs to this guild
    let storage_guild = storage::storage_guild_id(storage);
    assert!(option::is_some(&storage_guild), E_GUILD_MISMATCH);
    assert!(*option::borrow(&storage_guild) == object::id(guild), E_GUILD_MISMATCH);

    // TODO: Call seal::approve(id) — verify with sui-seal skill
    // seal::approve(id);
}

/// Seal approval for courier badge holders.
/// Couriers with accepted contracts can decrypt source/destination storage coordinates.
///
/// NOTE: Exact Seal API must be verified with sui-seal skill.
entry fun seal_approve_courier(
    badge: &CourierBadge,
    contract: &CourierContract,
    storage: &Storage,
    // id: vector<u8>, // Seal ID — uncomment after verifying Seal API
) {
    // Verify badge matches contract
    assert!(courier_market::badge_contract_id(badge) == object::id(contract), E_BADGE_MISMATCH);

    // Verify contract is active (Accepted or PendingConfirm)
    let status = courier_market::contract_status(contract);
    assert!(
        status == courier_market::status_accepted() || status == courier_market::status_pending_confirm(),
        E_CONTRACT_NOT_ACTIVE,
    );

    // Verify storage is either source or destination of contract
    let storage_id = object::id(storage);
    assert!(
        courier_market::contract_from_storage(contract) == storage_id ||
        courier_market::contract_to_storage(contract) == storage_id,
        E_CONTRACT_STORAGE_MISMATCH,
    );

    // TODO: Call seal::approve(id) — verify with sui-seal skill
    // seal::approve(id);
}
```

### Step 4: Add missing getter to courier_market

- [ ] **Add getter to `move/sources/courier_market.move`**

```move
/// Get the contract_id from a CourierBadge (needed by seal_policy)
public fun badge_contract_id(badge: &CourierBadge): ID { badge.contract_id }

/// Status constant getters (needed by seal_policy to avoid magic numbers)
public fun status_accepted(): u8 { STATUS_ACCEPTED }
public fun status_pending_confirm(): u8 { STATUS_PENDING_CONFIRM }
```

### Step 5: Write seal policy tests

- [ ] **Create `move/tests/seal_policy_tests.move`**

```move
#[test_only]
module astrologistics::seal_policy_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use astrologistics::storage::{Self, Storage};
use astrologistics::guild::{Self, Guild, GuildMemberCap};
use astrologistics::seal_policy;

#[test]
fun test_set_and_get_encrypted_coords() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let encrypted = b"encrypted_xyz_coords_here";
        storage::set_encrypted_coords(&mut s, &cap, encrypted);
        let result = storage::get_encrypted_coords(&s);
        assert!(result == encrypted);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
fun test_seal_approve_guild_member_valid() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, leader);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    // Set guild on storage + add member
    scenario.next_tx(leader);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    // Member calls seal_approve
    scenario.next_tx(member);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        // Should not abort
        seal_policy::seal_approve_guild_member(&guild, &cap, &s);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::seal_policy::E_NOT_GUILD_MEMBER)]
fun test_seal_approve_non_member() {
    let leader = @0xA1;
    let outsider = @0xA3;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, leader);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    // Outsider creates own guild to get a cap
    scenario.next_tx(outsider);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"FakeGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    // Outsider tries seal_approve with wrong guild cap
    scenario.next_tx(outsider);
    {
        // Take the leader's guild (the one on storage)
        let g1 = test_scenario::take_shared<Guild>(&scenario);
        let g2 = test_scenario::take_shared<Guild>(&scenario);
        let s = test_scenario::take_shared<Storage>(&scenario);
        let fake_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);

        let target = if (guild::guild_leader(&g1) == leader) { &g1 } else { &g2 };
        seal_policy::seal_approve_guild_member(target, &fake_cap, &s);

        test_scenario::return_to_sender(&scenario, fake_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(g1);
        test_scenario::return_shared(g2);
    };
    scenario.end();
}
```

### Step 6: Run tests

- [ ] **Run: `sui move test seal_policy`**

Expected: All PASS.

### Step 7: Commit

- [ ] **Commit**

```bash
git add move/Move.toml move/sources/seal_policy.move move/sources/storage.move move/tests/seal_policy_tests.move
git commit -m "feat(v3): seal policy module — encrypted coords + guild/courier approve"
```

---

## Task 6: Integration Testing + Build

**Files:**
- Modify: `move/tests/integration_tests.move`

### Step 1: Write integration tests

- [ ] **Add integration tests to `move/tests/integration_tests.move`**

Test scenarios:
1. **Full guild flow:** create_guild → add_member → set_storage_guild → verify_membership → guild_member_count
2. **Guild storage + courier (guild member):** create guild → create guild contract with bonus → courier accepts → deliver → guild settle → courier gets reward + bonus
3. **Guild storage + courier (outsider):** same setup → outsider uses old settle → gets reward only, bonus returns to client
4. **Private storage lifecycle:** create_private_storage → owner deposits → owner share_storage → other user deposits → guild assign
5. **Seal flow:** set_encrypted_coords → guild member approve succeeds → non-member approve fails
6. **Full E2E:** guild create → private storage → share → set guild → set coords → guild contract → guild courier deliver → guild settle

```move
// Integration test skeletons — implement full test code based on patterns above

#[test]
fun test_integration_guild_courier_full_flow() {
    // Leader creates guild
    // Leader creates storage, sets guild
    // Courier joins guild
    // Client deposits cargo
    // Client creates contract with guild bonus (required_guild_id = leader's guild)
    // Courier accepts, picks up, delivers
    // Client confirms
    // Courier settles as guild member → gets reward + bonus
    // Verify: courier received total payout, client received cancel_penalty
}

#[test]
fun test_integration_outsider_courier_on_guild_contract() {
    // Same setup as above but courier is NOT in guild
    // Courier uses old settle() → gets reward only
    // Client receives cancel_penalty + guild_bonus
}

#[test]
fun test_integration_private_to_shared_storage() {
    // Owner creates private storage
    // Owner deposits cargo (owns the storage object)
    // Owner calls share_storage
    // Another user can now deposit into the (now shared) storage
}

#[test]
fun test_integration_guild_withdraw_discount() {
    // Setup: guild + storage with guild_id set
    // Guild member deposits cargo
    // Guild member withdraws with discount
    // Verify fee is 30% less than normal
}

#[test]
fun test_integration_seal_guild_member_approve() {
    // Setup: guild + storage with guild + encrypted coords
    // Guild member: seal_approve_guild_member succeeds
    // Non-member: seal_approve_guild_member fails
}

#[test]
fun test_integration_seal_courier_approve() {
    // Setup: courier contract (accepted) + storage with coords
    // Courier with badge: seal_approve_courier succeeds
    // Badge from different contract: fails
}
```

### Step 2: Run integration tests

- [ ] **Run: `sui move test integration`**

Expected: All PASS.

### Step 3: Run full test suite

- [ ] **Run: `sui move test`**

Expected: All tests PASS (97 old + ~20-30 new).

### Step 4: Build verification

- [ ] **Run: `sui move build`**

Expected: Build succeeds with no errors (warnings acceptable).

### Step 5: Commit

- [ ] **Commit**

```bash
git add move/tests/integration_tests.move
git commit -m "test(v3): integration tests — guild + seal + courier bonus E2E flows"
```

### Step 6: Final verification

- [ ] **Run: `sui move test` one final time**

Expected: All tests PASS. Record total test count in progress.md.

---

## Post-Plan Notes

### Upgrade Deployment (separate chat)
After all tests pass, the upgrade should be deployed using `sui-deployer` skill:
1. `sui move build` → verify no errors
2. `sui client upgrade --upgrade-capability <UPGRADE_CAP>` on testnet
3. Re-run smoke test scripts with new functions
4. Verify backward compat: old contracts still settle with old `settle`

### Known Risks
- **Seal API uncertainty:** Task 5 seal_policy functions have placeholder `seal::approve` calls. Must verify with `sui-seal` skill during implementation.
- **dynamic_field cleanup:** All functions that destroy CourierContract must clean up GuildBonusInfo. Missing cleanup = runtime error on `object::delete`.
- **Guild dependency in storage:** Adding `use astrologistics::guild` to storage.move creates a new module dependency. Verify this doesn't break upgrade compatibility.
- **Two-guild test pattern:** Tests with multiple shared Guild objects need the same disambiguation pattern as existing multi-Storage tests (take both, select by property).

### Accepted Risks (Red Team Findings)

- **RT-V3-1 Guild revocation griefing (Medium):** Guild leader can `remove_member(courier)` between delivery and settlement, causing `settle_as_guild_member` to abort. Courier falls back to old `settle` and loses guild_bonus but keeps base reward. **Accepted for hackathon** — guild_bonus is an incentive, not a guarantee. Courier should assess guild leader trust. **Mainnet fix:** Snapshot guild membership at accept time via dynamic_field `GuildMemberAtAccept { is_member: bool }` on CourierContract.
- **RT-V3-2 Stale GuildMemberCap accumulation (Low):** After `remove_member`, the member's cap persists as an owned object (SUI limitation: cannot remotely delete owned objects). `verify_membership` correctly returns false. `destroy_stale_cap` provided for voluntary cleanup. Frontend should prompt users to clean up stale caps.
