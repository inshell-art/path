#[starknet::contract]
pub mod PathLook {
    use core::array::ArrayTrait;
    use core::byte_array::ByteArrayTrait;
    use core::option::{Option, OptionTrait};
    use path_look::rng;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use step_curve::StepCurve::StepCurve::{IStepCurveDispatcher, IStepCurveDispatcherTrait, Point};

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
    const RANK_SEED_T: felt252 = 100_u32.into();
    const RANK_SEED_W: felt252 = 10_u32.into();
    const RANK_SEED_A: felt252 = 1_u32.into();

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

    #[derive(Drop)]
    struct Strand {
        rank: u8,
        path: ByteArray,
        label: ByteArray,
        r: felt252,
        g: felt252,
        b: felt252,
    }

    #[abi(embed_v0)]
    impl PathLookImpl of super::IPathLook<ContractState> {
        fn generate_svg(
            self: @ContractState, token_id: felt252, thought_rank: u8, will_rank: u8, awa_rank: u8,
        ) -> ByteArray {
            const WIDTH: u32 = 1024;
            const HEIGHT: u32 = 1024;

            let rng_seed = self._rng_seed(token_id, thought_rank, will_rank, awa_rank);

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

            let thought_core =
                self._find_steps(rng_seed, @targets, WIDTH, HEIGHT, LABEL_THOUGHT_DX, LABEL_THOUGHT_DY);
            let mut thought_nodes: Array<Step> = array![];
            thought_nodes.append(start);
            let mut ti: usize = 0_usize;
            while ti < thought_core.len() {
                thought_nodes.append(*thought_core.at(ti));
                ti = ti + 1_usize;
            }
            thought_nodes.append(end);
            let raw_thought_path = self._curve_d(@thought_nodes, sharpness);
            let thought_path = self._strip_newlines(@raw_thought_path);

            let will_core =
                self._find_steps(rng_seed, @targets, WIDTH, HEIGHT, LABEL_WILL_DX, LABEL_WILL_DY);
            let mut will_nodes: Array<Step> = array![];
            will_nodes.append(start);
            let mut wi_i: usize = 0_usize;
            while wi_i < will_core.len() {
                will_nodes.append(*will_core.at(wi_i));
                wi_i = wi_i + 1_usize;
            }
            will_nodes.append(end);
            let raw_will_path = self._curve_d(@will_nodes, sharpness);
            let will_path = self._strip_newlines(@raw_will_path);

            let awa_core =
                self._find_steps(rng_seed, @targets, WIDTH, HEIGHT, LABEL_AWA_DX, LABEL_AWA_DY);
            let mut awa_nodes: Array<Step> = array![];
            awa_nodes.append(start);
            let mut aw_i: usize = 0_usize;
            while aw_i < awa_core.len() {
                awa_nodes.append(*awa_core.at(aw_i));
                aw_i = aw_i + 1_usize;
            }
            awa_nodes.append(end);
            let raw_awa_path = self._curve_d(@awa_nodes, sharpness);
            let awa_path = self._strip_newlines(@raw_awa_path);

            let mut minted: Array<Strand> = array![];
            let mut thought_opt = Option::Some(thought_path);
            let mut will_opt = Option::Some(will_path);
            let mut awa_opt = Option::Some(awa_path);
            let mut r_loop: u8 = 1_u8;
            while r_loop <= 3_u8 {
                if thought_rank == r_loop {
                    if let Option::Some(path_val) = thought_opt {
                        let mut label: ByteArray = Default::default();
                        label.append(@"thought");
                        minted.append(Strand { rank: thought_rank, path: path_val, label, r: 0, g: 0, b: 255 });
                    }
                    thought_opt = Option::None;
                }
                if will_rank == r_loop {
                    if let Option::Some(path_val) = will_opt {
                        let mut label: ByteArray = Default::default();
                        label.append(@"will");
                        minted.append(Strand { rank: will_rank, path: path_val, label, r: 255, g: 0, b: 0 });
                    }
                    will_opt = Option::None;
                }
                if awa_rank == r_loop {
                    if let Option::Some(path_val) = awa_opt {
                        let mut label: ByteArray = Default::default();
                        label.append(@"awa");
                        minted.append(Strand { rank: awa_rank, path: path_val, label, r: 0, g: 255, b: 0 });
                    }
                    awa_opt = Option::None;
                }
                r_loop = r_loop + 1_u8;
            }

            let any_minted = minted.len() > 0_usize;
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
                let mut k: usize = 0_usize;
                while k < minted.len() {
                    let strand = minted.at(k);
                    let path = strand.path;
                    let id = strand.label;
                    let r: u32 = (*strand.r).try_into().unwrap();
                    let g: u32 = (*strand.g).try_into().unwrap();
                    let b: u32 = (*strand.b).try_into().unwrap();
                    defs.append(@"<g id='strand-");
                    defs.append(id);
                    defs.append(@"' filter='url(#lightUp)'><path d='");
                    defs.append(path);
                    defs.append(@"' stroke='rgb(");
                    defs.append(@self._u32_to_string(r));
                    defs.append(@",");
                    defs.append(@self._u32_to_string(g));
                    defs.append(@",");
                    defs.append(@self._u32_to_string(b));
                    defs.append(@"' stroke-width='");
                    defs.append(@self._u32_to_string(stroke_w));
                    defs.append(@"' fill='none' stroke-linecap='round' stroke-linejoin='round' /></g>");
                    k = k + 1_usize;
                }

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
                let mut u: usize = 0_usize;
                while u < minted.len() {
                    let id = minted.at(u).label;
                    svg.append(@"<use href='#strand-");
                    svg.append(id);
                    svg.append(@"' style='mix-blend-mode:lighten;'/>");
                    u = u + 1_usize;
                }
            }
            svg.append(@"</g></svg>");

