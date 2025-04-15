use fuels::{
    prelude::*,
    types::{Identity, ContractId, Address},
};

 use fuels::tx::TxParameters;

 

abigen!(Contract(
    name = "TreasuryContract",
    abi = "contracts/treasury/out/debug/treasury-abi.json"
));

const BASE_ASSET_ID: [u8; 32] = [0u8; 32];

async fn get_contract_instance() -> (TreasuryContract<WalletUnlocked>, ContractId, Vec<WalletUnlocked>) {
    let wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(Some(3), Some(1), Some(1_000_000_000)),
        None,
        None,
    )
    .await
    .unwrap();
    
    let wallet = wallets.get(0).unwrap().clone();
    
    let id = Contract::load_from(
        "contracts/treasury/out/debug/treasury.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let instance = TreasuryContract::new(id.clone(), wallet.clone());

    // Call constructor with both owner and strategy
    instance.clone()
        .with_account(wallet.clone())
        .methods()
        .constructor(wallet.address(), Identity::Address(wallet.address().into()))
        .call()
        .await
        .unwrap();

    (instance, id.into(), wallets)
}

// For testing with a different wallet as strategy
async fn get_contract_instance_with_mock_strategy() -> (TreasuryContract<WalletUnlocked>, ContractId, Vec<WalletUnlocked>) {
    let wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(Some(3), Some(1), Some(1_000_000_000)),
        None,
        None,
    )
    .await
    .unwrap();
    
    let wallet = wallets.get(0).unwrap().clone();
    
    // Create a mock strategy ID for testing
    let mock_strategy_id = ContractId::from([2u8; 32]);
    
    let id = Contract::load_from(
        "contracts/treasury/out/debug/treasury.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let instance = TreasuryContract::new(id.clone(), wallet.clone());

    // Call constructor with both owner and strategy
    instance.clone()
        .with_account(wallet.clone())
        .methods()
        .constructor(wallet.address(), Identity::ContractId(mock_strategy_id))
        .call()
        .await
        .unwrap();

    (instance, id.into(), wallets)
}

#[tokio::test]
async fn test_owner_initialization() {
    let (instance, _id, wallets) = get_contract_instance().await;
    let wallet_0 = wallets.get(0).unwrap().clone();

    // Verify initial owner is set correctly
    let owner = instance
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    
    assert_eq!(owner, Identity::Address(wallet_0.address().into()));

    // Try to initialize again - should fail
    let result = instance
        .with_account(wallet_0.clone())
        .methods()
        .initialize_owner()
        .call()
        .await;
    
    assert!(result.is_err());
}

#[tokio::test]
async fn test_strategy_initialization() {
    let (instance, _id, wallets) = get_contract_instance().await;
    let wallet_0 = wallets.get(0).unwrap().clone();

    // Verify initial strategy is set correctly
    let strategy = instance
        .methods()
        .get_strategy()
        .call()
        .await
        .unwrap()
        .value;
    
    // The strategy should be the wallet's address
    let expected_strategy = Identity::Address(wallet_0.address().into());
    assert_eq!(strategy, expected_strategy);
}

#[tokio::test]
async fn test_strategy_initialization_with_mock() {
    let (instance, _id, _wallets) = get_contract_instance_with_mock_strategy().await;

    // Verify initial strategy is set correctly
    let strategy = instance
        .methods()
        .get_strategy()
        .call()
        .await
        .unwrap()
        .value;
    
    // The mock strategy we set in get_contract_instance_with_mock_strategy
    let expected_strategy = Identity::ContractId(ContractId::from([2u8; 32]));
    assert_eq!(strategy, expected_strategy);
}

#[tokio::test]
async fn test_constructor() {
    println!("\n=== Testing treasury constructor ===");
    let (instance, _, _) = get_contract_instance().await;
    
    let owner_address = Address::from([1u8; 32]);
    let strategy_id = Identity::ContractId(ContractId::from([3u8; 32])); // Different mock strategy
    
    let result = instance.methods()
        .constructor(owner_address, strategy_id)
        .call()
        .await;
        
    assert!(result.is_ok());
    println!("✓ Constructor successfully initialized");
}

