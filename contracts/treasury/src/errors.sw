library;

pub enum Error {

    Unauthorized: Identity,
    InvalidDepositAsset: AssetId,
    InvalidAmount: (),
    StrategyNotInitialized: (),
}

