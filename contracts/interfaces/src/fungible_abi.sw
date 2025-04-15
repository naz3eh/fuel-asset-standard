
library;

use std::{
    hash::{
        Hash,
        sha256,
    },
    revert::require,
    storage::storage_string::*,
    string::String,
};

abi UpgradableAsset {
    /// Initializes the contract with an owner
    #[storage(read, write)]
    fn initialize_owner() -> Identity;
    
    /// Gets the current owner of the contract
    #[storage(read)]
    fn get_owner() -> Identity;
    
    /// Sets a new owner for the contract
    #[storage(read, write)]
    fn set_owner(new_owner: Identity);
    
    /// Initializes the proxy with an initial implementation target
    #[storage(read, write)]
    fn initialize(initial_target: ContractId);
    
    /// Updates the implementation contract
    #[storage(read, write)]
    fn set_implementation(new_implementation: ContractId);
    
    /// Gets the current implementation contract
    #[storage(read)]
    fn get_implementation() -> Option<ContractId>;

    /// Approves or revokes a strategy contract's ability to mint/burn tokens
    #[storage(read, write)]
    fn set_strategy(strategy: ContractId, approved: bool);
    
    /// Checks if a strategy is approved
    #[storage(read)]
    fn is_strategy_approved(strategy: ContractId) -> bool;
}

abi FungibleAsset {

    #[storage(read)]
    fn total_assets() -> u64;

    #[storage(read)]
    fn total_supply(asset_id: AssetId) -> Option<u64>;

   
    #[storage(read)]
    fn name(asset_id: AssetId) -> Option<String>;

    #[storage(read)]
    fn symbol(asset_id: AssetId) -> Option<String>;
    
    #[storage(read)]
    fn decimals(asset_id: AssetId) -> Option<u8>;

    #[storage(read, write)]
    fn mint(recipient: Identity, vault_sub_id: SubId, amount: u64);

    #[storage(read, write)]
    fn burn(vault_sub_id: SubId, amount: u64);
    
    #[storage(write)]
    fn set_name(asset_id: AssetId, name: String);

    #[storage(write)]
    fn set_symbol(asset_id: AssetId, symbol: String);

    #[storage(write)]
    fn set_decimals(asset_id: AssetId, decimals: u8);

}
