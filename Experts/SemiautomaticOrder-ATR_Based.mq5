//+------------------------------------------------------------------+
//|         Boleta_Indice_Com_Painel_v1.58.mq5                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.58"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Enumerador para a seleção da proporção de risco do Gain
enum ENUM_RISK_RATIO
{
   RATIO_2_1 = 2, // Gain 2x o Loss
   RATIO_3_1 = 3  // Gain 3x o Loss
};

//--- Parâmetros de Entrada
input group "--- Configurações Operacionais ---"
input int               InpLotSize         = 1;         // Tamanho do Lote (1 Contrato para Mini-índice)
input ENUM_RISK_RATIO InpRiskRewardRatio = RATIO_2_1;  // Proporção do Gain (Multiplicador do Loss)
input int               InpMaxNegociosDia  = 3;         // Máximo de Negócios por Dia (Máx de Ordens = Negócios * 2)

input group "--- Configuração do Indicador Volatilidade ---"
input int               InpATRPeriod       = 14;        // Período do ATR utilizado na fórmula

const string PREFIX_OBJ = "Proj_";
const string PREFIX_TXT = "Painel_";
const string LABEL_PRECO_POSICAO = "LABEL_PRECO_POSICAO";

// Variáveis de controle de estado
bool operacaoPendente = false;
int  tipoOperacao = 0; // 1 = Compra, 2 = Venda
int  handleATR;        // Ponteiro do indicador ATR
string globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
bool posicaoEstavaAberta = false; 

// Variáveis das métricas do dia
double maiorAmplitudeGlobal = 0.0; 
string horarioMaiorCandle = "";    
int    totalCandlesDoDia = 0;      

int OnInit()
{
   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(handleATR == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao inicializar o indicador ATR.");
      return(INIT_FAILED);
   }

   // Timer super-rápido de 50ms para resposta imediata ao scroll do mouse
   EventSetMillisecondTimer(50);

   for(int i=0; i<10; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));

   Print("==========================================================");
   Print("[SISTEMA PRONTO] Boleta carregada com sucesso no ativo: ", _Symbol);
   Print("==========================================================");

   ChartRedraw(0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(handleATR);
   ApagarLinhasProjecao();
   Comment("");
   
   ObjectDelete(0, LABEL_PRECO_POSICAO);
   for(int i=0; i<10; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   Print("[INFO] Robô descarregado do gráfico.");
}

void OnTick() 
{
   ProcessarRotinasDeAtualizacao();
}

void OnTimer()
{
   ProcessarRotinasDeAtualizacao();
}

void ProcessarRotinasDeAtualizacao()
{
   CalcularMetricasDoDia();

   if(operacaoPendente)
   {
      AtualizarLinhasCustomizadas();
   }

   AtualizarPainelVisualEmTempoReal();
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   // Captura instantaneamente scroll, drag e zoom do mouse no gráfico
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      AtualizarLabelGraficoPreco("", clrNONE, false);
      ProcessarRotinasDeAtualizacao(); 
   }
   
   if(id == CHARTEVENT_KEYDOWN)
   {
      int tecla = (int)lparam;

      // Verifica se atingiu o limite máximo de ordens do dia (Negócios * 2)
      int maxOrdensPermitidas = InpMaxNegociosDia * 2;
      int operacoesFeitasHoje = CalcularOperacoesDoDia();

      if(operacoesFeitasHoje >= maxOrdensPermitidas)
      {
         globalMensagemStatus = "Limite de ordens atingido! Já deu por hoje.";
         ApagarLinhasProjecao();
         return;
      }

      if(tecla == 67 || tecla == 99) // Tecla 'C'
      {
         operacaoPendente = true;
         tipoOperacao = 1;
         AtualizarLinhasCustomizadas();
         globalMensagemStatus = "Modo compra ativo! (ENTER) Envia | (ESC) Cancela";
      }
      else if(tecla == 86 || tecla == 118) // Tecla 'V'
      {
         operacaoPendente = true;
         tipoOperacao = 2;
         AtualizarLinhasCustomizadas();
         globalMensagemStatus = "Modo venda ativo! (ENTER) Envia | (ESC) Cancela";
      }
      else if(tecla == 13) // Tecla 'ENTER'
      {
         if(operacaoPendente)
         {
            EnviarOrdemMercado();
         }
         else
         {
            bool ctrlPressionado = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);
            if(ctrlPressionado)
            {
               FecharPosicaoAberta();
            }
         }
      }
      else if(tecla == 27) // Tecla 'ESC'
      {
         ApagarLinhasProjecao();
         globalMensagemStatus = "Cancelado. Pressione (C) Compra | (V) Venda";
      }
   }
}

