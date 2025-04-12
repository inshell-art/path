use starknet::ContractAddress;

#[starknet::interface]
pub trait IPathNFT<TContractState> {
    fn mint (
        ref self: TContractState,
        recipient: ContractAddress,
        token_id: u256,
    ) -> ();
}