contract;

mod events;
mod errors;

pub type PoolId = (AssetId, AssetId, bool);

use events::*;
use errors::*;

use interfaces::sprout_token::Sprout_Token;
use interfaces::mira_amm::MiraAMM;
use interfaces::fungible_abi::FungibleAsset;
use standards::src3::SRC3;
use standards::src5::{AccessError, SRC5, State};
use standards::src20::{SRC20, SetDecimalsEvent, SetNameEvent, SetSymbolEvent, TotalSupplyEvent};

//use fungible_abi::*;

use std::{
    asset::{
        burn,
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
    string::String,
};

use std::storage::storage_vec::*;

// Token configuration
configurable {
    DECIMALS: u8 = 9u8,
    NAME: str[8] = __to_str_array("Swaylend"),
    SYMBOL: str[5] = __to_str_array("SLEND"),
    MAX_SUPPLY: u64 = 1_000_000_000_000_000_000u64,
}

const SCALE: u64 = 10000;

#[derive(AbiEncode)]
struct IdentityValidationEvent {
    error_code: u64,
}

pub struct TokenAllocation {
    pub token: AssetId,
    pub p_id: PoolId,
    pub percentage: u64,
}

pub struct Rebalance {
    pub old_alloc: StorageVec<TokenAllocation>,
    pub new_alloc: Vec<TokenAllocation>,
}

storage {
    withdrawal_fee: u64 = 0,
    sprout_receipt_token: ContractId = ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    fee_treasury_contract: Identity = Identity::Address(Address::from(ZERO_B256)),
    target_tokens: StorageVec<TokenAllocation> = StorageVec {},
    slippage_tolerance: u64 = 500, // 5% default in basis points
    owner: Option<Identity> = Option::None,
    target in 0x7bb458adc1d118713319a5baa00a2d049dd64d2916477d2688d76970c898cd55: Option<ContractId> = None,
    proxy_owner in 0xbb79927b15d9259ea316f2ecb2297d6cc8851888a98278c0a2e03e1a091ea754: State = State::Uninitialized,
    mira_amm_id: b256 = 0x2e40f2b244b98ed6b8204b3de0156c6961f98525c8162f80162fcf53eebd90e7,
    // Added storage for SRC20 implementation
    total_supply: u64 = 0,
    token_owner: State = State::Uninitialized,
}

abi Strategy {
    #[storage(read, write)]
    fn constructor(token_contract_id: ContractId, owner_address: Address);

    #[storage(read, write)]
    fn initialize_token_allocations(allocations: Vec<TokenAllocation>);
    
    #[storage(read, write), payable]
    fn deposit();

    #[storage(read, write), payable]
    fn withdraw();

    #[storage(read, write)]
    fn rebalance(new_allocations: Vec<TokenAllocation>);

    #[storage(read)]
    fn get_withdrawal_fee() -> u64;

    #[storage(write)]
    fn set_withdrawal_fee(fee: u64);

    #[storage(read)]
    fn get_sprout_receipt_token() -> ContractId;

    #[storage(write)]
    fn set_sprout_receipt_token(token: ContractId);

    #[storage(read)]
    fn get_fee_treasury_contract() -> Identity;

    #[storage(write)]
    fn set_fee_treasury_contract(treasury: Identity);

    #[storage(read, write)]
    fn set_mira_amm_contract(new_mira: ContractId);

    #[storage(read)]
    fn get_slippage_tolerance() -> u64;

    #[storage(write)]
    fn update_slippage_tolerance(new_tolerance: u64);

    #[storage(read)]
    fn get_target_tokens() -> Vec<TokenAllocation>;

    #[storage(read)]
    fn get_token_allocation(token: AssetId) -> Option<u64>;

    #[storage(read, write)]
    fn initialize_owner() -> Identity;

    #[storage(read)]
    fn get_owner() -> Identity;

    #[storage(read, write)]
    fn set_owner(new_owner: Identity);
    
    #[storage(read, write)]
    fn initialize(initial_target: ContractId);
    
    // Added for token functionality
    #[storage(read)]
    fn max_supply(asset: AssetId) -> Option<u64>;

    #[storage(read)]
    fn asset_id() -> AssetId;
    
    #[storage(read)]
    fn emit_src20_events();
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

// Implementation of SRC20 (Token standard)
impl SRC20 for Contract {
    #[storage(read)]
    fn total_assets() -> u64 {
        1_u64
    }

    #[storage(read)]
    fn total_supply(asset: AssetId) -> Option<u64> {
        if asset == AssetId::default() {
            Some(storage.total_supply.read())
        } else {
            None
        }
    }

    #[storage(read)]
    fn name(asset: AssetId) -> Option<String> {
        if asset == AssetId::default() {
            Some(String::from_ascii_str(from_str_array(NAME)))
        } else {
            None
        }
    }

    #[storage(read)]
    fn symbol(asset: AssetId) -> Option<String> {
        if asset == AssetId::default() {
            Some(String::from_ascii_str(from_str_array(SYMBOL)))
        } else {
            None
        }
    }

    #[storage(read)]
    fn decimals(asset: AssetId) -> Option<u8> {
        if asset == AssetId::default() {
            Some(DECIMALS)
        } else {
            None
        }
    }
}

// Implementation of SRC5 (Ownership standard)
impl SRC5 for Contract {
    #[storage(read)]
    fn owner() -> State {
        storage.token_owner.read()
    }
}

// Implementation of SRC3 (Mint and Burn standard)
impl SRC3 for Contract {
    #[storage(read, write)]
    fn mint(recipient: Identity, sub_id: Option<SubId>, amount: u64) {
        require(
            sub_id
                .is_some() && sub_id
                .unwrap() == DEFAULT_SUB_ID,
            "incorrect-sub-id",
        );
        require(
            storage
                .token_owner
                .read() == State::Initialized(msg_sender().unwrap()),
            AccessError::NotOwner,
        );
        require(
            storage
                .total_supply
                .read() + amount <= MAX_SUPPLY,
            "max-supply-reached",
        );

        let new_supply = storage.total_supply.read() + amount;
        storage.total_supply.write(new_supply);

        mint_to(recipient, DEFAULT_SUB_ID, amount);

        TotalSupplyEvent::new(AssetId::default(), new_supply, msg_sender().unwrap())
            .log();
    }

    #[payable]
    #[storage(read, write)]
    fn burn(sub_id: SubId, amount: u64) {
        require(sub_id == DEFAULT_SUB_ID, "incorrect-sub-id");
        require(msg_amount() == amount, "incorrect-amount-provided");
        require(
            msg_asset_id() == AssetId::default(),
            "incorrect-asset-provided",
        );

        let new_supply = storage.total_supply.read() - amount;
        storage.total_supply.write(new_supply);

        burn(DEFAULT_SUB_ID, amount);

        TotalSupplyEvent::new(AssetId::default(), new_supply, msg_sender().unwrap())
            .log();
    }
}

impl Strategy for Contract {
    #[storage(read, write)]
    fn constructor(token_contract_id: ContractId, owner_address: Address) {
        storage.sprout_receipt_token.write(token_contract_id);
        // Verify the token contract is valid by trying to call a method
        let receipt_token = abi(FungibleAsset, token_contract_id.into());
        
        // Initialize token owner
        storage.token_owner.write(State::Initialized(Identity::Address(owner_address)));
    }
    
    #[storage(read, write)]
    fn initialize(initial_target: ContractId) {
        // Check if already initialized
        let current_state = storage.proxy_owner.read();
        match current_state {
            State::Uninitialized => {
                // Set the initial owner
                storage.proxy_owner.write(State::Initialized(msg_sender().unwrap()));
                // Set the initial target
                storage.target.write(Some(initial_target));
            },
            _ => {
                revert(0);
            }
        };
    }

    #[storage(read, write)]
    fn initialize_token_allocations(allocations: Vec<TokenAllocation>) {
        require(
            msg_sender().unwrap() == storage.owner.read().unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );
        
        // Ensure no existing allocations
        require(
            storage.target_tokens.len() == 0,
            Error::AllocationAlreadyInitialized,
        );
        
        // Validate allocations
        require(allocations.len() > 0, Error::EmptyTokenAllocations);
        
        // Validate total percentage equals 100%
        let mut total = 0;
        let mut i = 0;
        while i < allocations.len() {
            total += allocations.get(i).unwrap().percentage;
            i += 1;
        }
        require(total == SCALE, Error::InvalidTokenAllocationPercentages);
        
        // Store allocations
        i = 0;
        while i < allocations.len() {
            storage.target_tokens.push(allocations.get(i).unwrap());
            i += 1;
        }
        
        // Log the allocation initialization
        log(Rebalance {
            old_alloc: StorageVec {}, // Empty since this is initialization
            new_alloc: allocations,
        });
    }
    

    #[storage(read, write)]
    fn initialize_owner() -> Identity {
        let owner = storage.owner.try_read().unwrap();

        // make sure the owner has NOT already been initialized
        require(owner.is_none(), "owner already initialized");

        // get the identity of the sender        
        let sender = msg_sender().unwrap();
        // set the owner to the sender's identity
        storage.owner.write(Option::Some(sender));

        log(OwnerUpdated {
            old_owner: Identity::Address(Address::from(ZERO_B256)),
            new_owner: sender,
        });

        // return the owner
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

    #[storage(read)]
    fn get_withdrawal_fee() -> u64 {
        storage.withdrawal_fee.read()
    }

    #[storage(write)]
    fn set_withdrawal_fee(fee: u64) {
        require(fee <= SCALE, Error::InvalidPercentage(fee));

        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );

        let old_fee = storage.withdrawal_fee.read();
        storage.withdrawal_fee.write(fee);

        log(WithdrawalFeeUpdated {
            old_fee: old_fee,
            new_fee: fee,
        });
    }

    #[storage(read)]
    fn get_sprout_receipt_token() -> ContractId {
        storage.sprout_receipt_token.read()
    }

    #[storage(write)]
    fn set_sprout_receipt_token(token: ContractId) {
        require(token != ContractId::from(ZERO_B256), Error::AddressZero);

        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );

        let old_sprout_receipt_address = storage.sprout_receipt_token.read();
        storage.sprout_receipt_token.write(token);

        log(ReceiptTokenUpdated {
            old_token: old_sprout_receipt_address,
            new_token: token,
        });
    }

    #[storage(read)]
    fn get_fee_treasury_contract() -> Identity {
        storage.fee_treasury_contract.read()
    }

    #[storage(write)]
    fn set_fee_treasury_contract(treasury: Identity) {

        require(
            treasury != Identity::Address(Address::from(ZERO_B256)),
            Error::AddressZero,
        );
        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );

        let old_treasury = storage.fee_treasury_contract.read();
        storage.fee_treasury_contract.write(treasury);

        log(TreasuryUpdated {
            old_treasury: old_treasury,
            new_treasury: treasury,
        });
    }

    #[storage(read, write)]
    fn set_mira_amm_contract(new_mira: ContractId) {
        require(
            msg_sender().unwrap() == storage.owner.read().unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );
        
        // If MIRA_AMM_ID is moved to storage:
        storage.mira_amm_id.write(new_mira.into());
        
        // Log the update
        log(MiraAMMUpdated {
            old_amm: ContractId::from(storage.mira_amm_id.read()),
            new_amm: new_mira,
        });
    }

    #[storage(read)]
    fn get_slippage_tolerance() -> u64 {
        storage.slippage_tolerance.read()
    }

    #[storage(write)]
    fn update_slippage_tolerance(new_tolerance: u64) {

        require(
            new_tolerance <= SCALE,
            Error::InvalidPercentage(new_tolerance),
        );
        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );

        let old_tolerance = storage.slippage_tolerance.read();
        storage.slippage_tolerance.write(new_tolerance);

        log(SlippageToleranceUpdated {
            old_tolerance: old_tolerance,
            new_tolerance: new_tolerance,
        });
    }

    #[storage(read)]
    fn get_target_tokens() -> Vec<TokenAllocation> {
        let mut tokens = Vec::new();
        let vec_length = storage.target_tokens.len();

        let mut i = 0;
        while i < vec_length {
            let stored_allocation = storage.target_tokens.get(i).unwrap();
            tokens.push(TokenAllocation {
                token: stored_allocation.read().token,
                p_id: stored_allocation.read().p_id,
                percentage: stored_allocation.read().percentage,
            });
            i += 1;
        }
        tokens
    }

    #[storage(read)]
    fn get_token_allocation(token: AssetId) -> Option<u64> {
        let vec_length = storage.target_tokens.len();
        let mut i = 0;

        while i < vec_length {
            let stored_allocation = storage.target_tokens.get(i).unwrap();
            if stored_allocation.read().token == token {
                return Some(stored_allocation.read().percentage);
            }
            i += 1;
        }
        None
    }

    #[storage(read)]
