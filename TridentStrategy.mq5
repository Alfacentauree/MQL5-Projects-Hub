//+------------------------------------------------------------------+
//|                                              TridentStrategy.mq5 |
//|                                  Copyright 2024, ADD             |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input int      InpStartHourNY   = 3;           // Start Hour (NY)
input int      InpEndHourNY     = 6;           // End Hour (NY)
input int      InpEndMinNY      = 30;          // End Minute (NY)
input int      InpGMTOffset     = 2;           // Broker GMT Offset
input int      InpEMA5          = 5;           // EMA 5 Period
input int      InpEMA9          = 9;           // EMA 9 Period
input int      InpEMA13         = 13;          // EMA 13 Period
input int      InpEMA21         = 21;          // EMA 21 Period
input int      InpEMA200        = 200;         // EMA 200 Period
input double   InpRiskPercent   = 1.0;         // Risk per trade (%)
input double   InpFixedLot      = 0.0;         // Fixed Lot (0 for risk-based)
input double   InpMinRR         = 20.0;        // Minimum RR (1:20)
input bool     InpGoldSpecial   = true;        // XAUUSD Special Rule (Candle Close SL)
input int      InpMinSLPoints   = 100;         // Minimum SL Distance in Points (100 = 1.00 Gold)
input double   InpSafetySLMult  = 3.0;         // Safety Hard SL Multiplier (x Doji Range)

//--- Global handles
int hEMA5, hEMA9, hEMA13, hEMA21, hEMA200;
CTrade trade;

//--- State variables
struct ST_Setup {
    bool     active;
    datetime time;
    double   fvg_ce;      // 50% level
    double   doji_high;
    double   doji_low;
    bool     doji_found;
    bool     invalidated;
};

ST_Setup current_setup;
datetime last_setup_day = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    hEMA5   = iMA(_Symbol, _Period, InpEMA5, 0, MODE_EMA, PRICE_CLOSE);
    hEMA9   = iMA(_Symbol, _Period, InpEMA9, 0, MODE_EMA, PRICE_CLOSE);
    hEMA13  = iMA(_Symbol, _Period, InpEMA13, 0, MODE_EMA, PRICE_CLOSE);
    hEMA21  = iMA(_Symbol, _Period, InpEMA21, 0, MODE_EMA, PRICE_CLOSE);
    hEMA200 = iMA(_Symbol, _Period, InpEMA200, 0, MODE_EMA, PRICE_CLOSE);

    if(hEMA5 == INVALID_HANDLE || hEMA200 == INVALID_HANDLE) {
        Print("Error creating indicators");
        return(INIT_FAILED);
    }

    trade.SetExpertMagicNumber(123456);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(hEMA5);
    IndicatorRelease(hEMA9);
    IndicatorRelease(hEMA13);
    IndicatorRelease(hEMA21);
    IndicatorRelease(hEMA200);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 1. One setup per day per pair
    datetime current_day = iTime(_Symbol, PERIOD_D1, 0);
    if(current_day != last_setup_day) {
        last_setup_day = current_day;
        current_setup.active = false;
        current_setup.doji_found = false;
        current_setup.invalidated = false;
    }

    if(PositionsTotal() > 0) {
        CheckVirtualSL();
        return;
    }

    if(current_setup.invalidated) return;

    // 2. NY Time Window Check
    if(!IsNewYorkTime()) return;

    // 3. Trend Alignment
    if(!CheckTrend()) return;

    // 4. FVG Detection
    if(!current_setup.active) {
        DetectFVG();
    }

    // 5. Trident (Doji) Logic
    if(current_setup.active && !current_setup.doji_found) {
        DetectDoji();
    }

    // 6. Entry Logic
    if(current_setup.doji_found && !current_setup.invalidated) {
        ManageEntry();
    }
}

//+------------------------------------------------------------------+
//| Helper: Check if current time is within NY window                |
//+------------------------------------------------------------------+
bool IsNewYorkTime()
{
    MqlDateTime dt;
    TimeCurrent(dt);
    
    // Simple GMT offset conversion. 
    // NY is GMT-5 (Standard) or GMT-4 (DST). 
    // Usually, Brokers are GMT+2 or GMT+3.
    // Adjusted logic: (Current Broker Time - InpGMTOffset) = GMT.
    // GMT - 5 = NY.
    
    int ny_hour = dt.hour - InpGMTOffset - 5; 
    if(ny_hour < 0) ny_hour += 24;
    
    // Check window 03:00 to 06:30 NY
    if(ny_hour < InpStartHourNY) return false;
    if(ny_hour > InpEndHourNY) return false;
    if(ny_hour == InpEndHourNY && dt.min > InpEndMinNY) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Helper: Check EMAs for alignment and slope                       |
//+------------------------------------------------------------------+
bool CheckTrend()
{
    double e5[2], e9[2], e13[2], e21[2], e200[1], close[1];
    if(CopyBuffer(hEMA5, 0, 0, 2, e5) < 2) return false;
    if(CopyBuffer(hEMA9, 0, 0, 2, e9) < 2) return false;
    if(CopyBuffer(hEMA13, 0, 0, 2, e13) < 2) return false;
    if(CopyBuffer(hEMA21, 0, 0, 2, e21) < 2) return false;
    if(CopyBuffer(hEMA200, 0, 0, 1, e200) < 1) return false;
    if(CopyClose(_Symbol, _Period, 0, 1, close) < 1) return false;

    // Price > 200 EMA
    if(close[0] < e200[0]) return false;

    // Stacked: 5 > 9 > 13 > 21
    if(!(e5[0] > e9[0] && e9[0] > e13[0] && e13[0] > e21[0])) return false;

    // Sloping Upwards (Current > Previous)
    if(!(e5[0] > e5[1] && e9[0] > e9[1] && e13[0] > e13[1] && e21[0] > e21[1])) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Helper: Detect Bullish FVG                                       |
//+------------------------------------------------------------------+
void DetectFVG()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 1, 3, rates) < 3) return;

    // Bullish FVG: Candle 1 High < Candle 3 Low (MQL5 index: 0 is oldest, 2 is newest)
    // Actually, in ICT Candle 1 High < Candle 3 Low is the gap.
    if(rates[0].high < rates[2].low) {
        current_setup.active = true;
        current_setup.fvg_ce = rates[0].high + (rates[2].low - rates[0].high) / 2.0;
        current_setup.time = rates[1].time;
        Print("FVG Detected at CE: ", current_setup.fvg_ce);
    }
}

