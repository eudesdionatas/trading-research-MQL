//+------------------------------------------------------------------+
//|                                                   ATR_Wilder.mq5 |
//|                                  Copyright 2026, Seu Nome Quant |
//+------------------------------------------------------------------+
#property copyright "Seu Nome Quant"
#property indicator_separate_window // Exibe o indicador em uma janela separada (abaixo do gráfico)
#property indicator_buffers 2       // Precisamos de 2 buffers (1 para o ATR visível, 1 para o TR temporário)
#property indicator_plots   1       // Apenas 1 linha será desenhada no gráfico

// Configurações da linha do ATR
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label1  "ATR Wilder"

//--- Inputs do Usuário
input int InpATRPeriod = 14; // Período do ATR

//--- Buffers Globais do Indicador
double ATRBuffer[];
double TRBuffer[]; // Buffer dinâmico oculto para calcular o True Range intermediário

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validação do input
   if(InpATRPeriod <= 0)
     {
      Print("Período do ATR inválido. Configurando para o padrão de 14.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Vincula os arrays dinâmicos aos buffers do indicador
   SetIndexBuffer(0, ATRBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, TRBuffer,  INDICATOR_CALCULATIONS); // Oculto, usado apenas para os cálculos

   // Define o nome curto que aparece na janela do indicador
   IndicatorSetString(INDICATOR_SHORTNAME, "ATR Wilder (" + IntegerToString(InpATRPeriod) + ")");
   
   // Define a precisão de casas decimais com base no ativo atual
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   // Se não houver barras suficientes na tela, aborta temporariamente
   if(rates_total < InpATRPeriod)
      return(0);

   // Descobre a partir de qual barra precisamos recalcular (otimização do MT5)
   int start = prev_calculated - 1;
   if(start < 0) start = 0;

   //------------------------------------------------------------------
   // PASSO 1 e 2: Calcular o True Range (TR) para cada barra do histórico
   //------------------------------------------------------------------
   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      if(i == 0)
        {
         // Na primeira barra da história do gráfico não existe 'Close anterior'
         TRBuffer[i] = high[i] - low[i];
        }
      else
        {
         // Calcula as 3 distâncias potenciais do True Range
         double max_min       = high[i] - low[i];
         double max_close_ant = MathAbs(high[i] - close[i - 1]);
         double min_close_ant = MathAbs(low[i] - close[i - 1]);

         // Captura o maior valor entre as 3 distâncias
         TRBuffer[i] = MathMax(max_min, MathMax(max_close_ant, min_close_ant));
        }
     }

   //------------------------------------------------------------------
   // PASSO 3: Calcular o ATR usando a Média Exponencial de Wilder
   //------------------------------------------------------------------
   // Fator de suavização de Wilder (equivale a ewm(com=periodos-1) no Pandas)
   double alpha = 1.0 / InpATRPeriod; 

   // Se for a primeira execução completa do indicador, inicializa a primeira média estável
   if(prev_calculated == 0)
     {
      double sum = 0;
      for(int i = 0; i < InpATRPeriod; i++)
        {
         sum += TRBuffer[i];
         ATRBuffer[i] = 0.0; // Deixa o início do indicador zerado enquanto acumula (warm-up)
        }
      // O primeiro ATR válido recebe a média simples do período de warm-up
      ATRBuffer[InpATRPeriod - 1] = sum / InpATRPeriod;
      
      // Ajusta o 'start' para continuar dali para frente
      start = InpATRPeriod;
     }

   // Loop que roda a suavização exponencial barra a barra
   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      // Fórmula da Média de Wilder: ATR de hoje = (TR de hoje * alpha) + (ATR de ontem * (1 - alpha))
      ATRBuffer[i] = (TRBuffer[i] * alpha) + (ATRBuffer[i - 1] * (1.0 - alpha));
     }

   // Retorna o total de taxas para atualizar o prev_calculated na próxima oscilação do preço
   return(rates_total);
}