module burn::burn_to_earn {
    use std::type_name;
    use sui::bcs;
    use sui::hash;
    use sui::ed25519;
    use sui::dynamic_field;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::event::emit;

    // ======== Errors =========
    const EExpiredTime: u64 = 1;
    const EInvalidSig: u64 = 2;

    public struct GlobalBank has key {
        id: UID,
        public_key: vector<u8>,
    }

    public struct AddBudget has copy, drop {
        sender: address,
        coin_type: std::ascii::String,
        amount: u64,
    }

    public struct ClaimCoin has copy, drop {
        sender: address,
        coin_type: std::ascii::String,
        amount: u64,
    }

    public struct ClaimInfo has drop {
        sender: address,
        coin_type: std::ascii::String,
        amount: u64,
        expired_at: u64,
    }

    fun init(ctx: &mut TxContext) {
        let public_key_data: vector<u8> = vector[];

        let global_bank = GlobalBank {
            id: object::new(ctx),
            public_key: public_key_data,
        };

        transfer::share_object(global_bank);
    }

    #[allow(lint(self_transfer))]
    public fun claim<T>(
        global_bank: &mut GlobalBank, 
        amount: u64,
        expired_at: u64,
        signature: vector<u8>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let now_ms = clock::timestamp_ms(clk);
        assert!(now_ms <= expired_at, EExpiredTime);

        let sender = ctx.sender();
        let coin_type = type_name::into_string(type_name::get_with_original_ids<T>());
        let claim_info = ClaimInfo {
            sender,
            coin_type,
            amount,
            expired_at,
        };
        let claim_data = bcs::to_bytes(&claim_info);
        let claim_data_hash = hash::keccak256(&claim_data);
        let pk: vector<u8> = global_bank.public_key;
        let verify = ed25519::ed25519_verify(&signature, &pk, &claim_data_hash);
        assert!(verify == true, EInvalidSig);

        if (dynamic_field::exists_(&global_bank.id, coin_type)) {
            let balance_bm = dynamic_field::borrow_mut<std::ascii::String, Balance<T>>(&mut global_bank.id, coin_type);
            let bounty = coin::take<T>(balance_bm, amount, ctx);
            transfer::public_transfer(bounty, sender);

            emit(ClaimCoin {
                sender,
                coin_type,
                amount,
            });
        };
    }

    public entry fun add<T>(global_bank: &mut GlobalBank, budget: Coin<T>, ctx: &TxContext) {
        let coin_type = type_name::into_string(type_name::get_with_original_ids<T>());
        let coin_amount = coin::value(&budget);
        if (dynamic_field::exists_(&global_bank.id, coin_type)) {
            let balance_bm = dynamic_field::borrow_mut<std::ascii::String, Balance<T>>(&mut global_bank.id, coin_type);
            coin::put<T>(balance_bm, budget);
        } else {
            let balance_t = coin::into_balance<T>(budget);
            dynamic_field::add<std::ascii::String, Balance<T>>(&mut global_bank.id, coin_type, balance_t);
        };

        emit(AddBudget {
            sender: ctx.sender(),
            coin_type,
            amount: coin_amount,
        });
    }

    public fun get<T>(global_bank: &GlobalBank): u64 {
        let coin_type = type_name::into_string(type_name::get_with_original_ids<T>());
        let mut amount: u64 = 0;
        if (dynamic_field::exists_(&global_bank.id, coin_type)) {
            let balance_b = dynamic_field::borrow<std::ascii::String, Balance<T>>(&global_bank.id, coin_type);
            amount = balance::value<T>(balance_b);
        };
        amount
    }

}

