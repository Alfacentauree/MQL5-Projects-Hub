//+------------------------------------------------------------------+
//|                                  FabioValentino_OrderFlow.mq5    |
//|                                  Copyright 2026, Gemini CLI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "1.30"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input string   sep1              = "--- Session Times (Broker Time) ---";
input int      InpBrokerHourOpen = 16;         // Broker Hour at NY Open (14:30 GMT)
input int      InpBrokerMinOpen  = 30;         // Broker Minute at NY Open
input int      InpSessionDurMin  = 30;         // Duration of Balance Range

input string   sep2              = "--- Aggression Settings ---";
input double   InpVolMultiplier  = 1.2;        // Volume Spike Multiplier (e.g. 1.2 = 120%)
input int      InpVolMAPeriod    = 20;         // Volume MA Period

input string   sep3              = "--- Risk Management ---";
input double   InpLotSize        = 0.1;        // Lot Size
input int      InpBreakEvenPts   = 50;         // Break-even at 50 points
input double   InpRewardRatio    = 3.0;        // Target RR Ratio
input int      InpMaxSpread      = 50;         // Max Spread
input long     InpMagicNum       = 555123;     // Magic Number

//--- Global Variables
CTrade         trade;
double         rangeHigh = 0, rangeLow = 0;
bool           isRangeSet = false;
bool           isBrokenOut = false;
int            breakoutDir = 0; 
datetime       lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   trade.SetDeviationInPoints(5);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Check Breakout                                                   |
//+------------------------------------------------------------------+
void CheckBreakout(double price)
{
   if(price > rangeHigh) { isBrokenOut = true; breakoutDir = 1; Print("Bullish Breakout Detected at ", price); }
   else if(price < rangeLow) { isBrokenOut = true; breakoutDir = -1; Print("Bearish Breakout Detected at ", price); }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBar != lastBarTime);
   if(isNewBar) lastBarTime = currentBar;

   MqlDateTime dt;
   TimeCurrent(dt); 
   int currentMinOfDay = dt.hour * 60 + dt.min;
   int startMin = InpBrokerHourOpen * 60 + InpBrokerMinOpen;
   int endMin = startMin + InpSessionDurMin;

   // 1. Manage Range Calculation
   if(!isRangeSet && currentMinOfDay >= endMin)
   {
      MqlDateTime st = dt;
      st.hour = InpBrokerHourOpen;
      st.min = InpBrokerMinOpen;
      st.sec = 0;
      datetime rangeStart = StructToTime(st);
      datetime rangeEnd = rangeStart + (InpSessionDurMin * 60);
      
      int startShift = iBarShift(_Symbol, _Period, rangeStart);
      int endShift = iBarShift(_Symbol, _Period, rangeEnd);
      
      if(startShift > endShift)
      {
         int count = startShift - endShift + 1;
         rangeHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, count, endShift));
         rangeLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, count, endShift));
         isRangeSet = (rangeHigh > 0 && rangeLow > 0);
         if(isRangeSet) Print("NY Range Defined: ", rangeHigh, " - ", rangeLow, " (Bars: ", count, ")");
      }
   }

   if(!isRangeSet) 
   {
      if(isNewBar) Print("Waiting for NY Session... Current Broker Time: ", dt.hour, ":", dt.min, " (Target: ", InpBrokerHourOpen, ":", InpBrokerMinOpen, ")");
      return;
   }

   // 2. Strategy Execution
   double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2.0;

   if(!isBrokenOut) CheckBreakout(mid);

   if(isNewBar && isBrokenOut && !PositionSelectByMagic(_Symbol, InpMagicNum))
   {
      if(CheckAggressiveRetest())
      {
         ExecuteOrder();
      }
   }
   
   ManagePositions();
   
   // Reset at Midnight
   if(dt.hour == 0 && dt.min == 0) { isRangeSet = false; isBrokenOut = false; breakoutDir = 0; }
}

