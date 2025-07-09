use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::contract_address::ContractAddress;
use crate::interface::IPathMinterDispatcher;

// re compute `SALES_ROLE` and `RESERVED_ROLE` selectors, and MAX_MINUS_ONE
const SALES_ROLE: felt252 = selector!("SALES_ROLE");
const RESERVED_ROLE: felt252 = selector!("RESERVED_ROLE");
pub const MAX_MINUS_ONE: u256 = u256 {
    low: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE, high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
};


pub fn deploy_fixture(
    reserved_cap: u64,
) -> (IPathMinterDispatcher, ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let nft_owner: ContractAddress = 1.try_into().unwrap();
    let minter_admin: ContractAddress = 2.try_into().unwrap();
    let minter_sales: ContractAddress = 3.try_into().unwrap();
    let minter_reserved: ContractAddress = 4.try_into().unwrap();
    let first_id_low = 0;
    let first_id_high = 0;

    // Deploy PathNFT and PathMinter contracts, and set up roles
    let nft_class = declare("PathNFT").unwrap().contract_class();
    let (nft_addr, _) = nft_class.deploy(@array![nft_owner.into()]).unwrap();

    let class = declare("PathMinter").unwrap().contract_class();
    let (minter_addr, _) = class
        .deploy(
            @array![
                minter_admin.into(),
                nft_addr.into(),
                first_id_low.into(),
                first_id_high.into(),
                reserved_cap.into(),
            ],
        )
        .unwrap();
    let minter_iface = IPathMinterDispatcher { contract_address: minter_addr };
    let minter_access_iface = IAccessControlDispatcher { contract_address: minter_addr };
    let nft_ownable_iface = IOwnableDispatcher { contract_address: nft_addr };

    // transfer ownership of the NFT contract to minter_addr
    start_cheat_caller_address(nft_addr, nft_owner);
    nft_ownable_iface.transfer_ownership(minter_addr);
    stop_cheat_caller_address(nft_addr);

    // Grant roles in minter contract as administrator
    start_cheat_caller_address(minter_addr, minter_admin);
    minter_access_iface.grant_role(SALES_ROLE, minter_sales);
    minter_access_iface.grant_role(RESERVED_ROLE, minter_reserved);
    stop_cheat_caller_address(minter_addr);

    return (minter_iface, minter_admin, minter_sales, minter_reserved, nft_addr);
}