fn max_supply(asset: AssetId) -> Option<u64> {
    if asset == AssetId::default() {
        Some(MAX_SUPPLY)
    } else {
        None
    }
}

#[storage(read)]
fn asset_id() -> AssetId {
    AssetId::default()
}

    #[storage(read)]
fn emit_src20_events() {
    // Metadata that is stored as a configurable should only be emitted once.
    let asset = AssetId::default();
    let sender = msg_sender().unwrap();
    let name = Some(String::from_ascii_str(from_str_array(NAME)));
    let symbol = Some(String::from_ascii_str(from_str_array(SYMBOL)));
 
    SetNameEvent::new(asset, name, sender).log();
    SetSymbolEvent::new(asset, symbol, sender).log();
    SetDecimalsEvent::new(asset, DECIMALS, sender).log();
    TotalSupplyEvent::new(asset, storage.total_supply.read(), sender).log();
}


    #[storage(read, write), payable]
    fn deposit() {
        require(
            msg_asset_id() == AssetId::base(),
            Error::InvalidDepositAsset(msg_asset_id()),
        );

        // Get the asset and amount deposited in this transaction
        let amount = msg_amount();
        
        // Get the sender's identity directly
        let sender_identity = msg_sender().unwrap();
        
        // Ensure we have target token allocations set
        require(
            storage.target_tokens.len() > 0,
            Error::NoCurrentTokenAllocations,
        );

        // Validate deposit amount
        require(amount > 0, Error::InvalidDepositAmount(amount));
        let new_supply = storage.total_supply.read() + amount;
    
    // Check against max supply
    require(new_supply <= MAX_SUPPLY, "max-supply-reached");
    
    // Update total supply
    storage.total_supply.write(new_supply);
    
    // Mint tokens to the sender
    mint_to(sender_identity, DEFAULT_SUB_ID, amount);
    
    // Log the total supply update event
    TotalSupplyEvent::new(AssetId::default(), new_supply, msg_sender().unwrap()).log();
    
        
        let mut i = 0;
        let mira = abi(MiraAMM, storage.mira_amm_id.read());
        let slippage = storage.slippage_tolerance.read();

        // Get target distributions
        while i < storage.target_tokens.len() {
            let allocation = storage.target_tokens.get(i).unwrap();
            let local_pool_id = allocation.read().p_id;
            let swap_amount = amount * allocation.read().percentage / SCALE;

            if swap_amount > 0 {
                transfer(
                    Identity::ContractId(ContractId::from(storage.mira_amm_id.read())),
                    AssetId::base(),
                    swap_amount,
                );
                let min_amount_out = swap_amount - (swap_amount * slippage / SCALE);

                // If our target token is token1 in the pool
                let (amount_0_out, amount_1_out) = if local_pool_id.1 == allocation.read().token {
                    (0, min_amount_out) // We want token1 out
                } else {
                    (min_amount_out, 0) // We want token0 out
                };

                // perform swap
                mira.swap(
                    local_pool_id,
                    amount_0_out,
                    amount_1_out,
                    Identity::ContractId(ContractId::this()),
                    Bytes::new(),
                );

            }
            
            i += 1;
        }

        log(Deposit {
            amount: amount,
            sender: sender_identity,
        });
    }

   #[storage(read, write), payable]
