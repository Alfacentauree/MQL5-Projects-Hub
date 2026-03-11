//+------------------------------------------------------------------+
//|                                           BollingerBandsEA.mq5   |
//|                                  Copyright 2026 ADD              |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "2.41"
#property strict

#include <Trade\Trade.mqh>

//--- input parameters
input int      InpLength     = 20;         // BB Length
input double   InpMult       = 2.0;        // BB Multiplier
input int      InpDirection  = 0;          // Strategy Direction (-1: Short, 0: Both, 1: Long)

input string   sep2          = "--- Money Management ---";
input bool     InpUsePropMode= true;       // Use Propfirm Mode (Fixed $ Risk)
input double   InpRiskDollar = 100.0;      // Risk Amount in Dollars ($)
input double   InpLotSize    = 0.1;        // Fixed Lot Size
input int      InpWaitMin    = 15;         // Wait minutes after trade close
input int      InpBufferPoints = 30;       // Safety Buffer from BB (Points)
input long     InpMagicNum   = 123456;     // EA Magic Number

input string   sep3          = "--- Session Filter ---";
input bool     InpUseAsia    = false;      // Use Asia Session (00:00-09:00)
input bool     InpUseLondon  = true;       // Use London Session (09:00-18:00)
input bool     InpUseNY      = true;       // Use New York Session (15:00-24:00)

//--- global variables
int            handleBB;                  // Handle for iBands indicator
CTrade         trade;                     // Trade class instance
double         upperBand[], lowerBand[], basisBand[];
datetime       lastExitTime = 0;          // Global tracker for cooldown
bool           wasPositionOpen = false;    // To detect when a position closes
bool           indicatorAdded = false;     // Visual check for chart display
bool           isTrailingActive = false;   // Global flag for trailing state

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   handleBB = iBands(_Symbol, _Period, InpLength, 0, InpMult, PRICE_CLOSE);
   
   if(handleBB == INVALID_HANDLE) 
   { 
      Print("CRITICAL: Failed to create BB handle. Error: ", GetLastError()); 
      return(INIT_FAILED); 
   }
   
   ArraySetAsSeries(upperBand, true);
   ArraySetAsSeries(lowerBand, true);
   ArraySetAsSeries(basisBand, true);
   
   isTrailingActive = false;
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
   // Try to add BB to chart visually once if not already done
   if(!indicatorAdded && MQLInfoInteger(MQL_VISUAL_MODE) == 0)
   {
      if(ChartIndicatorAdd(0, 0, handleBB)) indicatorAdded = true;
   }

   // 1. Monitor Position Changes for Cooldown & Reset
   bool isPositionOpen = PositionSelectByMagic(_Symbol, InpMagicNum);
   if(wasPositionOpen && !isPositionOpen) 
   {
      lastExitTime = TimeCurrent();
      isTrailingActive = false; // RESET TRAILING FLAG
      Print("Position Closed. Cooldown started & Trailing Reset.");
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
   
   double close0 = iClose(_Symbol, _Period, 0);
   double close1 = iClose(_Symbol, _Period, 1);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // 4. Entry Signals
   if(!isPositionOpen)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      
      bool isWithinSession = false;
      if(InpUseAsia && (hour >= 0 && hour < 9)) isWithinSession = true;
      if(InpUseLondon && (hour >= 9 && hour < 18)) isWithinSession = true;
      if(InpUseNY && (hour >= 15 && hour < 24)) isWithinSession = true;
      if(!InpUseAsia && !InpUseLondon && !InpUseNY) isWithinSession = true;

      if(isWithinSession)
      {
         // Long Signal
         if((close1 < lowerBand[1] && close0 >= lowerBand[0]) && (InpDirection == 0 || InpDirection == 1))
         {
            double sl = 0;
            if(InpUsePropMode) sl = CalculateSLByDollar(ask, POSITION_TYPE_BUY);
            
            trade.Buy(InpLotSize, _Symbol, ask, sl, 0, "BB_Prop_Buy");
         }
         // Short Signal
         else if((close1 > upperBand[1] && close0 <= upperBand[0]) && (InpDirection == 0 || InpDirection == -1))
         {
            double sl = 0;
            if(InpUsePropMode) sl = CalculateSLByDollar(bid, POSITION_TYPE_SELL);

            trade.Sell(InpLotSize, _Symbol, bid, sl, 0, "BB_Prop_Sell");
         }
      }
   }

   // 5. Dynamic Trailing Stop (Propfirm Logic)
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
         double currentTP = PositionGetDouble(POSITION_TP);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
         double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
         double brokerMin = MathMax(stopLevel, freezeLevel) + (5 * _Point);
         double userBuffer = InpBufferPoints * _Point;
         double finalBuffer = MathMax(brokerMin, userBuffer);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            // TRIGGER: Price touches or goes above Middle Band (Basis)
            // Once triggered, SL follows the Lower Band even if it moves down
            if(!isTrailingActive && (bid >= basisBand[0])) 
            {
               isTrailingActive = true;
               Print("Trailing activated for BUY.");
            }

            if(isTrailingActive) 
            {
               double newSL = NormalizeDouble(lowerBand[0] - finalBuffer, digits);
               
               // Validation: Must be below bid - brokerMin
               if(newSL < (bid - brokerMin))
               {
                  // Follow the band up AND down, but only if change is significant (> 1 point)
                  if(MathAbs(newSL - currentSL) > _Point || currentSL == 0)
                  {
                     trade.PositionModify(ticket, newSL, currentTP);
                  }
               }
            }
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            // TRIGGER: Price touches or goes below Middle Band (Basis)
            // Once triggered, SL follows the Upper Band even if it moves up
            if(!isTrailingActive && (ask <= basisBand[0])) 
            {
               isTrailingActive = true;
               Print("Trailing activated for SELL.");
            }

            if(isTrailingActive)
            {
               double newSL = NormalizeDouble(upperBand[0] + finalBuffer, digits);
               
               // Validation: Must be above ask + brokerMin
               if(newSL > (ask + brokerMin))
               {
                  // Follow the band down AND up, but only if change is significant (> 1 point)
                  if(MathAbs(newSL - currentSL) > _Point || currentSL == 0)
                  {
                     trade.PositionModify(ticket, newSL, currentTP);
                  }
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

   // Calculate points needed for the dollar risk
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
