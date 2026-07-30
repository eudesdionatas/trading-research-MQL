//+------------------------------------------------------------------+
//|                                          Stoch_Candle_Alert.mq5   |
//|  Indicador: Estocastico (M15) + pintura condicional de candles    |
//|  + alerta sonoro em zonas de sobrecompra/sobrevenda               |
//|  - Somente os candles que atendem as condicoes sao pintados;      |
//|    os demais ficam com a cor nativa do grafico (nao sao tocados). |
//|  - Alerta sonoro somente quando o grafico atual esta em M15.      |
//+------------------------------------------------------------------+
#property copyright "Custom Indicator"
#property version   "1.03"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   2

// Plot 1: Overlay - Sobrecompra (>80, rapida cruzou abaixo da lenta)
// DRAW_CANDLES aceita 3 cores: Borda/Pavio, Corpo de Alta, Corpo de Baixa
#property indicator_label1  "Overbought Reversal Candles"
#property indicator_type1   DRAW_CANDLES
#property indicator_color1  C'0,82,130', C'158,210,253', C'0,82,130'   // borda, alta, baixa

// Plot 2: Overlay - Sobrevenda (<20, rapida cruzou acima da lenta)
#property indicator_label2  "Oversold Reversal Candles"
#property indicator_type2   DRAW_CANDLES
#property indicator_color2  clrLimeGreen, C'180,255,180', clrLimeGreen // borda, alta, baixa

//--- Inputs do Estocastico (calculado sempre no timeframe M15)
input group "--- Estocastico (M15) ---"
input int                InpKPeriod    = 5;
input int                InpDPeriod    = 3;
input int                InpSlowing    = 3;
input ENUM_MA_METHOD     InpMAMethod   = MODE_SMA;
input ENUM_STO_PRICE     InpPriceField = STO_LOWHIGH;
input double             InpOverbought = 80.0;
input double             InpOversold   = 20.0;

input group "--- Alerta ---"
input bool               InpPlaySound  = true;
input string             InpSoundFile  = "alert.wav"; // arquivo em MQL5\Sounds

//--- Buffers - Plot 1 (Sobrecompra, DRAW_CANDLES)
double BufOBOpen[];
double BufOBHigh[];
double BufOBLow[];
double BufOBClose[];

//--- Buffers - Plot 2 (Sobrevenda, DRAW_CANDLES)
double BufOSOpen[];
double BufOSHigh[];
double BufOSLow[];
double BufOSClose[];

//--- Handle do Estocastico em M15
int    handleStoch = INVALID_HANDLE;

//--- Controle de alerta (evita repetir a cada tick / mesma barra)
datetime lastAlertTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufOBOpen,  INDICATOR_DATA);
   SetIndexBuffer(1, BufOBHigh,  INDICATOR_DATA);
   SetIndexBuffer(2, BufOBLow,   INDICATOR_DATA);
   SetIndexBuffer(3, BufOBClose, INDICATOR_DATA);

   SetIndexBuffer(4, BufOSOpen,  INDICATOR_DATA);
   SetIndexBuffer(5, BufOSHigh,  INDICATOR_DATA);
   SetIndexBuffer(6, BufOSLow,   INDICATOR_DATA);
   SetIndexBuffer(7, BufOSClose, INDICATOR_DATA);

   ArraySetAsSeries(BufOBOpen,  false);
   ArraySetAsSeries(BufOBHigh,  false);
   ArraySetAsSeries(BufOBLow,   false);
   ArraySetAsSeries(BufOBClose, false);
   ArraySetAsSeries(BufOSOpen,  false);
   ArraySetAsSeries(BufOSHigh,  false);
   ArraySetAsSeries(BufOSLow,   false);
   ArraySetAsSeries(BufOSClose, false);

   // Garante que bars com EMPTY_VALUE realmente nao sejam desenhados,
   // deixando o candle nativo do grafico visivel por baixo.
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   handleStoch = iStochastic(_Symbol, PERIOD_M15, InpKPeriod, InpDPeriod, InpSlowing, InpMAMethod, InpPriceField);
   if(handleStoch == INVALID_HANDLE)
      return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME, "Stochastic State Candles (M15)");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handleStoch != INVALID_HANDLE)
      IndicatorRelease(handleStoch);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int barsM15 = Bars(_Symbol, PERIOD_M15);
   if(rates_total < 2 || barsM15 <= (InpKPeriod + InpDPeriod + InpSlowing))
      return(0);

   double kBuf[];
   double dBuf[];
   ArraySetAsSeries(kBuf, true);
   ArraySetAsSeries(dBuf, true);

   int copied = MathMin(barsM15, 5000); // limite de seguranca
   if(CopyBuffer(handleStoch, 0, 0, copied, kBuf) <= 0) return(0); // %K = linha rapida (principal)
   if(CopyBuffer(handleStoch, 1, 0, copied, dBuf) <= 0) return(0); // %D = linha lenta (sinal)

   int limit = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   for(int i = limit; i < rates_total; i++)
     {
      // por padrao, nao desenha nada -> candle nativo do grafico fica visivel
      BufOBOpen[i] = EMPTY_VALUE; BufOBHigh[i] = EMPTY_VALUE; BufOBLow[i] = EMPTY_VALUE; BufOBClose[i] = EMPTY_VALUE;
      BufOSOpen[i] = EMPTY_VALUE; BufOSHigh[i] = EMPTY_VALUE; BufOSLow[i] = EMPTY_VALUE; BufOSClose[i] = EMPTY_VALUE;

      bool condOB = false;
      bool condOS = false;

      // localiza a barra correspondente em M15
      int shift = iBarShift(_Symbol, PERIOD_M15, time[i], false);
      if(shift >= 0 && shift < copied)
        {
         double k = kBuf[shift];
         double d = dBuf[shift];
         condOB = (k > InpOverbought && d > InpOverbought && k < d); // sobrecompra + rapida abaixo da lenta
         condOS = (k < InpOversold   && d < InpOversold   && k > d); // sobrevenda + rapida acima da lenta
        }

      if(condOB)
        {
         BufOBOpen[i] = open[i]; BufOBHigh[i] = high[i]; BufOBLow[i] = low[i]; BufOBClose[i] = close[i];
        }
      else if(condOS)
        {
         BufOSOpen[i] = open[i]; BufOSHigh[i] = high[i]; BufOSLow[i] = low[i]; BufOSClose[i] = close[i];
        }
      // caso contrario: candle fica sem pintura nenhuma (nativo do grafico)

      // --- ALERTA SONORO: apenas no grafico M15, na ultima barra ja fechada, uma vez por barra ---
      if(InpPlaySound && _Period == PERIOD_M15 && i == rates_total - 2 && (condOB || condOS))
        {
         ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
         if(tradeMode == SYMBOL_TRADE_MODE_FULL && time[i] > lastAlertTime)
           {
            PlaySound(InpSoundFile);
            lastAlertTime = time[i];
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+