double ArredondarParaPassoDoPreco(double pontos)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return pontos;
   return MathRound(pontos / tickSize) * tickSize;
}

double ObterValorATR()
{
   double atrBuffer[1];
   if(CopyBuffer(handleATR, 0, 0, 1, atrBuffer) < 1) return 1.0;
   return atrBuffer[0] / _Point;
}

double CalcularPontosSL()
{
   double valorATR = ObterValorATR();
   double lossMinimo = 25.0;
   double lossMaximo = 200.0;
   double resultado = lossMinimo + (valorATR - 50.0) * (lossMaximo - lossMinimo) / (400.0 - 50.0);
   
   if(resultado < lossMinimo) resultado = lossMinimo;
   if(resultado > lossMaximo) resultado = lossMaximo;
   
   return ArredondarParaPassoDoPreco(resultado);
}

void EnviarOrdemMercado()
{
   int maxOrdensPermitidas = InpMaxNegociosDia * 2;
   if(CalcularOperacoesDoDia() >= maxOrdensPermitidas)
   {
      globalMensagemStatus = "Limite de ordens atingido! Já deu por hoje.";
      ApagarLinhasProjecao();
      return;
   }

   double pontosSL = CalcularPontosSL();
   double pontosTP = ArredondarParaPassoDoPreco(pontosSL * (double)InpRiskRewardRatio);

   if(tipoOperacao == 1) 
   {
      double precoCompra = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      double slCompra    = NormalizeDouble(precoCompra - (pontosSL * _Point), _Digits);
      double tpCompra    = NormalizeDouble(precoCompra + (pontosTP * _Point), _Digits);
      trade.Buy(InpLotSize, _Symbol, precoCompra, slCompra, tpCompra, "Compra ATR Dinâmica");
   }
   else if(tipoOperacao == 2) 
   {
      double precoVenda = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      double slVenda    = NormalizeDouble(precoVenda + (pontosSL * _Point), _Digits);
      double tpVenda    = NormalizeDouble(precoVenda - (pontosTP * _Point), _Digits);
      trade.Sell(InpLotSize, _Symbol, precoVenda, slVenda, tpVenda, "Venda ATR Dinâmica");
   }

   ApagarLinhasProjecao();
   globalMensagemStatus = "Ordem enviada! Pressione (ESC) para cancelar a ordem";
}

void VerificarResultadoETocarSomSaida()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   double ultimoLucro = 0.0;
   bool encontrouDealSaida = false;

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               double lucro    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
               double swap     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
               double comissao = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);
               
               ultimoLucro = lucro + swap + comissao;
               encontrouDealSaida = true;
               break;
            }
         }
      }
   }

   if(encontrouDealSaida && ultimoLucro > 0.0)
   {
      PlaySound("\\Audio\\gain.wav");
   }
   else
   {
      PlaySound("stops.wav");
   }
}

void FecharPosicaoAberta()
{
   if(PositionSelect(_Symbol)) 
   {
      if(trade.PositionClose(_Symbol))
      {
         VerificarResultadoETocarSomSaida();
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
   }
   else
   {
      globalMensagemStatus = "Nenhuma posição aberta";
   }
}

void CalcularMetricasDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   if(inicioDoDia == 0) return; 

   MqlRates barras[];
   ArraySetAsSeries(barras, false); 
   int barrasCopiadas = CopyRates(_Symbol, _Period, inicioDoDia, TimeCurrent(), barras);
   
   if(barrasCopiadas > 0)
   {
      totalCandlesDoDia = barrasCopiadas;
      double maiorAmplitude = 0.0;
      datetime dataHoraCandle = 0;
      
      for(int i = 0; i < barrasCopiadas; i++)
      {
         MqlDateTime dt;
         TimeToStruct(barras[i].time, dt);
         if(dt.hour == 9 && dt.min == 0) continue;
         
         double amplitude = barras[i].high - barras[i].low;
         if(amplitude > maiorAmplitude) 
         {
            maiorAmplitude = amplitude;
            dataHoraCandle = barras[i].time;
         }
      }
      
      maiorAmplitudeGlobal = NormalizeDouble(maiorAmplitude / _Point, 0);
      horarioMaiorCandle = TimeToString(dataHoraCandle, TIME_MINUTES);
   }
}

double CalcularResultadoFinanceiroDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   double lucroTotalDia = 0.0;

   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            double lucroDeal    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
            double swapDeal     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
            double comissaoDeal = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);
            
            lucroTotalDia += (lucroDeal + swapDeal + comissaoDeal);
         }
      }
   }

   return lucroTotalDia;
}

double CalcularPontosDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   double totalPontos = 0.0;

   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            ulong positionID = HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID);
            
            if(entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               for(int j = 0; j < totalDeals; j++)
               {
                  ulong ticketIn = HistoryDealGetTicket(j);
                  if(ticketIn > 0 && HistoryDealGetInteger(ticketIn, DEAL_POSITION_ID) == positionID)
                  {
                     if(HistoryDealGetInteger(ticketIn, DEAL_ENTRY) == DEAL_ENTRY_IN)
                     {
                        double precoEntrada = HistoryDealGetDouble(ticketIn, DEAL_PRICE);
                        double precoSaida   = HistoryDealGetDouble(ticketDeal, DEAL_PRICE);
                        long tipoEntrada    = HistoryDealGetInteger(ticketIn, DEAL_TYPE);
                        
                        if(tipoEntrada == DEAL_TYPE_BUY)
                           totalPontos += (precoSaida - precoEntrada) / _Point;
                        else if(tipoEntrada == DEAL_TYPE_SELL)
                           totalPontos += (precoEntrada - precoSaida) / _Point;
                        
                        break;
                     }
                  }
               }
            }
         }
      }
   }

   return totalPontos;
}

int CalcularOperacoesDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   int totalOps = 0;

   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               totalOps++;
            }
         }
      }
   }

   return totalOps;
}

//--- Métricas do Mês ---
datetime ObterInicioDoMes()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

double CalcularResultadoFinanceiroDoMes()
{
   datetime inicioDoMes = ObterInicioDoMes();
   double lucroTotalMes = 0.0;

   HistorySelect(inicioDoMes, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            double lucroDeal    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
            double swapDeal     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
            double comissaoDeal = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);
            
            lucroTotalMes += (lucroDeal + swapDeal + comissaoDeal);
         }
      }
   }

   return lucroTotalMes;
}

double CalcularPontosDoMes()
{
   datetime inicioDoMes = ObterInicioDoMes();
   double totalPontosMes = 0.0;

   HistorySelect(inicioDoMes, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            ulong positionID = HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID);
            
            if(entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               for(int j = 0; j < totalDeals; j++)
               {
                  ulong ticketIn = HistoryDealGetTicket(j);
                  if(ticketIn > 0 && HistoryDealGetInteger(ticketIn, DEAL_POSITION_ID) == positionID)
                  {
                     if(HistoryDealGetInteger(ticketIn, DEAL_ENTRY) == DEAL_ENTRY_IN)
                     {
                        double precoEntrada = HistoryDealGetDouble(ticketIn, DEAL_PRICE);
                        double precoSaida   = HistoryDealGetDouble(ticketDeal, DEAL_PRICE);
                        long tipoEntrada    = HistoryDealGetInteger(ticketIn, DEAL_TYPE);
                        
                        if(tipoEntrada == DEAL_TYPE_BUY)
                           totalPontosMes += (precoSaida - precoEntrada) / _Point;
                        else if(tipoEntrada == DEAL_TYPE_SELL)
                           totalPontosMes += (precoEntrada - precoSaida) / _Point;
                        
                        break;
                     }
                  }
               }
            }
         }
      }
   }

   return totalPontosMes;
}