#[tokio::test]
async fn test_receive_fees_unauthorized() {
    println!("\n=== Testing unauthorized fee reception ===");
    // Use the mock strategy setup to ensure the wallet is NOT authorized
    let (instance, _, wallets) = get_contract_instance_with_mock_strategy().await;
    let wallet = wallets.get(0).unwrap().clone();
    
    // Try to send fees from unauthorized address
    let call_params = CallParameters::new(
        1000,                           // amount
        AssetId::new(BASE_ASSET_ID),   // base asset
        1_000_000,                     // gas forwarded
    );

    let result = instance
        .with_account(wallet.clone())
        .methods()
        .receive_fees()
        .call_params(call_params)
        .expect("call params should be valid")
        .call()
        .await;
        
    assert!(result.is_err());
    println!("✓ Unauthorized fee reception correctly rejected");
}

#[tokio::test]
async fn test_receive_fees_wrong_asset() {
    println!("\n=== Testing fee reception with wrong asset ===");
    let (instance, _, wallets) = get_contract_instance().await;
    let wallet = wallets.get(0).unwrap().clone();
    
    // Try to send fees with wrong asset
    let wrong_asset = AssetId::new([1u8; 32]);
    let call_params = CallParameters::new(
        1000,        // amount
        wrong_asset, // non-base asset
        1_000_000,  // gas forwarded
    );

    let result = instance
        .with_account(wallet.clone())
        .methods()
        .receive_fees()
        .call_params(call_params)
        .expect("call params should be valid")
        .call()
        .await;
        
    assert!(result.is_err());
    println!("✓ Wrong asset fee reception correctly rejected");
}

#[tokio::test]
async fn test_receive_fees_zero_amount() {
    println!("\n=== Testing fee reception with zero amount ===");
    let (instance, _, wallets) = get_contract_instance().await;
    let wallet = wallets.get(0).unwrap().clone();
    
    // Try to send zero fees
    let call_params = CallParameters::new(
        0,                              // zero amount
        AssetId::new(BASE_ASSET_ID),   // base asset
        1_000_000,                     // gas forwarded
    );

    let result = instance
        .with_account(wallet.clone())
        .methods()
        .receive_fees()
        .call_params(call_params)
        .expect("call params should be valid")
        .call()
        .await;
        
    assert!(result.is_err());
    println!("✓ Zero amount fee reception correctly rejected");
}

#[tokio::test]
async fn test_withdraw_fees_unauthorized() {
    println!("\n=== Testing unauthorized fee withdrawal ===");
    // Use the mock strategy setup to ensure the wallet is NOT authorized
    let (instance, _, wallets) = get_contract_instance_with_mock_strategy().await;
    let wallet = wallets.get(0).unwrap().clone();
    
    // Try to withdraw fees from unauthorized address
    let result = instance
        .with_account(wallet.clone())
        .methods()
        .withdraw_fees()
        .call()
        .await;
        
    assert!(result.is_err());
    println!("✓ Unauthorized fee withdrawal correctly rejected");
}

#[tokio::test]
async fn test_receive_fees_successful() {
    println!("\n=== Testing successful fee reception ===");
    let (instance, _id, wallets) = get_contract_instance().await;
    let wallet = wallets.get(0).unwrap().clone();

    // Send fees from the authorized wallet (which is set as the strategy)
    let amount = 1_000;
    let call_params = CallParameters::new(
        amount,
        AssetId::from(BASE_ASSET_ID),
        1_000_000
    );

    let result = instance
        .with_account(wallet.clone())
        .methods()
        .receive_fees()
        .call_params(call_params)
        .unwrap()
        .call()
        .await;

    // Should succeed because wallet is the strategy
    assert!(result.is_ok());
    println!("✓ Successfully sent fees to treasury");
}

#[tokio::test]
async fn test_set_strategy() {
    let (instance, _id, wallets) = get_contract_instance().await;
    let wallet_0 = wallets.get(0).unwrap().clone();
    
    // Create a new strategy ID
    let new_strategy_id = ContractId::from([5u8; 32]);
    let new_strategy_identity = Identity::ContractId(new_strategy_id);
    
    // Set new strategy as the owner
    let result = instance.clone()
        .with_account(wallet_0.clone())
        .methods()
        .set_strategy(new_strategy_identity)
        .call()
        .await;
        
    assert!(result.is_ok());
    
    // Verify the strategy was updated
    let updated_strategy = instance
        .methods()
        .get_strategy()
        .call()
        .await
        .unwrap()
        .value;
        
    assert_eq!(updated_strategy, new_strategy_identity);
}

