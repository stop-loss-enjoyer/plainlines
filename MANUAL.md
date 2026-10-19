# Plainlines manual

Everything the panel does, in detail. The short version is in the [README](README.md), the install with pictures in [INSTALL.md](INSTALL.md).

## The panel

The panel opens as the quick strip, one row:

- the status dot, which is also the handle to drag the panel;
- the risk buttons 0.5, 1 and 2 (percent), the risk field and its unit, % or the account currency;
- the order type, Mkt and Lmt;
- the open button with the side and the lot;
- the eye button and a chevron.

Some details of the strip:

- Any other risk is typed in the field: a percent, or a sum of money after a click on the currency (for example "100" with UST selected). Press Enter or click outside the field. The unit switch keeps the same risk and writes it in the other unit.
- With no SL the buttons give way to "No SL" (the lot is typed in the full panel).
- The second type segment reads Lmt, Stp or S-L when the order type that stands is one of those, and Cancel takes its place while a confirmation waits.
- The strip has no symbol (the chart title has it) and no status line. The dot shows the status, a block is named on the button, and the full phrase is in the full panel. The result of a send or a close (for example "Filled 0.52 at 1.08542") stands in the place of the button for 4 seconds, so a double click cannot send twice.

The chevron opens the full panel with the lines and prices, the result card, Costs, Positions and the menu. The minus button in its header brings the quick panel back. The menu section Look has "Quick panel": Strip (the default) or Card, an older quick panel of two rows with the header, the risk field and the flip button. The choice is kept for the terminal and survives a restart.

If the full panel is taller than the chart, scroll it with the mouse wheel, or choose a smaller scale in Look (100 fits a chart of about 460 pixels).

## Other order types, from the full panel

- **Lines.** Entry, SL and TP, and a Limit line for Stop-Limit. You can drag a line by its price tag at the right edge as well as by the line itself. When the lines hide the price, the eye button in the header (left of the menu button, also on the quick panel) takes them off the chart and brings them back; the prices stay and the fields of the panel set them.
- **Pending orders.** Market is chosen by default. To enter at another price, drag the Entry line there. The panel picks the type from where the line stands: for a buy (SL below the entry), above Ask is a Buy Stop and below is a Buy Limit; for a sell (SL above the entry), below Bid is a Sell Stop and above is a Sell Limit.
- **It follows you.** The type switches while you drag, in both directions, and the same happens when you type the Entry or move the SL across the entry (that changes the side). Drop the Entry back on the price (within about 6 screen pixels times the panel scale, with Scale on Auto the scale follows your Windows scaling, never less than 2 ticks), or press Market, for a market order. A price typed into the Entry field keeps a zone of 2 ticks, so a Limit just off the market stays a Limit.
- **Only your own move switches the type.** If the price runs past a waiting entry, the type stays and the panel says the entry is on the wrong side.
- **Stop-Limit** is chosen with its button and keeps its two lines.

## What the full panel shows

- The lot and the risk in the result card, and the spread at the right end of the Entry row. The money side of the spread, the commission and the swap is in Costs (the Costs link at the right end of the status line, see below).
- When there is nothing to warn about, the status line shows the swap of one night for the side and lot of the trade, for example "Swap -$1.37/night" (with "x3 Wed" on the day the swap is charged three times). It says "Ready to trade" when the swap is unknown or zero.
- If something blocks the trade, the status line says why in one line, and the button stays grey and names the reason in a few words ("Blocked: no SL").
- A warning (for example a wide spread) is shown in colour and does not stop you.
- If the trade will ask for a confirmation (see below), the button is amber and the status line says why once.

## After you press

Before the order goes out, the panel counts everything again on a fresh quote and sends the lot for your risk at that moment. It can differ from the lot on the plan (on the CONFIRM button, when there is one) in either direction, by up to about a tenth.

- The status line names the lot and the risk that went out, for example "Filled 2.42 at 1.11955 · risk $479.16".
- It adds "(planned $480.00)" when the fill moved the risk by more than 1 percent from the one on the button and the status line has room for it. At the 100 percent panel scale it has not, and the risk that went out stands alone.
- A pending order says "Placed Buy Limit 2.42 at 1.11900 · risk $479.16". The symbol is in the header.
- If the market price moved by more than a tenth of the SL distance, or the risk would be more than 2 percent above the one shown, it sends nothing and asks for a new confirmation.

