#[starknet::contract]
pub mod PathLook {
    use core::array::ArrayTrait;
    use core::byte_array::ByteArrayTrait;
    use core::pedersen::pedersen;
    use core::serde::Serde;
    use core::to_byte_array::AppendFormattedToByteArray;
    use core::traits::TryInto;
    use core::zeroable::NonZero;
    use path_look::rng;
    use super::{IPathNFTStageDispatcher, IPathNFTStageDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use step_curve::glyph_interface::{IGlyphDispatcher, IGlyphDispatcherTrait};

    const LABEL_STEP_COUNT: felt252 = 'STEP';
    const LABEL_SHARPNESS: felt252 = 'SHRP';
    const LABEL_PADDING: felt252 = 'PADD';
    const LABEL_TARGET_X: felt252 = 'TRGX';
    const LABEL_TARGET_Y: felt252 = 'TRGY';
    const LABEL_THOUGHT_DX: felt252 = 'THDX';
    const LABEL_THOUGHT_DY: felt252 = 'THDY';
    const LABEL_WILL_DX: felt252 = 'WIDX';
    const LABEL_WILL_DY: felt252 = 'WIDY';
    const LABEL_AWA_DX: felt252 = 'AWDX';
    const LABEL_AWA_DY: felt252 = 'AWDY';

    #[storage]
    struct Storage {
        pprf_address: ContractAddress,
        step_curve_address: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, pprf_address: ContractAddress, step_curve_address: ContractAddress,
    ) {
        self.pprf_address.write(pprf_address);
        self.step_curve_address.write(step_curve_address);
    }

    #[derive(Copy, Drop)]
    struct Step {
        x: i128,
        y: i128,
    }

    #[abi(embed_v0)]
    impl PathLookImpl of super::IPathLook<ContractState> {
        fn generate_svg(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            self._generate_svg(path_nft, token_id)
        }

        fn generate_svg_data_uri(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            self._generate_svg_data_uri(path_nft, token_id)
        }

        fn get_token_metadata(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            self._get_token_metadata(path_nft, token_id)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _generate_svg(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            const WIDTH: u32 = 1024;
            const HEIGHT: u32 = 1024;

            let stage = self._stage_from_path_nft(path_nft, token_id);
            let stage_minted = self._stage_minted_from_path_nft(path_nft, token_id);
            let quota_thought = self._movement_quota_from_path_nft(path_nft, 'THOUGHT');
            let quota_will = self._movement_quota_from_path_nft(path_nft, 'WILL');
            let quota_awa = self._movement_quota_from_path_nft(path_nft, 'AWA');
            let (thought_minted, will_minted, awa_minted) = self
                ._progress_counts(stage, stage_minted, quota_thought, quota_will, quota_awa);
            let rng_seed = self._token_seed(token_id);

            let step_number = self._random_range(rng_seed, LABEL_STEP_COUNT, 0, 1, 50);
            let sharpness = self._random_range(rng_seed, LABEL_SHARPNESS, 0, 1, 20);
            let stroke_w = self._max_u32(1, self._round_div(100, step_number));

            let (padding, _) = self._compute_padding(rng_seed, WIDTH);
            let targets = self._find_targets(rng_seed, WIDTH, HEIGHT, step_number, padding);
            let start = Step { x: 0_i128, y: (HEIGHT / 2_u32).into() };
            let end = Step { x: WIDTH.into(), y: (HEIGHT / 2_u32).into() };

            let mut ideal_steps: Array<Step> = array![];
            ideal_steps.append(start);
            let mut t_i: usize = 0_usize;
            while t_i < targets.len() {
                let t = *targets.at(t_i);
                ideal_steps.append(Step { x: t.x, y: t.y });
                t_i = t_i + 1_usize;
            }
            ideal_steps.append(end);
            let raw_ideal_path = self._curve_d(@ideal_steps, sharpness);
            let ideal_path = self._strip_newlines(@raw_ideal_path);
            let ideal_stroke_w = 1_u32;

            let thought_core = self._find_steps(
                rng_seed, @targets, WIDTH, HEIGHT, LABEL_THOUGHT_DX, LABEL_THOUGHT_DY,
            );
            let mut thought_nodes: Array<Step> = array![];
            thought_nodes.append(start);
            let mut ti: usize = 0_usize;
            while ti < thought_core.len() {
                thought_nodes.append(*thought_core.at(ti));
                ti = ti + 1_usize;
            }
            thought_nodes.append(end);

            let will_core = self._find_steps(
                rng_seed, @targets, WIDTH, HEIGHT, LABEL_WILL_DX, LABEL_WILL_DY,
            );
            let mut will_nodes: Array<Step> = array![];
            will_nodes.append(start);
            let mut wi_i: usize = 0_usize;
            while wi_i < will_core.len() {
                will_nodes.append(*will_core.at(wi_i));
                wi_i = wi_i + 1_usize;
            }
            will_nodes.append(end);

            let awa_core = self._find_steps(
                rng_seed, @targets, WIDTH, HEIGHT, LABEL_AWA_DX, LABEL_AWA_DY,
            );
            let mut awa_nodes: Array<Step> = array![];
            awa_nodes.append(start);
            let mut aw_i: usize = 0_usize;
            while aw_i < awa_core.len() {
                awa_nodes.append(*awa_core.at(aw_i));
                aw_i = aw_i + 1_usize;
            }
            awa_nodes.append(end);

            let any_minted = thought_minted > 0_u32 || will_minted > 0_u32 || awa_minted > 0_u32;
            let sigma = if any_minted {
                self._random_range(rng_seed, LABEL_SHARPNESS, 1, 3, 30)
            } else {
                0_u32
            };

            let mut defs: ByteArray = Default::default();
            defs.append(@"<g id='ideal-src'><path id='path_ideal' d='");
            defs.append(@ideal_path);
            defs.append(@"' stroke='rgb(255,255,255)' stroke-width='");
            defs.append(@self._u32_to_string(ideal_stroke_w));
            defs.append(@"' fill='none' stroke-linecap='round' stroke-linejoin='round' /></g>");

            if any_minted {
                defs.append(
                    @"<filter id='lightUp' filterUnits='userSpaceOnUse' x='-100%' y='-100%' width='200%' height='200%' color-interpolation-filters='sRGB'>",
                );
                defs.append(@"<feGaussianBlur in='SourceGraphic' stdDeviation='");
                defs.append(@self._u32_to_string(sigma));
                defs.append(@"' result='blur'></feGaussianBlur>");
                defs.append(@"<feMerge><feMergeNode in='blur'/><feMergeNode in='blur'/><feMergeNode in='SourceGraphic'/></feMerge></filter>");
            }

            let mut svg: ByteArray = Default::default();
            svg.append(@"<svg width='");
            svg.append(@self._u32_to_string(WIDTH));
            svg.append(@"' height='");
            svg.append(@self._u32_to_string(HEIGHT));
            svg.append(@"' viewBox='0 0 ");
            svg.append(@self._u32_to_string(WIDTH));
            svg.append(@" ");
            svg.append(@self._u32_to_string(HEIGHT));
            svg.append(@"' xmlns='http://www.w3.org/2000/svg' style='background:#000; isolation:isolate'>");
            svg.append(@"<defs>");
            svg.append(@defs);
            svg.append(@"</defs>");
            svg.append(@"<rect width='1024' height='1024' fill='#000'/>");
            svg.append(@"<g>");
            // Draw ideal first so it stays beneath any minted strands.
            svg.append(@"<use href='#ideal-src' style='mix-blend-mode:lighten;'/>");
            if any_minted {
                if thought_minted > 0_u32 {
                    let raw_thought_path = self._curve_d(@thought_nodes, sharpness);
                    let thought_path = self._strip_newlines(@raw_thought_path);
                    let mut thought_label: ByteArray = Default::default();
                    thought_label.append(@"thought");
                    self._append_segments(
                        ref svg,
                        @thought_label,
                        0_u32,
                        0_u32,
                        255_u32,
                        stroke_w,
                        @thought_path,
                        quota_thought,
                        thought_minted,
                    );
                }

                if will_minted > 0_u32 {
                    let raw_will_path = self._curve_d(@will_nodes, sharpness);
                    let will_path = self._strip_newlines(@raw_will_path);
                    let mut will_label: ByteArray = Default::default();
                    will_label.append(@"will");
                    self._append_segments(
                        ref svg,
                        @will_label,
                        255_u32,
                        0_u32,
                        0_u32,
                        stroke_w,
                        @will_path,
                        quota_will,
                        will_minted,
                    );
                }

                if awa_minted > 0_u32 {
                    let raw_awa_path = self._curve_d(@awa_nodes, sharpness);
                    let awa_path = self._strip_newlines(@raw_awa_path);
                    let mut awa_label: ByteArray = Default::default();
                    awa_label.append(@"awa");
                    self._append_segments(
                        ref svg,
                        @awa_label,
                        0_u32,
                        255_u32,
                        0_u32,
                        stroke_w,
                        @awa_path,
                        quota_awa,
                        awa_minted,
                    );
                }
            }
            svg.append(@"</g></svg>");

            svg
        }

        fn _generate_svg_data_uri(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            let svg = self._generate_svg(path_nft, token_id);
            let encoded = self._percent_encode(@svg);
            let mut data_uri: ByteArray = Default::default();
            data_uri.append(@"data:image/svg+xml;charset=UTF-8,");
            data_uri.append(@encoded);
            data_uri
        }

        fn _get_token_metadata(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            let stage = self._stage_from_path_nft(path_nft, token_id);
            let stage_minted = self._stage_minted_from_path_nft(path_nft, token_id);
            let quota_thought = self._movement_quota_from_path_nft(path_nft, 'THOUGHT');
            let quota_will = self._movement_quota_from_path_nft(path_nft, 'WILL');
            let quota_awa = self._movement_quota_from_path_nft(path_nft, 'AWA');
            let (thought_minted, will_minted, awa_minted) = self
                ._progress_counts(stage, stage_minted, quota_thought, quota_will, quota_awa);
            let rng_seed = self._token_seed(token_id);
            let token_id_str = self._u256_to_string(token_id);

            const WIDTH: u32 = 1024;
            const HEIGHT: u32 = 1024;

            let step_number = self._random_range(rng_seed, LABEL_STEP_COUNT, 0, 1, 50);
            let (padding, pad_pct) = self._compute_padding(rng_seed, WIDTH);
            let _targets_ignore = self._find_targets(rng_seed, WIDTH, HEIGHT, step_number, padding);
            let stroke_w = self._max_u32(1, self._round_div(100, step_number));
            let sharpness = self._random_range(rng_seed, LABEL_SHARPNESS, 0, 1, 20);
            let any_minted = thought_minted > 0_u32 || will_minted > 0_u32 || awa_minted > 0_u32;
            let sigma_val = if any_minted {
                self._random_range(rng_seed, LABEL_SHARPNESS, 1, 3, 30)
            } else {
                0_u32
            };
            let mut metadata: ByteArray = Default::default();
            let data_uri = self._generate_svg_data_uri(path_nft, token_id);

            let description: ByteArray = "**segments** sets the cadence; **stroke-width** sets how loudly the strand speaks.  **sharpness** controls how tightly the curve pulls between waypoints.  **padding-pct** sets the margin of the field.  The **Ideal Path** is the reference trajectory drawn first, always beneath.  The token gains its living strands through three **Movements**: THOUGHT, WILL, and AWA.  **Stage** marks the current progression, while **THOUGHT**, **WILL**, and **AWA** record progress as Minted(x/N).  When the first Movement appears, **sigma** awakens as one shared atmosphere across every living strand.";

            metadata.append(@"{\"name\":\"PATH #");
            metadata.append(@token_id_str);
            metadata.append(@"\",\"description\":\"");
            metadata.append(@description);
            metadata.append(@"\",\"image\":\"");
            metadata.append(@data_uri);
            metadata.append(@"\",\"external_url\":\"https://path.design/token/");
            metadata.append(@token_id_str);
            metadata.append(@"\",\"attributes\":[");

            metadata.append(@"{\"trait_type\":\"segments\",\"value\":");
            metadata.append(@self._u32_to_string(step_number));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"stroke-width\",\"value\":");
            metadata.append(@self._u32_to_string(stroke_w));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"sharpness\",\"value\":");
            metadata.append(@self._u32_to_string(sharpness));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"padding-pct\",\"value\":");
            metadata.append(@self._u32_to_string(pad_pct));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"sigma\",\"value\":");
            if sigma_val == 0_u32 {
                metadata.append(@"\"Dormant\"");
            } else {
                metadata.append(@self._u32_to_string(sigma_val));
            }
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"Stage\",\"value\":\"");
            metadata.append(@self._stage_label(stage));
            metadata.append(@"\"}");
            metadata.append(@",");

            metadata.append(@"{\"trait_type\":\"THOUGHT\",\"value\":\"");
            metadata.append(@self._manifest_progress(thought_minted, quota_thought));
            metadata.append(@"\"},");

            metadata.append(@"{\"trait_type\":\"WILL\",\"value\":\"");
            metadata.append(@self._manifest_progress(will_minted, quota_will));
            metadata.append(@"\"},");

            metadata.append(@"{\"trait_type\":\"AWA\",\"value\":\"");
            metadata.append(@self._manifest_progress(awa_minted, quota_awa));
            metadata.append(@"\"}");

            metadata.append(@"]");

            metadata.append(@"}");

            metadata
        }

        fn _token_seed(self: @ContractState, token_id: u256) -> felt252 {
            let low: felt252 = token_id.low.into();
            let high: felt252 = token_id.high.into();
            pedersen(low, high)
        }

        fn _stage_from_path_nft(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> u8 {
            let dispatcher = IPathNFTStageDispatcher { contract_address: path_nft };
            dispatcher.get_stage(token_id)
        }

        fn _stage_minted_from_path_nft(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> u32 {
            let dispatcher = IPathNFTStageDispatcher { contract_address: path_nft };
            dispatcher.get_stage_minted(token_id)
        }

        fn _movement_quota_from_path_nft(
            self: @ContractState, path_nft: ContractAddress, movement: felt252,
        ) -> u32 {
            let dispatcher = IPathNFTStageDispatcher { contract_address: path_nft };
            dispatcher.get_movement_quota(movement)
        }

        fn _progress_counts(
            self: @ContractState,
            stage: u8,
            stage_minted: u32,
            quota_thought: u32,
            quota_will: u32,
            quota_awa: u32,
        ) -> (u32, u32, u32) {
            let thought = if stage > 0_u8 { quota_thought } else { stage_minted };
            let will = if stage > 1_u8 {
                quota_will
            } else if stage == 1_u8 {
                stage_minted
            } else {
                0_u32
            };
            let awa = if stage > 2_u8 {
                quota_awa
            } else if stage == 2_u8 {
                stage_minted
            } else {
                0_u32
            };
            (thought, will, awa)
        }

        fn _stage_label(self: @ContractState, stage: u8) -> ByteArray {
            match stage {
                0_u8 => "THOUGHT",
                1_u8 => "WILL",
                2_u8 => "AWA",
                3_u8 => "COMPLETE",
                _ => "UNKNOWN",
            }
        }

        fn _compute_padding(self: @ContractState, seed: felt252, width: u32) -> (u32, u32) {
            // Margin is 20%–40% of canvas (tunable percentages).
            const PAD_MIN_PCT: u32 = 20;
            const PAD_MAX_PCT: u32 = 40;
            let pad_min = (width * PAD_MIN_PCT) / 100_u32;
            let pad_max = (width * PAD_MAX_PCT) / 100_u32;
            let padding = self._random_range(seed, LABEL_PADDING, 0, pad_min, pad_max);
            let pad_pct = self._round_div(padding * 100_u32, width);
            (padding, pad_pct)
        }

        fn _random_range(
            self: @ContractState,
            token_id: felt252,
            label: felt252,
            occurrence: u32,
            min: u32,
            max: u32,
        ) -> u32 {
            let address = self.pprf_address.read();
            rng::pseudo_random_range(address, token_id, label, occurrence, min, max)
        }

        fn _max_u32(self: @ContractState, a: u32, b: u32) -> u32 {
            if a > b {
                a
            } else {
                b
            }
        }

        fn _round_div(self: @ContractState, numerator: u32, denominator: u32) -> u32 {
            if denominator == 0_u32 {
                return numerator;
            }
            (numerator + denominator / 2_u32) / denominator
        }

        fn _find_targets(
            self: @ContractState,
            token_id: felt252,
            width: u32,
            height: u32,
            count: u32,
            padding: u32,
        ) -> Array<Step> {
            let max_x: i128 = (width - padding).into();
            let max_y: i128 = (height - padding).into();
            let min_x: i128 = padding.into();
            let min_y: i128 = padding.into();

            let mut targets: Array<Step> = array![];
            let mut i: u32 = 0_u32;
            while i < count {
                let x = self._random_range(token_id, LABEL_TARGET_X, i, min_x.try_into().unwrap(), max_x.try_into().unwrap());
                let y = self._random_range(token_id, LABEL_TARGET_Y, i, min_y.try_into().unwrap(), max_y.try_into().unwrap());
                targets.append(Step { x: x.into(), y: y.into() });
                i = i + 1;
            }

            targets
        }

        fn _find_steps(
            self: @ContractState,
            token_id: felt252,
            targets: @Array<Step>,
            max_x: u32,
            max_y: u32,
            dx_label: felt252,
            dy_label: felt252,
        ) -> Array<Step> {
            // Jitter caps are 1% of the canvas size (tunable).
            const JITTER_X_PCT: u32 = 1;
            const JITTER_Y_PCT: u32 = 1;
            let max_dx_cap: u32 = (max_x * JITTER_X_PCT) / 100_u32;
            let max_dy_cap: u32 = (max_y * JITTER_Y_PCT) / 100_u32;
            let max_dx = self._random_range(token_id, LABEL_PADDING, 0, 0_u32, max_dx_cap);
            let max_dy = self._random_range(token_id, LABEL_PADDING, 1, 0_u32, max_dy_cap);
            let max_x_i128: i128 = max_x.into();
            let max_y_i128: i128 = max_y.into();

            let mut steps: Array<Step> = array![];
            let mut i: usize = 0_usize;
            let len = targets.len();
            while i < len {
                let target = *targets.at(i);
                let occurrence: u32 = i.try_into().unwrap();
                let dx = self._random_range(token_id, dx_label, occurrence, 0_u32, max_dx);
                let dy = self._random_range(token_id, dy_label, occurrence, 0_u32, max_dy);

                let x = self._clamp_i128(target.x + dx.into(), 0_i128, max_x_i128);
                let y = self._clamp_i128(target.y + dy.into(), 0_i128, max_y_i128);

                steps.append(Step { x, y });

                i = i + 1_usize;
            }

            steps
        }

        fn _clamp_i128(
            self: @ContractState, value: i128, min_value: i128, max_value: i128,
        ) -> i128 {
            let mut result = value;
            if result < min_value {
                result = min_value;
            }
            if result > max_value {
                result = max_value;
            }
            result
        }

        fn _curve_d(
            self: @ContractState, steps: @Array<Step>, sharpness: u32,
        ) -> ByteArray {
            let addr = self.step_curve_address.read();
            let mut params: Array<felt252> = array![];
            params.append(sharpness.into());
            let mut i: usize = 0_usize;
            while i < steps.len() {
                let s = *steps.at(i);
                let x: felt252 = s.x.try_into().unwrap();
                let y: felt252 = s.y.try_into().unwrap();
                params.append(x);
                params.append(y);
                i = i + 1_usize;
            }
            let dispatcher = IGlyphDispatcher { contract_address: addr };
            let rendered = dispatcher.render(params.span());
            let mut rendered_span = rendered.span();
            Serde::deserialize(ref rendered_span).unwrap()
        }

        fn _append_segments(
            self: @ContractState,
            ref svg: ByteArray,
            label: @ByteArray,
            r: u32,
            g: u32,
            b: u32,
            stroke_w: u32,
            path_d: @ByteArray,
            quota: u32,
            minted: u32,
        ) {
            if minted == 0_u32 || path_d.len() == 0_usize {
                return;
            }

            let segments = if quota == 0_u32 { 1_u32 } else { quota };
            let mut filled: u32 = minted;
            if filled > segments {
                filled = segments;
            }
            if filled == 0_u32 {
                return;
            }

            svg.append(@"<g id='segments-");
            svg.append(label);
            svg.append(@"' filter='url(#lightUp)' style='mix-blend-mode:lighten;'>");

            let mut i: u32 = 0_u32;
            while i < filled {
                let idx: u32 = i;
                let offset: i128 = 0_i128 - i.into();

                svg.append(@"<path id='segment-");
                svg.append(label);
                svg.append(@"-");
                svg.append(@self._u32_to_string(idx));
                svg.append(@"' d='");
                svg.append(path_d);
                svg.append(@"' stroke='rgb(");
                svg.append(@self._u32_to_string(r));
                svg.append(@",");
                svg.append(@self._u32_to_string(g));
                svg.append(@",");
                svg.append(@self._u32_to_string(b));
                svg.append(@"' stroke-width='");
                svg.append(@self._u32_to_string(stroke_w));
                svg.append(@"' fill='none' stroke-linecap='round' stroke-linejoin='round' pathLength='");
                svg.append(@self._u32_to_string(segments));
                svg.append(@"'");
                if segments > 1_u32 {
                    svg.append(@" stroke-dasharray='1 ");
                    svg.append(@self._u32_to_string(segments - 1_u32));
                    svg.append(@"' stroke-dashoffset='");
                    svg.append(@self._i128_to_string(offset));
                    svg.append(@"'");
                }
                svg.append(@"/>");

                i = i + 1_u32;
            }

            svg.append(@"</g>");
        }


        fn _u128_to_string(self: @ContractState, value: u128) -> ByteArray {
            if value == 0_u128 {
                return "0";
            }

            let mut num = value;
            let mut digits: Array<u8> = array![];

            while num != 0_u128 {
                let digit: u8 = (num % 10_u128).try_into().unwrap();
                digits.append(digit);
                num = num / 10_u128;
            }

            let mut result: ByteArray = Default::default();
            let mut i = digits.len();
            while i > 0_usize {
                i = i - 1_usize;
                let digit = *digits.at(i);
                let digit_char = digit + 48_u8;
                result.append_byte(digit_char);
            }

            result
        }

        fn _i128_to_string(self: @ContractState, value: i128) -> ByteArray {
            if value >= 0_i128 {
                let unsigned: u128 = value.try_into().unwrap();
                return self._u128_to_string(unsigned);
            }

            let positive: u128 = (0_i128 - value).try_into().unwrap();
            let mut result: ByteArray = Default::default();
            result.append(@"-");
            let digits = self._u128_to_string(positive);
            result.append(@digits);
            result
        }

        fn _u256_to_string(self: @ContractState, value: u256) -> ByteArray {
            let base: NonZero<u256> = 10_u256.try_into().unwrap();
            let mut out: ByteArray = Default::default();
            value.append_formatted_to_byte_array(ref out, base);
            out
        }

        fn _u32_to_string(self: @ContractState, value: u32) -> ByteArray {
            if value == 0_u32 {
                return "0";
            }

            let mut num = value;
            let mut digits: Array<u8> = array![];

            while num != 0_u32 {
                let digit: u8 = (num % 10_u32).try_into().unwrap();
                digits.append(digit);
                num = num / 10_u32;
            }

            let mut result: ByteArray = Default::default();
            let mut i = digits.len();
            while i > 0_usize {
                i = i - 1_usize;
                let digit = *digits.at(i);
                let digit_char = digit + 48_u8;
                result.append_byte(digit_char);
            }

            result
        }

        fn _manifest_progress(self: @ContractState, minted: u32, quota: u32) -> ByteArray {
            let mut out: ByteArray = Default::default();
            out.append(@"Minted(");
            out.append(@self._u32_to_string(minted));
            out.append(@"/");
            out.append(@self._u32_to_string(quota));
            out.append(@")");
            out
        }

        fn _strip_newlines(self: @ContractState, svg: @ByteArray) -> ByteArray {
            let mut out: ByteArray = Default::default();
            let mut i: usize = 0_usize;
            let len = svg.len();
            while i < len {
                let b = svg.at(i).unwrap();
                if b == 10_u8 || b == 13_u8 {
                    out.append_byte(32_u8);
                } else {
                    out.append_byte(b);
                }
                i = i + 1_usize;
            }
            out
        }

        fn _is_unreserved(self: @ContractState, b: u8) -> bool {
            (b >= 48_u8 && b <= 57_u8)
                || (b >= 65_u8 && b <= 90_u8)
                || (b >= 97_u8 && b <= 122_u8)
                || b == 45_u8
                || b == 46_u8
                || b == 95_u8
                || b == 126_u8
        }

        fn _hex_nibble(self: @ContractState, n: u8) -> u8 {
            if n < 10_u8 {
                48_u8 + n
            } else {
                55_u8 + n
            }
        }

        fn _append_pct_encoded(self: @ContractState, ref out: ByteArray, b: u8) {
            out.append(@"%");
            let hi = b / 16_u8;
            let lo = b % 16_u8;
            out.append_byte(self._hex_nibble(hi));
            out.append_byte(self._hex_nibble(lo));
        }

        fn _percent_encode(self: @ContractState, svg: @ByteArray) -> ByteArray {
            let mut out: ByteArray = Default::default();
            let mut i: usize = 0_usize;
            let len = svg.len();
            while i < len {
                let b = svg.at(i).unwrap();
                if self._is_unreserved(b) {
                    out.append_byte(b);
                } else {
                    self._append_pct_encoded(ref out, b);
                }
                i = i + 1_usize;
            }
            out
        }

    }
}

use core::integer::u256;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IPathNFTStage<TContractState> {
    fn get_stage(self: @TContractState, token_id: u256) -> u8;
    fn get_stage_minted(self: @TContractState, token_id: u256) -> u32;
    fn get_movement_quota(self: @TContractState, movement: felt252) -> u32;
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
