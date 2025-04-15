// SPDX-License-Identifier: Apache-2.0
contract;

mod errors;

use std::{
    asset::*,
    context::{this_balance, balance_of},
    hash::{
        Hash,
        sha256,
    },
    revert::require,
    storage::storage_string::*,
    string::String,
    contract_id::ContractId,
     call_frames::{
        msg_asset_id,
    },
    auth::msg_sender,
    constants::ZERO_B256,
};
use src20::SRC20;
use src3::SRC3;
use fungible_abi::*;
use errors::*;

/// Represents the state of proxy ownership
enum State {
    //
    // The proxy has not been initialized yet
    Uninitialized: (),
    /// The proxy has been initialized with an owner
    Initialized: Identity,
    /// The proxy has been revoked
    Revoked: (),
}

storage {
    /// The name associated with a particular asset.
    name: StorageMap<AssetId, StorageString> = StorageMap {},
    /// The symbol associated with a particular asset.
    symbol: StorageMap<AssetId, StorageString> = StorageMap {},
    /// The decimals associated with a particular asset.
    decimals: StorageMap<AssetId, u8> = StorageMap {},
    /// The total number of coins minted for a particular asset.
    total_supply: StorageMap<AssetId, u64> = StorageMap {},
    /// The total number of unique assets minted by this contract.
    total_assets: u64 = 0,
    /// The owner of the contract.
    owner: Option<Identity> = Option::None,
    /// Proxy implementation target
    target: Option<ContractId> = None,
    /// Proxy ownership state
    proxy_owner: State = State::Uninitialized,
    /// Flag to track if constructor has been called
    constructor_called: bool = false,
    /// The approved strategy contracts that can mint/burn
    approved_strategies: StorageMap<ContractId, bool> = StorageMap {},
}

/// Event emitted when the owner is updated
struct OwnerUpdated {
    old_owner: Identity,
    new_owner: Identity,
}

/// Event emitted when the implementation contract is updated
struct ImplementationUpdated {
    old_implementation: ContractId,
    new_implementation: ContractId,
}

/// Add this event
struct StrategyUpdated {
    strategy: ContractId,
    approved: bool,
}

#[storage(read)]
fn only_owner() {
    let owner_opt = storage.owner.read();
    require(
        owner_opt.is_some() && msg_sender().unwrap() == owner_opt.unwrap(),
        Error::Unauthorized(msg_sender().unwrap())
    );
}

#[storage(read)]
fn only_proxy_owner() {
    let proxy_state = storage.proxy_owner.read();

    match proxy_state {
        State::Uninitialized => {
            // Allow the call if uninitialized
            return;
        },
       State::Initialized(owner) => {
            require(msg_sender().unwrap() == owner, Error::NotOwner);
        },
        State::Revoked => {
            revert(0);
        }
    } 
}


impl UpgradableAsset for Contract {
    #[storage(read, write)]
    fn initialize_owner() -> Identity {
        let owner = storage.owner.read();

        // Make sure the owner has NOT already been initialized
        require(owner.is_none(), Error::OwnerAlreadyInitialized);

        // Get the identity of the sender        
        let sender = msg_sender().unwrap();
        // Set the owner to the sender's identity
        storage.owner.write(Option::Some(sender));

        log(OwnerUpdated {
            old_owner: Identity::Address(Address::from(ZERO_B256)),
            new_owner: sender,
        });

        // Return the owner
        return sender;
    }

    #[storage(read)]
    fn get_owner() -> Identity {
        require(
            storage.owner.read().is_some(),
            Error::OwnerNotInitialized
        );
        storage.owner.read().unwrap()
    }

    #[storage(read, write)]
    fn set_owner(new_owner: Identity) {
        only_owner();
        let old_owner = storage.owner.read().unwrap();
        storage.owner.write(Option::Some(new_owner));

        log(OwnerUpdated {
            old_owner: old_owner,
            new_owner: new_owner,
        });
    }
    
    #[storage(read, write)]
    fn initialize(initial_target: ContractId) {
        // Check if already initialized
        let current_state = storage.proxy_owner.read();
        match current_state {
            State::Uninitialized => {
                // Set the initial owner
                let sender = msg_sender().unwrap();
                storage.proxy_owner.write(State::Initialized(sender));
                // Set the initial target
                storage.target.write(Some(initial_target));
            },
            _ => {
                revert(1);
            }
        };
    }
    
    #[storage(read, write)]
    fn set_implementation(new_implementation: ContractId) {
        only_proxy_owner();
        require(
            new_implementation != ContractId::from(ZERO_B256),
            Error::AddressZero
        );
        
        let old_implementation = storage.target.read().unwrap_or(ContractId::from(ZERO_B256));
        storage.target.write(Some(new_implementation));
        
        log(ImplementationUpdated {
            old_implementation: old_implementation,
            new_implementation: new_implementation,
        });
    }
    
    #[storage(read)]
    fn get_implementation() -> Option<ContractId> {
        storage.target.read()
    }

    #[storage(read, write)]
    fn set_strategy(strategy: ContractId, approved: bool) {
        // Only owner can approve strategies
        only_owner();
        
        require(
            strategy != ContractId::from(ZERO_B256),
            Error::AddressZero
        );
        
        storage.approved_strategies.insert(strategy, approved);
        
        log(StrategyUpdated {
            strategy: strategy,
            approved: approved,
        });
    }
    
    #[storage(read)]
    fn is_strategy_approved(strategy: ContractId) -> bool {
        storage.approved_strategies.get(strategy).try_read().unwrap_or(false)
    }
}

