# Compatibility

State as of October 2026 (written on 15 October 2026, updated on 17 October 2026), for version 0.9.0 (shown as 0.90 in the terminal). Terminal builds change. This page is a record of what was checked on that date, not a promise. The checks of 0.9.0 below were done on demo accounts or by reading data without trading. Plainlines is also used by the author in live trading on a real broker account (Bybit) and a real prop firm account (FTMO).

## Terminal and platform

| Item | State |
|---|---|
| MetaTrader 5 build 6254 | Checked. The demo stand runs this build and every live check of 0.9.0 was made on it. The lowest build that works is not known. |
| MetaTrader 5 build 6230 | A read-only probe script built on 6254 loaded and ran in terminals of build 6230. Earlier release candidates, built on 6254, were used by the author in terminals of build 6230 in live trading from 14 October 2026. |
| Demo account at FTMO, hedging mode | Checked. |
| Wine on Linux | Checked: this is the system everything was tested on. |
| Windows | Not checked. |
| macOS | Not checked. |
| Netting accounts | Supported with refusals: reverse or close of the open position, a pending order already open on the symbol, no pending order while a position is open, an SL is required when adding, one TP when adding, a TP share below the minimum lot, no split of a lot above the broker's maximum, no risk room left, the open position cannot be valued. Run live on a MetaQuotes netting demo account (Forex Netting, USD) and checked by test vectors. |
| Bybit | Symbol parameters and the commission rules were read in a live Bybit terminal (read only). With 0.9.0 no order was sent and nothing was traded there, and 0.9.0 itself has not been run on a Bybit account; earlier release candidates were used there by the author. See the symbol tests below. |
| Other brokers | Not checked. |
| Strategy tester, including visual mode | Not checked. |
| Several accounts in one terminal | Checked live: an FTMO demo and a MetaQuotes netting demo in one terminal, and a real and a demo FTMO account. The risk and Max total risk follow the account without setup. |
| Plainlines and Plainlines Pro in one terminal | Plainlines Pro is planned, not released yet. The two will not trade in one terminal: while a program named `PlainlinesPro` stands on a chart of the terminal, Plainlines sends no order and manages no position ("Blocked: other Plainlines"). The other one is found by its program name, so do not rename the `.ex5` file. |
| Real accounts | Used by the author in live trading on a real Bybit account (broker) and a real FTMO account (prop firm) since October 2026. Test on a demo account first. |

An `.ex5` built on a newer terminal may fail to load on an older one ("newer unsupported version" was reported on the MQL5 forum). Build on the terminal you will use, or on an older build.

## Symbol tests

The symbol test runs the calculation on recorded parameters of every symbol of a set: the lot grid, the refusal without a quote, the loss per lot by the tick value and by OrderCalcProfit against the numbers the terminal gave when the symbol was probed, the margin, and the broker commission rule. It sends nothing and reads nothing from the terminal. On 15 October 2026 it ran with no failed check out of 4,572.

**FTMO demo.** All 166 symbols of the demo were probed (the demo allows selecting them all) and every one passes the test. Calculation modes covered: FOREX (43 symbols) and CFDLEVERAGE (123 symbols). Symbol classes: forex pairs 28 and exotic pairs 15, stock CFDs 59, cash CFDs 16 (indices, two oil symbols and the dollar index), metals 9, crypto 30, agricultural CFDs 7, other commodity CFDs 2. All 166 symbols have a broker commission rule that Plainlines accepts: 43 are MONEY_SPECIFIED (forex), 7 MONEY_DEPOSIT (agricultural), 116 PERCENT; 22 of the rules have a rate of zero. 73 markets were closed at the time of the probe (02:00 server time). They give the refusal "Market closed" and the same lot as a fresh run. On 17 forex crosses a sell has two loss figures that differ by up to 0.21 percent. Plainlines takes the larger one, which means a smaller lot.

**Bybit.** The probe read 599 symbols in a live Bybit terminal. The account currency there is UST, not USD. Plainlines does not treat that as a known currency name: it learns the conversion from the tick value. 33 symbols were tradable and had quotes: 30 in the mode FOREX_NO_LEVERAGE and 3 in the mode CFD (copper, gold, oil). These 33 got the full calculation test. 22 symbols are disabled for trading and were skipped. The other tradable symbols had no quote in Market Watch at that time, so for them only the lot grid and the refusal without a quote were tested. Not checked on Bybit with 0.9.0: any order, the commission as a trade (the Bybit rules were read on 14 October 2026: 103 symbols with a plain rule in UST and 474 shares with a tier in USD, 0.02 per lot with a minimum of 0.20, which Plainlines accepts by converting USD through the tick value of the symbol; no order was sent with them), the stop levels in a live trade.

**Not covered by any test.** The modes CFDINDEX, EXCH_STOCKS, the futures modes (EXCH_FUTURES, FUTURES, FORTS) and the other exchange modes. Symbols of the bond and collateral types are refused on purpose. Accounts with an account currency other than USD and UST were not tested, and neither was a cent account.

## Comparison with Position Sizer

The lot and risk of Plainlines were compared with the Position Sizer 3.15 expert advisor on the FTMO demo account, on these instruments:

| Instrument | Order types compared | Result |
|---|---|---|
| EURUSD | Market buy, Market sell, Buy Limit | Same lot and same risk |
| USDJPY | Market buy, Market sell, Buy Stop | Same lot; risk differs by one cent on the Buy Stop (conversion rate taken at a different price) |
| XAUUSD | Market buy, Market sell, Buy Limit | Same lot on the pending order; market orders were read at different ticks, so the formula was compared instead |
| US500.cash | Market buy, Buy Limit | Same lot on the pending order; market orders compared by formula |
| BTCUSD | Market buy, Buy Limit (percent commission) | Same lot on the pending order; risk differs by under a dollar because the percent commission is taken from the entry and the SL price, not from the ask on both sides |

Differences from Position Sizer, on purpose:

1. **Minimum lot.** Position Sizer raises the lot to the broker minimum without asking. Plainlines never raises it silently. With an SL it shows the real risk at the minimum lot and asks for a confirmation, also when Confirmation is off. It blocks when that risk is above the hard cap, and always when there is no SL. In the comparison (XAUUSD Buy Limit, target 0.005 percent) Position Sizer set 0.01 lot with a risk of 18.00 and Plainlines did not send it without a decision.
2. **No rate of 1.** When the terminal cannot give the loss at the SL, Plainlines blocks. Position Sizer calculates with a rate of 1. This case was not run, because the demo server has every rate.
3. **Loss per lot.** Plainlines takes the loss from OrderCalcProfit and checks it against the tick value, and it uses the larger one. Position Sizer uses the tick value. This is the one-cent difference on the USDJPY Buy Stop.
4. **Percent commission.** Plainlines takes it from the entry price and from the SL price. Position Sizer takes the same amount for both sides from the ask. This is the difference on BTCUSD.
5. **Spread in the risk on a market entry.** Plainlines counts a buy from the ask and a sell from the bid, so the spread is in the risk. This was meant as a difference, but Position Sizer starts from the ask and the bid too. The lots matched on XAUUSD and US500.cash.

Not compared: other symbol classes, other brokers, accounts with a non-USD currency.

## Prop firms

Plainlines works on any MT5 account, a prop firm account included: it is a manual panel that sizes the lot and sends what you press. Whether a firm accepts such a panel is the firm's rule, so read the firm's current rules yourself, and ask the firm in writing when they are unclear. No firm has confirmed this panel in writing and Plainlines has been submitted to none. Prop-firm account limits (daily and total loss floors for FTMO and other firms) are planned for a separate Plainlines Pro.
