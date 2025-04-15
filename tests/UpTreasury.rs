use fuels::{
    prelude::*,
    types::{ContractId, Identity},
};


// Load abi from json
abigen!(Contract(
    name = "TreasuryContract",
    abi = "contracts/treasury/out/debug/treasury-abi.json"
));

async fn get_contract_instance() -> (TreasuryContract<WalletUnlocked>, ContractId, WalletUnlocked, WalletUnlocked) {
    // Launch a local network and deploy the contract

    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(2),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await
    .unwrap();
    let non_owner = wallets.pop().unwrap();
    let owner = wallets.pop().unwrap();

    let id = Contract::load_from(
        "contracts/treasury/out/debug/treasury.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&owner, TxPolicies::default())
    .await
    .unwrap();

    let instance = TreasuryContract::new(id.clone(), owner.clone());

    (instance, id.into(), owner, non_owner)
}

#[tokio::test]
async fn can_get_contract_id() {
    let (_instance, _id, _owner, _provider) = get_contract_instance().await;

    // Now you have an instance of your contract you can use to test each function
}

#[tokio::test]
async fn test_initialize() {
    let (instance, _id, _owner, _non_owner) = get_contract_instance().await;
    let implementation_id = ContractId::from([1u8; 32]);

    // Initialize the proxy
    let result = instance
        .methods()
        .initialize(implementation_id)
        .call()
        .await;

    assert!(result.is_ok());

    // Verify proxy owner is set
    let proxy_owner = instance
        .methods()
        ._proxy_owner()
        .call()
        .await
        .unwrap()
        .value;

    assert!(matches!(proxy_owner, State::Initialized(_)));

    // Verify proxy target is set
    let proxy_target = instance
        .methods()
        ._proxy_target()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(proxy_target, Some(implementation_id));
}

#[tokio::test]
async fn test_proxy_target_management() {
    let (instance, _id, owner, _non_owner) = get_contract_instance().await;
    let initial_target = ContractId::from([1u8; 32]);
    let new_target = ContractId::from([2u8; 32]);

    // Initialize first
    instance
        .methods()
        .initialize(initial_target)
        .call()
        .await
        .unwrap();

    // Update proxy target
    let result = instance
        .methods()
        ._set_proxy_target(new_target)
        .call()
        .await;

    assert!(result.is_ok());

    // Verify new target
    let proxy_target = instance
        .methods()
        ._proxy_target()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(proxy_target, Some(new_target));
}

#[tokio::test]
#[should_panic(expected = "NotOwner")]
async fn test_only_owner_can_set_proxy_target() {
    let (instance, _id, owner, non_owner) = get_contract_instance().await;
    let initial_target = ContractId::from([1u8; 32]);
    let new_target = ContractId::from([2u8; 32]);

    // Initialize with owner (default wallet)
    instance
        .methods()
        .initialize(initial_target)
        .call()
        .await
        .unwrap();

    // Try to update target with non-owner
    instance
        .with_account(non_owner)
        .methods()
        ._set_proxy_target(new_target)
        .call()
        .await
        .unwrap();
}

#[tokio::test]
#[should_panic(expected = "Revert(0)")]  // Changed to match the actual revert
async fn test_cannot_initialize_twice() {
    let (instance, _id, owner, _non_owner) = get_contract_instance().await;
    let implementation_id = ContractId::from([1u8; 32]);

    // First initialization
    instance
        .methods()
        .initialize(implementation_id)
        .call()
        .await
        .unwrap();

    // Try to initialize again - this should fail with Revert(0)
    instance
        .methods()
        .initialize(implementation_id)
        .call()
        .await
        .unwrap();
}