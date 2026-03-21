module astrologistics::fuel;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::coin_registry;

/// One-Time Witness for FUEL coin
public struct FUEL has drop {}

/// Wrapper around TreasuryCap for public API
public struct FuelTreasuryCap has key, store {
    id: UID,
    cap: TreasuryCap<FUEL>,
}

fun init(witness: FUEL, ctx: &mut TxContext) {
    let (initializer, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        9,
        b"FUEL".to_string(),
        b"Astro Fuel".to_string(),
        b"Fuel token for AstroLogistics cross-galaxy transport".to_string(),
        b"".to_string(),
        ctx,
    );
    // Finalize currency registration and destroy metadata cap
    let metadata_cap = initializer.finalize(ctx);
    transfer::public_transfer(metadata_cap, ctx.sender());

    let fuel_treasury = FuelTreasuryCap {
        id: object::new(ctx),
        cap: treasury_cap,
    };
    transfer::transfer(fuel_treasury, ctx.sender());
}

/// Mint FUEL tokens
public fun mint(treasury: &mut FuelTreasuryCap, amount: u64, ctx: &mut TxContext): Coin<FUEL> {
    coin::mint(&mut treasury.cap, amount, ctx)
}

/// Burn FUEL tokens
public fun burn(treasury: &mut FuelTreasuryCap, coin: Coin<FUEL>) {
    coin::burn(&mut treasury.cap, coin);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(FUEL {}, ctx);
}
