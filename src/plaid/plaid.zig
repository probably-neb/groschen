const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const ui = @import("ui");
const term = @import("term");

const Color = ui.Color;
const BoxFlags = ui.BoxFlags;
const interaction = ui.interaction;
const http = std.http;

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

const bg_color: Color = .{ .rgb = .{ 20, 20, 30 } };
const fg_color: Color = .{ .ansi = .white };
const accent_color: Color = .{ .ansi = .cyan };
const muted_color: Color = .{ .ansi = .bright_black };
const panel_bg: Color = .{ .rgb = .{ 30, 30, 45 } };
const button_bg: Color = .{ .rgb = .{ 50, 50, 70 } };
const success_color: Color = .{ .ansi = .green };
const warning_color: Color = .{ .ansi = .yellow };
const error_color: Color = .{ .ansi = .red };
const alt_row_bg: Color = .{ .rgb = .{ 35, 35, 50 } };

// ---------------------------------------------------------------------------
// Flag bundles
// ---------------------------------------------------------------------------

const button_flags: BoxFlags = .{
    .clickable = true,
    .keyboard_clickable = true,
    .focus_hot = true,
    .draw_background = true,
    .draw_border = true,
    .draw_text = true,
    .draw_side_top = true,
    .draw_side_bottom = true,
    .draw_side_left = true,
    .draw_side_right = true,
    .draw_hot_effects = true,
    .draw_active_effects = true,
};

const panel_flags: BoxFlags = .{
    .draw_background = true,
    .draw_border = true,
    .draw_side_top = true,
    .draw_side_bottom = true,
    .draw_side_left = true,
    .draw_side_right = true,
};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const Environment = enum {
    sandbox,
    production,

    pub fn base_url(env: Environment) []const u8 {
        return switch (env) {
            .sandbox => "https://sandbox.plaid.com",
            .production => "https://production.plaid.com",
        };
    }
};

pub const Credentials = struct {
    client_id: []const u8,
    secret: []const u8,
    env: Environment = .sandbox,
};

pub const PlaidError = struct {
    error_type: []const u8 = "",
    error_code: []const u8 = "",
    error_message: []const u8 = "",
    display_message: []const u8 = "",
    request_id: []const u8 = "",
};

pub const Account = struct {
    account_id: []const u8,
    name: []const u8,
    official_name: ?[]const u8 = null,
    mask: ?[]const u8 = null,
    type: []const u8,
    subtype: ?[]const u8 = null,
    balances: Balances,

    pub const Balances = struct {
        available: ?f64 = null,
        current: ?f64 = null,
        limit: ?f64 = null,
        iso_currency_code: ?[]const u8 = null,
    };
};

pub const AuthStatus = enum(u8) {
    no_credentials,
    ready,
    connecting,
    authenticated,
    auth_error,
};

