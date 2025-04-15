
// SPDX-License-Identifier: Apache-2.0
library;

/// Error codes used throughout the contract.
pub enum Error {
    /// The provided address is zero.
    AddressZero: (),

    /// The operation tried to set a name that was already set.
    NameAlreadySet: (),

    /// The operation tried to set a symbol that was already set.
    SymbolAlreadySet: (),

    /// The operation tried to set decimals that were already set.
    DecimalsAlreadySet: (),

    /// The operation would burn more tokens than are available.
    BurnInsufficientBalance: (),

    /// The method caller is not authorized.
    Unauthorized: Identity,

    /// The owner is not initialized.
    OwnerNotInitialized: (),

    /// The owner is already initialized.
    OwnerAlreadyInitialized: (),
    
    /// The contract is already initialized.
    AlreadyInitialized: (),
    
    /// The caller is not the owner.
    NotOwner: (),
}