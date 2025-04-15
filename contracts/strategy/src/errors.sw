library;

pub enum Error {

    InvalidPercentage: u64,
    AddressZero: (),
    InvalidDepositAsset: AssetId,
    InvalidDepositAmount: u64,
    NoCurrentTokenAllocations: (),
    InvalidWithdrawalAsset: AssetId,
    InvalidWithdrawalAmount: u64,
    InvalidFeeTreasury: (),
    InvalidFeeAmount: u256,
    EmptyTokenAllocations: (),
    InvalidTokenAllocationPercentages: (),
    Unauthorized: Identity,
    AllocationAlreadyInitialized: (),
}

