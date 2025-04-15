use fuels::{
    prelude::*, 
    client::FuelClient,
    types::{
        Bytes32,
        Identity, 
        SizedAsciiString,
        ContractId, 
        AssetId,
        Bits256
    }
};
use fuel_core_client::client::types::TransactionStatus;


abigen!(
    Contract(
        name = "StrategyContract",
        abi = "contracts/strategy/out/debug/strategy-abi.json"
    ),
    Contract(
        name = "MiraAMM",
        abi = "contracts/mockMira/out/debug/mockMira-abi.json"
    ),
    Contract(
        name = "MockSproutToken",
       abi = "contracts/mocktoken/out/debug/mocktoken-abi.json"
    ));


const BASE_ASSET_ID: [u8; 32] = [0u8; 32];
const SCALE: u64 = 10000; // Same as in your contract 

async fn get_contract_instance() -> (
    StrategyContract<WalletUnlocked>, 
    MiraAMM<WalletUnlocked>, 
    MockSproutToken<WalletUnlocked>, // Add the mock token instance
    ContractId, 
    ContractId, 
    ContractId, // Add token contract ID
    Vec<WalletUnlocked>
) {
    let wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(Some(3), Some(1), Some(1_000_000_000)),
        None,
        None,
    )
    .await
    .unwrap();
    
    let wallet = wallets.get(0).unwrap().clone();
    println!("Deployer wallet address: {:?}", wallet.address());

    let token_id = Contract::load_from(
        "contracts/mocktoken/out/debug/mocktoken.bin", 
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let token_instance = MockSproutToken::new(token_id.clone(), wallet.clone());

    // Deploy MiraAMM contract
    let mira_id = Contract::load_from(
        "contracts/mockMira/out/debug/mockMira.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let mira_instance = MiraAMM::new(mira_id.clone(), wallet.clone());
    
     // Initialize token contract with reference to strategy

     let strategy_id = Contract::load_from(
        "contracts/strategy/out/debug/strategy.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let strategy_instance = StrategyContract::new(strategy_id.clone(), wallet.clone());
// Initialize token owner
token_instance.clone()
    .with_account(wallet.clone())
    .methods()
    .initialize_owner()
    .call()
    .await
    .unwrap();

// Approve the strategy in the token contract
token_instance.clone()
    .with_account(wallet.clone())
    .methods()
    .set_strategy(strategy_id.clone(), true)
    .call()
    .await
    .unwrap();

// Verify strategy is approved
let is_approved = token_instance.clone()
    .methods()
    .is_strategy_approved(strategy_id.clone())
    .call()
    .await
    .unwrap()
    .value;
println!("Strategy approval status: {}", is_approved);
assert!(is_approved, "Strategy was not approved in token contract");

// Initialize strategy with token ID
strategy_instance.clone()
    .with_account(wallet.clone())
    .methods()
    .constructor(&token_id, wallet.address())
    .call()
    .await
    .unwrap();

// Initialize strategy owner
println!("Initializing strategy owner with address: {:?}", wallet.address());
strategy_instance.clone()
    .with_account(wallet.clone())
    .methods()
    .initialize_owner()
    .call()
    .await
    .unwrap();
    // Verify owner was set
    let current_owner = strategy_instance.clone()
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    println!("Owner after initialization: {:?}", current_owner);

    // After initializing the owner and verifying it was set
// Add this:
strategy_instance.clone()
.with_account(wallet.clone())
.methods()
.set_mira_amm_contract(&mira_id)
.call()
.await
.unwrap();

    (
        strategy_instance,
        mira_instance,
        token_instance,
        strategy_id.into(),
        mira_id.into(),
        token_id.into(),
        wallets
    )

}

#[tokio::test]
async fn test_owner_initialization() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let wallet_0 = wallets.get(0).unwrap().clone();

    // Verify initial owner is set correctly
    let owner = strategy_instance
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    
    assert_eq!(owner, Identity::Address(wallet_0.address().into()));

    // Try to initialize again - should fail
    let result = strategy_instance
        .with_account(wallet_0.clone())
        .methods()
        .initialize_owner()
        .call()
        .await;
    
    assert!(result.is_err());
}

#[tokio::test]
async fn can_set_owner() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    
    // get access to test wallets
    let wallet_0 = wallets.get(0).unwrap().clone(); // Current owner
    let wallet_1 = wallets.get(1).unwrap().clone(); // New owner
    let new_owner_identity = Identity::Address(wallet_1.address().into());

    // Print current owner for debugging
    let current_owner = strategy_instance.clone()
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    println!("Current owner before change: {:?}", current_owner);
    println!("Wallet 0 address: {:?}", wallet_0.address());
    println!("Attempting to set new owner: {:?}", new_owner_identity);

    // Use initial owner (wallet_0) to set wallet_1 as the new owner
    let _result = strategy_instance.clone()
        .with_account(wallet_0)
        .methods()
        .set_owner(new_owner_identity)
        .call()
        .await
        .unwrap();

    // verify the owner was set correctly
    let final_owner = strategy_instance
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    println!("Final owner after change: {:?}", final_owner);
    assert!(new_owner_identity == final_owner);
}

