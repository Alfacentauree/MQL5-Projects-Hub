//+------------------------------------------------------------------+
//|                                     BollingerBands_Scalper.mq5   |
//|                                  Copyright 2026, ADD             |
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
input bool     InpUsePropMode= true;       // Use Propfirm Mode (Fixed $ Risk)
input double   InpRiskDollar = 50.0;       // Risk Amount in Dollars ($)
input bool     InpUseRiskPct = false;      // Use Risk Percentage (%) for Lots
input double   InpRiskPercent= 1.0;        // Risk % per Trade
input double   InpLotSize    = 0.1;        // Fixed Lot Size (if Risk is off)
input int      InpWaitMin    = 15;         // Wait minutes after trade close
input int      InpBufferPoints = 100;      // Safety Buffer from BB (Points - BTC safe: 100+)
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
bool           indicatorAdded = false;     // Visual check for chart display

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
   // Visual display once
   if(!indicatorAdded && MQLInfoInteger(MQL_VISUAL_MODE) == 0)
   {
      if(ChartIndicatorAdd(0, 0, handleBB)) indicatorAdded = true;
   }

   // 1. Monitor Position Changes for Cooldown
   bool isPositionOpen = PositionSelectByMagic(_Symbol, InpMagicNum);
   if(wasPositionOpen && !isPositionOpen) 
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

   // 4. Entry Signals
   if(!isPositionOpen)
   {
      MqlDateTime dtGMT;
      TimeToStruct(TimeGMT(), dtGMT);
      int hourGMT = dtGMT.hour;
      
      bool isWithinSession = false;
      if(InpUseAsia && (hourGMT >= InpAsiaStart && hourGMT < InpAsiaEnd)) isWithinSession = true;
      if(InpUseLondon && (hourGMT >= InpLondonStart && hourGMT < InpLondonEnd)) isWithinSession = true;
      if(InpUseNY && (hourGMT >= InpNYStart && hourGMT < InpNYEnd)) isWithinSession = true;
      if(!InpUseAsia && !InpUseLondon && !InpUseNY) isWithinSession = true;

      if(isWithinSession)
      {
         double minBreach = InpMinBreach * _Point;
         bool isLowerRejection = (low1 <= (lowerBand[1] - minBreach) && close1 > lowerBand[1] && open1 > lowerBand[1] && lowerWick >= (bodySize * InpWickRatio));
         bool isUpperRejection = (high1 >= (upperBand[1] + minBreach) && close1 < upperBand[1] && open1 < upperBand[1] && upperWick >= (bodySize * InpWickRatio));

         if(isLowerRejection && (InpDirection == 0 || InpDirection == 1))
         {
            double sl = low1;
            if(InpUsePropMode) sl = CalculateSLByDollar(ask, POSITION_TYPE_BUY);
            
            double lot = InpLotSize;
            if(InpUseRiskPct) lot = CalculateLotSize(ask, sl);
            
            trade.Buy(lot, _Symbol, ask, sl, 0, "BB_Wick_Buy");
         }
         else if(isUpperRejection && (InpDirection == 0 || InpDirection == -1))
         {
            double sl = high1;
            if(InpUsePropMode) sl = CalculateSLByDollar(bid, POSITION_TYPE_SELL);
            
            double lot = InpLotSize;
            if(InpUseRiskPct) lot = CalculateLotSize(bid, sl);

            trade.Sell(lot, _Symbol, bid, sl, 0, "BB_Wick_Sell");
         }
      }
   }

   // 5. Dynamic Trailing Stop (Safety Logic)
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
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
         double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
         double brokerMin = MathMax(stopLevel, freezeLevel) + (10 * _Point);
         double userBuffer = InpBufferPoints * _Point;
         double finalBuffer = MathMax(brokerMin, userBuffer);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double emergencySL = CalculateSLByDollar(openPrice, POSITION_TYPE_BUY);
            bool isTrailingActive = (currentSL > 0 && currentSL > emergencySL + _Point);
            bool triggerReached = (bid >= basisBand[0]);

            if(triggerReached || isTrailingActive) 
            {
               double newSL = NormalizeDouble(lowerBand[0] - finalBuffer, digits);
               if(newSL < (bid - brokerMin) && (newSL > currentSL || currentSL == 0))
               {
                  if(MathAbs(newSL - currentSL) > _Point)
                     trade.PositionModify(ticket, newSL, 0);
               }
            }
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double emergencySL = CalculateSLByDollar(openPrice, POSITION_TYPE_SELL);
            bool isTrailingActive = (currentSL > 0 && currentSL < emergencySL - _Point);
            bool triggerReached = (ask <= basisBand[0]);

            if(triggerReached || isTrailingActive)
            {
               double newSL = NormalizeDouble(upperBand[0] + finalBuffer, digits);
               if(newSL > (ask + brokerMin) && (newSL < currentSL || currentSL == 0))
               {
                  if(MathAbs(newSL - currentSL) > _Point)
                     trade.PositionModify(ticket, newSL, 0);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate SL Price based on Fixed Dollar Risk                    |
//+------------------------------------------------------------------+
double CalculateSLByDollar(double entryPrice, ENUM_POSITION_TYPE type)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(tickValue <= 0 || InpLotSize <= 0) return 0;

   double points = InpRiskDollar / (InpLotSize * (tickValue / tickSize));
   
   double slPrice = 0;
   if(type == POSITION_TYPE_BUY)
      slPrice = NormalizeDouble(entryPrice - points, digits);
   else
      slPrice = NormalizeDouble(entryPrice + points, digits);

   return slPrice;
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
