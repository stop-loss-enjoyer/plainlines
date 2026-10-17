# Security

## Threat model, in short

Plainlines is an expert advisor that can place and change real orders, so the realistic risks are these:

1. A downloaded `.ex5` that is not what the source says (it is a closed binary; you cannot read it).
2. The code doing something you did not expect with your money or your data: sending data out, trading by itself, losing protection.
3. The terminal setting that lets expert advisors trade, which is wider than this one program.
4. Mistakes in the panel itself (a wrong lot, a double send).

What the project does about them (this page and `audit.sh` are about the code of this repository, the free Plainlines):

- The source is public and the program has no network access, no DLL and no telemetry (see PRIVACY.md). `audit.sh` enforces this on the source.
- You can build your own `.ex5` from the source (see "Build from source" in MANUAL.md). A SHA-256 sum of a released file only identifies that file. MetaEditor does not produce identical bytes twice, so the sum is not proof that the file was built from this source.
- Orders are sent from one place in the code only (`audit.sh` refuses `OrderSend`, `OrderSendAsync` and `CTrade` anywhere else). Every order is first checked in the terminal with OrderCheck. SL and TP go to the broker inside the order. A guard blocks a second send until the first is settled, and an order whose answer was lost is never sent again by itself.
- A build made without `--release` (a plain compile in MetaEditor, or `./build.sh` without flags) is a demo build. It refuses to trade on anything but a demo account.
- Mistakes are possible. This is version 0.9.1, an early public release. It has been tested on FTMO and MetaQuotes demo accounts and used by the author in live trading on a real Bybit account and a real FTMO account. Test on a demo account first and never risk money you cannot afford to lose.

## Algo Trading

The Algo Trading button in the terminal toolbar is a switch for the whole terminal. When it is on, every expert advisor on every chart can trade, not just Plainlines. Plainlines needs it only to send orders. Check what is attached to your charts before turning it on, and turn it off when you do not need it.

## What `audit.sh` checks

`audit.sh` scans the `.mq5` and `.mqh` files of `src` (and the local files they include) and fails if it finds any of these:

- `#import`, also in a standard header that an include pulls in (this is how DLLs and WinAPI come in). Standard includes (`<...>`) must start with one of these standard library paths: `Trade/`, `Controls/`, `Canvas/`, `Arrays/`, `ChartObjects/`, `Object.mqh`, `StdLibErr.mqh`, `Strings/`, `Generic/`, `Math/`. In them `WinAPI/`, absolute paths and paths with `..` are refused. A local include (`"..."`) is followed and scanned too. A local include that cannot be found is refused. The headers a standard include pulls in are followed, but only if the MetaEditor `Include` folder is present on the machine that runs the audit. Without it that part is skipped, with a notice.
- `WebRequest`, sockets (any name starting with `Socket`), `SendMail`, `SendNotification`, `SendFTP`.
- `FILE_COMMON`, `FileCopy`, `FileMove` (writing outside the terminal's own `MQL5/Files`).
- `__DATE__`, `__DATETIME__`, `__MQLBUILD__` (they bake time and build into the file).
- A `FileOpen` call with a number written in it on one line (use the named `FILE_*` constants).
- `OrderSend`, `OrderSendAsync` or `CTrade` anywhere except `src/Trade/SendOrderSafe.mqh`, the one file meant for sending.
- A definition of the build switches `PL_DEV_LOG`, `PL_RELEASE` or `PL_ALLOW_REAL` in any scanned file. Only `./build.sh` sets the build mode, in its own temporary copy.
- `ACCOUNT_LOGIN` anywhere except `src/Terminal/Account.mqh` (which keeps it in memory), and `ACCOUNT_NAME` anywhere.

Comments are stripped and string contents are blanked before matching, so text that merely mentions a word does not fail. Lines split with a trailing backslash are joined first. `tests/audit/run.sh` runs the audit on sample files that must pass and sample files that must fail.

## What `audit.sh` does not catch

- Macro tricks, for example `#define W WebRequest` and then `W(...)`.
- Identifiers built by token pasting.
- Literal flag values: `FileOpen(n, FILE_WRITE|4096)` equals `FILE_COMMON`. Any integer literal inside a one-line `FileOpen` call is flagged, but multi-line calls and constants hidden behind a variable are not.
- Anything in the compiled `.ex5`. The audit reads source, not the binary you downloaded. It protects you only if you build the file yourself from audited source.
- Logic mistakes. It finds forbidden calls, not wrong calculations.

## Reporting a problem

- Ordinary bugs and questions: open an issue in the GitHub repository stop-loss-enjoyer/plainlines.
- Security problems: please do not post details in a public issue. Use a private report through GitHub Security Advisories of the same repository ("Report a vulnerability" on the Security tab).
- Response time: a first answer within 48 hours, for security reports and ordinary issues alike.
