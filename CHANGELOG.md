# Changelog

## 0.9.4 (2026-10-19)

- Gold and silver on servers that publish a wrong tick value now trade. On a FundingPips account XAUUSD showed a tick price of 0.01 for one lot of 100 oz and XAGUSD 0.5 for one lot of 5000 oz, so the panel blocked them with "Loss figures disagree" and showed a reward of a few cents. Now, when the terminal's own profit calculation agrees with the price move times the contract, the lot, reward, spread, swap and the BE button are counted from it. Any other disagreement still blocks, with a clearer phrase: "Broker data conflict, not trading".
- The plan lines no longer get in the way of open orders. When a line of the plan lies on a line of a live order or position, the line under the pointer is the plan line: dragging it moves the plan and never the real order. Order lines anywhere else on the chart drag as before. A pending plan the panel places itself (after a trade, on the Limit or Stop button) also keeps clear of the levels of live orders, so after placing a Limit the eye no longer brings the plan back on top of it.
- Removing Plainlines from the chart always removes its lines. Before, about one removal in ten left the Entry, SL and TP lines on the chart.
- Placing a pending order plays the same soft click as opening a trade.

## 0.9.3 (2026-10-17)

- New option in Advanced, Click to place (off by default). With it on, the Market and Limit buttons (in the strip, the card and the full panel) start placing the lines with the pointer: the SL line follows the cursor, a left click fixes it, then TP1 follows (its label shows the live R) and a click fixes it. Limit starts with the Entry line, then the SL, then TP1, and the order type still changes between Limit and Stop as it does when you drag the Entry. The last click only places TP1, it never sends an order: the trade button and Shift+T stay the only way to send. Esc, a right click, the same button again, the other type button, the menu, the trade button, Shift+T, a symbol or timeframe change and switching the option off cancel it and the lines go back to where they were (the trade button and Shift+T cancel without sending). If the lines are hidden, pressing the button shows them first. With the option off nothing changes: Market and Limit only switch the type.

## 0.9.2 (2026-10-17)

- The Look section of the menu has a new choice, Lines: Thin or Thick. Thick (the default, as before) draws the lines on the chart 2 px wide, 3 px above scale 100; Thin draws them 1 px wide. The lines change at once, and the choice is kept for the terminal like the theme. A line can still be dragged by its price tag at either width.

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
