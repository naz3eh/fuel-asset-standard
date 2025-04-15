library;

use std::{bytes::Bytes, string::String};

pub type PoolId = (AssetId, AssetId, bool);

abi MiraAMM {
    #[payable]
    #[storage(read, write)]
    fn swap(
        pool_id: PoolId,
        amount_0_out: u64,
        amount_1_out: u64,
        to: Identity,
        data: Bytes,
    );
}