/// Add this helper function
#[storage(read)]
fn only_owner_or_strategy() {
    let owner_opt = storage.owner.read();
    let sender_identity = msg_sender().unwrap();
    
    // Check if it's the owner
    if owner_opt.is_some() && sender_identity == owner_opt.unwrap() {
        return;
    }
    
    // Check if it's an approved strategy
    if let Identity::ContractId(contract_id) = sender_identity {
        require(
            storage.approved_strategies.get(contract_id).try_read().unwrap_or(false),
            Error::Unauthorized(sender_identity)
        );
    } else {
        // Neither owner nor approved strategy
        revert(1);
    }
}


impl FungibleAsset for Contract {
    /*
           ____  ____  ____   ____ ____   ___  
          / / / / ___||  _ \ / ___|___ \ / _ \ 
         / / /  \___ \| |_) | |     __) | | | |
        / / /    ___) |  _ <| |___ / __/| |_| |
       /_/_/    |____/|_| \_\\____|_____|\___/                                         
    */
    #[storage(read)]
    fn total_assets() -> u64 {
        storage.total_assets.try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn total_supply(asset_id: AssetId) -> Option<u64> {
        storage.total_supply.get(asset_id).try_read()
    }

    #[storage(read)]
    fn name(asset_id: AssetId) -> Option<String> {
        storage.name.get(asset_id).read_slice()
    }

    #[storage(read)]
    fn symbol(asset_id: AssetId) -> Option<String> {
        storage.symbol.get(asset_id).read_slice()
    }

    #[storage(read)]
    fn decimals(asset_id: AssetId) -> Option<u8> {
        storage.decimals.get(asset_id).try_read()
    }

    /*
           ____  ____  ____   ____ _____ 
          / / / / ___||  _ \ / ___|___ / 
         / / /  \___ \| |_) | |     |_ \ 
        / / /    ___) |  _ <| |___ ___) |
       /_/_/    |____/|_| \_\\____|____/   
    */
    #[storage(read, write)]
    fn mint(recipient: Identity, sub_id: SubId, amount: u64) {

         // Allow both owner and approved strategies
        only_owner_or_strategy();

        let asset_id = AssetId::new(ContractId::this(), sub_id);

        let supply = storage.total_supply.get(asset_id);

        // Only increment the number of assets minted by this contract if it hasn't been minted before.
        if supply.try_read().is_none() {
            storage.total_assets.write(storage.total_assets.read() + 1);
        }

        storage
            .total_supply
            .insert(asset_id, supply.try_read().unwrap_or(0) + amount);

        // The `asset_id` constructed within the `mint_to` method is a sha256 hash of
        // the `contract_id` and the `sub_id` (the same as the `asset_id` constructed here).
        mint_to(recipient, sub_id, amount);
    }

    #[storage(read, write)]
    fn burn(sub_id: SubId, amount: u64) {

         // Allow both owner and approved strategies
        only_owner_or_strategy();

        let asset_id = AssetId::new(ContractId::this(), sub_id);

        require(
            this_balance(asset_id) >= amount,
            Error::BurnInsufficientBalance,
        );

        // If we pass the check above, we can assume it is safe to unwrap.
        storage
            .total_supply
            .insert(asset_id, storage.total_supply.get(asset_id).read() - amount);

        burn(sub_id, amount);
    }

    /*
           ____  ____       _   _                
          / / / / ___|  ___| |_| |_ ___ _ __ ___ 
         / / /  \___ \ / _ \ __| __/ _ \ '__/ __|
        / / /    ___) |  __/ |_| ||  __/ |  \__ \
       /_/_/    |____/ \___|\__|\__\___|_|  |___/
    */
    #[storage(write)]
    fn set_name(asset_id: AssetId, name: String) {
        require(
            storage
                .name
                .get(asset_id)
                .read_slice()
                .is_none(),
            Error::NameAlreadySet,
        );
        storage.name.insert(asset_id, StorageString {});
        storage.name.get(asset_id).write_slice(name);
    }

    #[storage(write)]
    fn set_symbol(asset_id: AssetId, symbol: String) {
        require(
            storage
                .symbol
                .get(asset_id)
                .read_slice()
                .is_none(),
            Error::SymbolAlreadySet,
        );
        storage.symbol.insert(asset_id, StorageString {});
        storage.symbol.get(asset_id).write_slice(symbol);
    }

    #[storage(write)]
    fn set_decimals(asset_id: AssetId, decimals: u8) {
        require(
            storage
                .decimals
                .get(asset_id)
                .try_read()
                .is_none(),
            Error::DecimalsAlreadySet,
        );
        storage.decimals.insert(asset_id, decimals);
    }

    /*
           ____  ____        _                      
          / / / | __ )  __ _| | __ _ _ __   ___ ___ 
         / / /  |  _ \ / _` | |/ _` | '_ \ / __/ _ \
        / / /   | |_) | (_| | | (_| | | | | (_|  __/
       /_/_/    |____/ \__,_|_|\__,_|_| |_|\___\___|
    */
    fn this_balance(sub_id: SubId) -> u64 {
        let asset_id = AssetId::new(ContractId::this(), sub_id);
        balance_of(ContractId::this() , asset_id)
    }

    fn get_balance(target: ContractId, sub_id: SubId) -> u64 {
        let asset_id = AssetId::new(ContractId::this(), sub_id);
        balance_of(target, asset_id)
    }

    /*
           ____  _____                     __           
          / / / |_   _| __ __ _ _ __  ___ / _| ___ _ __ 
         / / /    | || '__/ _` | '_ \/ __| |_ / _ \ '__|
        / / /     | || | | (_| | | | \__ \  _|  __/ |   
       /_/_/      |_||_|  \__,_|_| |_|___/_|  \___|_|
    */
    fn transfer(to: Identity, sub_id: SubId, amount: u64) {
        let asset_id = AssetId::new(ContractId::this(), sub_id);

        transfer(to, asset_id, amount);
    }
}
