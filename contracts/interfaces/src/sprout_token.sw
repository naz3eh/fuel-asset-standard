library;


abi Sprout_Token {
    #[storage(read)]
    fn main_contract() -> ContractId;

    #[storage(read, write)]
    fn mint(user: Identity, sub_id: SubId, amount: u64);

    #[storage(read, write)]
    fn burn(sub_id: SubId, amount: u64);

    #[storage(read, write)]
    fn update_main_caller_contract(new_contract: ContractId);

    #[storage(read, write)]
    fn initialize_owner() -> Identity;

    #[storage(read)]
    fn get_owner() -> Identity;

    #[storage(read, write)]
    fn set_owner(new_owner: Identity);

    #[storage(read)]
    fn total_assets() -> u64;

    #[storage(read)]
    fn total_supply(asset: AssetId) -> Option<u64>;
}