## When the trade closes

When a position of Plainlines closes, by its SL or TP, by a button of the panel, in the terminal window or by a stop out, the status line says how it ended: "TP hit · +2.0R · +$190.40 net", "SL hit · -1.0R · -$96.80 net", "Closed · +0.4R · +$38.10 net" or "Stop out · ...".

- Net is profit, commission, swap and fee of all the deals of the position, entry and exit together.
- R is net divided by the first risk, which is the loss from the entry to the SL of the entry deal plus all commissions and fees, so a clean SL comes out near -1.0R. A position with no SL says "no SL" and no R.
- A partial close says "Closed part · +$12.30 net" and no R.
- A trade that went out as several positions says it once for each, as each closes. Close all and close by symbol end with one sum, said when the last exit of the batch arrives, for example "Closed 3 · -$12.40 net" (or after a few seconds, as "Closed 2 of 3 · ...", when an exit is late).
- The result is green for a profit and red for a loss, it does not fade, and it stays until your next click on the panel, key press or dragged line, or until the next trade of Plainlines.
- It is read from the broker's history, nothing is stored and nothing is sent. A terminal started after the close does not show it, because the event was before the start.
- When breakeven or the trailing stop moves an SL, the status line says so.

## After a fill: managing the position

- **The live SL moves in the terminal.** Drag the position's level on the chart (the Modify window that may open is MetaTrader's own). The panel picks up the new SL by itself and recounts the open risk.
- **The plan lines hide by themselves.** Right after a trade of the panel, the Entry, SL and TP lines would stand on the same prices as the position's, and a drag there would grab the level of the position in MetaTrader 5, not a plan line. So the eye button turns itself off on that symbol and the plan lines are hidden. The levels you see on the chart are the position's. Press the eye to bring the plan lines back for the next trade. If MetaTrader shows its One Click Trading disclaimer after a drag on a position level, press Cancel: Accept turns on one-click trading for the whole terminal.
- **The panel's tools** are in the row of the position (see Close a trade below): breakeven now, close a part, breakeven on or off, trailing on or off.
- **One press still sends.** Confirmation is off by default, so the button stays live. Set your risk before the next click.

## Close a trade

- When Plainlines has positions or orders, a Positions row stands at the end of the full panel, under the result card. It shows the count and the profit, for example "2 pos +$45.20" (the profit in green, a loss in red); a position and a pending order together read "1 pos · 1 order"; "1 order" when there are only pending orders.
- The row is collapsed by default. A click on it opens the list, a second click collapses it. On a short chart it can be below the edge: scroll the panel with the wheel.
- Each row has an x that closes it. It takes one click while Confirmation is off (the default).
- A position row has a BE now button. It shows while closing the position at its SL would still lose money, by the same measure as the Open risk line: the move from the open to the SL, plus the swap, minus the commission still to pay at the exit (what was paid at the entry is already gone and is not in that number). It goes away as soon as that number is zero or more, whoever set the SL, so the button and the Open risk line never disagree. One click moves the SL to breakeven: the open price plus the commission in and out and a negative swap already paid, and one tick more, then tick by tick toward the profit until closing at that SL gives zero or more by the same measure. The button is muted while the price has not passed that level (a click then says why), and while the level is not known, for example when the entry deal is not in the history yet, so the commission cannot be read. The button needs no setup and no record of the position.
- A click on a position row opens three buttons: close a part, breakeven on or off for that position, trailing on or off for that position. Close a part takes one click while Confirmation is off.
- Two buttons under the list close everything of Plainlines, or everything of Plainlines on the chart symbol (the close buttons setting turns them off). They need a second press, between half a second and three seconds after the first.
- With no positions and no orders the row is not there, and it is hidden while Costs is open (Costs and the list are never shown together). When the last position or order is gone, the row is collapsed again.
- The block lists the positions and pending orders that Plainlines opened (found by the magic number or by their record file), with the open risk and the margin use.

## Shift+T

