# Changelog

## 0.9.0 (2026-10-17)

First public release. The terminal shows this version as 0.90 (for example "0.90 demo" in the Look section of a build you compile yourself).

What is inside:

- A panel on the chart with Entry, SL and TP lines. Drag the SL, pick the risk, press once.
- The lot from risk, as a percent of balance or equity, or as money. Spread, commission and the broker's lot rules go into the lot.
- Market, Limit, Stop and Stop-Limit orders, on hedging and netting accounts. Up to three take profits, each with its share of the lot.
- Position tools: breakeven with the commission and a paid swap counted, trailing stop, partial close, Close all and close by symbol.
- Costs of the trade before you press (spread, commission, the swap of one night), and the result of a closed trade in R and in money, net.
- Your own limits: max total risk, max open positions and orders, max entries a day. Several accounts in one terminal, the risk is remembered for each account.
- Light and dark theme, Shift+T to open a trade (two presses, so typing a symbol never trades), a soft key click on open and close.

Safe by default:

- SL and TP go to the broker inside the order, no hidden stops.
- A lot below the broker minimum is never raised silently, and a currency rate is never guessed: the trade is blocked or asked about.
- A check before every send, a hard cap on risk per trade (5 percent unless you raise it; a raised cap is remembered for that account, a new account starts at 5), and never a second send when an answer is lost.
- No network, no DLL, no telemetry, no account number in the files. `audit.sh` enforces this on the source.

What was tested (details in COMPATIBILITY.md):

- Demo accounts: FTMO (hedging) and MetaQuotes (netting), on Linux under Wine. Windows and macOS have not been checked.
- Earlier release candidates were used by the author on a real Bybit account. This 0.9.0 itself has been tested on demo accounts only.

Prop firm rules (daily and total loss floors for FTMO and other firms) are planned for a separate Plainlines Pro. Plainlines works on any MT5 account, a prop firm account included.
