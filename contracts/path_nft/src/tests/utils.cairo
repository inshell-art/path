use openzeppelin::security::interface::IPausableDispatcher;
use openzeppelin::token::erc721::interface::IERC721Dispatcher;
use path_interfaces::IPathNFTDispatcher;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

// Helper: To declare and deploy the contract, and trigger calls to the contract
pub fn deploy_contract(owner: ContractAddress) -> ContractAddress {
    let owner_felt: felt252 = owner.into();
    let (addr, _) = declare("PathNFT")
        .unwrap()
        .contract_class()
        .deploy(@array![owner_felt])
        .unwrap();

    addr
}

pub fn deploy_ERC721ReceiverStub() -> ContractAddress {
    let (addr, _) = declare("ERC721ReceiverStub")
        .unwrap()
        .contract_class()
        .deploy(@array![])
        .unwrap();

    addr
}

// Helper: Deploy contract, and prepare the interfaces
pub fn setup() -> (
    ContractAddress,
    ContractAddress,
    IPathNFTDispatcher,
    IERC721Dispatcher,
    IPausableDispatcher,
    u256,
    ContractAddress,
    Span<felt252>,
) {
    let owner: ContractAddress = 1.try_into().unwrap();
    let addr = deploy_contract(owner);
    let nft_iface = IPathNFTDispatcher { contract_address: addr };
    let erc721_iface = IERC721Dispatcher { contract_address: addr };
    let pausable_iface = IPausableDispatcher { contract_address: addr };
    let token_id = 2_u256;
    let recipient: ContractAddress = deploy_ERC721ReceiverStub();
    let data = array![].span();
    (owner, addr, nft_iface, erc721_iface, pausable_iface, token_id, recipient, data)
}