Shift+T opens a trade in two presses: the first arms the button (it reads CONFIRM with the side and the lot), the second Shift+T or a click sends, from half a second to three seconds after the first. This holds also when Confirmation is off, because a capital T typed on the chart (for example when you type TSLA or ETHUSD to change the symbol) is the same key: typing a symbol must never send a trade. Any other key while the button is armed cancels it (Shift, Ctrl, Alt, Caps Lock and the Windows key alone do not count), so typing a symbol only arms the button for a moment and lets it go. The button itself sends in one click when Confirmation is off.

Hotkeys only work while the chart has keyboard focus (click on the chart first), and not while you are typing in a panel field. Enter does not confirm a trade: MetaTrader 5 itself uses it on a chart to open a small "symbol,period" box, and a trade must not depend on a key that can change the symbol of the chart. (The Enter that you press after typing a risk in a panel field only fills in that field.) A confirmation is sent by the button or by Shift+T and cancelled by Escape or any other key.

From the quick panel Shift+T works the same way and the view does not change. If the menu is open, the first Shift+T also brings back the main view.

## Confirmation

Confirmation is off by default: one click of the button sends at once (after the very first trade of this terminal, which asks once; Shift+T always takes two presses, see above), using the lines as they are. You can turn Confirmation on in the menu (Confirm). A settings file written before the default changed is switched to off once, when it is first read, and after that your choice stands.

With Confirmation on, the button turns into a CONFIRM button that shows the frozen plan: side, order type, lot, SL, the first TP and the risk. When the lot goes out in several orders, the button says "x" and the number of orders. Press it again, or press Shift+T, to send. A second press earlier than half a second after the first is ignored (a double click guard). The confirmation lapses after three seconds. Escape or the Cancel button cancels it, and so do moving a line, changing a field or the menu, and changing the symbol or the timeframe. If a market price moves by more than a tenth of the SL distance while you wait, the panel cancels and asks again.

These guards stay even with Confirmation off:

- The hard cap on risk (5 percent unless you raised it) blocks, and nothing overrides it.
- A confirmation is asked once for the very first trade of this terminal after install.
- A confirmation is still asked when the trade has no SL, when the lot is below the broker minimum and would be raised to it, when the lot is split into several orders, when the margin use after the trade is above the Confirm margin above value (50 percent by default), when the trade adds to an open position on a netting account, and when the answer to the last order on this symbol was lost.
- A press within one second of the last answer is ignored, and so is the same key twice within half a second. A press while an order is being sent or checked is ignored.

The hard cap is 5 percent unless you raise it yourself in the Advanced section (up to 100 percent, for example to trade a brokerage account with a risk of 10 percent). A raised cap is remembered for that account, also after a terminal restart, and comes back when you log in to the account again. An account you have not raised it on starts with 5 percent, and so does an account the panel has not recognised yet; one account's raised cap is never used on another.

## The menu

The menu opens from the panel and has these sections, in the order of use. At the right of each section title, in grey, is the current state of that section (for example "Balance · 1 TP · GTC" for Trade, "broker" for Commission, "on · above 2%" for Confirm), so you can see the settings without opening the sections. Advanced says "changed" in amber when one of its risky options is on, otherwise it names the rare options that are on ("ATR 1.5x", "Sub open", "No TP") or says "rarely needed".

