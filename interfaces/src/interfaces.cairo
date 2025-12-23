use core::byte_array::ByteArray;
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

    /// Update the PathLook contract used for token_uri rendering.
    fn set_path_look(ref self: TContractState, path_look: ContractAddress);

    /// Read the configured PathLook contract address.
    fn get_path_look(self: @TContractState) -> ContractAddress;

    /// Set the authorized movement minter for a movement tag.
    fn set_authorized_minter(
        ref self: TContractState, movement: felt252, minter: ContractAddress,
    );

    /// Read the authorized movement minter for a movement tag.
    fn get_authorized_minter(self: @TContractState, movement: felt252) -> ContractAddress;

    /// Read the current stage for a PATH token.
    fn get_stage(self: @TContractState, token_id: u256) -> u8;

    /// Consume a PATH token movement (called by authorized movement contracts).
    fn consume_movement(
        ref self: TContractState, path_token_id: u256, movement: felt252, claimer: ContractAddress,
    );
}

#[starknet::interface]
pub trait IPathLook<TContractState> {
    fn generate_svg(
        self: @TContractState, path_nft: ContractAddress, token_id: u256,
    ) -> ByteArray;

    fn generate_svg_data_uri(
        self: @TContractState, path_nft: ContractAddress, token_id: u256,
    ) -> ByteArray;

    fn get_token_metadata(
        self: @TContractState, path_nft: ContractAddress, token_id: u256,
    ) -> ByteArray;
}