const Page = enum {
    connect,
    accounts,
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

pub const State = struct {
    arena: *Arena,
    status: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(AuthStatus.ready)),
    access_token: []const u8 = "",
    item_id: []const u8 = "",
    error_msg: []const u8 = "",
    accounts: []const Account = &.{},
    fetching_accounts: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    credentials: ?Credentials = null,
    page: Page = .connect,
    token_saved: bool = false,

    pub fn get_status(state: *const State) AuthStatus {
        return @enumFromInt(state.status.load(.acquire));
    }

    fn set_status(state: *State, new_status: AuthStatus) void {
        state.status.store(@intFromEnum(new_status), .release);
    }

    fn is_fetching(state: *const State) bool {
        return state.fetching_accounts.load(.acquire);
    }

    fn set_error(state: *State, message: []const u8) void {
        state.error_msg = state.arena.dupe(u8, message) catch "error (out of memory)";
        state.set_status(.auth_error);
    }

    fn set_tokens(state: *State, access_tok: []const u8, item: []const u8) void {
        state.access_token = state.arena.dupe(u8, access_tok) catch "";
        state.item_id = state.arena.dupe(u8, item) catch "";
        state.set_status(.authenticated);
    }

    fn reset(state: *State) void {
        join_thread(state);
        state.arena.clear();
        state.access_token = "";
        state.item_id = "";
        state.error_msg = "";
        state.accounts = &.{};
        state.fetching_accounts.store(false, .release);
        state.set_status(.ready);
        state.token_saved = false;
    }

    fn join_thread(state: *State) void {
        if (state.thread) |t| {
            t.join();
            state.thread = null;
        }
    }
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn init_state(arena: *Arena) State {
    return .{ .arena = arena };
}

pub fn load_saved_state(state: *State) void {
    state.credentials = load_credentials_from_env();
    if (state.credentials == null) {
        state.set_status(.no_credentials);
    } else {
        if (load_access_token(state)) {
            state.set_status(.authenticated);
        }
    }
}

pub fn is_busy(state: *const State) bool {
    return state.get_status() == .connecting or state.is_fetching();
}

pub fn tick(state: *State) void {
    if (!state.token_saved and state.get_status() == .authenticated and state.access_token.len > 0) {
        save_access_token(state.access_token, state.item_id);
        state.token_saved = true;
    }
}

pub fn deinit(state: *State) void {
    state.join_thread();
}

pub fn status_text(state: *const State) []const u8 {
    return switch (state.get_status()) {
        .no_credentials => " \xe2\x9a\xa0 Set PLAID_CLIENT_ID and PLAID_SECRET env vars | q: quit",
        .ready => " Tab: focus | Enter: activate | q: quit",
        .connecting => " \xe2\x8f\xb3 Connecting to Plaid... | q: quit",
        .authenticated => " \xe2\x9c\x93 Connected | Tab: focus | Enter: activate | q: quit",
        .auth_error => " \xe2\x9c\x97 Error \xe2\x80\x94 see above | q: quit",
    };
}

pub fn status_color(state: *const State) Color {
    return switch (state.get_status()) {
        .no_credentials => warning_color,
        .connecting => accent_color,
        .authenticated => success_color,
        .auth_error => error_color,
        .ready => bg_color,
    };
}

// ---------------------------------------------------------------------------
// UI: top-level page dispatch
// ---------------------------------------------------------------------------

pub fn build_page(state: *State) !void {
    switch (state.page) {
        .connect => try build_connect_page(state),
        .accounts => try build_accounts_page(state),
    }
}

// ---------------------------------------------------------------------------
// UI: connect page
// ---------------------------------------------------------------------------

fn build_connect_page(state: *State) !void {
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    ui.push_bg(panel_bg);
    defer ui.pop_bg();
    ui.push_border_color(muted_color);
    defer ui.pop_border_color();
    _ = ui.push_parent_box(" Plaid Connection ##connect_panel", panel_flags);
    defer ui.pop_parent();

    ui.spacer(.y, 1);

    switch (state.get_status()) {
        .no_credentials => build_no_credentials_view(),
        .ready => build_ready_view(state),
        .connecting => build_connecting_view(),
        .authenticated => try build_authenticated_view(state),
        .auth_error => try build_error_view(state),
    }

    ui.spacer(.y, 1);
}

fn build_no_credentials_view() void {
    ui.push_text_padding(1);
    defer ui.pop_text_padding();

    label_row("Missing Plaid credentials.", warning_color);
    ui.spacer(.y, 1);
    label_row("Set the following environment variables:", muted_color);
    ui.spacer(.y, 1);
    label_row("  PLAID_CLIENT_ID=<your client id>", fg_color);
    label_row("  PLAID_SECRET=<your sandbox secret>", fg_color);
    ui.spacer(.y, 1);
    label_row("Get keys at https://dashboard.plaid.com/developers/keys", muted_color);
}

fn build_ready_view(state: *State) void {
    {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();
        label_row("Connect to Plaid Sandbox to access financial data.", muted_color);
        label_row("This will create a test item with First Platypus Bank.", muted_color);
    }

    ui.spacer(.y, 1);

    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("##connect_buttons", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 2);

    if (build_button("Connect to Plaid##connect_btn", accent_color).clicked()) {
        if (state.credentials) |creds| {
            start_sandbox_auth(state, creds, "ins_109508");
        }
    }

    ui.spacer(.x, 2);
}

fn build_connecting_view() void {
    ui.push_text_padding(1);
    defer ui.pop_text_padding();
    label_row("Connecting to Plaid Sandbox...", accent_color);
    ui.spacer(.y, 1);
    label_row("Creating sandbox token and exchanging for access token.", muted_color);
}

fn build_authenticated_view(state: *State) !void {
    {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();

        label_row("\xe2\x9c\x93 Connected to Plaid", success_color);
        ui.spacer(.y, 1);

        const token_display = try ui.arena_print("  Access Token: {s}...", .{truncate(state.access_token, 20)});
        label_row(token_display, muted_color);

        const item_display = try ui.arena_print("  Item ID: {s}...", .{truncate(state.item_id, 20)});
        label_row(item_display, muted_color);
    }

    ui.spacer(.y, 1);

    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("##auth_buttons", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 2);

    if (build_button("View Accounts##view_accounts_btn", accent_color).clicked()) {
        state.page = .accounts;
        if (!state.is_fetching() and state.accounts.len == 0) {
            if (state.credentials) |creds| {
                start_fetch_accounts(state, creds);
            }
        }
    }

    ui.spacer(.x, 1);

    if (build_button("Reconnect##reconnect_btn", warning_color).clicked()) {
        state.reset();
    }

    ui.spacer(.x, 2);
}

fn build_error_view(state: *State) !void {
    {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();

        label_row("\xe2\x9c\x97 Connection Failed", error_color);
        ui.spacer(.y, 1);

        const err_msg = try ui.arena_print("  {s}", .{state.error_msg});
        label_row(err_msg, fg_color);
    }

    ui.spacer(.y, 1);

    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("##error_buttons", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 2);

    if (build_button("Retry##retry_btn", warning_color).clicked()) {
        state.join_thread();
        state.set_status(.ready);
    }

    ui.spacer(.x, 2);
}

// ---------------------------------------------------------------------------
// UI: accounts page
// ---------------------------------------------------------------------------

fn build_accounts_page(state: *State) !void {
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    ui.push_bg(panel_bg);
    defer ui.pop_bg();
    ui.push_border_color(muted_color);
    defer ui.pop_border_color();
    _ = ui.push_parent_box(" Accounts ##accounts_panel", panel_flags);
    defer ui.pop_parent();

    ui.spacer(.y, 1);

    if (state.is_fetching()) {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();
        label_row("Fetching accounts...", accent_color);
    } else if (state.accounts.len > 0) {
        try build_accounts_header();
        for (state.accounts, 0..) |account, index| {
            try build_account_row(account, index);
        }
    } else if (state.get_status() == .auth_error) {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();
        const msg = try ui.arena_print("  {s}", .{state.error_msg});
        label_row(msg, error_color);
    }

    ui.spacer(.y, 1);

    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("##accounts_nav_buttons", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 2);

    if (build_button("\xe2\x86\x90 Back##back_btn", muted_color).clicked()) {
        state.page = .connect;
    }

    ui.spacer(.x, 1);

    if (build_button("Refresh##refresh_btn", accent_color).clicked()) {
        if (state.credentials) |creds| {
            state.accounts = &.{};
            start_fetch_accounts(state, creds);
        }
    }

    ui.spacer(.x, 2);
}

fn build_accounts_header() !void {
    ui.push_text_padding(1);
    defer ui.pop_text_padding();

    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    ui.push_color(accent_color);
    defer ui.pop_color();
    _ = ui.push_parent_box("##acct_header", .{});
    defer ui.pop_parent();

    ui.next_width(.pct(0.35, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("Account Name", .{ .draw_text = true });

    ui.next_width(.pct(0.15, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("Type", .{ .draw_text = true });

    ui.next_width(.pct(0.15, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("Mask", .{ .draw_text = true });

    {
        ui.next_width(.pct(0.15, 0));
        ui.next_height(.pct(1, 0));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        _ = ui.build_box("Available", .{ .draw_text = true });
    }

    {
        ui.next_width(.pct(0.20, 0));
        ui.next_height(.pct(1, 0));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        _ = ui.build_box("Current", .{ .draw_text = true });
    }
}

fn build_account_row(account: Account, index: usize) !void {
    ui.push_text_padding(1);
    defer ui.pop_text_padding();

    const row_bg: Color = if (index % 2 == 0) panel_bg else alt_row_bg;

    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    ui.push_bg(row_bg);
    defer ui.pop_bg();
    ui.push_color(fg_color);
    defer ui.pop_color();

    const row_key = try ui.arena_print("##acct_row_{d}", .{index});
    _ = ui.push_parent_box(row_key, .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(0.35, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box(try ui.arena_print("{s}##acct_name_{d}", .{ account.name, index }), .{ .draw_text = true });

    ui.next_width(.pct(0.15, 0));
    ui.next_height(.pct(1, 0));
    const type_str = account.subtype orelse account.type;
    _ = ui.build_box(try ui.arena_print("{s}##acct_type_{d}", .{ type_str, index }), .{ .draw_text = true });

    ui.next_width(.pct(0.15, 0));
    ui.next_height(.pct(1, 0));
    const mask_str = account.mask orelse "----";
    _ = ui.build_box(try ui.arena_print("****{s}##acct_mask_{d}", .{ mask_str, index }), .{ .draw_text = true });

    {
        ui.next_width(.pct(0.15, 0));
        ui.next_height(.pct(1, 0));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        ui.push_color(success_color);
        defer ui.pop_color();
        const available_label = if (account.balances.available) |avail|
            try ui.arena_print("${d:.2}##acct_avail_{d}", .{ avail, index })
        else
            try ui.arena_print("\xe2\x80\x94##acct_avail_{d}", .{index});
        _ = ui.build_box(available_label, .{ .draw_text = true });
    }

    {
        ui.next_width(.pct(0.20, 0));
        ui.next_height(.pct(1, 0));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        const current_label = if (account.balances.current) |cur|
            try ui.arena_print("${d:.2}##acct_cur_{d}", .{ cur, index })
        else
            try ui.arena_print("\xe2\x80\x94##acct_cur_{d}", .{index});
        _ = ui.build_box(current_label, .{ .draw_text = true });
    }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

fn label_row(text: []const u8, color: Color) void {
    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    ui.push_color(color);
    defer ui.pop_color();
    _ = ui.build_box(text, .{ .draw_text = true });
}

fn build_button(string: []const u8, border_color: Color) ui.Signal {
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(3, 1));
    ui.push_bg(button_bg);
    defer ui.pop_bg();
    ui.push_color(fg_color);
    defer ui.pop_color();
    ui.push_border_color(border_color);
    defer ui.pop_border_color();
    ui.next_text_padding(1);
    const box = ui.build_box(string, button_flags);
    return interaction.signal_from_box(box);
}

fn truncate(string: []const u8, max_len: usize) []const u8 {
    if (string.len <= max_len) return string;
    return string[0..max_len];
}

// ---------------------------------------------------------------------------
// Credential loading
// ---------------------------------------------------------------------------

fn load_credentials_from_env() ?Credentials {
    const client_id = std.posix.getenv("PLAID_CLIENT_ID") orelse return null;
    const secret = std.posix.getenv("PLAID_SECRET") orelse return null;
    const env_str = std.posix.getenv("PLAID_ENV") orelse "sandbox";

    const env: Environment = if (std.mem.eql(u8, env_str, "production"))
        .production
    else
        .sandbox;

    return .{
        .client_id = client_id,
        .secret = secret,
        .env = env,
    };
}

// ---------------------------------------------------------------------------
// Background auth worker
// ---------------------------------------------------------------------------

fn start_sandbox_auth(state: *State, creds: Credentials, institution_id: []const u8) void {
    state.set_status(.connecting);
    state.thread = std.Thread.spawn(.{}, sandbox_auth_worker, .{ state, creds, institution_id }) catch {
        state.set_error("Failed to spawn auth thread");
        return;
    };
}

fn sandbox_auth_worker(state: *State, creds: Credentials, institution_id: []const u8) void {
    sandbox_auth_impl(state, creds, institution_id) catch {
        if (state.get_status() != .auth_error) {
            state.set_error("Auth failed (unknown error)");
        }
    };
}

fn sandbox_auth_impl(state: *State, creds: Credentials, institution_id: []const u8) !void {
    var request_buf: [2048]u8 = undefined;
    const create_body = try format_sandbox_token_request(&request_buf, creds, institution_id, &.{"transactions"});

    var response_buf: [max_response_size]u8 = undefined;
    const create_response = try post_json(
        try endpoint_url(&creds, "/sandbox/public_token/create"),
        create_body,
        &response_buf,
    );

    if (create_response.status != .ok) {
        set_error_from_response(state, create_response.body, "Sandbox token creation failed");
        return error.PlaidApiError;
    }

    const create_parsed = std.json.parseFromSlice(
        struct { public_token: []const u8, request_id: []const u8 },
        std.heap.page_allocator,
        create_response.body,
        .{ .ignore_unknown_fields = true },
    ) catch {
        state.set_error("Failed to parse sandbox token response");
        return error.PlaidApiError;
    };
    defer create_parsed.deinit();

    const public_token = create_parsed.value.public_token;

    var exchange_req_buf: [2048]u8 = undefined;
    const exchange_body = std.fmt.bufPrint(&exchange_req_buf,
        \\{{"client_id":"{s}","secret":"{s}","public_token":"{s}"}}
    , .{ creds.client_id, creds.secret, public_token }) catch return error.HttpRequestFailed;

    var exchange_resp_buf: [max_response_size]u8 = undefined;
    const exchange_response = try post_json(
        try endpoint_url(&creds, "/item/public_token/exchange"),
        exchange_body,
        &exchange_resp_buf,
    );

    if (exchange_response.status != .ok) {
        set_error_from_response(state, exchange_response.body, "Token exchange failed");
        return error.PlaidApiError;
    }

    const exchange_parsed = std.json.parseFromSlice(
        struct { access_token: []const u8, item_id: []const u8, request_id: []const u8 },
        std.heap.page_allocator,
        exchange_response.body,
        .{ .ignore_unknown_fields = true },
    ) catch {
        state.set_error("Failed to parse exchange response");
        return error.PlaidApiError;
    };
    defer exchange_parsed.deinit();

    state.set_tokens(exchange_parsed.value.access_token, exchange_parsed.value.item_id);
}

// ---------------------------------------------------------------------------
// Background accounts fetch
// ---------------------------------------------------------------------------

fn start_fetch_accounts(state: *State, creds: Credentials) void {
    state.fetching_accounts.store(true, .release);
    state.accounts = &.{};

    state.thread = std.Thread.spawn(.{}, fetch_accounts_worker, .{ state, creds }) catch {
        state.set_error("Failed to spawn accounts thread");
        state.fetching_accounts.store(false, .release);
        return;
    };
}

fn fetch_accounts_worker(state: *State, creds: Credentials) void {
    fetch_accounts_impl(state, creds) catch {
        if (state.get_status() != .auth_error) {
            state.set_error("Failed to fetch accounts");
        }
    };
    state.fetching_accounts.store(false, .release);
}

fn fetch_accounts_impl(state: *State, creds: Credentials) !void {
    var request_buf: [2048]u8 = undefined;
    const body = std.fmt.bufPrint(&request_buf,
        \\{{"client_id":"{s}","secret":"{s}","access_token":"{s}"}}
    , .{ creds.client_id, creds.secret, state.access_token }) catch return error.HttpRequestFailed;

    var response_buf: [max_response_size]u8 = undefined;
    const response = try post_json(
        try endpoint_url(&creds, "/accounts/get"),
        body,
        &response_buf,
    );

    if (response.status != .ok) {
        set_error_from_response(state, response.body, "Failed to fetch accounts");
        return error.PlaidApiError;
    }

    const parsed = std.json.parseFromSlice(
        struct { accounts: []const Account, request_id: []const u8 },
        std.heap.page_allocator,
        response.body,
        .{ .ignore_unknown_fields = true },
    ) catch {
        state.set_error("Failed to parse accounts response");
        return error.PlaidApiError;
    };
    defer parsed.deinit();

    const source = parsed.value.accounts;
    const accounts = state.arena.alloc(Account, source.len) catch {
        state.set_error("Out of memory copying accounts");
        return error.PlaidApiError;
    };

    for (source, 0..) |src_account, index| {
        accounts[index] = .{
            .account_id = state.arena.dupe(u8, src_account.account_id) catch "",
            .name = state.arena.dupe(u8, src_account.name) catch "",
            .official_name = if (src_account.official_name) |name| (state.arena.dupe(u8, name) catch null) else null,
            .mask = if (src_account.mask) |mask| (state.arena.dupe(u8, mask) catch null) else null,
            .type = state.arena.dupe(u8, src_account.type) catch "",
            .subtype = if (src_account.subtype) |sub| (state.arena.dupe(u8, sub) catch null) else null,
            .balances = src_account.balances,
        };
    }

    state.accounts = accounts;
}

// ---------------------------------------------------------------------------
// Persistent token storage
// ---------------------------------------------------------------------------

fn save_access_token(access_token: []const u8, item_id: []const u8) void {
    const home = std.posix.getenv("HOME") orelse return;

    var path_buf: [512]u8 = undefined;
    const dir_path = std.fmt.bufPrint(&path_buf, "{s}/.config/groschen", .{home}) catch return;
    std.fs.cwd().makePath(dir_path) catch {};

    var file_path_buf: [512]u8 = undefined;
    const sentinel_path = std.fmt.bufPrint(&file_path_buf, "{s}/.config/groschen/auth.json\x00", .{home}) catch return;

    var content_buf: [1024]u8 = undefined;
    const content = std.fmt.bufPrint(&content_buf,
        \\{{"access_token":"{s}","item_id":"{s}"}}
    , .{ access_token, item_id }) catch return;

    const file = std.fs.cwd().openFileZ(
        @ptrCast(sentinel_path.ptr),
        .{ .mode = .write_only },
    ) catch std.fs.cwd().createFileZ(
        @ptrCast(sentinel_path.ptr),
        .{ .truncate = true },
    ) catch return;
    defer file.close();

    file.writeAll(content) catch {};
}

fn load_access_token(state: *State) bool {
    const home = std.posix.getenv("HOME") orelse return false;

    var file_path_buf: [512]u8 = undefined;
    const sentinel_path = std.fmt.bufPrint(&file_path_buf, "{s}/.config/groschen/auth.json\x00", .{home}) catch return false;

    const file = std.fs.cwd().openFileZ(
        @ptrCast(sentinel_path.ptr),
        .{},
    ) catch return false;
    defer file.close();

    var content_buf: [2048]u8 = undefined;
    const bytes_read = file.readAll(&content_buf) catch return false;
    const content = content_buf[0..bytes_read];

    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        item_id: []const u8,
    }, std.heap.page_allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch return false;
    defer parsed.deinit();

    state.set_tokens(parsed.value.access_token, parsed.value.item_id);
    return true;
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

const max_response_size = 256 * 1024;

const HttpResponse = struct {
    status: http.Status,
    body: []const u8,
};

const ApiError = error{
    PlaidApiError,
    HttpRequestFailed,
};

fn post_json(url: []const u8, body: []const u8, response_buf: []u8) ApiError!HttpResponse {
    var client: http.Client = .{ .allocator = std.heap.page_allocator };
    defer client.deinit();

    var writer = std.Io.Writer.fixed(response_buf);

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .response_writer = &writer,
    }) catch return error.HttpRequestFailed;

    return .{
        .status = result.status,
        .body = response_buf[0..writer.end],
    };
}

fn endpoint_url(creds: *const Credentials, path: []const u8) ApiError![]const u8 {
    const Static = struct {
        threadlocal var buf: [256]u8 = undefined;
    };
    return std.fmt.bufPrint(&Static.buf, "{s}{s}", .{ creds.env.base_url(), path }) catch return error.HttpRequestFailed;
}

fn set_error_from_response(state: *State, body: []const u8, fallback: []const u8) void {
    const err_parsed = std.json.parseFromSlice(PlaidError, std.heap.page_allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch {
        state.set_error(fallback);
        return;
    };
    defer err_parsed.deinit();

    if (err_parsed.value.error_message.len > 0) {
        const scratch = Arena.get_scratch(&.{state.arena});
        defer scratch.release();
        const msg = std.fmt.allocPrint(scratch.arena.allocator(), "Plaid: {s}", .{err_parsed.value.error_message}) catch {
            state.set_error(fallback);
            return;
        };
        state.set_error(msg);
    } else {
        state.set_error(fallback);
    }
}

// ---------------------------------------------------------------------------
// JSON request formatting
// ---------------------------------------------------------------------------

fn format_sandbox_token_request(buf: []u8, creds: Credentials, institution_id: []const u8, products: []const []const u8) ApiError![]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer();

    writer.writeAll("{\"client_id\":\"") catch return error.HttpRequestFailed;
    writer.writeAll(creds.client_id) catch return error.HttpRequestFailed;
    writer.writeAll("\",\"secret\":\"") catch return error.HttpRequestFailed;
    writer.writeAll(creds.secret) catch return error.HttpRequestFailed;
    writer.writeAll("\",\"institution_id\":\"") catch return error.HttpRequestFailed;
    writer.writeAll(institution_id) catch return error.HttpRequestFailed;
    writer.writeAll("\",\"initial_products\":[") catch return error.HttpRequestFailed;

    for (products, 0..) |product, index| {
        if (index > 0) writer.writeAll(",") catch return error.HttpRequestFailed;
        writer.writeAll("\"") catch return error.HttpRequestFailed;
        writer.writeAll(product) catch return error.HttpRequestFailed;
        writer.writeAll("\"") catch return error.HttpRequestFailed;
    }

    writer.writeAll("],\"options\":{\"webhook\":\"https://example.com\"}}") catch return error.HttpRequestFailed;

    return fbs.getWritten();
}
