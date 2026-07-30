//+------------------------------------------------------------------+
//|                                         RSI_ATR_Dynamic_EA.mq5   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.20"

#include <Trade\Trade.mqh>
CTrade trade;

//--- PARÂMETROS DE ENTRADA
input group "--- Parâmetros do RSI ---"
input int            InpRSIPeriod   = 14;       // Período do RSI
input double         InpRSILowLevel = 20.0;     // Nível de Compra (<= 20)
input double         InpRSIHighLevel= 80.0;     // Nível de Venda (>= 80)

input group "--- Gerenciamento de Risco (ATR) ---"
input int            InpATRPeriod   = 14;       // Período do ATR
input double         InpATRMulSL    = 3.0;      // multiplicador_stop = 3 (Igual ao Python)
input double         InpLotSize     = 100;      // Tamanho do lote das operações

//--- VARIÁVEIS GLOBAIS
int      rsiHandle;   
int      atrHandle;   
datetime lastBarTime; 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   rsiHandle = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Erro ao inicializar os indicadores.");
      return(INIT_FAILED);
   }

   lastBarTime = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Executa no fechamento da barra (Garante consistência com o resample do Python)
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime) return;
   
   if(PositionsTotal() > 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == _Symbol) return; 
      }
   }

   double rsiValues[];
   double atrValues[];
   
   ArraySetAsSeries(rsiValues, true);
   ArraySetAsSeries(atrValues, true);
   
   if(CopyBuffer(rsiHandle, 0, 1, 2, rsiValues) < 2) return;
   if(CopyBuffer(atrHandle, 0, 1, 2, atrValues) < 2) return;
   
   double currentRSI = rsiValues[0];
   double currentATR = atrValues[0];
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- CÁLCULO DINÂMICO DOS ALVOS (Equivalente ao Passo 5 do Python) ---
   double stopLossDistance   = currentATR * InpATRMulSL;
   double takeProfitDistance = stopLossDistance * 2.0; // Proporção 2:1
   
   // Filtros de segurança mínimos (Equivalente ao .clip(lower=0.15) e .clip(lower=0.30) do Python)
   if(stopLossDistance < 0.15)   stopLossDistance = 0.15;
   if(takeProfitDistance < 0.30) takeProfitDistance = 0.30;
   
   //--- LÓGICA DE EXECUÇÃO ---
   
   // Compra se RSI <= 20
   if(currentRSI <= InpRSILowLevel)
   {
      double stopLoss   = ask - stopLossDistance;
      double takeProfit = ask + takeProfitDistance;
      
      stopLoss   = NormalizeDouble(stopLoss, _Digits);
      takeProfit = NormalizeDouble(takeProfit, _Digits);
      
      if(trade.Buy(InpLotSize, _Symbol, ask, stopLoss, takeProfit, "RSI Extreme Buy"))
      {
         lastBarTime = currentBarTime; 
      }
   }
   // Venda se RSI >= 80
   else if(currentRSI >= InpRSIHighLevel)
   {
      double stopLoss   = bid + stopLossDistance;
      double takeProfit = bid - takeProfitDistance;
      
      stopLoss   = NormalizeDouble(stopLoss, _Digits);
      takeProfit = NormalizeDouble(takeProfit, _Digits);
      
      if(trade.Sell(InpLotSize, _Symbol, bid, stopLoss, takeProfit, "RSI Extreme Sell"))
      {
         lastBarTime = currentBarTime; 
      }
   }
}
//+------------------------------------------------------------------+