module astrologistics::seal_policy;

use astrologistics::guild::{Self, Guild, GuildMemberCap};
use astrologistics::storage::{Self, Storage};
use astrologistics::courier_market::{Self, CourierContract, CourierBadge};

// ============ Error codes (EPascalCase for new module) ============
const ENotGuildMember: u64 = 0;
const EGuildMismatch: u64 = 1;
const EBadgeMismatch: u64 = 2;
const EContractStorageMismatch: u64 = 3;
const EContractNotActive: u64 = 4;

// ============ Seal Policy Functions ============

/// Seal approval for guild members.
/// Guild members can decrypt coordinates of any storage in their guild.
entry fun seal_approve_guild_member(
    guild: &Guild,
    guild_cap: &GuildMemberCap,
    storage: &Storage,
    // id: vector<u8>, // Seal ID — uncomment after integrating Seal SDK
) {
    assert!(guild::verify_membership(guild, guild_cap), ENotGuildMember);
    let storage_guild = storage::storage_guild_id(storage);
    assert!(option::is_some(&storage_guild), EGuildMismatch);
    assert!(*option::borrow(&storage_guild) == object::id(guild), EGuildMismatch);

    // TODO: Call seal::approve(id) after integrating Seal SDK dependency
}

/// Seal approval for courier badge holders.
/// Couriers with accepted contracts can decrypt source/destination storage coordinates.
entry fun seal_approve_courier(
    badge: &CourierBadge,
    contract: &CourierContract,
    storage: &Storage,
    // id: vector<u8>, // Seal ID — uncomment after integrating Seal SDK
) {
    assert!(courier_market::badge_contract_id(badge) == object::id(contract), EBadgeMismatch);

    let status = courier_market::contract_status(contract);
    assert!(
        status == courier_market::status_accepted() || status == courier_market::status_pending_confirm(),
        EContractNotActive,
    );

    let storage_id = object::id(storage);
    assert!(
        courier_market::contract_from_storage(contract) == storage_id ||
        courier_market::contract_to_storage(contract) == storage_id,
        EContractStorageMismatch,
    );

    // TODO: Call seal::approve(id) after integrating Seal SDK dependency
}
