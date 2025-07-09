use starknet::ContractAddress;
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

    // Set the original minter for a sparkers token
    fn set_sparker_original_minter(ref self: TContractState, token_id: u256, minter: ByteArray);
}
