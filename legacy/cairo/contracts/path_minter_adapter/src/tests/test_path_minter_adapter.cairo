use core::array::ArrayTrait;
use core::traits::TryInto;
use path_minter_adapter::path_minter_adapter::{
    IAdapterAdminDispatcher, IAdapterAdminDispatcherTrait,
};
use pulse_adapter::interface::{
    IPulseAdapterDispatcher, IPulseAdapterDispatcherTrait, IPulseAdapterSafeDispatcher,
    IPulseAdapterSafeDispatcherTrait,
};
use snforge_std::cheatcodes::{CheatSpan, mock_call};
use snforge_std::{ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
use starknet::ContractAddress;

#[derive(Drop)]
struct AdapterHandles {
    addr: ContractAddress,
    admin: IAdapterAdminDispatcher,
    adapter: IPulseAdapterDispatcher,
    adapter_safe: IPulseAdapterSafeDispatcher,
}

fn deploy_adapter(
    owner: ContractAddress, auction: ContractAddress, minter: ContractAddress,
) -> AdapterHandles {
    let class = declare("PathMinterAdapter").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    owner.serialize(ref calldata);
    auction.serialize(ref calldata);
    minter.serialize(ref calldata);
    let (addr, _) = class.deploy(@calldata).unwrap();

    AdapterHandles {
        addr,
        admin: IAdapterAdminDispatcher { contract_address: addr },
        adapter: IPulseAdapterDispatcher { contract_address: addr },
        adapter_safe: IPulseAdapterSafeDispatcher { contract_address: addr },
    }
}

fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}
fn ALICE() -> ContractAddress {
    'ALICE'.try_into().unwrap()
}
fn BOB() -> ContractAddress {
    'BOB'.try_into().unwrap()
}
fn MINTER() -> ContractAddress {
    'MINTER'.try_into().unwrap()
}

#[test]
fn gl_adapter_constructor_sets_config_and_target() {
    let adapter = deploy_adapter(ADMIN(), ALICE(), BOB());

    let (auction, minter) = adapter.admin.get_config();
    assert_eq!(auction, ALICE());
    assert_eq!(minter, BOB());
    assert_eq!(IPulseAdapterDispatcherTrait::target(adapter.adapter), ALICE());
}

#[test]
fn admin_set_auction_updates_config() {
    let adapter = deploy_adapter(ADMIN(), ALICE(), BOB());

    cheat_caller_address(adapter.addr, ADMIN(), CheatSpan::TargetCalls(1));
    adapter.admin.set_auction(MINTER());

    let (auction, minter) = adapter.admin.get_config();
    assert_eq!(auction, MINTER());
    assert_eq!(minter, BOB());
    assert_eq!(IPulseAdapterDispatcherTrait::target(adapter.adapter), MINTER());
}

#[test]
fn admin_set_minter_updates_config() {
    let adapter = deploy_adapter(ADMIN(), ALICE(), BOB());

    cheat_caller_address(adapter.addr, ADMIN(), CheatSpan::TargetCalls(1));
    adapter.admin.set_minter(MINTER());

    let (auction, minter) = adapter.admin.get_config();
    assert_eq!(auction, ALICE());
    assert_eq!(minter, MINTER());
}

#[test]
#[feature("safe_dispatcher")]
fn settle_requires_auction() {
    let adapter = deploy_adapter(ADMIN(), ALICE(), BOB());

    cheat_caller_address(adapter.addr, BOB(), CheatSpan::TargetCalls(1));
    match IPulseAdapterSafeDispatcherTrait::settle(adapter.adapter_safe, ALICE(), array![].span()) {
        Result::Ok(_) => panic!("settle by non-auction should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ONLY_AUCTION'); },
    }
}

#[test]
fn settle_forwards_to_minter() {
    let adapter = deploy_adapter(ADMIN(), ALICE(), BOB());

    // Mock PathMinter.mint_public(buyer, data) return value.
    mock_call(BOB(), selector!("mint_public"), array![0].span(), 1);

    cheat_caller_address(adapter.addr, ALICE(), CheatSpan::TargetCalls(1));
    let minted = IPulseAdapterDispatcherTrait::settle(adapter.adapter, ALICE(), array![].span());
    assert_eq!(minted, 1_u256);
}
