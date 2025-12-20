use core::array::{ArrayTrait, Span};
use core::result::ResultTrait;
use core::option::OptionTrait;
use core::byte_array::ByteArrayTrait;
use path_look::path_look::{IPathLookDispatcher, IPathLookDispatcherTrait};
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;
use step_curve::StepCurve::StepCurve;

#[starknet::contract]
mod StepCurveMock {
    use super::StepCurve::IStepCurve;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockImpl of IStepCurve<ContractState> {
        fn d_from_nodes(
            self: @ContractState, nodes: Span<super::StepCurve::Point>, handle_scale: u32,
        ) -> ByteArray {
            let _ = nodes;
            let _ = handle_scale;
            let mut path: ByteArray = Default::default();
            path.append(@"M 0 0");
            path
        }

        fn d_from_flattened_xy(
            self: @ContractState, nodes_xy: Span<felt252>, handle_scale: u32,
        ) -> ByteArray {
            let _ = nodes_xy;
            let _ = handle_scale;
            let mut path: ByteArray = Default::default();
            path.append(@"M 0 0");
            path
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
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let svg = dispatcher.generate_svg(1, 0, 0, 0);
    assert(svg.len() > 0_u32, 'svg empty');
}

#[test]
fn metadata_returns_payload() {
    let mock = deploy_mock_pprf(222_222_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let metadata = dispatcher.get_token_metadata(5, 1, 0, 0);
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
    let svg_ideal = dispatcher.generate_svg(42, 0, 0, 0);
    assert(contains_bytes(@svg_ideal, @"id='ideal-src'"), 'ideal missing');
    assert(!contains_bytes(@svg_ideal, @"strand-"), 'unexpected strand');
    assert(!contains_bytes(@svg_ideal, @"stdDeviation='"), 'sigma should be absent');

    // Mixed ranks: will=1 (bottom), thought=2, awa=3 (top)
    let svg_layers = dispatcher.generate_svg(42, 2, 1, 3);
    assert(contains_bytes(@svg_layers, @"id='ideal-src'"), 'ideal missing layered');
    assert(contains_bytes(@svg_layers, @"id='strand-thought'"), 'strand1 missing');
    assert(contains_bytes(@svg_layers, @"id='strand-will'"), 'strand2 missing');
    assert(contains_bytes(@svg_layers, @"id='strand-awa'"), 'strand3 missing');
    assert(contains_bytes(@svg_layers, @"stdDeviation='"), 'sigma missing');
}

#[test]
fn metadata_reflects_flags() {
    let mock = deploy_mock_pprf(7_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let metadata = dispatcher.get_token_metadata(9, 2, 0, 1);
    assert(contains_bytes(@metadata, @"\"Movement Order\",\"value\":\"AWA->THOUGHT->"), 'movement order');
    assert(contains_bytes(@metadata, @"\"THOUGHT\",\"value\":\"Manifested\""), 'thought status');
    assert(contains_bytes(@metadata, @"\"WILL\",\"value\":\"Latent\""), 'will status');
    assert(contains_bytes(@metadata, @"\"AWA\",\"value\":\"Manifested\""), 'awa status');
    assert(contains_bytes(@metadata, @"\"Breath\",\"value\":"), 'breath present');
}

#[test]
fn svg_has_no_newlines() {
    let mock = deploy_mock_pprf(1_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let svg = dispatcher.generate_svg(3, 1, 0, 0);
    assert(!has_byte(@svg, 10_u8), 'contains newline');
    assert(!has_byte(@svg, 13_u8), 'contains carriage');
}

#[test]
fn data_uri_is_percent_encoded() {
    let mock = deploy_mock_pprf(2_u32);
    let step_curve = deploy_step_curve();
    let contract = deploy_path_look(mock, step_curve);
    let dispatcher = IPathLookDispatcher { contract_address: contract };

    let uri = dispatcher.generate_svg_data_uri(4, 0, 1, 0);
    assert(contains_bytes(@uri, @"data:image/svg+xml;charset=UTF-8,"), 'missing prefix');
    assert(contains_bytes(@uri, @"%3Csvg"), 'missing encoded svg tag');
    assert(contains_bytes(@uri, @"%23lightUp"), 'missing encoded hash');
    assert(!contains_bytes(@uri, @"<svg"), 'raw svg present');
}
