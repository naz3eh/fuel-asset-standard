library;

pub struct ReceiveFees {
    pub amount: u64,
    pub sender: Identity,
}

pub struct WithdrawFees {
    pub amount: u64,
    pub recipient: Identity,
}

pub struct OwnerUpdated {
    pub old_owner: Identity,
    pub new_owner: Identity,
}


pub struct StrategyUpdated {
    pub old_strategy: Identity,
    pub new_strategy: Identity,
}

