//+------------------------------------------------------------------+
//|                                     SupertrendHeikenAshiEA.mq5   |
//|                                  Copyright 2026, ADD             |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- input parameters
input int      InpATRPeriod    = 10;        // Supertrend ATR Period
input double   InpMultiplier   = 2.0;       // Supertrend Multiplier
input double   InpRiskPercent  = 2.0;       // Risk % per trade
input int      InpTP_Points    = 400;       // Take Profit in Points
input int      InpSL_Points    = 200;       // Stop Loss in Points
input int      InpTSL_Trigger  = 150;       // Trailing Trigger (Points)
input int      InpTSL_Distance = 100;       // Trailing Distance (Points)
input long     InpMagicNum     = 555666;    // Magic Number

//--- global variables
CTrade         trade;
datetime       lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   trade.SetTypeFillingBySymbol(_Symbol);
   lastBarTime = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Trailing Stop (Every Tick)
   ManageTrailingStop();

   // 2. Strategy Logic (Only on New Bar)
   if(IsNewBar())
   {
      double stValue;
      int trend = CalculateSupertrendHA(1, stValue); // Calculate for the last completed bar

      // Trend: 1 = UP, -1 = DOWN
      if(trend == 1) // BUY SIGNAL
      {
         if(!PositionExists(POSITION_TYPE_BUY))
         {
            ClosePosition(POSITION_TYPE_SELL); // Close opposite
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = ask - InpSL_Points * _Point;
            double tp = ask + InpTP_Points * _Point;
            double lot = CalculateLot(InpSL_Points);
            trade.Buy(lot, _Symbol, ask, sl, tp, "ST-HA Buy");
         }
      }
      else if(trend == -1) // SELL SIGNAL
      {
         if(!PositionExists(POSITION_TYPE_SELL))
         {
            ClosePosition(POSITION_TYPE_BUY); // Close opposite
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = bid + InpSL_Points * _Point;
            double tp = bid - InpTP_Points * _Point;
            double lot = CalculateLot(InpSL_Points);
            trade.Sell(lot, _Symbol, bid, sl, tp, "ST-HA Sell");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Supertrend based on Heiken Ashi Values                 |
//+------------------------------------------------------------------+
int CalculateSupertrendHA(int index, double &supertrendValue)
{
   // We need more bars to calculate ATR
   int lookback = InpATRPeriod + index + 5;
   double haClose[], haOpen[], haHigh[], haLow[];
   ArraySetAsSeries(haClose, true); ArraySetAsSeries(haOpen, true);
   ArraySetAsSeries(haHigh, true);  ArraySetAsSeries(haLow, true);
   ArrayResize(haClose, lookback); ArrayResize(haOpen, lookback);
   ArrayResize(haHigh, lookback);  ArrayResize(haLow, lookback);

   // Calculate Heiken Ashi Values
   for(int i = lookback - 1; i >= 0; i--)
   {
      double o = iOpen(_Symbol, _Period, i);
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);

      haClose[i] = (o + h + l + c) / 4.0;
      if(i == lookback - 1) haOpen[i] = (o + c) / 2.0;
      else haOpen[i] = (haOpen[i+1] + haClose[i+1]) / 2.0;
      
      haHigh[i] = MathMax(h, MathMax(haOpen[i], haClose[i]));
      haLow[i]  = MathMin(l, MathMin(haOpen[i], haClose[i]));
   }

   // Calculate ATR on HA
   double atr = 0;
   for(int i = 0; i < InpATRPeriod; i++)
   {
      double tr = MathMax(haHigh[index+i] - haLow[index+i], 
                  MathMax(MathAbs(haHigh[index+i] - haClose[index+i+1]), 
                          MathAbs(haLow[index+i] - haClose[index+i+1])));
      atr += tr;
   }
   atr /= InpATRPeriod;

   // Calculate Supertrend Line
   double median = (haHigh[index] + haLow[index]) / 2.0;
   double upBand = median + InpMultiplier * atr;
   double dnBand = median - InpMultiplier * atr;

   static int trend = 0;
   static double lastST = 0;

   // Simple trend detection
   if(haClose[index] > lastST) trend = 1;
   else if(haClose[index] < lastST) trend = -1;

   supertrendValue = (trend == 1) ? dnBand : upBand;
   lastST = supertrendValue;

   return trend;
}

//+------------------------------------------------------------------+
//| Support Functions                                                |
//+------------------------------------------------------------------+
bool IsNewBar() { datetime t = iTime(_Symbol, _Period, 0); if(t != lastBarTime) { lastBarTime = t; return true; } return false; }

bool PositionExists(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetTicket(i))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNum && PositionGetInteger(POSITION_TYPE) == type) return true;
   return false;
}

void ClosePosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetTicket(i))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNum && PositionGetInteger(POSITION_TYPE) == type)
            trade.PositionClose(PositionGetTicket(i));
}

double CalculateLot(int slPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(slPoints <= 0 || tickValue <= 0 || tickSize <= 0) 
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   // Formula: Lot = Risk / (SL_Price_Distance * (TickValue / TickSize))
   double slPriceDist = slPoints * point;
   double lot = riskAmount / ((slPriceDist / tickSize) * tickValue);
   
   // Get broker constraints
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize lot to step
   lot = MathFloor(lot / step) * step;
   
   // Clamp to min/max
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   Print("Lot Calc: Balance=", NormalizeDouble(balance, 2), 
         " Risk=", NormalizeDouble(riskAmount, 2), 
         " SL_Points=", slPoints, 
         " Calculated_Lot=", lot);
   
   return NormalizeDouble(lot, 2);
}

void ManageTrailingStop()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNum && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               if((bid - open) / _Point >= InpTSL_Trigger)
               {
                  double nSL = NormalizeDouble(bid - InpTSL_Distance * _Point, _Digits);
                  if(nSL > sl || sl == 0) trade.PositionModify(PositionGetTicket(i), nSL, PositionGetDouble(POSITION_TP));
               }
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               if((open - ask) / _Point >= InpTSL_Trigger)
               {
                  double nSL = NormalizeDouble(ask + InpTSL_Distance * _Point, _Digits);
                  if(nSL < sl || sl == 0) trade.PositionModify(PositionGetTicket(i), nSL, PositionGetDouble(POSITION_TP));
               }
            }
         }
      }
   }
}
