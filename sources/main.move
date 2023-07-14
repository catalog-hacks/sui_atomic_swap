module atomic_swapv1::AtomicSwap {

    use sui::sui::{Self, SUI};                      // Sui tokens
    use sui::object::{Self, ID, UID};               // objects for the structs
    use sui::coin::{Self, Coin};                    // the coins
    use sui::tx_context::{Self, TxContext};         // Transaction Context
    use sui::clock::{Self, Clock};                  // To access time
    use sui::transfer;                              // To make the object publicly accessible

    use 0x1::hash;                                  // To hash the secret, for the case of redeeming

    // Error codes, self-explanatory
    const ENOT_ENOUGH_BALANCE: u64 = 1;
    const ESWAP_EXPIRED: u64 = 2;
    const ESWAP_NOT_EXPIRED: u64 = 3;
    const ESECRET_MISMATCH: u64 = 4;
    const ECREATED_SWAP_NOT_OURS: u64 = 5;
    const ESWAP_ALREADY_REDEEMED_OR_REFUNDED: u64 = 6;

    // The Swap struct
    struct Swap has key {
        id: UID,
        sender: address,
        reciever: address,
        amount: u64,
        secret_hash: vector<u8>,
        coins: Coin<SUI>,
        expiry: u64,
    }

    // --------------------------------------- Event Structs ---------------------------------------

    // Struct for the initialized Event
    struct InitializeEvent has copy, drop {
        Swap_ID: ID,
        sender: address,
        reciever: address,
    }

    // Struct for the refund Event
    struct RefundEvent has copy, drop {
        Swap_ID: ID,
        sender: address,
        reciever: address,
    }

    // Struct for the redeem Event
    struct RedeemEvent has copy, drop {
        Swap_ID: ID,
        sender: address,
        reciever: address,
        secret: vector<u8>
    }

    // Creates a swap object and makes it a shared_object
    public entry fun initialize_Swap(
        reciever: address,
        coins: &mut Coin<SUI>,
        secret_hash: vector<u8>,
        amount: u64, 
        expiry_hours: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check that value of coins exceeds amount in swap
        assert!(coin::value<SUI>(coins) >= amount, ENOT_ENOUGH_BALANCE);

        // get the required amount out of the users balance
        let swap = Swap {
            id: object::new(ctx),                                               // Create a new ID for the object
            sender: tx_context::sender(ctx),                                    // The address of the sender 
            reciever: reciever,                                                 // The address of the reciever
            amount: amount,                                                     // The amount to be transferred
            secret_hash: secret_hash,                                           // The hashed secret
            coins: coin::split(coins, amount, ctx),                             // The coins where value(coins) == amount
            expiry: clock::timestamp_ms(clock) + expiry_hours * 3600 * 1000     // THe expiry, being (expiry_hours) hours away from initialization time
        };

        // Share the object so anyone can access nad mutate it
        transfer::share_object<Swap>(swap);

        // To Do : Emit event
    }

    // Refunds the coins and destroys Swap object
    public entry fun refund_Swap(
        swap: &mut Swap, 
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // Makes sure that swap has expired
        assert!(swap.expiry < clock::timestamp_ms(clock), ESWAP_NOT_EXPIRED);

        // Unpack the Swap object, only need sender, coins and id (it cant be dropped) so the rest are all _ 
        let amount = swap.amount;
        let sender = swap.sender;

        // If coins are 0, then swap has been used
        assert!(coin::value<SUI>(&swap.coins) > 0, ESWAP_ALREADY_REDEEMED_OR_REFUNDED);

        // Transfer the coins to the sender
        sui::transfer(
            coin::split(
                &mut swap.coins,
                amount,
                ctx
            ), 
            sender
        );
    }

    // Redeems the coins and destroys the Swap object
    public entry fun redeem_Swap(
        swap: &mut Swap,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // Makes sure that swap has expired
        assert!(swap.expiry >= clock::timestamp_ms(clock), ESWAP_EXPIRED);

        // Ensure that the secret sent, after hashing, is same as the hashed_secret we have stored
        assert!(swap.secret_hash == hash::sha2_256(secret), ESECRET_MISMATCH);

        // Unpack the Swap object, only need sender, coins and id (it cant be dropped) so the rest are all _ 
        let amount = swap.amount;
        let reciever = swap.reciever;

        // If coins are 0, then swap has been used
        assert!(coin::value<SUI>(&swap.coins) > 0, ESWAP_ALREADY_REDEEMED_OR_REFUNDED);

        // Transfer the coins to the sender
        sui::transfer(
            coin::split(
                &mut swap.coins,
                amount,
                ctx
            ), 
            reciever
        );
    }

    // ================================================= Tests ================================================= 

    #[test_only]
    use sui::test_scenario;     // The test scenario

    // Test just the initialization part of it
    #[test]
    public fun test_Initialization(){
        let sender_address: address = @0x0;     // Address of the sender    
        let reciever_address: address = @0x1;   // Address of the receiver

        // The secrets
        let secret = b"ABAB";
        let secret_hash = hash::sha2_256(secret);

        let expiry: u64 = 1;
        let amount: u64 = 100;

        // Initializing the scenarios
        let scenario_val = test_scenario::begin(sender_address);
        let scenario = &mut scenario_val;

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let coins_for_test = coin::mint_for_testing<SUI>(amount + 50, test_scenario::ctx(scenario));   // The coins we are going to give

        sui::transfer(coins_for_test, tx_context::sender(test_scenario::ctx(scenario)));

        test_scenario::next_tx(scenario, sender_address);

        let sui_Balance = test_scenario::take_from_sender<Coin<SUI>>(scenario);

        initialize_Swap(
            reciever_address,
            &mut sui_Balance,
            secret_hash,
            amount, 
            expiry,
            &clock,
            test_scenario::ctx(scenario)
        );
        
        // Check that the amount got deducted from the sender's balance!!!!!!!
        assert!(coin::value<SUI>(&sui_Balance) == 50, 69);

        // Send it back to sender
        test_scenario::return_to_sender(scenario, sui_Balance);

        // Make sure that transaction is over
        test_scenario::next_tx(scenario, sender_address);

        // Check the shared swap exists
        let shared_Swap = test_scenario::take_shared<Swap>(scenario);

        assert!(shared_Swap.sender == sender_address, ECREATED_SWAP_NOT_OURS);
        assert!(shared_Swap.reciever == reciever_address, ECREATED_SWAP_NOT_OURS);
        assert!(coin::value<SUI>(&shared_Swap.coins) == amount, ECREATED_SWAP_NOT_OURS);
        assert!(shared_Swap.secret_hash == secret_hash, ECREATED_SWAP_NOT_OURS);

        test_scenario::return_shared(shared_Swap);

        // boilerplate to end the test
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    // Test the refund flow
    #[test]
    public fun test_Refunding(){
        let sender_address: address = @0x0;     // Address of the sender    
        let reciever_address: address = @0x1;   // Address of the receiver

        // The secrets
        let secret = b"ABAB";
        let secret_hash = hash::sha2_256(secret);

        let expiry: u64 = 0;
        let amount: u64 = 100;

        // Initializing the scenarios
        let scenario_val = test_scenario::begin(sender_address);
        let scenario = &mut scenario_val;

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let coins_for_test = coin::mint_for_testing<SUI>(amount + 50, test_scenario::ctx(scenario));   // The coins we are going to give
        sui::transfer(coins_for_test, tx_context::sender(test_scenario::ctx(scenario)));


        test_scenario::next_tx(scenario, sender_address);

        let sui_Balance = test_scenario::take_from_sender<Coin<SUI>>(scenario);

        initialize_Swap(
            reciever_address,
            &mut sui_Balance,
            secret_hash,
            amount, 
            expiry,
            &clock,
            test_scenario::ctx(scenario)
        );
        
        test_scenario::next_tx(scenario, sender_address);

        // Take the swap and increment clock (for refund)
        test_scenario::return_to_sender(scenario, sui_Balance);
        let shared_Swap = test_scenario::take_shared<Swap>(scenario);
        clock::increment_for_testing(&mut clock, 100);
        test_scenario::next_tx(scenario, sender_address);


        refund_Swap(
            &mut shared_Swap,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(shared_Swap);
        test_scenario::next_tx(scenario, sender_address);
 
        // boilerplate to end the test
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    // Test the redeem flow
    #[test]
    public fun test_Redeeming(){
        let sender_address: address = @0x0;     // Address of the sender    
        let reciever_address: address = @0x1;   // Address of the receiver

        // The secrets
        let secret = b"ABAB";
        let secret_hash = hash::sha2_256(secret);

        let expiry: u64 = 0;
        let amount: u64 = 100;

        // Initializing the scenarios
        let scenario_val = test_scenario::begin(sender_address);
        let scenario = &mut scenario_val;

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let coins_for_test = coin::mint_for_testing<SUI>(amount + 50, test_scenario::ctx(scenario));   // The coins we are going to give
        sui::transfer(coins_for_test, tx_context::sender(test_scenario::ctx(scenario)));

        test_scenario::next_tx(scenario, sender_address);

        let sui_Balance = test_scenario::take_from_sender<Coin<SUI>>(scenario);

        initialize_Swap(
            reciever_address,
            &mut sui_Balance,
            secret_hash,
            amount, 
            expiry,
            &clock,
            test_scenario::ctx(scenario)
        );
        
        test_scenario::next_tx(scenario, sender_address);

        // Take the swap and increment clock (for refund)
        test_scenario::return_to_sender(scenario, sui_Balance);
        let shared_Swap = test_scenario::take_shared<Swap>(scenario);
        test_scenario::next_tx(scenario, sender_address);


        redeem_Swap(
            &mut shared_Swap,
            secret,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(shared_Swap);
        test_scenario::next_tx(scenario, sender_address);
 
        // boilerplate to end the test
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    // Test redeeming after swap expires (it will abort)
    #[test]
    #[expected_failure(abort_code = ESWAP_EXPIRED)]
    public fun test_Redeeming_after_expiry(){
        let sender_address: address = @0x0;     // Address of the sender    
        let reciever_address: address = @0x1;   // Address of the receiver

        // The secrets
        let secret = b"ABAB";
        let secret_hash = hash::sha2_256(secret);

        let expiry: u64 = 0;
        let amount: u64 = 100;

        // Initializing the scenarios
        let scenario_val = test_scenario::begin(sender_address);
        let scenario = &mut scenario_val;

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let coins_for_test = coin::mint_for_testing<SUI>(amount + 50, test_scenario::ctx(scenario));   // The coins we are going to give
        sui::transfer(coins_for_test, tx_context::sender(test_scenario::ctx(scenario)));

        test_scenario::next_tx(scenario, sender_address);

        let sui_Balance = test_scenario::take_from_sender<Coin<SUI>>(scenario);

        initialize_Swap(
            reciever_address,
            &mut sui_Balance,
            secret_hash,
            amount, 
            expiry,
            &clock,
            test_scenario::ctx(scenario)
        );
        
        test_scenario::next_tx(scenario, sender_address);

        // Take the swap and increment clock (for refund)
        test_scenario::return_to_sender(scenario, sui_Balance);
        let shared_Swap = test_scenario::take_shared<Swap>(scenario);
        clock::increment_for_testing(&mut clock, 100);
        test_scenario::next_tx(scenario, sender_address);

        redeem_Swap(
            &mut shared_Swap,
            secret,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(shared_Swap);
        test_scenario::next_tx(scenario, sender_address);
 
        // boilerplate to end the test
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    // Test refunding before swap expires (it will abort)
    #[test]
    #[expected_failure(abort_code = ESWAP_NOT_EXPIRED)]
    public fun test_Refunding_before_expiry(){
        let sender_address: address = @0x0;     // Address of the sender    
        let reciever_address: address = @0x1;   // Address of the receiver

        // The secrets
        let secret = b"ABAB";
        let secret_hash = hash::sha2_256(secret);

        let expiry: u64 = 0;
        let amount: u64 = 100;

        // Initializing the scenarios
        let scenario_val = test_scenario::begin(sender_address);
        let scenario = &mut scenario_val;

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let coins_for_test = coin::mint_for_testing<SUI>(amount + 50, test_scenario::ctx(scenario));   // The coins we are going to give
        sui::transfer(coins_for_test, tx_context::sender(test_scenario::ctx(scenario)));

        test_scenario::next_tx(scenario, sender_address);

        let sui_Balance = test_scenario::take_from_sender<Coin<SUI>>(scenario);

        initialize_Swap(
            reciever_address,
            &mut sui_Balance,
            secret_hash,
            amount, 
            expiry,
            &clock,
            test_scenario::ctx(scenario)
        );
        
        test_scenario::next_tx(scenario, sender_address);

        // Take the swap and increment clock (for refund)
        test_scenario::return_to_sender(scenario, sui_Balance);
        let shared_Swap = test_scenario::take_shared<Swap>(scenario);
        test_scenario::next_tx(scenario, sender_address);

        refund_Swap(
            &mut shared_Swap,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(shared_Swap);
        test_scenario::next_tx(scenario, sender_address);
 
        // boilerplate to end the test
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    // Test refunding after swap has been redeemed (it will abort)
    #[test]
    #[expected_failure(abort_code = ESWAP_ALREADY_REDEEMED_OR_REFUNDED)]
    public fun test_Refund_after_redeem(){
        let sender_address: address = @0x0;     // Address of the sender    
        let reciever_address: address = @0x1;   // Address of the receiver

        // The secrets
        let secret = b"ABAB";
        let secret_hash = hash::sha2_256(secret);

        let expiry: u64 = 0;
        let amount: u64 = 100;

        // Initializing the scenarios
        let scenario_val = test_scenario::begin(sender_address);
        let scenario = &mut scenario_val;

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let coins_for_test = coin::mint_for_testing<SUI>(amount + 50, test_scenario::ctx(scenario));   // The coins we are going to give
        sui::transfer(coins_for_test, tx_context::sender(test_scenario::ctx(scenario)));


        test_scenario::next_tx(scenario, sender_address);

        let sui_Balance = test_scenario::take_from_sender<Coin<SUI>>(scenario);

        initialize_Swap(
            reciever_address,
            &mut sui_Balance,
            secret_hash,
            amount, 
            expiry,
            &clock,
            test_scenario::ctx(scenario)
        );
        
        test_scenario::next_tx(scenario, sender_address);

        // Take the swap and increment clock (for refund)
        test_scenario::return_to_sender(scenario, sui_Balance);
        let shared_Swap = test_scenario::take_shared<Swap>(scenario);
        test_scenario::next_tx(scenario, sender_address);

        redeem_Swap(
            &mut shared_Swap,
            secret,
            &clock,
            test_scenario::ctx(scenario)
        );

        clock::increment_for_testing(&mut clock, 100);
        test_scenario::next_tx(scenario, sender_address);

        refund_Swap(
            &mut shared_Swap,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(shared_Swap);
        test_scenario::next_tx(scenario, sender_address);

        // boilerplate to end the test
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }
}