- **Trade** (open when the menu opens): risk base (balance or equity), Take profits 1, 2 or 3 with their R targets and shares (TP1 gets what the others leave; the defaults for TP2 and TP3 are 30 and 20 percent), pending order expiry (good till cancelled, today, or a number of hours). The state shows the base, the number of take profits ("No TP" when it is off in Advanced) and the expiry.
- **Position**: move SL to breakeven at a chosen R (commission and a negative swap are taken into account), trailing (distance in pips for forex or points otherwise, kept per symbol, 0 means the distance of the initial SL), partial close percent (50 by default), close buttons. Breakeven and trailing both start once the price is the chosen R, times the SL distance, in profit. The state names breakeven and trailing when they are on and says "off" when neither is.
- **Confirm**: Confirmation on or off (off by default), and the Confirm above value (percent of the risk base, 2 by default): with Confirmation on, a risk over it turns the button amber and the confirmation names the risk; with Confirmation off the risk asks nothing (the hard cap still blocks). A note says that Shift+T opens the trade from the chart; the hotkey cannot be changed.
- **Commission**: where you set the commission of the chart symbol: the kind (none, per lot / side, per lot / round, % notional / side), the rate, and the last deal of the symbol with a Use button when there is one. The chart symbol is shown at the right of the section title, because the rate is kept per symbol, not for the whole terminal like the other settings. When the terminal gives a broker rule that the panel understands for the symbol, it is always used and there is nothing to set: the section shows the kind and the rate with the words "broker rate", the note "Set by the broker, counted in the lot.", and the title says "broker". The kind button, the rate field, the last deal and its Use button appear only for a symbol without such a rule. See Costs below.
- **Limits**: max total risk (percent of balance, counts every position and order of the account), max open incl. orders (every position and pending order of the account, the orders this trade would add included), max entries a day (every entering deal on the account since midnight of the server clock, each TP leg and each part of a split counts, a pending order counts when it fills). The day of Max entries a day ends at midnight of the server clock shown in the terminal, not at midnight of your PC or of your time zone, and the count starts again then. While Max entries a day is on, a new trade waits until the deal history adds up to the account balance (a moment after every closed trade, or for good if the broker returns an incomplete history) and the panel says why. Right after a start or an account switch a new trade also waits while the account is not recognised yet and an account file of the same server has Max total risk set. The state shows "set" when at least one of the three is set, otherwise "off".
- **Advanced**: what to do above the broker's max lot (Block, Trim or Split into several orders, Block by default), the hard cap, trade without SL, magic number, max spread as a percent of the SL distance (30 by default, a warning only), the margin use that asks for a confirmation (50 percent by default). After them come the options that few traders touch: subtract open risk, ATR stop (off by default, multiplier 1.5 and period 14; the SL line then follows the ATR and cannot be dragged), No TP, Click to place, and the comment (it is sent to the broker, see PRIVACY.md). Click to place is off by default: with it on, the Market and Limit buttons start placing the lines with the pointer. Market: the SL line follows the cursor, a left click fixes it, then TP1 follows (its label shows the R) and a click fixes it. Limit: the Entry line first, then the SL, then TP1; the order type still changes between Limit and Stop as when you drag the Entry. The last click only places TP1 and never sends an order. Esc, a right click, the same button again, the menu, the trade button, Shift+T, a symbol or timeframe change cancel it and the lines go back (the trade button and Shift+T cancel without sending). While it waits the chart does not scroll and the right-click menu of the chart is off, and the status line says what to click (the quick strip has no status line, only the dot). It does not start with Stop-Limit, with an ATR stop (the SL line is the ATR's) or, for Market, with both SL and TP off.
- **Look**: theme (Auto, Light, Dark), scale (Auto, 100, 125, 150), Quick panel (Strip or Card), Lines (Thin or Thick), sounds, version. Lines sets how thick the Entry, SL and TP lines are on the chart: Thick (the default) is 2 px, 3 px above scale 100, which is easy to grab with the mouse, Thin is 1 px. The lines change at once, the choice is kept for the terminal and survives a restart. A line can be dragged by its price tag at either width. The dashed TP2 and TP3 stay dashed, with longer dashes when Thin, as the terminal draws a 1 px dashed line. Sounds are on by default and can be turned off here. They are the press of a mechanical keyboard key, one recording: it plays as recorded when a position opens, a little lower when one closes in profit and lowest when one closes in a loss.
- **Reset to defaults** at the bottom sets the menu settings back.

A trade without SL always asks for confirmation, even with Confirmation off (the default). It is refused while Max total risk is on. Its risk is shown as undefined, and its lot is never raised to the broker minimum.

## What the panel does not do, and why

