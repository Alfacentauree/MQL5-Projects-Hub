//+------------------------------------------------------------------+
//|                                       Advanced_EMA_CCI_EA.mq5    |
//|                                  Copyright 2026, Gemini CLI      |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://mql5.com"
#property version   "1.00"
#property strict

// Include Trade Class
#include <Trade\Trade.mqh>

//--- Input Parameters
input int      InpEMAPeriod   = 50;          // EMA Period
input int      InpCCI50Period = 50;          // Long-term CCI Period
input int      InpCCI25Period = 25;          // Medium-term CCI Period
input int      InpCCI14Period = 14;          // Short-term CCI Period
input double   InpLotSize     = 0.1;         // Fixed Lot Size
input int      InpSLBuffer    = 50;          // SL Buffer (Points)
input double   InpTPRatio     = 2.0;         // Take Profit (Risk:Reward Ratio)
input int      InpSwingLookback = 10;        // Swing High/Low Lookback
input int      InpMagicNumber = 123456;      // Magic Number

//--- Global Variables
int      handleEMA;
int      handleCCI50;
int      handleCCI25;
int      handleCCI14;
CTrade   trade;
datetime lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Indicator Handles
   handleEMA = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleCCI50 = iCCI(_Symbol, _Period, InpCCI50Period, PRICE_TYPICAL);
   handleCCI25 = iCCI(_Symbol, _Period, InpCCI25Period, PRICE_TYPICAL);
   handleCCI14 = iCCI(_Symbol, _Period, InpCCI14Period, PRICE_TYPICAL);

   // Validate Handles
   if(handleEMA == INVALID_HANDLE || handleCCI50 == INVALID_HANDLE || 
      handleCCI25 == INVALID_HANDLE || handleCCI14 == INVALID_HANDLE)
   {
      Print("Error: Failed to initialize indicator handles.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   lastBarTime = 0;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release Handles
   IndicatorRelease(handleEMA);
   IndicatorRelease(handleCCI50);
   IndicatorRelease(handleCCI25);
   IndicatorRelease(handleCCI14);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // New Bar Logic: Only execute at the close of a candle
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(lastBarTime == currentBarTime) return;
   
   // Check if we already have a position open for this symbol and magic number
   if(HasOpenPosition()) return;

   lastBarTime = currentBarTime;

   // Buffers to store indicator values
   double emaVal[2], cci50[2], cci25[1], cci14[1];
   
   // Copy values (Index 1 is the most recently closed candle)
   if(CopyBuffer(handleEMA, 0, 1, 2, emaVal) < 2) return;
   if(CopyBuffer(handleCCI50, 0, 1, 2, cci50) < 2) return;
   if(CopyBuffer(handleCCI25, 0, 1, 1, cci25) < 1) return;
   if(CopyBuffer(handleCCI14, 0, 1, 1, cci14) < 1) return;

   MqlTick latest_tick;
   if(!SymbolInfoTick(_Symbol, latest_tick)) return;

   double closePrice = iClose(_Symbol, _Period, 1);

   // Check Buy Signal
   // 1. Price > 50 EMA
   // 2. CCI 50 crosses above 0
   // 3. CCI 25 and 14 are > 0
   if(closePrice > emaVal[1] && cci50[1] > 0 && cci50[0] <= 0 && cci25[0] > 0 && cci14[0] > 0)
   {
      double sl = CalculateSwingLow(InpSwingLookback) - InpSLBuffer * _Point;
      double risk = latest_tick.ask - sl;
      double tp = latest_tick.ask + (risk * InpTPRatio);
      
      if(sl < latest_tick.ask)
         trade.Buy(InpLotSize, _Symbol, latest_tick.ask, sl, tp, "EMA-CCI Buy");
   }

   // Check Sell Signal
   // 1. Price < 50 EMA
   // 2. CCI 50 crosses below 0
   // 3. CCI 25 and 14 are < 0
   if(closePrice < emaVal[1] && cci50[1] < 0 && cci50[0] >= 0 && cci25[0] < 0 && cci14[0] < 0)
   {
      double sl = CalculateSwingHigh(InpSwingLookback) + InpSLBuffer * _Point;
      double risk = sl - latest_tick.bid;
      double tp = latest_tick.bid - (risk * InpTPRatio);
      
      if(sl > latest_tick.bid)
         trade.Sell(InpLotSize, _Symbol, latest_tick.bid, sl, tp, "EMA-CCI Sell");
   }
}

//+------------------------------------------------------------------+
//| Helper: Check if a position is already open                      |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Calculate Recent Swing Low                               |
//+------------------------------------------------------------------+
double CalculateSwingLow(int lookback)
{
   int lowestIdx = iLowest(_Symbol, _Period, MODE_LOW, lookback, 1);
   if(lowestIdx < 0) return iLow(_Symbol, _Period, 1);
   return iLow(_Symbol, _Period, lowestIdx);
}

//+------------------------------------------------------------------+
//| Helper: Calculate Recent Swing High                              |
//+------------------------------------------------------------------+
double CalculateSwingHigh(int lookback)
{
   int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, lookback, 1);
   if(highestIdx < 0) return iHigh(_Symbol, _Period, 1);
   return iHigh(_Symbol, _Period, highestIdx);
}
