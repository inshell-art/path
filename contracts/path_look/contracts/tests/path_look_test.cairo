use core::array::{ArrayTrait, Span};
use core::result::ResultTrait;
use core::byte_array::ByteArrayTrait;
use path_look::path_look::{IPathLookDispatcher, IPathLookDispatcherTrait};
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;

#[starknet::contract]
mod StepCurveMock {
    use step_curve::glyph_interface::IGlyph;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl GlyphMockImpl of IGlyph<ContractState> {
        fn render(self: @ContractState, params: Span<felt252>) -> Array<felt252> {
            let _ = params;
            let mut path: ByteArray = Default::default();
            path.append(@"M 0 0");
            let mut out: Array<felt252> = array![];
            path.serialize(ref out);
            out
        }

        fn metadata(self: @ContractState) -> Span<felt252> {
            array![].span()
        }
    }
}

#[starknet::contract]
mod PathNFTMock {
    use path_look::path_look::IPathNFTStage;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        stage: u8,
        stage_minted: u32,
        quota_thought: u32,
        quota_will: u32,
        quota_awa: u32,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, stage: u8, stage_minted: u32, quota_thought: u32,
        quota_will: u32, quota_awa: u32,
    ) {
        self.stage.write(stage);
        self.stage_minted.write(stage_minted);
        self.quota_thought.write(quota_thought);
        self.quota_will.write(quota_will);
        self.quota_awa.write(quota_awa);
    }

    #[abi(embed_v0)]
    impl MockImpl of IPathNFTStage<ContractState> {
        fn get_stage(self: @ContractState, token_id: u256) -> u8 {
            let _ = token_id;
            self.stage.read()
        }

        fn get_stage_minted(self: @ContractState, token_id: u256) -> u32 {
            let _ = token_id;
            self.stage_minted.read()
        }

        fn get_movement_quota(self: @ContractState, movement: felt252) -> u32 {
            if movement == 'THOUGHT' {
                return self.quota_thought.read();
            }
            if movement == 'WILL' {
                return self.quota_will.read();
            }
            if movement == 'AWA' {
                return self.quota_awa.read();
            }
            0_u32
        }
    }
}

#[starknet::contract]
mod MockPprf {
    use core::array::ArrayTrait;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use glyph_pprf::IGlyph;

    #[storage]
    struct Storage {
        value: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, value: u32) {
        self.value.write(value);
    }

    #[abi(embed_v0)]
    impl GlyphMock of IGlyph<ContractState> {
        fn render(self: @ContractState, params: Span<felt252>) -> Array<felt252> {
            let mut data: Array<felt252> = array![];
            data.append(self.value.read().into());
            data
        }

        fn metadata(self: @ContractState) -> Span<felt252> {
            array![].span()
        }
    }
}

fn deploy_mock_pprf(value: u32) -> ContractAddress {
    let declared = declare("MockPprf").unwrap();
    let class = declared.contract_class();
    // constructor calldata: value
    let mut calldata = array![value.into()];
    let result = class.deploy(@calldata).unwrap();
    let (address, _) = result;
    address
}

fn deploy_step_curve() -> ContractAddress {
    let class = declare("StepCurveMock").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let result = class.deploy(@calldata).unwrap();
    let (address, _) = result;
    address
}

fn deploy_path_nft_mock(
    stage: u8, stage_minted: u32, quota_thought: u32, quota_will: u32, quota_awa: u32,
) -> ContractAddress {
    let class = declare("PathNFTMock").unwrap().contract_class();
    let mut calldata = array![
        stage.into(),
        stage_minted.into(),
        quota_thought.into(),
        quota_will.into(),
        quota_awa.into()
    ];
    let result = class.deploy(@calldata).unwrap();
    let (address, _) = result;
    address
}

fn deploy_path_look(
    pprf_address: ContractAddress, step_curve_address: ContractAddress,
) -> ContractAddress {
    let class = declare("PathLook").unwrap().contract_class();
    // constructor calldata: pprf_address, step_curve_address
    let mut calldata = array![pprf_address.into(), step_curve_address.into()];
    let result = class.deploy(@calldata).unwrap();
    let (address, _) = result;
    address
}