fn withdraw() {
    // Ensure the received asset is the default asset (our own token)
    require(
        msg_asset_id() == AssetId::default(),
        Error::InvalidWithdrawalAsset(msg_asset_id()),
    );

    let amount = msg_amount();
    require(amount > 0, Error::InvalidWithdrawalAmount(amount));

    let sender = match msg_sender() {
        Ok(identity) => match identity {
            Identity::Address(addr) => addr,
            Identity::ContractId(_) => {
                log(IdentityValidationEvent { error_code: 1 });
                revert(1);
            },
            _ => {
                log(IdentityValidationEvent { error_code: 2 });
                revert(2);
            }
        },
        Err(_) => {
            log(IdentityValidationEvent { error_code: 3 });
            revert(3);
        }
    };

    // Use internal burn functionality instead of calling external contract
    let new_supply = storage.total_supply.read() - amount;
    storage.total_supply.write(new_supply);
    
    // Burn the tokens
    burn(DEFAULT_SUB_ID, amount);
    
    // Log the total supply update event
    TotalSupplyEvent::new(AssetId::default(), new_supply, msg_sender().unwrap()).log();

    let mira = abi(MiraAMM, storage.mira_amm_id.read());
    let slippage = storage.slippage_tolerance.read();
    let mut total_base_asset = 0;
    let mut i = 0;

    while i < storage.target_tokens.len() {
        let allocation = storage.target_tokens.get(i).unwrap();
        let local_pool_id = allocation.read().p_id;
        let token_amount = amount * allocation.read().percentage / SCALE;

        if token_amount > 0 {
            // Calculate minimum amount out based on slippage
            let min_amount_out = token_amount - (token_amount * slippage / SCALE);

            // For swap back to base asset, we need to swap in the opposite direction
            let (amount_0_out, amount_1_out) = if local_pool_id.1 == allocation.read().token {
                (min_amount_out, 0) // We want token0 (base asset) out
            } else {
                (0, min_amount_out) // We want token1 (base asset) out
            };

            // Approve and swap
            transfer(
                Identity::ContractId(ContractId::from(storage.mira_amm_id.read())),
                allocation
                    .read()
                    .token,
                token_amount,
            );

            // Perform swap back to base asset
            mira.swap(
                local_pool_id,
                amount_0_out,
                amount_1_out,
                Identity::ContractId(ContractId::this()),
                Bytes::new(),
            );

            total_base_asset += min_amount_out;
        }
        i += 1;
    }

    // Calculate and deduct withdrawal fee
    let fee_amount = (total_base_asset * storage.withdrawal_fee.read()) / SCALE;
    let amount_after_fees = total_base_asset - fee_amount;

    // Send fee to treasury if configured
    if fee_amount > 0 {
        let treasury = storage.fee_treasury_contract.read();

        require(
            treasury != Identity::Address(Address::from(ZERO_B256)),
            Error::InvalidFeeTreasury,
        );

        transfer(treasury, AssetId::base(), fee_amount);
    }

    // Send remaining base asset to user
    transfer(
        Identity::Address(sender),
        AssetId::base(),
        amount_after_fees,
    );

    log(Withdraw {
        amount: amount,
        fee_collected: fee_amount,
        recipient: Identity::Address(sender),
    });
}

    #[storage(read, write)]
    fn rebalance(new_allocations: Vec<TokenAllocation>) {

        require(
            msg_sender()
                .unwrap() == storage
                .owner
                .read()
                .unwrap(),
            Error::Unauthorized(msg_sender().unwrap()),
        );
        // First validate new allocations
        require(new_allocations.len() > 0, Error::EmptyTokenAllocations);


        // Validate total percentage equals 100%
        let mut total = 0;
        let mut i = 0;
        while i < new_allocations.len() {
            total += new_allocations.get(i).unwrap().percentage;
            i += 1;
        }
        require(total == SCALE, Error::InvalidTokenAllocationPercentages);

        // First swap all current tokens to base asset
        let mira = abi(MiraAMM, storage.mira_amm_id.read());
        let slippage = storage.slippage_tolerance.read();
        let mut total_base_asset = 0;
        i = 0;

        // Swap existing tokens to base asset
        while i < storage.target_tokens.len() {
            let allocation = storage.target_tokens.get(i).unwrap();
            let local_pool_id = allocation.read().p_id;

            // Get current balance of this token
            let token_balance = balance_of(
                Identity::ContractId(ContractId::this())
                    .as_contract_id()
                    .unwrap(),
                allocation
                    .read()
                    .token,
            );

            if token_balance > 0 {
                // Calculate minimum amount out based on slippage
                let min_amount_out = token_balance - (token_balance * slippage / SCALE);

                // For swap back to base asset, we need to swap in the opposite direction
                let (amount_0_out, amount_1_out) = if local_pool_id.1 == allocation.read().token {
                    (min_amount_out, 0) // We want token0 (base asset) out
                } else {
                    (0, min_amount_out) // We want token1 (base asset) out
                };

                // Transfer token to Mira
                transfer(
                    Identity::ContractId(ContractId::from(storage.mira_amm_id.read())),
                    allocation
                        .read()
                        .token,
                    token_balance,
                );

                // Perform swap back to base asset
                mira.swap(
                    local_pool_id,
                    amount_0_out,
                    amount_1_out,
                    Identity::ContractId(ContractId::this()),
                    Bytes::new(),
                );

                total_base_asset += min_amount_out;
            }
            i += 1;
        }

        let old_allocations = storage.target_tokens.read();

        // Update storage with new allocations
        // Clear existing allocations
        while storage.target_tokens.len() > 0 {
            storage.target_tokens.pop();
        }

        // Add new allocations
        i = 0;
        while i < new_allocations.len() {
            storage.target_tokens.push(new_allocations.get(i).unwrap());
            i += 1;
        }

        // Now swap base asset to new allocations
        i = 0;
        while i < storage.target_tokens.len() {
            let allocation = storage.target_tokens.get(i).unwrap();
            let local_pool_id = allocation.read().p_id;
            let swap_amount = total_base_asset * allocation.read().percentage / SCALE;

            if swap_amount > 0 {
                transfer(
                    Identity::ContractId(ContractId::from(storage.mira_amm_id.read())),
                    AssetId::base(),
                    swap_amount,
                );
                let min_amount_out = swap_amount - (swap_amount * slippage / SCALE);

                // If our target token is token1 in the pool
                let (amount_0_out, amount_1_out) = if local_pool_id.1 == allocation.read().token {
                    (0, min_amount_out) // We want token1 out
                } else {
                    (min_amount_out, 0) // We want token0 out
                };

                // perform swap
                mira.swap(
                    local_pool_id,
                    amount_0_out,
                    amount_1_out,
                    Identity::ContractId(ContractId::this()),
                    Bytes::new(),
                );
            }
            i += 1;
        }

        log(Rebalance {
            old_alloc: old_allocations,
            new_alloc: new_allocations,
        });

    }
}