- **No hidden stops.** SL and TP always go to the broker inside the order. Closing the terminal does not remove them. But some things are done by Plainlines itself and stop when the terminal or the advisor is off: breakeven, trailing, the partial closes on a netting account, and deleting an expired pending order when the broker has no lifetime type that fits (the panel says "Expiry is kept by Plainlines while the terminal runs"). They are kept in `pos_<ticket>.dat` files and go on when Plainlines runs again. Only one chart with Plainlines manages positions at a time (of the charts allowed to trade, the one with the lowest internal chart id). If none is allowed to trade, the panel says "Positions not managed" with the reason.
- **One Plainlines per terminal.** Plainlines Pro is a planned paid version, not released yet, and the two will not trade together. While a program whose name starts with `PlainlinesPro` stands on a chart of the terminal, this one sends no order and manages no position, and the button says "Blocked: other Plainlines" while the status line says "Remove Plainlines Pro first: one Plainlines per terminal" (cut to "Remove Plainlines Pro first" where the line is narrow). Then nobody runs breakeven, trailing, the partial closes on a netting account or the expiry kept by the panel, while SL and TP at the broker stay as they are. Remove one of the two to go on. Do not rename the `.ex5` file: this check, and the choice of the chart that manages positions, go by the program name.
- **No silent minimum lot.** If the risk you asked for is smaller than the broker's minimum lot allows, Plainlines does not quietly raise the lot. With an SL it shows the minimum lot and the real risk at that lot, says "Lot below minimum, risk is higher" and asks for a confirmation, also when Confirmation is off. If that risk is above the hard cap, it blocks. Without an SL it blocks ("Lot is below the broker minimum").
- **No guessing a currency rate.** The loss per lot comes from the terminal's own OrderCalcProfit and is checked against the tick value. The two must agree within 1 percent plus half a unit of the last digit of the account currency. If they do not, or if the terminal gives no loss for the SL, the panel blocks the trade (the terminal converts by itself, nothing to add to Market Watch). It never calculates with a rate of 1.
- **Slippage is shown, not capped.** On market execution the broker fills at its own price. After a fill the panel recounts the risk from the real open price and adds "Slipped" after the risk when it is more than 2 percent above the risk you asked for (or the risk on the CONFIRM button, if that was higher). Position Sizer has the same limit: a market order fills at the broker's price.
- **No order without a check.** Every order goes through OrderCheck in the terminal first. If the check says no, nothing is sent and the reason is shown in plain words. The broker's server can still refuse the order. Then the panel shows its answer.
- **No second send after a lost answer.** If the answer to an order is lost, the panel looks for the order for 30 seconds and never sends it again by itself. After that it says "check the Trade tab".
- **No network, no DLL, no telemetry.** See PRIVACY.md.

## Costs

The Costs block is opened by the Costs link (with a chevron) at the right end of the status line, and closed by the cross in its header. It is a short grid for the trade on the chart: next to its title it shows the side and the lot (for example "Buy 1.05 lot"), and each row has a grey detail and the money on the right.

