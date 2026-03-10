//+------------------------------------------------------------------+
//|                                     BollingerBands_Scalper.mq5   |
//|                                  Copyright 2026, Gemini CLI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- input parameters
input int      InpLength     = 20;         // BB Length
input double   InpMult       = 2.0;        // BB Multiplier
input int      InpWickRatio  = 2.0;        // Wick to Body Ratio (Min)
input int      InpMinBreach  = 50;         // Min Breach outside Band (Points/10 for Pips)
input int      InpDirection  = 0;          // Strategy Direction (-1: Short, 0: Both, 1: Long)

input string   sep2          = "--- Money Management ---";
input bool     InpUseRisk    = true;       // Use Risk Percentage (%)
input double   InpRiskPercent= 1.0;        // Risk % per Trade
input double   InpLotSize    = 0.1;        // Fixed Lot Size (if Risk is off)
input int      InpWaitMin    = 15;         // Wait minutes after trade close
input long     InpMagicNum   = 987654;     // EA Magic Number (Unique)

input string   sep3          = "--- Session Filter (GMT) ---";
input bool     InpUseAsia    = false;      // Use Asia Session
input int      InpAsiaStart  = 0;          // Asia Start (GMT Hour)
input int      InpAsiaEnd    = 9;          // Asia End (GMT Hour)

input bool     InpUseLondon  = true;       // Use London Session
input int      InpLondonStart= 8;          // London Start (GMT Hour)
input int      InpLondonEnd  = 17;         // London End (GMT Hour)

input bool     InpUseNY      = true;       // Use New York Session
input int      InpNYStart    = 13;         // NY Start (GMT Hour)
input int      InpNYEnd      = 22;         // NY End (GMT Hour)

//--- global variables
int            handleBB;                  // Handle for iBands indicator
CTrade         trade;                     // Trade class instance
double         upperBand[], lowerBand[], basisBand[];
datetime       lastExitTime = 0;          // Global tracker for cooldown
bool           wasPositionOpen = false;    // To detect when a position closes

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   handleBB = iBands(_Symbol, _Period, InpLength, 0, InpMult, PRICE_CLOSE);
   if(handleBB == INVALID_HANDLE) { Print("Failed to create BB handle"); return(INIT_FAILED); }
   
   ArraySetAsSeries(upperBand, true);
   ArraySetAsSeries(lowerBand, true);
   ArraySetAsSeries(basisBand, true);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { IndicatorRelease(handleBB); }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Monitor Position Changes for Cooldown
   bool isPositionOpen = PositionSelectByMagic(_Symbol, InpMagicNum);
   if(wasPositionOpen && !isPositionOpen) // Position just closed
   {
      lastExitTime = TimeCurrent();
      Print("Position Closed. Cooldown started.");
   }
   wasPositionOpen = isPositionOpen;

   // 2. Cooldown Check
   if(!isPositionOpen && lastExitTime > 0)
   {
      long secondsPassed = TimeCurrent() - lastExitTime;
      if(secondsPassed < InpWaitMin * 60) return; 
   }

   // 3. Copy indicator data
   if(CopyBuffer(handleBB, 0, 0, 2, basisBand) < 0 ||
      CopyBuffer(handleBB, 1, 0, 2, upperBand) < 0 || 
      CopyBuffer(handleBB, 2, 0, 2, lowerBand) < 0) return;
   
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   
   double bodySize  = MathAbs(open1 - close1);
   double upperWick = high1 - MathMax(open1, close1);
   double lowerWick = MathMin(open1, close1) - low1;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // 4. Entry Signals (Long Wick Rejection + GMT Session)
   if(!isPositionOpen)
   {
      MqlDateTime dtGMT;
      TimeToStruct(TimeGMT(), dtGMT); // Use GMT Time
      int hourGMT = dtGMT.hour;
      
      bool isWithinSession = false;
      
      // Check GMT Sessions
      if(InpUseAsia && (hourGMT >= InpAsiaStart && hourGMT < InpAsiaEnd)) isWithinSession = true;
      if(InpUseLondon && (hourGMT >= InpLondonStart && hourGMT < InpLondonEnd)) isWithinSession = true;
      if(InpUseNY && (hourGMT >= InpNYStart && hourGMT < InpNYEnd)) isWithinSession = true;
      
      // If no sessions are selected, allow 24/7 trading
      if(!InpUseAsia && !InpUseLondon && !InpUseNY) isWithinSession = true;

      if(isWithinSession)
      {
         double minBreach = InpMinBreach * _Point;

         // Rejection Conditions (Candle 1 must touch band but close/open inside)
         bool isLowerRejection = (low1 <= (lowerBand[1] - minBreach) && close1 > lowerBand[1] && open1 > lowerBand[1] && lowerWick >= (bodySize * InpWickRatio));
         bool isUpperRejection = (high1 >= (upperBand[1] + minBreach) && close1 < upperBand[1] && open1 < upperBand[1] && upperWick >= (bodySize * InpWickRatio));

         // Long Signal
         if(isLowerRejection && (InpDirection == 0 || InpDirection == 1))
         {
            double sl = low1;
            double lot = InpLotSize;
            if(InpUseRisk) lot = CalculateLotSize(ask, sl);
            
            if(lowerWick > 0) trade.Buy(lot, _Symbol, ask, sl, 0, "BB_Wick_Buy");
         }
         // Short Signal
         else if(isUpperRejection && (InpDirection == 0 || InpDirection == -1))
         {
            double sl = high1;
            double lot = InpLotSize;
            if(InpUseRisk) lot = CalculateLotSize(bid, sl);

            if(upperWick > 0) trade.Sell(lot, _Symbol, bid, sl, 0, "BB_Wick_Sell");
         }
      }
   }

   // 5. Dynamic Trailing Stop (Follows Opposite Band)
   if(isPositionOpen)
   {
      ulong ticket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(PositionSelectByTicket(t))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNum)
            {
               ticket = t;
               break;
            }
         }
      }

      if(ticket > 0)
      {
         double currentSL = PositionGetDouble(POSITION_SL);
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            // Activate Trailing after price touches/crosses Middle Band
            if(bid >= basisBand[0] || currentSL > 0) 
            {
               double newSL = NormalizeDouble(lowerBand[0], digits);
               if(MathAbs(newSL - currentSL) > _Point || currentSL == 0)
                  trade.PositionModify(ticket, newSL, 0);
            }
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            // Activate Trailing after price touches/crosses Middle Band
            if(ask <= basisBand[0] || currentSL > 0)
            {
               double newSL = NormalizeDouble(upperBand[0], digits);
               if(MathAbs(newSL - currentSL) > _Point || currentSL == 0)
                  trade.PositionModify(ticket, newSL, 0);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Select position by magic number and symbol                       |
//+------------------------------------------------------------------+
bool PositionSelectByMagic(string symbol, long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk %                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double price, double sl)
{
   if(sl <= 0 || price == sl) return InpLotSize;

   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0) return InpLotSize;

   double slPoints = MathAbs(price - sl) / tickSize;
   double lot = riskAmount / (slPoints * tickValue);

   // Normalize Lot Size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;

   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}