//+------------------------------------------------------------------+
//| Helper: Detect Doji and Wick Touch                               |
//+------------------------------------------------------------------+
void DetectDoji()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1) return;

    double body = MathAbs(rates[0].open - rates[0].close);
    double range = rates[0].high - rates[0].low;

    if(range == 0) return;

    // Doji: Body < 10% of total range
    if(body < (range * 0.1)) {
        // Wick wicks into FVG CE
        if(rates[0].low <= current_setup.fvg_ce) {
            current_setup.doji_found = true;
            current_setup.doji_high = rates[0].high;
            current_setup.doji_low = rates[0].low;
            Print("Doji Found and Wick Touch. High: ", current_setup.doji_high, " Low: ", current_setup.doji_low);
        }
    }
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
{
    // High RR strategies are best judged by profit factor or recovery factor
    double profit = TesterStatistics(STAT_PROFIT);
    double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    if(dd <= 0) return profit;
    return profit / dd;
}

//+------------------------------------------------------------------+
//| Helper: Manage Entry and Validation                              |
//+------------------------------------------------------------------+
void ManageEntry()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1) return;

    // Validation: The candle following the Doji must NOT close above the Doji’s high before the entry is triggered.
    // If it closes above, invalidate.
    static datetime doji_time = 0;
    if(doji_time == 0) doji_time = rates[0].time;

    // If a new bar has formed since the Doji
    if(rates[0].time > doji_time) {
        MqlRates prev_rate[];
        if(CopyRates(_Symbol, _Period, 1, 1, prev_rate) > 0) {
            if(prev_rate[0].close > current_setup.doji_high) {
                current_setup.invalidated = true;
                Print("Setup Invalidated: Candle closed above Doji High (", prev_rate[0].close, " > ", current_setup.doji_high, ")");
                return;
            }
        }
    }

    // Trigger: Buy at Doji High
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(current_price >= current_setup.doji_high) {
        ExecuteTrade();
    }
}

//+------------------------------------------------------------------+
//| Helper: Normalize Lot Size                                       |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double normalized = NormalizeDouble(lot / step, 0) * step;
    if(normalized < min_lot) normalized = min_lot;
    if(normalized > max_lot) normalized = max_lot;
    
    return NormalizeDouble(normalized, 2);
}

//+------------------------------------------------------------------+
//| Helper: Execute Trade with Risk Management                       |
//+------------------------------------------------------------------+
void ExecuteTrade()
{
    double sl_dist = current_setup.doji_high - current_setup.doji_low;
    // Enforce minimum SL distance in points to avoid crazy lot sizes
    if(sl_dist < InpMinSLPoints * _Point) {
        sl_dist = InpMinSLPoints * _Point;
    }

    double entry = current_setup.doji_high;
    double sl = entry - sl_dist;
    double risk_points = sl_dist / _Point;
    
    if(risk_points <= 0) return;

    double tp = entry + (risk_points * _Point * InpMinRR);
    
    double lot = InpFixedLot;
    if(lot <= 0) {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double risk_amount = balance * (InpRiskPercent / 100.0);
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        if(tick_value <= 0) tick_value = 1.0;
        if(tick_size <= 0) tick_size = _Point;
        
        lot = risk_amount / (risk_points * _Point * tick_value / tick_size);
        lot = NormalizeLot(lot);
    }

    // Check XAUUSD special rule for SL
    double hard_sl = sl;
    string sym = _Symbol;
    StringToUpper(sym);
    if(InpGoldSpecial && (StringFind(sym, "XAUUSD") >= 0 || StringFind(sym, "GOLD") >= 0)) {
        // Use a Safety Hard SL (far away) to prevent account wipeout if candle close logic fails to fire in time
        hard_sl = entry - (sl_dist * InpSafetySLMult);
    }

    if(trade.Buy(lot, _Symbol, 0, hard_sl, tp, "Trident EA")) {
        current_setup.active = false;
        current_setup.doji_found = false;
        current_setup.invalidated = true; // One trade per day
        Print("Trade Opened. Lot: ", lot, " TP: ", tp, " Safety SL: ", hard_sl);
    }
}

//+------------------------------------------------------------------+
//| Helper: Gold Special Rule - Close on Candle Close                |
//+------------------------------------------------------------------+
void CheckVirtualSL()
{
    if(!(InpGoldSpecial && (_Symbol == "XAUUSD" || _Symbol == "GOLD"))) return;

    // Only check on bar close
    static datetime last_bar = 0;
    datetime current_bar = iTime(_Symbol, _Period, 0);
    if(current_bar == last_bar) return;
    last_bar = current_bar;

    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 1, 1, rates) < 1) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
                if(rates[0].close < current_setup.doji_low) {
                    trade.PositionClose(PositionGetTicket(i));
                    Print("Gold Special: Position closed on 30m candle close below Doji low");
                }
            }
        }
    }
}
