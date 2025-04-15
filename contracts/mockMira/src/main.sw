contract;

use std::{
    bytes::Bytes,
    identity::Identity,
    storage::*,
};

pub type PoolId = (AssetId, AssetId, bool);

abi MiraAMM {
    #[payable]
    fn swap(
        p_id: PoolId,
        amount_0_out: u64,
        amount_1_out: u64,
        to: Identity,
        data: Bytes,
    );
}

impl MiraAMM for Contract {
    #[payable]
    fn swap(
        _p_id: PoolId,
        _amount_0_out: u64,
        _amount_1_out: u64,
        _to: Identity,
        _data: Bytes,
    ) {
        // Do nothing - just pretend it worked
        // This is the simplest possible mock for testing
    }
}