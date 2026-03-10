# MQL5 Projects Hub

A collection of MetaTrader 5 Expert Advisors (EAs) focusing on scalping, trend-following, and volatility-based strategies.

## Included EAs

### 1. BollingerBands_Scalper.mq5
- **Strategy:** Scalping based on Bollinger Band wick rejections.
- **Key Features:** 
  - Dynamic Wick-to-Body ratio filtering.
  - Minimum breach (points) requirement for band rejection.
  - Risk Management: Percentage-based lot sizing (Account Risk %) or Fixed Lots.
  - Dynamic Trailing Stop following opposite bands.
  - GMT Session Filters (Asia, London, NY).

### 2. BollingerBandsEA.mq5
- **Strategy:** Classic Bollinger Band mean reversion/breakout strategy.
- **Key Features:**
  - Standard entry on band touches/closes.
  - Dynamic Trailing Stop.
  - Session filters.

### 3. Advanced_EMA_CCI_EA.mq5
- **Strategy:** Trend-following using Exponential Moving Averages (EMA) and Commodity Channel Index (CCI).

### 4. ChannelBreakOutEA.mq5
- **Strategy:** Momentum trading based on price channel breakouts.

### 5. FabioValentino_OrderFlow.mq5
- **Strategy:** Order flow-based trading logic.

### 6. ScalperFractalEA_V10.mq5
- **Strategy:** Fractal-based scalping for high-frequency price action.

### 7. SupertrendHeikenAshiEA.mq5
- **Strategy:** Combination of Supertrend indicator and Heiken Ashi candles for trend clarity.

## Installation
1. Copy the `.mq5` files to your MT5 `MQL5/Experts/` folder.
2. Compile the files in MetaEditor or restart MT5.
3. Attach the EA to your desired chart and configure the input parameters.

## License
MIT License
