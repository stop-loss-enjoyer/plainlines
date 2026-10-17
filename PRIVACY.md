# Privacy

This text describes version 0.9.3 of Plainlines. It runs inside your terminal and talks to nothing else.

## What it does not do

- No network. The code has no `WebRequest`, no sockets, no `SendMail`, `SendNotification` or `SendFTP`. It does not send anything about you or your trades anywhere.
- No telemetry, no analytics, no licence check, no activation, no cloud.
- No DLL. The code has no `#import`, so "Allow DLL imports" is not needed and can stay off.
- It writes only inside `MQL5/Files` of your terminal (never the shared common folder) and does not copy or move files.

These rules are checked in the source by `audit.sh` (see SECURITY.md). They hold for the source in this repository. A file built from different source has no such guarantee, which is why you can build your own.

## What it reads

Only what the calculation and the guards need:

- The chart symbol and its trading properties, quotes, and the symbols of your open positions and pending orders.
- The balance, equity and margin of the account, its currency, its margin and stop-out settings, and whether it is a demo account.
- The trading rights: whether Algo Trading is on, whether the login is read-only (investor password), whether the broker allows expert advisors.
- Your open positions and pending orders (all of them, not only those of Plainlines, because Max total risk and Max open count them) and the deal history of the account.
- The server name and the server clock. The server name is part of the fingerprint that finds your account again, and the server clock gives the midnight where Max entries a day starts counting.
- The account number. It is read only to notice that you switched account while the program runs. It is kept in memory and is never written anywhere.
- The names of the programs on the charts of the terminal (only to see whether Plainlines Pro stands on one of them, and which chart of Plainlines manages positions). Nothing else about the other programs is read, and nothing of this is stored.

## What it stores, and where

In `MQL5/Files/Plainlines` inside the data folder of your terminal (File, Open Data Folder), as plain text:

- `settings.dat`: menu and look settings and the last risk you set, for the terminal and for each account, and the hard cap of an account where you raised it. It is written when the account is first recognised and whenever a setting changes. The risk of an account is stored under keys that end with `@` and the 16 hexadecimal characters of the account id, the same hash that names `acct_<id>.dat` (that file may not exist, see below). The comment text and the magic number you set are in this file too.
- `sym_<key>.dat`: the draft for a kind of symbol (order type, take profit targets, commission setting). It is written when you change something for a symbol and when the panel leaves that symbol. The key is built from the symbol's currencies, calculation mode, contract size, digits and tick size, so the same symbol at two brokers can share one file; for a symbol whose two currencies are equal the key also holds the symbol name without its suffix. It is not made from anything about you.
- `acct_<id>.dat`: the Max total risk setting of one account (keys it does not know stay as they are when it is written). It does not exist until the account is recognised and you change Max total risk, or log in to a second account of the same server and currency where one account already has this file (then it is made with the same Max total risk). `<id>` is 16 hexadecimal characters, a hash of a fingerprint of the account. The file also holds that fingerprint in plain text, to recognise the account after a restart: the server name, the account currency, and the time and amount of the first balance entry in the history. The account number, a hash of it and the login name are not stored.
- `pos_<ticket>.dat`: a record about a position or pending order the panel manages. It is made only when there is something for the panel to do with it (breakeven or trailing switched on, several take profits, or an expiry that the panel keeps), so a plain trade has none. It is deleted when the position or order is gone (a full close from the panel deletes it at once, a close elsewhere within about ten minutes). It holds: server name, symbol, side, magic number, time of opening, stop levels at the open, volume at the open, breakeven, trailing and partial close state, expiry time, the take profit levels and shares of the parts, and the time the record was made. No account number. The ticket is in the file name.

Every file ends with a checksum line.

Chart objects named `PL_...` (the lines, their labels, the input boxes and the panel bitmap) live on the chart.

While the terminal runs, Plainlines also keeps temporary terminal global variables. Other programs in the same terminal can see them. They vanish when the terminal closes:

- `PL.noalgo.<chart id>`: exists while the Plainlines on that chart is not allowed to trade. It is how the charts agree which one manages positions.
- `PL.snd.deal`: the ticket of the last deal that played a sound, so that several charts play it once.

Trade comments sent to the broker contain the text from the Comment field (default "Plainlines", cut to 20 characters) and a random tag of five letters or digits that Plainlines uses to recognise its own orders ("/1", "/2" and so on is added when a trade goes out as several orders). Orders carry the magic number (default 20261011). A close sent by the panel has the comment "Plainlines close". Your broker sees these, as it sees any order.

The release build and the demo build write no log file. Only the development build (`./build.sh --dev`) writes a `dev.log`; it never contains the account number.

## What it does not store

The account number, the account name, the password, e-mail, IP address or anything that identifies you outside the terminal. It does not read your terminal's saved login data.

## How to remove everything

1. Remove Plainlines from the chart (right click the chart, Expert List (Alt+X), pick Plainlines, Remove).
2. Delete the folder `MQL5/Files/Plainlines` in the data folder.
3. Delete `Plainlines.ex5` (and the source, if you copied it) from `MQL5/Experts`.
4. Chart objects whose names start with `PL_` disappear with the advisor or can be deleted from the chart's object list.
5. The temporary global variables disappear when you close the terminal.