int CalcularOperacoesDoMes()
{
   datetime inicioDoMes = ObterInicioDoMes();
   int totalOpsMes = 0;

   HistorySelect(inicioDoMes, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               totalOpsMes++;
            }
         }
      }
   }

   return totalOpsMes;
}

void DefaultAtualizarLinhasCustomizadas()
{
   double pontosSL = CalcularPontosSL();
   double pontosTP = ArredondarParaPassoDoPreco(pontosSL * (double)InpRiskRewardRatio);

   double precoReferencia = 0;
   double slProjetado = 0;
   double tpProjetado = 0;
   color corEntrada = clrNONE;

   if(tipoOperacao == 1) 
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slProjetado     = precoReferencia - (pontosSL * _Point);
      tpProjetado     = precoReferencia + (pontosTP * _Point);
      corEntrada      = clrDodgerBlue;
   }
   else if(tipoOperacao == 2) 
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slProjetado     = precoReferencia + (pontosSL * _Point);
      tpProjetado     = precoReferencia - (pontosTP * _Point);
      corEntrada      = clrCrimson;
   }

   if(precoReferencia <= 0) return;

   DesenharLinhaH(PREFIX_OBJ+"Entrada", precoReferencia, corEntrada, STYLE_SOLID, 2);
   DesenharLinhaH(PREFIX_OBJ+"Loss",    slProjetado, clrRed, STYLE_DOT, 1);
   DesenharLinhaH(PREFIX_OBJ+"Gain",    tpProjetado, clrLimeGreen, STYLE_DOT, 1);
   ChartRedraw(0);
}

void AtualizarLinhasCustomizadas() { DefaultAtualizarLinhasCustomizadas(); }

void AtualizarLabelGraficoPreco(string texto = "", color cor = clrNONE, bool atualizarTexto = false)
{
   if(!PositionSelect(_Symbol))
   {
      ObjectDelete(0, LABEL_PRECO_POSICAO);
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1) return;

   int x = 0, y = 0;
   if(ChartTimePriceToXY(ChartID(), 0, rates[0].time, rates[0].close, x, y))
   {
      string textoFinal = texto;
      color corFinal = cor;

      if(!atualizarTexto && ObjectFind(0, LABEL_PRECO_POSICAO) >= 0)
      {
         textoFinal = ObjectGetString(0, LABEL_PRECO_POSICAO, OBJPROP_TEXT);
         corFinal = (color)ObjectGetInteger(0, LABEL_PRECO_POSICAO, OBJPROP_COLOR);
      }

      long larguraGrafico = ChartGetInteger(ChartID(), CHART_WIDTH_IN_PIXELS);
      int margemEscalaPrecos = 75; 
      int posXDesejada = (int)(larguraGrafico - margemEscalaPrecos);
      int posXFinal = (x < posXDesejada) ? x + 40 : posXDesejada;

      int posYFinal = y - 18; 

      CriarTextoLabelGrafico(LABEL_PRECO_POSICAO, textoFinal, posXFinal, posYFinal, 9, corFinal);
   }
}

void CriarTextoLabelGrafico(string nome, string texto, int x, int y, int tamanhoFonte, color cor)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x); 
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanhoFonte);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetString(0, nome, OBJPROP_FONT, "Arial Black");
}

ENUM_BASE_CORNER ObterMelhorCantoPainel()
{
   double precoMaximoVisivel = ChartGetDouble(ChartID(), CHART_PRICE_MAX);
   double precoMinimoVisivel = ChartGetDouble(ChartID(), CHART_PRICE_MIN);
   
   if(precoMaximoVisivel <= precoMinimoVisivel) return CORNER_RIGHT_UPPER;

   double amplitude = precoMaximoVisivel - precoMinimoVisivel;
   double linhaCorteTopo = precoMaximoVisivel - (amplitude * 0.30);

   int totalVisiveis = (int)ChartGetInteger(ChartID(), CHART_VISIBLE_BARS);
   if(totalVisiveis <= 0) return CORNER_RIGHT_UPPER;

   int limiteAvaliacao = (int)MathMax(1, totalVisiveis * 0.35);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(_Symbol, _Period, 0, limiteAvaliacao, rates);
   if(copied > 0)
   {
      for(int i = 0; i < copied; i++)
      {
         if(rates[i].high >= linhaCorteTopo)
         {
            return CORNER_RIGHT_LOWER; 
         }
      }
   }
   
   return CORNER_RIGHT_UPPER; 
}

