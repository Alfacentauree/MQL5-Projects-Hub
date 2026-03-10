//+------------------------------------------------------------------+
//|                                         ScalperFractalEA_V9_1.mq5|
//|                                  Copyright 2026, Gemini CLI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "9.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- input parameters
input int      InpBars_N       = 5;         // Fractal N (5 Left + 5 Right)
input double   InpRiskPercent  = 2.0;       // Risk % per trade
input int      InpTP_Points    = 200;       // Take Profit in Points
input int      InpSL_Points    = 200;       // Stop Loss in Points
input int      InpTSL_Trigger  = 150;       // Trailing Stop Trigger (Points)
input int      InpTSL_Distance = 100;       // Trailing Stop Distance (Points)
input int      InpOrderDist    = 20;        // Order Distance (Points)
input int      InpStart_Hour   = 7;         // Trading Start Hour
input int      InpEnd_Hour     = 21;        // Trading End Hour
input long     InpMagicNum     = 987654;    // Magic Number

//--- global variables
CTrade         trade;
COrderInfo     orderInfo;
CPositionInfo  posInfo;
datetime       lastBarTime;
datetime       lastHighFractalTime = 0;
datetime       lastLowFractalTime  = 0;

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
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "FrBox_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageTrailingStop();

   if(!IsTradingTime())
   {
      DeletePendingOrders();
      ObjectsDeleteAll(0, "FrBox_");
      return;
   }

   // Strategy Logic: Check on every tick for orders, but use New Bar to trigger scans
   if(IsNewBar())
   {
      CheckAndPlaceFractalOrders();
   }
}

//+------------------------------------------------------------------+
//| Scan for Latest Fractals and Place Both Buy/Sell Stop Orders     |
//+------------------------------------------------------------------+
void CheckAndPlaceFractalOrders()
{
   int n = InpBars_N;
   int scanLimit = 30; // Scan back 30 bars to find the latest valid fractals
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   datetime expireTime = TimeCurrent() + PeriodSeconds(_Period) * 100;

   // --- SCAN FOR LATEST HIGH FRACTAL (BUY STOP) ---
   if(CountPendingOrders(ORDER_TYPE_BUY_STOP) == 0 && !PositionExists(POSITION_TYPE_BUY))
   {
      for(int i = n + 1; i < n + 1 + scanLimit; i++)
      {
         if(IsFractalHigh(i))
         {
            datetime midTime = iTime(_Symbol, _Period, i);
            double midHigh = iHigh(_Symbol, _Period, i);
            double entry = NormalizeDouble(midHigh + InpOrderDist * point, _Digits);
            
            if(entry < ask + stopLevel) entry = NormalizeDouble(ask + stopLevel + point, _Digits);
            
            double sl = NormalizeDouble(entry - InpSL_Points * point, _Digits);
            double tp = NormalizeDouble(entry + InpTP_Points * point, _Digits);
            double lot = CalculateLot(InpSL_Points);
            
            if(lot > 0)
            {
               if(trade.BuyStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expireTime, "BS Fractal"))
               {
                  DrawBox("High", midTime, midHigh, iLow(_Symbol, _Period, i), clrLime);
                  Print("Buy Stop placed on Latest Fractal High at bar ", i);
               }
            }
            break; // Found the latest, stop scanning for High
         }
      }
   }

   // --- SCAN FOR LATEST LOW FRACTAL (SELL STOP) ---
   if(CountPendingOrders(ORDER_TYPE_SELL_STOP) == 0 && !PositionExists(POSITION_TYPE_SELL))
   {
      for(int i = n + 1; i < n + 1 + scanLimit; i++)
      {
         if(IsFractalLow(i))
         {
            datetime midTime = iTime(_Symbol, _Period, i);
            double midLow = iLow(_Symbol, _Period, i);
            double entry = NormalizeDouble(midLow - InpOrderDist * point, _Digits);
            
            if(entry > bid - stopLevel) entry = NormalizeDouble(bid - stopLevel - point, _Digits);
            
            double sl = NormalizeDouble(entry + InpSL_Points * point, _Digits);
            double tp = NormalizeDouble(entry - InpTP_Points * point, _Digits);
            double lot = CalculateLot(InpSL_Points);
            
            if(lot > 0)
            {
               if(trade.SellStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expireTime, "SS Fractal"))
               {
                  DrawBox("Low", midTime, iHigh(_Symbol, _Period, i), midLow, clrRed);
                  Print("Sell Stop placed on Latest Fractal Low at bar ", i);
               }
            }
            break; // Found the latest, stop scanning for Low
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Fractal Logic: Checks N bars on both sides                       |
//+------------------------------------------------------------------+
bool IsFractalHigh(int index)
{
   double val = iHigh(_Symbol, _Period, index);
   for(int k = 1; k <= InpBars_N; k++)
   {
      if(iHigh(_Symbol, _Period, index + k) > val)  return false; // Left
      if(iHigh(_Symbol, _Period, index - k) >= val) return false; // Right
   }
   return true;
}

bool IsFractalLow(int index)
{
   double val = iLow(_Symbol, _Period, index);
   for(int k = 1; k <= InpBars_N; k++)
   {
      if(iLow(_Symbol, _Period, index + k) < val)  return false; // Left
      if(iLow(_Symbol, _Period, index - k) <= val) return false; // Right
   }
   return true;
}

//+------------------------------------------------------------------+
//| Visual Box Drawing                                               |
//+------------------------------------------------------------------+
void DrawBox(string type, datetime time, double hi, double lo, color clr)
{
   string name = "FrBox_" + type + "_" + (string)time;
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, time, hi, time + PeriodSeconds(_Period), lo))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == InpMagicNum && posInfo.Symbol() == _Symbol)
      {
         double open = posInfo.PriceOpen(), sl = posInfo.StopLoss(), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            if((bid - open) / point >= InpTSL_Trigger)
            {
               double nSL = NormalizeDouble(bid - InpTSL_Distance * point, _Digits);
               if(nSL > sl || sl == 0) trade.PositionModify(posInfo.Ticket(), nSL, posInfo.TakeProfit());
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            if((open - ask) / point >= InpTSL_Trigger)
            {
               double nSL = NormalizeDouble(ask + InpTSL_Distance * point, _Digits);
               if(nSL < sl || sl == 0) trade.PositionModify(posInfo.Ticket(), nSL, posInfo.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Utilities                                                        |
//+------------------------------------------------------------------+
bool IsNewBar() { datetime t = iTime(_Symbol, _Period, 0); if(t != lastBarTime) { lastBarTime = t; return true; } return false; }

bool IsTradingTime() { MqlDateTime dt; TimeCurrent(dt); return (dt.hour >= InpStart_Hour && dt.hour < InpEnd_Hour); }

void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(orderInfo.Select(OrderGetTicket(i)) && orderInfo.Magic() == InpMagicNum) trade.OrderDelete(orderInfo.Ticket());
}

bool PositionExists(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == InpMagicNum && posInfo.PositionType() == type) return true;
   return false;
}

int CountPendingOrders(ENUM_ORDER_TYPE type)
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(orderInfo.Select(OrderGetTicket(i)) && orderInfo.Magic() == InpMagicNum && orderInfo.OrderType() == type) c++;
   return c;
}

double CalculateLot(int slPoints)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slPoints <= 0 || tick <= 0) return 0.01;
   double lot = risk / (slPoints * (tick / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)) * _Point);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathMax(MathFloor(lot/step)*step, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
}
