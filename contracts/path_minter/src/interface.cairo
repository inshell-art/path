use core::integer::u256;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IPathMinter<TState> {
    /// View the reserved cap for minting.
    fn get_reserved_cap(ref self: TState) -> u64;

    /// View the remaining reserved NFTs that can be minted.
    fn get_reserved_remaining(ref self: TState) -> u64;

    /// Mints a public token to the specified address.
    fn mint_public(ref self: TState, to: ContractAddress, data: Span<felt252>) -> u256;

    /// Mints reserved NFTs to the specified address.
    fn mint_sparker(ref self: TState, to: ContractAddress, data: Span<felt252>) -> u256;
}

#[starknet::interface]
pub trait IForwarder<TState> {
    /// Execute `target.selector(calldata)` as this contract.
    //! here is the //!
    // yes can not //
    fn execute(
        ref self: TState, target: ContractAddress, selector: felt252, calldata: Span<felt252>,
    ) -> Span<felt252>;
}