- **Spread**: in pips for forex or points otherwise, and the money for this lot.
- **Commission**: the money for this lot, and in one word where the rate comes from: "broker" (the broker's rule; "broker, none" when the rule charges nothing, "min $0.20" when the broker minimum of an order is the commission of this trade), "your rate" (set by you) or "last deals" (taken with the Use button). When no rate is known it says "not counted" and gives a "set in menu" link that opens the Commission section of the menu.
- **Swap**: only the side of this trade, for one night. Plus is green and minus is red. Under it, a small note "x3 on <day>" names the day that charges the swap three times, when the symbol has one.

Costs is about the trade on the chart (the lot on the panel), not about a position that is already open.

The commission comes from these sources, in this order:

1. The broker's commission rule, read from the terminal (SymbolInfoCommissions). Plainlines accepts only the plain shape: one rule with one tier, charged at once, by volume, in the account currency. A rate in the currency of the symbol (for example USD on a UST account, as Bybit has it for shares) is accepted when the symbol's own currency can be converted the way the swap is, from the tick value. A minimum commission per order, charged once for the round (a share at 0.02 per lot with a minimum of 0.20), is counted in the lot, the risk and the reward: every order pays at least the minimum, so a trade that goes out as several orders pays it several times, and when the money for the trade is no more than the minimum, the lot goes to the minimum lot with a confirmation that shows the true risk. Anything else is not used. When the terminal gives such a rule, it is always used, because it is read for the account you are logged in to and one terminal can hold accounts of one broker with different commission.
2. Your own setting for the symbol (per lot and side, per lot and round, or percent of notional), made in the Commission section of the menu. It applies only to a symbol that has no such broker rule, because a rate you typed belongs to the symbol and not to the account.
3. Nothing. The panel then says "Commission not counted" and the Costs block says "not counted". When the symbol has a deal in the last 90 days, its commission is offered as a suggestion in the Commission section, with a Use button, and you decide.

The open risk of your pending orders uses the same order and then the commission of the last deals of that symbol. With no source at all it counts zero and says "Commission not counted: <symbol>". The commission still to pay at the exit of an open position (in the breakeven level and in the open risk) comes from the broker's rule, then your setting, then what the last closed position of the symbol paid at its exit, and then the entry commission again.

## Several accounts in one terminal

You can log in to different accounts in one terminal and keep Plainlines on the chart. Switching needs no setup. The risk, its value and its unit (percent or money), is remembered for each account, and a new account starts with the last risk of the terminal. The hard cap on risk is kept for each account too, but a new account always starts with 5 percent, never with another account's raised cap. Max total risk is kept for each account too, and the file of an account is found by its first deposit. Switching was checked live between an FTMO demo and a MetaQuotes netting demo in one terminal, and between a real and a demo FTMO account.

## Files it writes

Everything the panel writes goes to `MQL5/Files/Plainlines` inside your terminal's data folder, as plain key=value text:

- `settings.dat`: menu and look settings, and the risk you typed or chose last, for the terminal and for each account, and the hard cap of each account (the account keys carry the same 16 hexadecimal characters as `acct_<id>.dat`). It is the same on every symbol of this terminal and comes back after a restart; another terminal has its own.
- `sym_<key>.dat`: the draft for a kind of symbol (order type, take profit targets, commission setting and so on). The key is built from the symbol's currencies, calculation mode, contract size, digits and tick size, so one file can serve the same symbol at two brokers.
- `acct_<id>.dat`: the Max total risk of an account and the fingerprint that finds the account again (keys it does not know stay as they are when it is written). On an account with no balance entry in its history Max total risk cannot be saved, and the panel says "No deposit in history: limits cannot be saved". It appears only when you change Max total risk (or log in to a second account of the same server and currency where one account already has the file, then it is made with the same Max total risk), and only once the panel has recognised the account. Until then there is no such file. The id is 16 hexadecimal characters, a hash of the server name, the account currency and the time and amount of the first balance entry, so every chart of the account finds the same file. The account number is not in it.
- `pos_<ticket>.dat`: what Plainlines remembers about a position or pending order it manages (breakeven, trailing, take profit parts, expiry). It is made only when there is something for the panel to do (breakeven or trailing on, several take profits, an expiry the panel keeps), so a plain trade has none, and it goes when the position or order does.

Every file ends with a checksum line, so a file cut off by a crash is noticed instead of being trusted. The release build writes no log file.

Details and how to remove everything are in PRIVACY.md.

## Build from source

You compile it yourself with your own MetaTrader 5. A plain build is a demo build (see below).

1. Copy the contents of the `src` folder into `MQL5/Experts/Plainlines` in your data folder (keep the subfolders, `Plainlines.mq5` is the main file). The other `.mq5` files in `src` are development and test scripts. You do not need to compile them; when run, they write their results into `MQL5/Files`.
2. Open `Plainlines.mq5` in MetaEditor and press Compile (F7).
3. The result is `Plainlines.ex5` next to it, in `MQL5/Experts/Plainlines`. In the Navigator it appears under Expert Advisors, Plainlines. Continue with step 3 of INSTALL.md, and keep only one copy: if you also put a downloaded `Plainlines.ex5` in `MQL5/Experts`, the Navigator shows two.

**This gives the demo build.** It trades only on a demo account, and the version in the Look section reads "0.94 demo". The same is true of `./build.sh` without flags, which makes `PlainlinesDemo.ex5`. Keep only one build of Plainlines in a terminal: two builds under different names would both manage the same positions. The build without the demo-only check is made by `./build.sh --release`. It needs committed sources and a passing audit. Without the script, add the line `#define PL_RELEASE` to `Build.mqh` in your own copy. `audit.sh` refuses that line in the repository on purpose.

MetaEditor and the MQL5 standard library belong to MetaQuotes and are not part of this repository. Two checks are included for people who want them: `audit.sh` scans the source for forbidden calls (see SECURITY.md), and `build.sh` is a Linux helper that compiles under Wine.

Do not expect two builds to be byte for byte the same: MetaEditor writes varying data into the file. A SHA-256 sum of a released `.ex5` only identifies that file. It does not prove it was built from this source. If you do not trust a downloaded `.ex5`, build your own.

