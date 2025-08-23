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
pub trait IPathNFT<TContractState> {
    // Burn a token (sets owner to zero address)
    fn burn(ref self: TContractState, token_id: u256);

    // Safely mint a new token, with a data payload
    fn safe_mint(
        ref self: TContractState, recipient: ContractAddress, token_id: u256, data: Span<felt252>,
    );

    // Alias for camelCase compatibility
    fn safeMint(
        ref self: TContractState, recipient: ContractAddress, tokenId: u256, data: Span<felt252>,
    );
}
