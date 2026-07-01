# WealthBridge 🌉

<p align="center">
  <a href="https://www.fidelity.com">
    <img src="https://img.shields.io/badge/Platform-Fidelity-1DB954?style=flat-square" alt="Platform Fidelity">
  </a>
  <a href="https://wealthfolio.app">
    <img src="https://img.shields.io/badge/Platform-Wealthfolio-d5ca8f?style=flat-square" alt="Platform Wealthfolio">
  </a>
  <a href="https://github.com/WiseDodge/WealthBridge/commits/main">
    <img src="https://img.shields.io/github/last-commit/WiseDodge/WealthBridge?style=flat-square&color=333" alt="Last Commit">
  </a>
</p>

WealthBridge is a portable bridge for moving Fidelity position snapshots into Wealthfolio-compatible holdings CSV imports.

It is built to stay relocatable and GitHub-friendly.

## ✨ Features

- **Smart Normalization**: Normalizes broker snapshot exports into Wealthfolio-compatible CSV snapshots.
- **Data Safety**: Handles same-date Fidelity exports safely.
- **Sleeve Aggregation**: Aggregates brokerage sleeves when requested.
- **Automated Cash Conversion**: Normalizes cash-like rows to Wealthfolio's `$CASH` symbol.
- **Scope Preservation**: Preserves account scope so brokerage cash and CMA cash remain separate rows.

## 🔄 Monthly Workflow

1. Finish your monthly investing activity first.
2. In Fidelity, go to Portfolio, then Positions.
3. Select the configured My View in the dropdown on the left.
4. Wait until Pending Activity is empty.
5. Download the CSV for this program and place it in `raw/`.
6. Run `src/run-normalize-fidelity-snapshots.bat`.
7. Import the generated files from `normalized-holdings/` into Wealthfolio from oldest snapshot to newest.

## 💵 Cash Handling

Cash-like Fidelity rows are normalized to Wealthfolio's `$CASH` symbol.

Supported cash-like inputs:
- `SPAXX`
- `SPAXX**`
- `Cash Management (Individual)` cash rows

Cash row output behavior:
- `Symbol` becomes `$CASH`
- `Quantity` becomes the cash amount
- `Average cost basis` becomes `1`
- `Currency` stays `USD`
- `Description` is retained as a friendly label such as `Cash (SPAXX)` or `Cash (Cash Management)`

## ⚙️ Fidelity My View Columns

Configure Fidelity Positions My View to show only these columns:
- Symbol
- Current value
- Quantity
- Average cost basis
- Cost basis total
- Account type
- Currency
- Total gain/loss $
- Total gain/loss %
- Exp ratio (net)
- YTD
- Sector

Remove all other columns.

## 🧰 Usage

Use the batch file in `src/`:
- `src/run-normalize-fidelity-snapshots.bat`

It runs the PowerShell normalizer from the same folder with:
- `powershell.exe`
- `-NoProfile`
- `-ExecutionPolicy Bypass`
- `-AggregateSameSymbolRows`

## 📂 Project Structure

- `raw/`: Fidelity source CSVs.
- `src/`: PowerShell normalizer and batch launcher.
- `normalized-holdings/`: Generated Wealthfolio-ready CSVs.
- `docs/README.md`: Full guide.
- `README.md`: Short root pointer for GitHub homepage visibility.

## ⚠️ Limitations

- This project is a data normalization bridge, not financial advice.
- The workflow assumes Fidelity Positions exports are used as snapshots, not transaction history.
- Same-date duplicate Fidelity exports are handled conservatively.

## 🔗 Source References

- Fidelity: https://www.fidelity.com
- Wealthfolio codebase: https://github.com/wealthfolio/wealthfolio
- Wealthfolio product: https://wealthfolio.app