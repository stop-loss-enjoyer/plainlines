# Changelog

## 0.9.1 (2026-10-17)

- The BE now button of a position row shows while closing the position at its SL would still lose money, by the same measure as the Open risk line, and the click moves the SL to the level where that measure is zero or more, so the button and Open risk never disagree. Before, the button hid at an SL one tick past the open even when the commission and the swap still made the position a loss (it showed Open risk with no button), and a position without a record of the panel had no commission or swap in the level.
- The lines on the chart are thicker (2 px, 3 px above panel scale 100), so they are easier to grab with the mouse. The dashed TP2 and TP3 stay dashed.
- A line can be dragged by its price tag too. The line follows the pointer, the chart does not scroll, and the order type changes while you drag Entry or SL just as when you drag the line.

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
- Used by the author in live trading on a real Bybit account (broker) and a real FTMO account (prop firm).

Prop firm rules (daily and total loss floors for FTMO and other firms) are planned for a separate Plainlines Pro. Plainlines works on any MT5 account, a prop firm account included.