//+------------------------------------------------------------------+
//| Check Retest + Aggression                                        |
//+------------------------------------------------------------------+
bool CheckAggressiveRetest()
{
   bool isLocationValid = false;
   double low1 = iLow(_Symbol, _Period, 1);
   double high1 = iHigh(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);

   // Retest Check: Bar 1 low/high should be near range boundary or retesting FVG
   if(breakoutDir == 1)
   {
      // If bar 1 low is within 50 points of rangeHigh or retesting FVG
      if(low1 <= rangeHigh + (50 * _Point)) isLocationValid = true;
      if(!isLocationValid) isLocationValid = IsRetestingFVG(1);
      
      if(!isLocationValid) Print("Retest Failed: Bar Low (", low1, ") is too far from Range High (", rangeHigh, ")");
   }
   else if(breakoutDir == -1)
   {
      if(high1 >= rangeLow - (50 * _Point)) isLocationValid = true;
      if(!isLocationValid) isLocationValid = IsRetestingFVG(-1);

      if(!isLocationValid) Print("Retest Failed: Bar High (", high1, ") is too far from Range Low (", rangeLow, ")");
   }

   if(!isLocationValid) return false;

   // Aggression Check
   long volumes[];
   ArraySetAsSeries(volumes, true);
   if(CopyTickVolume(_Symbol, _Period, 0, InpVolMAPeriod + 2, volumes) < InpVolMAPeriod + 2) return false;
   
   double avgVol = 0;
   for(int i=2; i<=InpVolMAPeriod+1; i++) avgVol += (double)volumes[i];
   avgVol /= (double)InpVolMAPeriod;
   
   double volRatio = (avgVol > 0) ? ((double)volumes[1] / avgVol) : 0;
   
   if(volRatio < InpVolMultiplier) 
   {
      Print("Aggression Failed: Volume Ratio ", volRatio, " < Required ", InpVolMultiplier);
      return false;
   }
   
   double open1 = iOpen(_Symbol, _Period, 1);
   bool isCorrectCandle = (breakoutDir == 1) ? (close1 > open1) : (close1 < open1);

   if(!isCorrectCandle) Print("Aggression Failed: Candle color wrong (Need Bullish for Buy, Bearish for Sell)");

   if(isLocationValid && volRatio >= InpVolMultiplier && isCorrectCandle) 
   {
      Print("STRATEGY SIGNAL! Retest OK, Volume Ratio: ", volRatio, ". Executing...");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| FVG Logic                                                        |
//+------------------------------------------------------------------+
bool IsRetestingFVG(int dir)
{
   for(int i=1; i<10; i++)
   {
      double h3 = iHigh(_Symbol, _Period, i+2);
      double l1 = iLow(_Symbol, _Period, i);
      double l3 = iLow(_Symbol, _Period, i+2);
      double h1 = iHigh(_Symbol, _Period, i);
      
      if(dir == 1 && h3 < l1) 
      {
         if(iLow(_Symbol, _Period, 1) <= l1 && iLow(_Symbol, _Period, 1) >= h3) return true;
         break;
      }
      else if(dir == -1 && l3 > h1)
      {
         if(iHigh(_Symbol, _Period, 1) >= h1 && iHigh(_Symbol, _Period, 1) <= l3) return true;
         break;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute Order                                                    |
//+------------------------------------------------------------------+
void ExecuteOrder()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Spread Check
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > InpMaxSpread)
   {
      Print("Trade Aborted: Spread (", currentSpread, ") > MaxSpread (", InpMaxSpread, ")");
      return;
   }

   if(breakoutDir == 1)
   {
      double sl = iLow(_Symbol, _Period, 1) - (5 * _Point);
      double tp = ask + ((ask - sl) * InpRewardRatio);
      if(trade.Buy(InpLotSize, _Symbol, ask, NormalizeDouble(sl, digits), NormalizeDouble(tp, digits)))
         Print("BUY Order Placed successfully!");
      else
         Print("BUY Order FAILED: ", trade.ResultRetcodeDescription());
   }
   else if(breakoutDir == -1)
   {
      double sl = iHigh(_Symbol, _Period, 1) + (5 * _Point);
      double tp = bid - ((sl - bid) * InpRewardRatio);
      if(trade.Sell(InpLotSize, _Symbol, bid, NormalizeDouble(sl, digits), NormalizeDouble(tp, digits)))
         Print("SELL Order Placed successfully!");
      else
         Print("SELL Order FAILED: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Manage Positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNum)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               if(currentPrice - openPrice >= InpBreakEvenPts * _Point && currentSL < openPrice)
                  trade.PositionModify(ticket, NormalizeDouble(openPrice + (1 * _Point), _Digits), PositionGetDouble(POSITION_TP));
            }
            else
            {
               if(openPrice - currentPrice >= InpBreakEvenPts * _Point && (currentSL > openPrice || currentSL == 0))
                  trade.PositionModify(ticket, NormalizeDouble(openPrice - (1 * _Point), _Digits), PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Select position by magic number                                  |
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
