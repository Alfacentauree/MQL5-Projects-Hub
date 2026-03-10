//+------------------------------------------------------------------+
//|                                           BollingerBandsEA.mq5   |
//|                                  Copyright 2026, Gemini CLI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini CLI"
#property link      "https://www.mql5.com"
#property version   "2.20"
#property strict

#include <Trade\Trade.mqh>

//--- input parameters
input int      InpLength     = 20;         // BB Length
input double   InpMult       = 2.0;        // BB Multiplier
input int      InpDirection  = 0;          // Strategy Direction (-1: Short, 0: Both, 1: Long)

input string   sep2          = "--- Money Management ---";
input double   InpLotSize    = 0.1;        // Trading Lot Size
input int      InpWaitMin    = 15;         // Wait minutes after trade close
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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   handleBB = iBands(_Symbol, _Period, InpLength, 0, InpMult, PRICE_CLOSE);
   if(handleBB == INVALID_HANDLE) { Print("Failed to create BB handle"); return(INIT_FAILED); }
   
   if(!ChartIndicatorAdd(0, 0, handleBB)) Print("Failed to add BB to chart");
   
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
      Print("Position Closed. 15-minute cooldown started.");
   }
   wasPositionOpen = isPositionOpen;

   // 2. Cooldown Check
   if(!isPositionOpen && lastExitTime > 0)
   {
      long secondsPassed = TimeCurrent() - lastExitTime;
      if(secondsPassed < InpWaitMin * 60) return; // Still in cooldown
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
      
      // Asia Session: 00:00 - 09:00
      if(InpUseAsia && (hour >= 0 && hour < 9)) isWithinSession = true;
      
      // London Session: 09:00 - 18:00
      if(InpUseLondon && (hour >= 9 && hour < 18)) isWithinSession = true;
      
      // New York Session: 15:00 - 24:00
      if(InpUseNY && (hour >= 15 && hour < 24)) isWithinSession = true;
      
      // If no sessions are selected, we assume trading is always allowed (unless you want it OFF by default)
      if(!InpUseAsia && !InpUseLondon && !InpUseNY) isWithinSession = true;

      if(isWithinSession)
      {
         // Long Signal
         if((close1 < lowerBand[1] && close0 >= lowerBand[0]) && (InpDirection == 0 || InpDirection == 1))
         {
            trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "BBandLE");
         }
         // Short Signal
         else if((close1 > upperBand[1] && close0 <= upperBand[0]) && (InpDirection == 0 || InpDirection == -1))
         {
            trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "BBandSE");
         }
      }
   }

   // 5. Fully Dynamic Trailing Stop (Follows Band exactly)
   if(isPositionOpen)
   {
      // Find the specific ticket for THIS EA instance
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
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            // Activate ONLY after price touches/crosses Middle Band (Basis)
            if(bid >= basisBand[0] || currentSL > 0) 
            {
               double newSL = NormalizeDouble(lowerBand[0], digits);
               
               // Move SL if it changed by more than 1 point (Up or Down)
               if(MathAbs(newSL - currentSL) > _Point || currentSL == 0)
               {
                  if(!trade.PositionModify(ticket, newSL, currentTP))
                     Print("Dynamic SL Update Failed: ", trade.ResultRetcodeDescription());
               }
            }
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            // Activate ONLY after price touches/crosses Middle Band (Basis)
            if(ask <= basisBand[0] || currentSL > 0)
            {
               double newSL = NormalizeDouble(upperBand[0], digits);
               
               // Move SL if it changed by more than 1 point (Up or Down)
               if(MathAbs(newSL - currentSL) > _Point || currentSL == 0)
               {
                  if(!trade.PositionModify(ticket, newSL, currentTP))
                     Print("Dynamic SL Update Failed: ", trade.ResultRetcodeDescription());
               }
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