#[tokio::test]
async fn test_withdrawal_fee() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let owner = wallets.get(0).unwrap().clone();
    
    // Test initial fee is 0
    let initial_fee = strategy_instance
        .methods()
        .get_withdrawal_fee()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(initial_fee, 0);

    // Set new fee
    let new_fee = 100; // 1%
    strategy_instance.clone()
        .with_account(owner.clone())
        .methods()
        .set_withdrawal_fee(new_fee)
        .call()
        .await
        .unwrap();

    // Verify fee was set
    let updated_fee = strategy_instance
        .methods()
        .get_withdrawal_fee()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(updated_fee, new_fee);

    // Test non-owner cannot set fee
    let non_owner = wallets.get(1).unwrap().clone();
    let result = strategy_instance
        .with_account(non_owner)
        .methods()
        .set_withdrawal_fee(200)
        .call()
        .await;
    assert!(result.is_err());
}

#[tokio::test]
async fn test_sprout_receipt_token() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let owner = wallets.get(0).unwrap().clone();
    
    // Get initial token
    let initial_token = strategy_instance.clone()  // Add clone here
        .methods()
        .get_sprout_receipt_token()
        .call()
        .await
        .unwrap()
        .value;

    // Set new token
    let new_token = ContractId::from([2u8; 32]);
    strategy_instance.clone()  // Add clone here
        .with_account(owner.clone())
        .methods()
        .set_sprout_receipt_token(new_token)
        .call()
        .await
        .unwrap();

    // Verify token was set
    let updated_token = strategy_instance  // Last use doesn't need clone
        .methods()
        .get_sprout_receipt_token()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(updated_token, new_token);
}

#[tokio::test]
async fn test_fee_treasury() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let owner = wallets.get(0).unwrap().clone();
    
    // Get initial treasury
    let _initial_treasury = strategy_instance.clone()  // Add clone here
        .methods()
        .get_fee_treasury_contract()
        .call()
        .await
        .unwrap()
        .value;

    // Set new treasury
    let new_treasury = Identity::Address(wallets.get(1).unwrap().address().into());
    strategy_instance.clone()  // Add clone here
        .with_account(owner.clone())
        .methods()
        .set_fee_treasury_contract(new_treasury)
        .call()
        .await
        .unwrap();

    // Verify treasury was set
    let updated_treasury = strategy_instance  // Last use doesn't need clone
        .methods()
        .get_fee_treasury_contract()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(updated_treasury, new_treasury);
}


#[tokio::test]
async fn test_slippage_tolerance() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let owner = wallets.get(0).unwrap().clone();
    
    // Get initial slippage
    let initial_slippage = strategy_instance.clone()  // Add clone here
        .methods()
        .get_slippage_tolerance()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(initial_slippage, 500); // 5% default

    // Set new slippage
    let new_slippage = 300; // 3%
    strategy_instance.clone()  // Add clone here
        .with_account(owner.clone())
        .methods()
        .update_slippage_tolerance(new_slippage)
        .call()
        .await
        .unwrap();

    // Verify slippage was set
    let updated_slippage = strategy_instance  // Last use doesn't need clone
        .methods()
        .get_slippage_tolerance()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(updated_slippage, new_slippage);
}

#[tokio::test]
async fn test_target_tokens() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let owner = wallets.get(0).unwrap().clone();
    
    // Initially no tokens
    let initial_tokens = strategy_instance.clone()
        .methods()
        .get_target_tokens()
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(initial_tokens.len(), 0);

    // Get a specific token allocation that doesn't exist yet
    let test_token = AssetId::new([3u8; 32]);
    let initial_allocation = strategy_instance.clone()
        .methods()
        .get_token_allocation(test_token)
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(initial_allocation, None);
}