            svg
        }

        fn generate_svg_data_uri(
            self: @ContractState,
            token_id: felt252,
            thought_rank: u8,
            will_rank: u8,
            awa_rank: u8,
        ) -> ByteArray {
            let svg = self.generate_svg(token_id, thought_rank, will_rank, awa_rank);
            let encoded = self._percent_encode(@svg);
            let mut data_uri: ByteArray = Default::default();
            data_uri.append(@"data:image/svg+xml;charset=UTF-8,");
            data_uri.append(@encoded);
            data_uri
        }

        fn get_token_metadata(
            self: @ContractState,
            token_id: felt252,
            thought_rank: u8,
            will_rank: u8,
            awa_rank: u8,
        ) -> ByteArray {
            let rng_seed = self._rng_seed(token_id, thought_rank, will_rank, awa_rank);
            let token_id_str = self._felt_to_string(token_id);
            let thought_minted = thought_rank != 0_u8;
            let will_minted = will_rank != 0_u8;
            let awa_minted = awa_rank != 0_u8;

            const WIDTH: u32 = 1024;
            const HEIGHT: u32 = 1024;

            let step_number = self._random_range(rng_seed, LABEL_STEP_COUNT, 0, 1, 50);
            let (padding, pad_pct) = self._compute_padding(rng_seed, WIDTH);
            let _targets_ignore = self._find_targets(rng_seed, WIDTH, HEIGHT, step_number, padding);
            let stroke_w = self._max_u32(1, self._round_div(100, step_number));
            let sharpness = self._random_range(rng_seed, LABEL_SHARPNESS, 0, 1, 20);
            let any_minted = thought_minted || will_minted || awa_minted;
            let sigma_val = if any_minted {
                self._random_range(rng_seed, LABEL_SHARPNESS, 1, 3, 30)
            } else {
                0_u32
            };
            let mut metadata: ByteArray = Default::default();
            let data_uri = self
                .generate_svg_data_uri(token_id, thought_rank, will_rank, awa_rank);

            let description: ByteArray = "**Steps** sets the cadence; **Voice** sets how loudly the strand speaks.  **Tension** controls how tightly the curve pulls between waypoints.  The **Ideal Path** is the reference trajectory drawn first, always beneath.  The token gains its living strands through three **Movements**: THOUGHT, WILL, and AWA.  **THOUGHT**, **WILL**, and **AWA** record which Movements have appeared (Manifested / Latent).  **Movement Order** preserves the chronology--earlier arrivals remain lower, later arrivals rest on top.  When the first Movement appears, **Breath** awakens as one shared atmosphere across every living strand.";

            let movement_order = self._movement_order(thought_rank, will_rank, awa_rank);

            metadata.append(@"{\"name\":\"PATH #");
            metadata.append(@token_id_str);
            metadata.append(@"\",\"description\":\"");
            metadata.append(@description);
            metadata.append(@"\",\"image\":\"");
            metadata.append(@data_uri);
            metadata.append(@"\",\"external_url\":\"https://path.design/token/");
            metadata.append(@token_id_str);
            metadata.append(@"\",\"attributes\":[");

            metadata.append(@"{\"trait_type\":\"Steps\",\"value\":");
            metadata.append(@self._u32_to_string(step_number));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"Voice\",\"value\":");
            metadata.append(@self._u32_to_string(stroke_w));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"Tension\",\"value\":");
            metadata.append(@self._u32_to_string(sharpness));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"Margin\",\"value\":");
            metadata.append(@self._u32_to_string(pad_pct));
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"Breath\",\"value\":");
            if sigma_val == 0_u32 {
                metadata.append(@"\"Dormant\"");
            } else {
                metadata.append(@self._u32_to_string(sigma_val));
            }
            metadata.append(@"},");

            metadata.append(@"{\"trait_type\":\"THOUGHT\",\"value\":\"");
            metadata.append(@self._manifest_string(thought_minted));
            metadata.append(@"\"},");

            metadata.append(@"{\"trait_type\":\"WILL\",\"value\":\"");
            metadata.append(@self._manifest_string(will_minted));
            metadata.append(@"\"},");

            metadata.append(@"{\"trait_type\":\"AWA\",\"value\":\"");
            metadata.append(@self._manifest_string(awa_minted));
            metadata.append(@"\"},");

            metadata.append(@"{\"trait_type\":\"Movement Order\",\"value\":\"");
            metadata.append(@movement_order);
            metadata.append(@"\"}");

            metadata.append(@"]");

            metadata.append(@"}");

            metadata
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _rng_seed(
            self: @ContractState, token_id: felt252, thought_rank: u8, will_rank: u8, awa_rank: u8,
        ) -> felt252 {
            let mut seed = token_id * 1000;
            let th: felt252 = thought_rank.into();
            let wi: felt252 = will_rank.into();
            let aw: felt252 = awa_rank.into();
            seed = seed + th * RANK_SEED_T;
            seed = seed + wi * RANK_SEED_W;
            seed = seed + aw * RANK_SEED_A;
            seed
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

        fn _curve_d(self: @ContractState, steps: @Array<Step>, sharpness: u32) -> ByteArray {
            let addr = self.step_curve_address.read();
            let mut nodes: Array<Point> = array![];
            let mut i: usize = 0_usize;
            while i < steps.len() {
                let s = *steps.at(i);
                nodes.append(Point { x: s.x, y: s.y });
                i = i + 1_usize;
            }
            let dispatcher = IStepCurveDispatcher { contract_address: addr };
            dispatcher.d_from_nodes(nodes.span(), sharpness)
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

        fn _felt_to_string(self: @ContractState, value: felt252) -> ByteArray {
            if value == 0 {
                return "0";
            }

            let num_u256: u256 = value.into();
            let mut num = num_u256;
            let mut digits: Array<u8> = array![];

            while num != 0 {
                let digit: u8 = (num % 10).try_into().unwrap();
                digits.append(digit);
                num = num / 10;
            }

            let mut result: ByteArray = Default::default();
            let mut i = digits.len();
            while i > 0 {
                i -= 1;
                let digit = *digits.at(i);
                let digit_char = digit + 48;
                result.append_byte(digit_char);
            }

            result
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

        fn _manifest_string(self: @ContractState, minted: bool) -> ByteArray {
            if minted {
                "Manifested"
            } else {
                "Latent"
            }
        }

        fn _movement_order(self: @ContractState, thought_rank: u8, will_rank: u8, awa_rank: u8) -> ByteArray {
            let mut parts: Array<ByteArray> = array![];
            let mut r: u8 = 1_u8;
            while r <= 3_u8 {
                if thought_rank == r {
                    let label: ByteArray = "THOUGHT";
                    parts.append(label);
                }
                if will_rank == r {
                    let label: ByteArray = "WILL";
                    parts.append(label);
                }
                if awa_rank == r {
                    let label: ByteArray = "AWA";
                    parts.append(label);
                }
                r = r + 1_u8;
            }

            let mut order: ByteArray = Default::default();
            let mut i: usize = 0_usize;
            match parts.len() {
                0_usize => {
                    order.append(@"--");
                },
                1_usize => {
                    // Single manifests end with an arrow to imply order start.
                    order.append(parts.at(0_usize));
                    order.append(@"->");
                },
                2_usize => {
                    order.append(parts.at(0_usize));
                    order.append(@"->");
                    order.append(parts.at(1_usize));
                    order.append(@"->");
                },
                _ => {
                    while i < parts.len() {
                        if i > 0_usize {
                            order.append(@"->");
                        }
                        order.append(parts.at(i));
                        i = i + 1_usize;
                    }
                },
            }
            order
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

#[starknet::interface]
pub trait IPathLook<TContractState> {
    fn generate_svg(
        self: @TContractState,
        token_id: felt252,
        thought_rank: u8,
        will_rank: u8,
        awa_rank: u8,
    ) -> ByteArray;

    fn generate_svg_data_uri(
        self: @TContractState,
        token_id: felt252,
        thought_rank: u8,
        will_rank: u8,
        awa_rank: u8,
    ) -> ByteArray;

    fn get_token_metadata(
        self: @TContractState,
        token_id: felt252,
        thought_rank: u8,
        will_rank: u8,
        awa_rank: u8,
    ) -> ByteArray;
}