#[test]
fn generate_svg_returns_payload() {
    let mock = deploy_mock_pprf(111_111_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let path_nft = deploy_path_nft_mock(0_u8, 0_u32, 1_u32, 1_u32, 1_u32);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let svg = dispatcher.generate_svg(path_nft, 1_u256);
    assert(svg.len() > 0_u32, 'svg empty');
}

#[test]
fn metadata_returns_payload() {
    let mock = deploy_mock_pprf(222_222_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let path_nft = deploy_path_nft_mock(1_u8, 0_u32, 1_u32, 1_u32, 1_u32);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let metadata = dispatcher.get_token_metadata(path_nft, 5_u256);
    assert(metadata.len() > 0_u32, 'meta empty');
}

fn contains_bytes(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let hay_len = haystack.len();
    let ned_len = needle.len();
    if ned_len == 0_usize {
        return true;
    }
    if ned_len > hay_len {
        return false;
    }
    let mut i: usize = 0_usize;
    while i + ned_len <= hay_len {
        let mut j: usize = 0_usize;
        let mut matched = true;
        while j < ned_len {
            if haystack.at(i + j).unwrap() != needle.at(j).unwrap() {
                matched = false;
                break;
            }
            j = j + 1_usize;
        }
        if matched {
            return true;
        }
        i = i + 1_usize;
    }
    false
}

fn has_byte(data: @ByteArray, needle: u8) -> bool {
    let len = data.len();
    let mut i: usize = 0_usize;
    while i < len {
        if data.at(i).unwrap() == needle {
            return true;
        }
        i = i + 1_usize;
    }
    false
}

#[test]
fn svg_hides_minted_and_sigma_changes() {
    let mock = deploy_mock_pprf(123_456_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    // No colored strands yet; only ideal
    let path_nft_ideal = deploy_path_nft_mock(0_u8, 0_u32, 2_u32, 2_u32, 2_u32);
    let svg_ideal = dispatcher.generate_svg(path_nft_ideal, 42_u256);
    assert(contains_bytes(@svg_ideal, @"id='ideal-src'"), 'ideal missing');
    assert(!contains_bytes(@svg_ideal, @"segments-"), 'unexpected segments');
    assert(!contains_bytes(@svg_ideal, @"stdDeviation='"), 'sigma should be absent');

    // Stage 3: all movements manifest in fixed order.
    let path_nft_full = deploy_path_nft_mock(3_u8, 0_u32, 2_u32, 2_u32, 2_u32);
    let svg_layers = dispatcher.generate_svg(path_nft_full, 42_u256);
    assert(contains_bytes(@svg_layers, @"id='ideal-src'"), 'ideal missing layered');
    assert(contains_bytes(@svg_layers, @"id='segments-thought'"), 'thought missing');
    assert(contains_bytes(@svg_layers, @"id='segments-will'"), 'will missing');
    assert(contains_bytes(@svg_layers, @"id='segments-awa'"), 'awa missing');
    assert(contains_bytes(@svg_layers, @"stdDeviation='"), 'sigma missing');
}

#[test]
fn metadata_reflects_flags() {
    let mock = deploy_mock_pprf(7_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let path_nft = deploy_path_nft_mock(2_u8, 1_u32, 2_u32, 2_u32, 2_u32);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let metadata = dispatcher.get_token_metadata(path_nft, 9_u256);
    assert(contains_bytes(@metadata, @"\"Stage\",\"value\":\"AWA\""), 'stage');
    assert(contains_bytes(@metadata, @"\"THOUGHT\",\"value\":\"Manifested(2/2)\""), 'thought status');
    assert(contains_bytes(@metadata, @"\"WILL\",\"value\":\"Manifested(2/2)\""), 'will status');
    assert(contains_bytes(@metadata, @"\"AWA\",\"value\":\"Manifested(1/2)\""), 'awa status');
    assert(contains_bytes(@metadata, @"\"Breath\",\"value\":"), 'breath present');
}

#[test]
fn svg_has_no_newlines() {
    let mock = deploy_mock_pprf(1_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let path_nft = deploy_path_nft_mock(1_u8, 0_u32, 1_u32, 1_u32, 1_u32);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let svg = dispatcher.generate_svg(path_nft, 3_u256);
    assert(!has_byte(@svg, 10_u8), 'contains newline');
    assert(!has_byte(@svg, 13_u8), 'contains carriage');
}

#[test]
fn data_uri_is_percent_encoded() {
    let mock = deploy_mock_pprf(2_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let path_nft = deploy_path_nft_mock(0_u8, 0_u32, 1_u32, 1_u32, 1_u32);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let uri = dispatcher.generate_svg_data_uri(path_nft, 4_u256);
    assert(contains_bytes(@uri, @"data:image/svg+xml;charset=UTF-8,"), 'missing prefix');
    assert(contains_bytes(@uri, @"%3Csvg"), 'missing encoded svg tag');
    assert(contains_bytes(@uri, @"%23ideal-src"), 'missing encoded hash');
    assert(!contains_bytes(@uri, @"<svg"), 'raw svg present');
}