#[tokio::test]
#[should_panic]
async fn only_owner_can_set_owner() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    // get access to test wallets
    let non_owner = wallets.get(1).unwrap();
    
    // this should fail - non-owner trying to set itself as owner
    let new_owner = Identity::Address(non_owner.address().into());
    strategy_instance
        .with_account(non_owner.clone())
        .methods()
        .set_owner(new_owner)
        .call()
        .await
        .unwrap();
}

//Integrating the tests that use Mira

#[tokio::test]
async fn test_mira_basic_swap() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let wallet = wallets.get(0).unwrap().clone();

    // Create a pool ID for testing
    let pool_id = (
        AssetId::from([1u8; 32]),  // token0
        AssetId::from([2u8; 32]),  // token1
        false                         // stable
    );

    // Create empty bytes for data parameter
    let empty_bytes = Bytes::from_hex_str("0x").unwrap();

    // Test basic swap through MiraAMM
    let _result = mira_instance
        .with_account(wallet.clone())
        .methods()
        .swap(
            pool_id,
            1000,  // amount_0_out
            1000,  // amount_1_out
            Identity::Address(wallet.address().into()),
            empty_bytes
        )
        .call()
        .await
        .unwrap();
}

#[tokio::test]
async fn test_strategy_mira_integration() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let owner = wallets.get(0).unwrap().clone();
    
    // Setup the tokens for testing
    let token0 = AssetId::new([1u8; 32]);  // Changed to AssetId
    let token1 = AssetId::from([2u8; 32]);
    let pool_id = (
        AssetId::from([1u8; 32]),
        AssetId::from([2u8; 32]),
        false
    );

    // Verify token allocation (if this method exists in your contract)
    let token_allocation = strategy_instance
        .methods()
        .get_token_allocation(token0)
        .call()
        .await
        .unwrap()
        .value;

    // Create empty bytes for data parameter
    let empty_bytes = Bytes::from_hex_str("0x").unwrap();

    // Do a swap through MiraAMM
    let _swap_result = mira_instance
        .with_account(owner.clone())
        .methods()
        .swap(
            pool_id,
            500,   // amount_0_out
            500,   // amount_1_out
            Identity::Address(owner.address().into()),
            empty_bytes
        )
        .call()
        .await
        .unwrap();
}

        #[tokio::test]
        async fn test_usdc_fuel_deposit() {
            let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
            let wallet = wallets.get(0).unwrap().clone();
            
            // Get initial balance for later comparison
            let initial_base_balance = wallet
                .get_asset_balance(&AssetId::zeroed())
                .await
                .unwrap();
            println!("Initial FUEL balance: {}", initial_base_balance);
            
            // Define USDC token ID (you'd use the real USDC asset ID in production)
            let fuel_asset = AssetId::zeroed();
            let usdc_asset = AssetId::new([0x75, 0x73, 0x64, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]); // Example USDC asset ID
            
            // Create pool ID for FUEL/USDC
            let pool_id: (AssetId, AssetId, bool) = (
                fuel_asset,
                usdc_asset,
                false // not stable
            );
            
            // Create token allocation for 50/50 USDC/FUEL split
            let token_allocations = vec![
                TokenAllocation {
                    token: usdc_asset,
                    p_id: pool_id,
                    percentage: 5000, // 50%
                },
                TokenAllocation {
                    token: fuel_asset,
                    p_id: pool_id,
                    percentage: 5000, // 50%
                }
            ];
            
            // Initialize the token allocations
            strategy_instance.clone()
                .with_account(wallet.clone())
                .methods()
                .initialize_token_allocations(token_allocations.clone())
                .call()
                .await
                .unwrap();
            
            // Set up the fee treasury
            strategy_instance.clone()
                .with_account(wallet.clone())
                .methods()
                .set_fee_treasury_contract(Identity::Address(wallet.address().into()))
                .call()
                .await
                .unwrap();
            
            // Getting the default asset ID from the strategy contract
            // This is the asset that will be minted directly to the user now
            let receipt_asset_id = strategy_instance.clone()
                .methods()
                .asset_id()
                .call()
                .await
                .unwrap()
                .value;
            println!("Receipt asset ID: {:?}", receipt_asset_id);
            
            // Get initial receipt token balance 
            let initial_receipt_balance = wallet
                .get_asset_balance(&receipt_asset_id)
                .await
                .unwrap_or(0);
            println!("Initial receipt token balance: {}", initial_receipt_balance);
            
            // Set up deposit amount
            let deposit_amount: u64 = 100_000; // Ensure this is greater than 0
            
            // Create deposit parameters 
            let deposit_params = CallParameters::default()
                .with_amount(deposit_amount)
                .with_asset_id(AssetId::zeroed()); // Ensure this is the correct asset ID
            
            // Execute deposit function
            println!("Depositing {} FUEL...", deposit_amount);
            let result = strategy_instance.clone()
                .with_account(wallet.clone())
                .methods()
                .deposit()
                .call_params(deposit_params)
                .unwrap()
                .with_variable_output_policy(VariableOutputPolicy::Exactly(1))
                .with_contract_ids(&[mira_id.into()])  // No need for token_id since minting is internal
                .call()
                .await;
            
            // Verify deposit succeeded
            assert!(result.is_ok(), "Deposit failed: {:?}", result.err());
            
            // Verify receipt tokens were minted to user
            let post_deposit_receipt_balance = wallet
                .get_asset_balance(&receipt_asset_id)
                .await
                .unwrap_or(0);
            println!("Post-deposit receipt token balance: {}", post_deposit_receipt_balance);
            println!("Initial receipt token balance: {}", initial_receipt_balance);
            println!("Deposit amount: {}", deposit_amount);
          
            let post_deposit_fuel_balance = wallet
                .get_asset_balance(&fuel_asset)
                .await
                .unwrap_or(0);
            println!("Post-deposit FUEL balance: {}", post_deposit_fuel_balance);
            
            // Check that receipt tokens were minted (should have increased by deposit_amount)
            assert_eq!(
                post_deposit_receipt_balance - initial_receipt_balance,
                deposit_amount,
                "Receipt tokens weren't minted 1:1 with deposit amount"
            );
            
            // Check that FUEL was transferred from wallet (balance should have decreased by at least deposit_amount)
            assert!(
                initial_base_balance - post_deposit_fuel_balance >= deposit_amount,
                "FUEL wasn't transferred from wallet"
            );
            
            println!("Successfully deposited into USDC/FUEL 50/50 strategy");
        }

        #[tokio::test]
