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
    fn mint_finder(ref self: TState, to: ContractAddress, data: Span<felt252>) -> u256;
}
