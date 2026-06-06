const meta = @import("zabi-meta");
const std = @import("std");
const transactions = @import("transaction.zig");

const transaction = @import("transaction.zig");
const EthCall = transaction.EthCall;
const types = @import("ethereum.zig");
const log = @import("log.zig");
const utils = @import("zabi-utils").utils;

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Extract = meta.utils.Extract;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;
const Transaction = transactions.Transaction;
const Value = std.json.Value;
const Wei = types.Wei;

/// Block tag used for RPC requests.
pub const BlockTag = enum {
    latest,
    earliest,
    pending,
    safe,
    finalized,
};
/// Specific tags used in some RPC requests
pub const BalanceBlockTag = Extract(BlockTag, "latest,pending,earliest");
/// Specific tags used in some RPC requests
pub const ProofBlockTag = Extract(BlockTag, "latest,earliest");

/// Used in the RPC method requests
pub const BlockRequest = struct {
    block_number: ?u64 = null,
    tag: ?BlockTag = .latest,
    include_transaction_objects: ?bool = false,
};
/// Used in the RPC method requests
pub const BlockHashRequest = struct {
    block_hash: Hash,
    include_transaction_objects: ?bool = false,
};
/// Used in the RPC method requests
pub const BalanceRequest = struct {
    address: Address,
    block_number: ?u64 = null,
    tag: ?BalanceBlockTag = .latest,
};
/// Used in the RPC method requests
pub const BlockNumberRequest = struct {
    block_number: ?u64 = null,
    tag: ?BalanceBlockTag = .latest,
};

pub const BlockOverrides = struct {
    number: ?u256 = null,
    difficulty: ?u256 = null,
    time: ?u64 = null,
    gas_limit: ?u64 = null,
    coinbase: ?[20]u8 = null,
    random: ?[32]u8 = null,
    base_Fee: ?u256 = null,
    blob_base_fee: ?u256 = null,
    beacon_root: ?[32]u8 = null,
    block_hash: ?[32]u8 = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// A wrapper for account state maps to handle EVM JSON serialization
pub const StateMap = struct {
    map: std.AutoHashMap([32]u8, [32]u8),

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            // 1. Format the 32-byte Key
            var hex_key: [66]u8 = undefined;
            hex_key[0] = '0';
            hex_key[1] = 'x';
            const key_chars = std.fmt.bytesToHex(entry.key_ptr.*, .lower);
            @memcpy(hex_key[2..], &key_chars);

            try jws.objectField(&hex_key);

            // 2. Format the 32-byte Value
            var hex_val: [66]u8 = undefined;
            hex_val[0] = '0';
            hex_val[1] = 'x';
            const val_chars = std.fmt.bytesToHex(entry.value_ptr.*, .lower);
            @memcpy(hex_val[2..], &val_chars);

            // 3. Write the value as a JSON string
            try jws.write(&hex_val);
        }

        try jws.endObject();
    }
};

pub const AccountOverride = struct {
    balance: ?u256 = null,
    nonce: ?u64 = null,
    code: ?[]const u8 = null,
    state: ?StateMap = null,
    state_diff: ?StateMap = null,
    move_precompile_to: ?[20]u8 = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

// pub const StateOverride = std.AutoHashMap([20]u8, AccountOverride);

pub const StateOverride = struct {
    map: std.AutoHashMap([20]u8, AccountOverride),

    /// Custom JSON stringifier required by Zig's std.json and zabi
    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        // 1. Tell the JSON writer we are starting an object `{`
        try jws.beginObject();

        // 2. Iterate through our HashMap
        var it = self.map.iterator();
        while (it.next()) |entry| {
            // 3. Prepare a buffer for "0x" + 40 hex characters (20 bytes * 2)
            // 3. Prepare a buffer for "0x" + 40 hex characters (20 bytes * 2)
            var hex_key: [42]u8 = undefined;
            hex_key[0] = '0';
            hex_key[1] = 'x';

            // 4. Generate the hex array.
            // In Zig 0.14+, this returns a [40]u8 array directly.
            const hex_chars = std.fmt.bytesToHex(entry.key_ptr.*, .lower);

            // Copy those 40 characters into our buffer right after the "0x"
            @memcpy(hex_key[2..], &hex_chars);

            // 5. Write the stringified key
            try jws.objectField(&hex_key);
            // 6. Write the corresponding AccountOverride value
            // (As long as AccountOverride has standard types, Zig handles this automatically)
            try jws.write(entry.value_ptr.*);
        }

        // 7. Close the object `}`
        try jws.endObject();
    }
};