void AtualizarPainelVisualEmTempoReal()
{
   double exSL = CalcularPontosSL();
   double exTP = ArredondarParaPassoDoPreco(exSL * (double)InpRiskRewardRatio);
   int margemDireita = 400;  
   
   ENUM_BASE_CORNER cantoPainel = ObterMelhorCantoPainel();

   string textoPnLPainel = StringFormat("Posição (0 %s)", _Symbol);
   color corPnL = clrSilver;

   // Validação de limite diário para atualizar a mensagem visual de status
   int maxOrdensPermitidas = InpMaxNegociosDia * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   color corStatus = clrDarkSlateGray;

   if(operacoesFeitasHoje >= maxOrdensPermitidas)
   {
      globalMensagemStatus = "Já deu por hoje";
      corStatus = clrRed;
      ApagarLinhasProjecao();
   }
   else
   {
      // Se o limite aumentou e estava bloqueado, restaura o estado padrão inicial caso não haja posição aberta
      if(globalMensagemStatus == "Já deu por hoje" && !PositionSelect(_Symbol))
      {
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
      }
   }

   if(PositionSelect(_Symbol))
   {
      posicaoEstavaAberta = true; 
      if(operacoesFeitasHoje < maxOrdensPermitidas)
         globalMensagemStatus = "Ordem executada! (CTRL + Enter) para Zerar";

      long tipoPos = PositionGetInteger(POSITION_TYPE);
      double precoAberturaPos = PositionGetDouble(POSITION_PRICE_OPEN);
      double precoAtual = (tipoPos == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lucroFinanceiro = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
      
      double diffPontos = 0.0;
      if(tipoPos == POSITION_TYPE_BUY)
         diffPontos = (precoAtual - precoAberturaPos) / _Point;
      else
         diffPontos = (precoAberturaPos - precoAtual) / _Point;

      string tipoStr = (tipoPos == POSITION_TYPE_BUY) ? "Compra" : "Venda";
      int volumePos = (int)PositionGetDouble(POSITION_VOLUME);
      
      string valorFormatado = DoubleToString(lucroFinanceiro, 2);
      StringReplace(valorFormatado, ".", ",");
      
      textoPnLPainel = StringFormat("(%s: %d %s) | PnL: R$ %s | %.0f pontos", tipoStr, volumePos, _Symbol, valorFormatado, diffPontos);
      
      if(lucroFinanceiro > 0.0)
         corPnL = clrLimeGreen;
      else if(lucroFinanceiro < 0.0)
         corPnL = clrRed;
      else
         corPnL = clrSilver;
   
      string textoLabel = StringFormat("R$ %s", valorFormatado);
      AtualizarLabelGraficoPreco(textoLabel, corPnL, true);
   }
   else
   {
      if(posicaoEstavaAberta)
      {
         VerificarResultadoETocarSomSaida();
         if(operacoesFeitasHoje < maxOrdensPermitidas)
            globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }

      ObjectDelete(0, LABEL_PRECO_POSICAO);
   }

   // Métricas do Dia
   double totalDoDia = CalcularResultadoFinanceiroDoDia();
   double totalPontosDia = CalcularPontosDoDia();
   
   string strTotalDia = DoubleToString(totalDoDia, 2);
   StringReplace(strTotalDia, ".", ",");
   
   string strPontosDia = DoubleToString(totalPontosDia, 0);
   StringReplace(strPontosDia, ".", ",");

   string textoTotalDia = StringFormat("PnL Diário: R$ %s | %s Pontos | Operações: %d/%d", strTotalDia, strPontosDia, operacoesFeitasHoje, maxOrdensPermitidas);
   
   color corTotalDia = clrSilver;
   if(totalDoDia > 0.0)
      corTotalDia = clrLimeGreen;
   else if(totalDoDia < 0.0)
      corTotalDia = clrRed;

   // Métricas do Mês
   double totalDoMes = CalcularResultadoFinanceiroDoMes();
   double totalPontosMes = CalcularPontosDoMes();
   int totalOperacoesMes = CalcularOperacoesDoMes();

   string strTotalMes = DoubleToString(totalDoMes, 2);
   StringReplace(strTotalMes, ".", ",");

   string strPontosMes = DoubleToString(totalPontosMes, 0);
   StringReplace(strPontosMes, ".", ",");

   string textoTotalMes = StringFormat("PnL Mensal: R$ %s | %s Pontos | Operações: %d", strTotalMes, strPontosMes, totalOperacoesMes);

   color corTotalMes = clrSilver;
   if(totalDoMes > 0.0)
      corTotalMes = clrLimeGreen;
   else if(totalDoMes < 0.0)
      corTotalMes = clrRed;

   if(cantoPainel == CORNER_RIGHT_LOWER)
   {
      CriarTextoLabel(PREFIX_TXT+"0", textoPnLPainel, margemDireita, 130, 9, corPnL, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"1", "-----------------------------------------------------------------------------------------", margemDireita, 117, 9, clrSilver, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"2", "Maior candle do dia: " + DoubleToString(maiorAmplitudeGlobal, 0) + " pontos | Horário: " + horarioMaiorCandle, margemDireita, 103, 9, clrOrangeRed, cantoPainel); 
      CriarTextoLabel(PREFIX_TXT+"3", "Total de candles do dia: " + IntegerToString(totalCandlesDoDia), margemDireita, 88, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"4", "Alvos (" + IntegerToString(InpRiskRewardRatio) + ":1): SL = " + DoubleToString(exSL, 2) + " pts | TP = " + DoubleToString(exTP, 2) + " pts", margemDireita, 73, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"7", textoTotalMes, margemDireita, 58, 9, corTotalMes, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"6", textoTotalDia, margemDireita, 43, 9, corTotalDia, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"5", globalMensagemStatus, margemDireita, 28, 9, corStatus, cantoPainel);
   }
   else
   {
      CriarTextoLabel(PREFIX_TXT+"5", globalMensagemStatus, margemDireita, 20, 9, corStatus, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"6", textoTotalDia, margemDireita, 35, 9, corTotalDia, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"7", textoTotalMes, margemDireita, 50, 9, corTotalMes, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"2", "Maior candle do dia: " + DoubleToString(maiorAmplitudeGlobal, 0) + " pontos | Horário: " + horarioMaiorCandle, margemDireita, 65, 9, clrOrangeRed, cantoPainel); 
      CriarTextoLabel(PREFIX_TXT+"3", "Total de candles do dia: " + IntegerToString(totalCandlesDoDia), margemDireita, 80, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"4", "Alvos (" + IntegerToString(InpRiskRewardRatio) + ":1): SL = " + DoubleToString(exSL, 2) + " pts | TP = " + DoubleToString(exTP, 2) + " pts", margemDireita, 95, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"1", "-----------------------------------------------------------------------------------------", margemDireita, 108, 9, clrSilver, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"0", textoPnLPainel, margemDireita, 121, 9, corPnL, cantoPainel);
   }
   
   ChartRedraw(0);
}

void CriarTextoLabel(string nome, string texto, int x, int y, int tamanhoFonte, color cor, ENUM_BASE_CORNER canto = CORNER_RIGHT_UPPER)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetInteger(0, nome, OBJPROP_CORNER, canto);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x); 
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanhoFonte);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetString(0, nome, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
}

void DesenharLinhaH(string nome, double preco, color cor, ENUM_LINE_STYLE estilo, int largura)
{
   if(ObjectFind(0, nome) >= 0) ObjectDelete(0, nome);

   ObjectCreate(0, nome, OBJ_HLINE, 0, 0, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, largura);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
}

void ApagarLinhasProjecao()
{
   operacaoPendente = false;
   tipoOperacao = 0;
   ObjectDelete(0, PREFIX_OBJ+"Entrada");
   ObjectDelete(0, PREFIX_OBJ+"Loss");
   ObjectDelete(0, PREFIX_OBJ+"Gain");
   ChartRedraw(0);
}