#[tokio::test]
async fn test_only_owner_can_set_strategy() {
    let (instance, _id, wallets) = get_contract_instance().await;
    let non_owner = wallets.get(1).unwrap().clone();
    
    // Non-owner trying to set strategy
    let new_strategy_id = ContractId::from([6u8; 32]);
    let new_strategy_identity = Identity::ContractId(new_strategy_id);
    
    let result = instance
        .with_account(non_owner)
        .methods()
        .set_strategy(new_strategy_identity)
        .call()
        .await;
    
    // Should fail because sender is not the owner
    assert!(result.is_err());
    println!("✓ Non-owner cannot set strategy");
}

#[tokio::test]
async fn can_set_owner() {
    let (instance, _id, wallets) = get_contract_instance().await;
    let wallet_0 = wallets.get(0).unwrap().clone();
    let wallet_1 = wallets.get(1).unwrap().clone();
    let new_owner_identity = Identity::Address(wallet_1.address().into());

    // Use initial owner (wallet_0) to set wallet_1 as the new owner
    let _result = instance.clone()
        .with_account(wallet_0)
        .methods()
        .set_owner(new_owner_identity)
        .call()
        .await
        .unwrap();

    // verify the owner was set correctly
    let final_owner = instance
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(new_owner_identity, final_owner);
}

#[tokio::test]
async fn test_withdraw_fees_successful() {
    println!("\n=== Testing successful fee withdrawal ===");
    let (instance, treasury_id, wallets) = get_contract_instance().await;
    let wallet = wallets.get(0).unwrap().clone();
    
    // Print the strategy identity for debugging
    let strategy_identity = instance
        .methods()
        .get_strategy()
        .call()
        .await
        .unwrap()
        .value;
    println!("✓ Strategy identity: {:?}", strategy_identity);
    
    // Print the sender identity for debugging
    let wallet_identity = Identity::Address(wallet.address().into());
    println!("✓ Wallet identity: {:?}", wallet_identity);
    
    // First fund the treasury
    let treasury_funds = 10_000;
    let treasury_id_bech32 = Bech32ContractId::from(treasury_id);
    
    wallet.force_transfer_to_contract(
        &treasury_id_bech32,
        treasury_funds,
        AssetId::from(BASE_ASSET_ID),
        TxPolicies::default()
    )
    .await
    .unwrap();
    
    println!("✓ Funded treasury with {} tokens", treasury_funds);
    
    // Record wallet balance before withdrawal
    let wallet_balance_before = wallet.get_asset_balance(&AssetId::from(BASE_ASSET_ID)).await.unwrap();
    println!("✓ Wallet balance before withdrawal: {}", wallet_balance_before);

    let tx_policies = TxPolicies::default();
    
    // Withdraw fees (this works because wallet is the mock strategy)
    println!("✓ Calling withdraw_fees function with variable outputs...");
    let result = instance.clone()
        .with_account(wallet.clone())
        .methods()
        .withdraw_fees()
        .with_variable_output_policy(VariableOutputPolicy::Exactly(1))
        .call()
        .await;
    
    // Print detailed error information if there's a failure
    match &result {
        Ok(_) => println!("✓ Withdraw fees call succeeded"),
        Err(e) => {
            println!("✗ Withdraw fees call failed: {:?}", e);
            println!("Error details: {}", e);
        }
    }
         
    assert!(result.is_ok());
    println!("✓ Successfully withdrew fees from treasury");
    
    // Check wallet balance after withdrawal
    let wallet_balance_after = wallet.get_asset_balance(&AssetId::from(BASE_ASSET_ID)).await.unwrap();
    println!("✓ Wallet balance after withdrawal: {}", wallet_balance_after);
    
    // Balance should have increased by the treasury funds (minus gas)
    assert!(wallet_balance_after > wallet_balance_before);
    println!("✓ Successfully received funds from treasury");
}

#[tokio::test]
#[should_panic]
async fn only_owner_can_set_owner() {
    let (instance, _id, wallets) = get_contract_instance().await;
    let non_owner = wallets.get(1).unwrap();
    let new_owner = Identity::Address(non_owner.address().into());
    
    // This should fail - non-owner trying to set itself as owner
    instance
        .with_account(non_owner.clone())
        .methods()
        .set_owner(new_owner)
        .call()
        .await
        .unwrap();
}