// SPDX-License-Identifier: Apache-2.0
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
    /*
           ____  ____  ____   ____ ____   ___  
          / / / / ___||  _ \ / ___|___ \ / _ \ 
         / / /  \___ \| |_) | |     __) | | | |
        / / /    ___) |  _ <| |___ / __/| |_| |
       /_/_/    |____/|_| \_\\____|_____|\___/                                          
    */

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

    /*
           ____  ____  ____   ____ _____ 
          / / / / ___||  _ \ / ___|___ / 
         / / /  \___ \| |_) | |     |_ \ 
        / / /    ___) |  _ <| |___ ___) |
       /_/_/    |____/|_| \_\\____|____/   
       
    */
    /// Mints new assets using the `vault_sub_id` sub-identifier.
    ///
    /// # Arguments
    ///
    /// * `recipient`: [Identity] - The user to which the newly minted asset is transferred to.
    /// * `vault_sub_id`: [SubId] - The sub-identifier of the newly minted asset.
    /// * `amount`: [u64] - The quantity of coins to mint.
    ///
    /// # Examples
    ///
    /// ```sway
    /// use src3::SRC3;
    ///
    /// fn foo(contract_id: ContractId) {
    ///     let contract_abi = abi(SR3, contract);
    ///     contract_abi.mint(Identity::ContractId(contract_id), ZERO_B256, 100);
    /// }
    /// ```
    #[storage(read, write)]
    fn mint(recipient: Identity, vault_sub_id: SubId, amount: u64);

    /// Burns assets sent with the given `vault_sub_id`.
    ///
    /// # Additional Information
    ///
    /// NOTE: The sha-256 hash of `(ContractId, SubId)` must match the `AssetId` where `ContractId` is the id of
    /// the implementing contract and `SubId` is the given `vault_sub_id` argument.
    ///
    /// # Arguments
    ///
    /// * `vault_sub_id`: [SubId] - The sub-identifier of the asset to burn.
    /// * `amount`: [u64] - The quantity of coins to burn.
    ///
    /// # Examples
    ///
    /// ```sway
    /// use src3::SRC3;
    ///
    /// fn foo(contract_id: ContractId, asset_id: AssetId) {
    ///     let contract_abi = abi(SR3, contract_id);
    ///     contract_abi {
    ///         gas: 10000,
    ///         coins: 100,
    ///         asset_id: asset_id,
    ///     }.burn(ZERO_B256, 100);
    /// }
    /// ```
    #[storage(read, write)]
    fn burn(vault_sub_id: SubId, amount: u64);

    /*
           ____  ____       _   _                
          / / / / ___|  ___| |_| |_ ___ _ __ ___ 
         / / /  \___ \ / _ \ __| __/ _ \ '__/ __|
        / / /    ___) |  __/ |_| ||  __/ |  \__ \
       /_/_/    |____/ \___|\__|\__\___|_|  |___/
    */
    
    #[storage(write)]
    fn set_name(asset_id: AssetId, name: String);

    #[storage(write)]
    fn set_symbol(asset_id: AssetId, symbol: String);

    #[storage(write)]
    fn set_decimals(asset_id: AssetId, decimals: u8);

    /*
           ____  ____        _                      
          / / / | __ )  __ _| | __ _ _ __   ___ ___ 
         / / /  |  _ \ / _` | |/ _` | '_ \ / __/ _ \
        / / /   | |_) | (_| | | (_| | | | | (_|  __/
       /_/_/    |____/ \__,_|_|\__,_|_| |_|\___\___|
    */
  
    fn this_balance(sub_id: SubId) -> u64;
  
    fn get_balance(target: ContractId, sub_id: SubId) -> u64;

    /*
           ____  _____                     __           
          / / / |_   _| __ __ _ _ __  ___ / _| ___ _ __ 
         / / /    | || '__/ _` | '_ \/ __| |_ / _ \ '__|
        / / /     | || | | (_| | | | \__ \  _|  __/ |   
       /_/_/      |_||_|  \__,_|_| |_|___/_|  \___|_|
    */
   
    fn transfer(to: Identity, sub_id: SubId, amount: u64);
   
}
