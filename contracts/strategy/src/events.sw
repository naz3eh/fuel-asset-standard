library;

pub struct TokenAllocation {

    pub token: AssetId,
    pub p_id: (AssetId, AssetId, bool),
    pub percentage: u64,
}

pub struct Deposit {
    pub amount: u64,
    pub sender: Identity,
}


pub struct Withdraw {
    pub amount: u64,
    pub fee_collected: u64,
    pub recipient: Identity,
}

pub struct WithdrawalFeeUpdated {
    pub old_fee: u64,
    pub new_fee: u64,
}

pub struct TreasuryUpdated {
    pub old_treasury: Identity,
    pub new_treasury: Identity,
}

pub struct ReceiptTokenUpdated {
    pub old_token: ContractId,
    pub new_token: ContractId,
}

pub struct SlippageToleranceUpdated {
    pub old_tolerance: u64,
    pub new_tolerance: u64,
}

pub struct OwnerUpdated {
    pub old_owner: Identity,
    pub new_owner: Identity,
}


pub struct MiraAMMUpdated {
    pub old_amm: ContractId,
    pub new_amm: ContractId,
}


pub struct StrategyInitialized {
    pub receipt_token: ContractId,
   pub owner: Identity,
}



