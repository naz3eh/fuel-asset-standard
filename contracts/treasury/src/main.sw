contract;

mod events;
mod errors;

use ::events::*;
use ::errors::*;

use std::{
    asset::{
        mint_to,
        transfer,
    },
    bytes::Bytes,
    call_frames::msg_asset_id,
    constants::DEFAULT_SUB_ID,
    constants::ZERO_B256,
    context::{
        balance_of,
        msg_amount,
    },
    storage::*,
    auth::msg_sender,
};

use standards::{src14::*, src5::*};


abi Treasury {
    #[storage(read, write)]
    fn constructor(owner_address: Address, strategy_identity: Identity);

    #[storage(read, write)]
    fn withdraw_fees();

    #[storage(read, write), payable]
    fn receive_fees();

    #[storage(read, write)]
    fn initialize_strategy(strategy: Identity) -> Identity;

    #[storage(read)]
    fn get_strategy() -> Identity;

    #[storage(read, write)]
    fn set_strategy(new_strategy: Identity);

    #[storage(read, write)]
    fn initialize_owner() -> Identity;

    #[storage(read)]
    fn get_owner() -> Identity;

    #[storage(read, write)]
    fn set_owner(new_owner: Identity);
    
    // SRC14 initialization
    #[storage(read, write)]
    fn initialize(initial_target: ContractId);
}

abi SRC14 {
    // SRC14 interface
    #[storage(read, write)]
    fn _set_proxy_target(new_target: ContractId);
    
    #[storage(read)]
    fn _proxy_target() -> Option<ContractId>;
}

abi SRC14Extension {
    #[storage(read)]
    fn _proxy_owner() -> State;
    
    #[storage(write)]
    fn _set_proxy_owner(new_proxy_owner: State);
}

storage {
    main_strategy_contract: Option<Identity> = Option::None,
    owner: Option<Identity> = Option::None,
    target in 0x7bb458adc1d118713319a5baa00a2d049dd64d2916477d2688d76970c898cd55: Option<ContractId> = None,
    proxy_owner in 0xbb79927b15d9259ea316f2ecb2297d6cc8851888a98278c0a2e03e1a091ea754: State = State::Uninitialized,
}

#[storage(read)]
fn only_proxy_owner() {
    let owner_state = storage.proxy_owner.read();

    match owner_state {
        State::Uninitialized => {
            // Allow the call if uninitialized
            return;
        },
        State::Initialized(owner) => {
            require(msg_sender().unwrap() == owner, "NotOwner");
        },
        State::Revoked => {
            revert(0);
        }
    }
}

#[storage(read)]
fn _proxy_target() -> Option<ContractId> {
    storage.target.read()
}

#[storage(write)]
fn _set_proxy_owner(new_proxy_owner: State) {
    storage.proxy_owner.write(new_proxy_owner);
}

impl SRC14 for Contract {
    #[storage(read, write)]
    fn _set_proxy_target(new_target: ContractId) {
        only_proxy_owner(); // Add access control
        storage.target.write(Some(new_target));
    }

    #[storage(read)]
    fn _proxy_target() -> Option<ContractId> {
        _proxy_target()
    }
}

impl SRC14Extension for Contract {
    #[storage(read)]
    fn _proxy_owner() -> State {
        storage.proxy_owner.read()
    }

    #[storage(write)]
    fn _set_proxy_owner(new_proxy_owner: State) {
        only_proxy_owner();
        _set_proxy_owner(new_proxy_owner);
    }
}

impl Treasury for Contract {
    #[storage(read, write)]
    fn constructor(owner_address: Address, strategy_identity: Identity) {
        // Initialize the owner
        storage.owner.write(Option::Some(Identity::Address(owner_address)));
        
        // Initialize the strategy
        storage.main_strategy_contract.write(Option::Some(strategy_identity));
        
        // Log the initialization events
        log(OwnerUpdated {
            old_owner: Identity::Address(Address::from(ZERO_B256)),
            new_owner: Identity::Address(owner_address),
        });
        
        log(StrategyUpdated {
            old_strategy: Identity::Address(Address::from(ZERO_B256)),
            new_strategy: strategy_identity,
        });
    }

    #[storage(read, write)]
    fn initialize(initial_target: ContractId) {
        // Check if already initialized
        let current_state = storage.proxy_owner.read();
        match current_state {
            State::Uninitialized => {
                // Set the initial owner
                storage
                    .proxy_owner
                    .write(State::Initialized(msg_sender().unwrap()));
                // Set the initial target
                storage.target.write(Some(initial_target));
            },
            _ => {
                revert(0);
            }
        };
    }

    #[storage(read, write)]
    fn withdraw_fees() {
        let sender = msg_sender().unwrap(); 
        let balance = balance_of(
            Identity::ContractId(ContractId::this())
                .as_contract_id()
                .unwrap(),
            AssetId::base(),
        ); // Get balance of base asset
        require(
            sender == storage
                .main_strategy_contract
                .read()
                .unwrap(),
            Error::Unauthorized(sender),
        );

        require(balance > 0, Error::InvalidAmount);

        transfer(sender, AssetId::base(), balance);

        log(WithdrawFees {
            amount: balance,
            recipient: sender,
        });
    }

    #[storage(read, write), payable]
    fn receive_fees() {
        require(
            msg_sender()
                .unwrap() == storage
                .main_strategy_contract
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );
        require(
            msg_asset_id() == AssetId::base(),
            Error::InvalidDepositAsset(msg_asset_id()),
        );

        require(msg_amount() > 0, Error::InvalidAmount);

        log(ReceiveFees {
            amount: msg_amount(),
            sender: msg_sender().unwrap(),
        });
    }

    #[storage(read, write)]
    fn initialize_strategy(strategy: Identity) -> Identity {
        let current_strategy = storage.main_strategy_contract.try_read().unwrap();
        require(current_strategy.is_none(), "strategy already initialized");
        storage.main_strategy_contract.write(Option::Some(strategy));
        
        log(StrategyUpdated {
            old_strategy: Identity::Address(Address::from(ZERO_B256)),
            new_strategy: strategy,
        });
        
        return strategy;
    }

    #[storage(read)]
    fn get_strategy() -> Identity {
        storage.main_strategy_contract.read().unwrap()
    }

    #[storage(read, write)]
    fn set_strategy(new_strategy: Identity) {
        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );
        let old_strategy = storage.main_strategy_contract.read().unwrap();
        storage
            .main_strategy_contract
            .write(Option::Some(new_strategy));
        log(StrategyUpdated {
            old_strategy,
            new_strategy,
        });
    }

    #[storage(read, write)]
    fn initialize_owner() -> Identity {
        let owner = storage.owner.try_read().unwrap();
        require(owner.is_none(), "owner already initialized");
        let sender = msg_sender().unwrap();
        storage.owner.write(Option::Some(sender));
        log(OwnerUpdated {
            old_owner: Identity::Address(Address::from(ZERO_B256)),
            new_owner: sender,
        });
        return sender;
    }

    #[storage(read)]
    fn get_owner() -> Identity {
        storage.owner.read().unwrap()
    }

    #[storage(read, write)]
    fn set_owner(new_owner: Identity) {
        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );
        let old_owner = storage.owner.read().unwrap();
        storage.owner.write(Option::Some(new_owner));

        log(OwnerUpdated {
            old_owner: old_owner,
            new_owner: new_owner,
        });
    }
}