async fn test_successful_withdraw() {
    let (strategy_instance, mira_instance, token_instance, strategy_id, mira_id, token_id, wallets) = get_contract_instance().await;
    let wallet = wallets.get(0).unwrap().clone();
    
    println!("\n=== Starting test_successful_withdraw ===");
    println!("Wallet address: {:?}", wallet.address());
    
    // Set up token allocations as before
    let fuel_asset = AssetId::zeroed();
    let usdc_asset = AssetId::new([0x75, 0x73, 0x64, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    
    println!("Setting up token allocations...");
    // Create pool ID for FUEL/USDC
    let pool_id: (AssetId, AssetId, bool) = (
        fuel_asset,
        usdc_asset,
        false // not stable
    );
    
    // Set up token allocations
    let token_allocations = vec![
        TokenAllocation {
            token: usdc_asset,
            p_id: pool_id,
            percentage: 5000, // 50%
        },
        TokenAllocation {
            token: fuel_asset,
            p_id: pool_id,
            percentage: 5000, // 50%
        }
    ];
    
    // Initialize token allocations
    println!("Initializing token allocations...");
    strategy_instance.clone()
        .with_account(wallet.clone())
        .methods()
        .initialize_token_allocations(token_allocations.clone())
        .call()
        .await
        .unwrap();
    
    // Set up fee treasury
    println!("Setting up fee treasury...");
    strategy_instance.clone()
        .with_account(wallet.clone())
        .methods()
        .set_fee_treasury_contract(Identity::Address(wallet.address().into()))
        .call()
        .await
        .unwrap();
    
    // Get receipt token asset ID
    println!("Getting receipt token asset ID...");
    let receipt_asset_id = strategy_instance.clone()
        .methods()
        .asset_id()
        .call()
        .await
        .unwrap()
        .value;
    println!("Receipt token asset ID: {:?}", receipt_asset_id);
    
    // Get initial balances
    println!("Getting initial balances...");
    let initial_fuel_balance = wallet
        .get_asset_balance(&fuel_asset)
        .await
        .unwrap();
    println!("Initial FUEL balance: {}", initial_fuel_balance);
    
    // Deposit to get receipt tokens
    let deposit_amount = 100_000;
    println!("Making deposit of {} FUEL...", deposit_amount);
    let deposit_result = strategy_instance.clone()
        .with_account(wallet.clone())
        .methods()
        .deposit()
        .call_params(CallParameters::default()
            .with_amount(deposit_amount)
            .with_asset_id(fuel_asset))
        .unwrap()
        .with_variable_output_policy(VariableOutputPolicy::Exactly(1))
        .with_contract_ids(&[mira_id.into()])
        .call()
        .await;
    
    assert!(deposit_result.is_ok(), "Deposit failed: {:?}", deposit_result.err());
    println!("Deposit successful!");
    
    // Verify receipt tokens balance
    println!("Checking receipt token balance...");
    let receipt_balance = wallet
        .get_asset_balance(&receipt_asset_id)
        .await
        .unwrap_or(0);
    println!("Receipt token balance after deposit: {}", receipt_balance);
    
    assert!(receipt_balance >= deposit_amount, "Receipt tokens not received");
    
    // IMPORTANT: Fund the strategy contract directly with FUEL
    let funding_amount = 200_000; // More than we'll withdraw
    println!("Funding strategy contract with {} FUEL...", funding_amount);

    // Convert ContractId to Address and then to Bech32Address
    let strategy_address: Bech32Address = Address::new(*strategy_id).into();
    println!("Strategy contract address: {:?}", strategy_address.clone());
    
    // Use add_custom_asset to send funds directly to the strategy contract
    let funding_result = strategy_instance.clone()
        .with_account(wallet.clone())
        .methods()
        .get_owner() // Using any function that doesn't modify state
        .add_custom_asset(
            fuel_asset,
            funding_amount,
            Some(strategy_address.clone()),
        )
        .call()
        .await;
    
    assert!(funding_result.is_ok(), "Funding strategy contract failed");
    println!("Strategy contract funding successful!");
    
    // Check strategy contract state before withdrawal
    println!("\nChecking strategy contract state before withdrawal:");
    
    // Get the current owner to verify contract state
    let strategy_owner = strategy_instance.clone()
        .methods()
        .get_owner()
        .call()
        .await
        .unwrap()
        .value;
    println!("Strategy owner: {:?}", strategy_owner);
    
    // Get the current token allocations
    let token_allocations = strategy_instance.clone()
        .methods()
        .get_target_tokens()
        .call()
        .await
        .unwrap()
        .value;
    println!("Token allocations: {:?}", token_allocations);
    
    // Get the current withdrawal fee
    let withdrawal_fee = strategy_instance.clone()
        .methods()
        .get_withdrawal_fee()
        .call()
        .await
        .unwrap()
        .value;
    println!("Withdrawal fee: {}", withdrawal_fee);
    
    // Withdraw a small portion
    let withdraw_amount = 100;
    println!("\nAttempting to withdraw {} receipt tokens...", withdraw_amount);
    println!("Current receipt token balance: {}", receipt_balance);
    println!("Strategy contract address: {:?}", strategy_address.clone());
    
    let withdraw_result = strategy_instance.clone()
        .with_account(wallet.clone())
        .methods()
        .withdraw()
        .call_params(CallParameters::default()
            .with_amount(withdraw_amount)
            .with_asset_id(receipt_asset_id))
        .unwrap()
        .with_variable_output_policy(VariableOutputPolicy::Exactly(1))
        .with_contract_ids(&[mira_id.into()])
        .call()
        .await;
    
    assert!(withdraw_result.is_ok(), "Withdrawal failed: {:?}", withdraw_result.err());
    println!("Withdrawal successful!");
    
    // Verify receipt token balance decreased
    println!("Checking final receipt token balance...");
    let final_receipt_balance = wallet
        .get_asset_balance(&receipt_asset_id)
        .await
        .unwrap_or(0);
    println!("Final receipt token balance: {}", final_receipt_balance);
    
    assert_eq!(
        receipt_balance - final_receipt_balance,
        withdraw_amount,
        "Receipt token balance didn't decrease by the expected amount"
    );
    
    // Check final FUEL balance
    let final_fuel_balance = wallet
        .get_asset_balance(&fuel_asset)
        .await
        .unwrap();
    println!("Final FUEL balance: {}", final_fuel_balance);
    
    println!("=== test_successful_withdraw completed successfully ===\n");
}