pub const SimBlock = struct {
    block_overrides: ?BlockOverrides = null,
    state_overrides: ?StateOverride = null,
    calls: []EthCall,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

pub const SimulatePayload = struct {
    block_state_calls: []SimBlock,
    trace_transfers: bool = true,
    validation: bool = false,
    return_full_transactions: bool = false,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Withdrawal field struct type.
pub const Withdrawal = struct {
    index: u64,
    validatorIndex: u64,
    address: Address,
    amount: Wei,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// The most common block that can be found before the
/// ethereum merge. Doesn't contain the `withdrawals` or
/// `withdrawalsRoot` fields.
pub const LegacyBlock = struct {
    baseFeePerGas: ?Gwei = null,
    difficulty: u256,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: u64,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// The most common block that can be found before the
/// ethereum merge. Doesn't contain the `withdrawals` or
/// `withdrawalsRoot` fields.
pub const ArbitrumBlock = struct {
    baseFeePerGas: ?Gwei = null,
    difficulty: u256,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: u64,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    l1BlockNumber: u64,
    sendCount: u64,
    sendRoot: Hash,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Possible transactions that can be found in the
/// block struct fields.
pub const BlockTransactions = union(enum) {
    hashes: []const Hash,
    objects: []const Transaction,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .array)
            return error.UnexpectedToken;

        if (source.array.items.len == 0)
            return @unionInit(@This(), "hashes", try allocator.alloc(Hash, 0));

        const last = source.array.getLast();

        switch (last) {
            .string => {
                const arr = try allocator.alloc(Hash, source.array.items.len);
                for (source.array.items, arr) |item, *res| {
                    if (!utils.isHash(item.string))
                        return error.InvalidCharacter;

                    var hash: Hash = undefined;
                    _ = std.fmt.hexToBytes(hash[0..], item.string[2..]) catch return error.InvalidCharacter;
                    res.* = hash;
                }

                return @unionInit(@This(), "hashes", arr);
            },
            .object => return @unionInit(@This(), "objects", try std.json.parseFromValueLeaky([]const Transaction, allocator, source, options)),
            else => return error.UnexpectedToken,
        }
    }

    pub fn jsonStringify(
        self: @This(),
        stream: anytype,
    ) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try meta.json.innerStringify(value, stream),
        }
    }
};

pub const SimulateError = struct {
    code: i32,
    message: []const u8,
    data: ?[]const u8,
};

pub const SimCallResult = struct {
    returnData: ?[]const u8,
    logs: ?[]const log.Log,
    gasUsed: ?[]const u8,
    maxUsedGas: ?[]const u8,
    status: []const u8,
    @"error": ?SimulateError = null,
};

pub const Eth_SimulateV1BlockResult = struct {
    // baseFeePerGas: ?[]const u8,
    // blobGasUsed: []const u8,
    // difficulty: []const u8,
    // excessBlobGas: []const u8,
    // extraData: Hex,
    // gasLimit: ?[]const u8,
    // gasUsed: ?[]const u8,
    // hash: ?Hash,
    // logsBloom: ?Hex,
    // miner: Address,
    // mixHash: ?Hash = null,
    // nonce: ?[]const u8,
    // number: ?[]const u8,
    // parentBeaconBlockRoot: ?Hash = null,
    // // requestsRoot: ?Hash = null,
    // parentHash: Hash,
    // receiptsRoot: Hash,
    // // sealFields: ?[]const Hex = null,
    // sha3Uncles: Hash,
    // size: ?[]const u8 = null,
    // stateRoot: Hash,
    // timestamp: []const u8,
    // // totalDifficulty: ?u256 = null,
    // calls: []const Call,
    // transactions: ?BlockTransactions = null,
    // transactionsRoot: Hash,
    // uncles: ?[]const Hash = null,
    // withdrawalsRoot: ?Hash = null,
    // withdrawals: ?[]const Withdrawal = null,
    // requestsHash: ?Hash = null,
    // @"error": ?CallError = null,

    baseFeePerGas: ?Gwei,
    blobGasUsed: Gwei,
    difficulty: u256,
    excessBlobGas: Gwei,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentBeaconBlockRoot: ?Hash = null,
    requestsRoot: ?Hash = null,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: ?u64 = null,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    withdrawalsRoot: ?Hash = null,
    withdrawals: ?[]const Withdrawal = null,
    requestsHash: ?Hash = null,
    calls: []SimCallResult,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Almost similar to `LegacyBlock` but with
/// the `withdrawalsRoot` and `withdrawals` fields.
pub const BeaconBlock = struct {
    baseFeePerGas: ?Gwei,
    difficulty: u256,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: u64,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    withdrawalsRoot: Hash,
    withdrawals: []const Withdrawal,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Almost similar to `BeaconBlock` but with this support blob fields
pub const BlobBlock = struct {
    baseFeePerGas: ?Gwei,
    blobGasUsed: Gwei,
    difficulty: u256,
    excessBlobGas: Gwei,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentBeaconBlockRoot: ?Hash = null,
    requestsRoot: ?Hash = null,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: ?u64 = null,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    withdrawalsRoot: ?Hash = null,
    withdrawals: ?[]const Withdrawal = null,
    requestsHash: ?Hash = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Union type of the possible blocks found on the network.
pub const Block = union(enum) {
    beacon: BeaconBlock,
    legacy: LegacyBlock,
    cancun: BlobBlock,
    arbitrum: ArbitrumBlock,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        if (source.object.get("blobGasUsed") != null)
            return @unionInit(@This(), "cancun", try std.json.parseFromValueLeaky(BlobBlock, allocator, source, options));

        if (source.object.get("withdrawals") != null)
            return @unionInit(@This(), "beacon", try std.json.parseFromValueLeaky(BeaconBlock, allocator, source, options));

        if (source.object.get("l1BlockNumber") != null)
            return @unionInit(@This(), "arbitrum", try std.json.parseFromValueLeaky(ArbitrumBlock, allocator, source, options));

        return @unionInit(@This(), "legacy", try std.json.parseFromValueLeaky(LegacyBlock, allocator, source, options));
    }

    pub fn jsonStringify(
        self: @This(),
        stream: anytype,
    ) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};
