//+------------------------------------------------------------------+
//|         Boleta_Indice_Com_Painel_v2.04.mq5                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "2.04"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Parâmetros de Entrada
input group "--- Configurações Operacionais ---"
input int               InpFaseInicial     = 1;           // Fase Inicial do Trader (1 a 10)
input int               InpMaxNegociosDia  = 3;           // Máximo de Negócios por Dia

input group "--- Configuração do Indicador Volatilidade ---"
input int               InpATRPeriod       = 14;        // Período do ATR utilizado na fórmula

const string PREFIX_OBJ = "Proj_";
const string PREFIX_TXT = "Painel_";
const string LABEL_PRECO_POSICAO = "LABEL_PRECO_POSICAO";

// Variáveis globais de controle de estado e fases
int  faseAtual = 1;
bool operacaoPendente = false;
int  tipoOperacao = 0; // 1 = Compra, 2 = Venda
int  handleATR;        
string globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
bool posicaoEstavaAberta = false; 

// Variável de controle do canto do painel (Padrão: Superior Direito)
ENUM_BASE_CORNER cantoPainelAtual = CORNER_RIGHT_UPPER;

// Variáveis das métricas do dia
double maiorAmplitudeGlobal = 0.0; 
string horarioMaiorCandle = "";    
int    totalCandlesDoDia = 0;      

// Estrutura de dados para a tabela de Fases
struct StructFase
{
   double lossDiario;
   double gainDiario;
   int    loteMax;
   double lft;
   double acumProg;
   double acumReg;
};

// Tabela de Fases baseada na imagem de referência
StructFase TabelaFases[11] = 
{
   {0.0,    0.0,    0,   0.0,    0.0,       0.0},        // Índice 0 (Não usado)
   {-50.0,  50.0,   1,  -25.0,   250.0,    -250.0},      // Fase 1
   {-100.0, 100.0,  2,  -50.0,   500.0,    -500.0},      // Fase 2
   {-150.0, 150.0,  3,  -75.0,   750.0,    -750.0},      // Fase 3
   {-168.0, 200.0,  4,  -84.0,   1200.0,   -1200.0},     // Fase 4
   {-190.0, 250.0,  5,  -95.0,   1250.0,   -1250.0},     // Fase 5
   {-213.0, 300.0,  6,  -106.5,  1500.0,   -1500.0},     // Fase 6
   {-234.5, 350.0,  7,  -117.25, 1750.0,   -1750.0},     // Fase 7
   {-248.0, 400.0,  8,  -124.0,  2000.0,   -2000.0},     // Fase 8
   {-283.5, 450.0,  9,  -141.75, 2250.0,   -2250.0},     // Fase 9
   {-305.0, 500.0,  10, -152.5,  2500.0,   -2500.0}      // Fase 10
};

int OnInit()
{
   faseAtual = MathMin(10, MathMax(1, InpFaseInicial));

   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(handleATR == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao inicializar o indicador ATR.");
      return(INIT_FAILED);
   }

   EventSetMillisecondTimer(50);

   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, "Btn_FaseMenos");
   ObjectDelete(0, "Btn_FaseMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");

   Print("==========================================================");
   Print("[SISTEMA PRONTO] Boleta de Fases carregada. Fase atual: ", faseAtual);
   Print("==========================================================");

   ProcessarRotinasDeAtualizacao();
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
   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, "Btn_FaseMenos");
   ObjectDelete(0, "Btn_FaseMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
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
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      AtualizarLabelGraficoPreco("", clrNONE, false);
      ProcessarRotinasDeAtualizacao(); 
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "Btn_FaseMenos")
      {
         if(faseAtual > 1) faseAtual--;
         ChartRedraw(0);
      }
      else if(sparam == "Btn_FaseMais")
      {
         if(faseAtual < 10) faseAtual++;
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelCima")
      {
         cantoPainelAtual = CORNER_RIGHT_UPPER;
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelBaixo")
      {
         cantoPainelAtual = CORNER_RIGHT_LOWER;
         ChartRedraw(0);
      }
   }
   
   if(id == CHARTEVENT_KEYDOWN)
   {
      int tecla = (int)lparam;

      int maxOrdensPermitidas = InpMaxNegociosDia * 2;
      int operacoesFeitasHoje = CalcularOperacoesDoDia();
      double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

      bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);
      bool limiteLossAtingido    = (pnlDiarioAtual <= TabelaFases[faseAtual].lossDiario);
      bool limiteGainAtingido    = (pnlDiarioAtual >= TabelaFases[faseAtual].gainDiario);

      if(limiteOrdensAtingido || limiteLossAtingido || limiteGainAtingido)
      {
         globalMensagemStatus = "Já deu por hoje";
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

double ObterPontosAlvosFase(double &slOut, double &tpOut)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0) tickValue = 1.0;

   double financeiroLoss = MathAbs(TabelaFases[faseAtual].lossDiario);
   double financeiroGain = MathAbs(TabelaFases[faseAtual].gainDiario);
   int loteMaximo = TabelaFases[faseAtual].loteMax;

   double pontosLossTotal = (financeiroLoss / (tickValue * loteMaximo)) * (tickSize / _Point);
   double pontosGainTotal = (financeiroGain / (tickValue * loteMaximo)) * (tickSize / _Point);

   slOut = ArredondarParaPassoDoPreco(MathMax(50.0, pontosLossTotal / 3.0));
   tpOut = ArredondarParaPassoDoPreco(MathMax(50.0, pontosGainTotal / 3.0));
   return slOut;
}

void EnviarOrdemMercado()
{
   int maxOrdensPermitidas = InpMaxNegociosDia * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

   if(operacoesFeitasHoje >= maxOrdensPermitidas || 
      pnlDiarioAtual <= TabelaFases[faseAtual].lossDiario || 
      pnlDiarioAtual >= TabelaFases[faseAtual].gainDiario)
   {
      globalMensagemStatus = "Já deu por hoje";
      ApagarLinhasProjecao();
      return;
   }

   double pontosSL = 0, pontosTP = 0;
   ObterPontosAlvosFase(pontosSL, pontosTP);

   int loteFase = TabelaFases[faseAtual].loteMax;

   if(tipoOperacao == 1) 
   {
      double precoCompra = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      double slCompra    = NormalizeDouble(precoCompra - (pontosSL * _Point), _Digits);
      double tpCompra    = NormalizeDouble(precoCompra + (pontosTP * _Point), _Digits);
      trade.Buy(loteFase, _Symbol, precoCompra, slCompra, tpCompra, "Compra Fase " + IntegerToString(faseAtual));
   }
   else if(tipoOperacao == 2) 
   {
      double precoVenda = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      double slVenda    = NormalizeDouble(precoVenda + (pontosSL * _Point), _Digits);
      double tpVenda    = NormalizeDouble(precoVenda - (pontosTP * _Point), _Digits);
      trade.Sell(loteFase, _Symbol, precoVenda, slVenda, tpVenda, "Venda Fase " + IntegerToString(faseAtual));
   }

   ApagarLinhasProjecao();
   globalMensagemStatus = "Ordem enviada com Lote Max da Fase! Pressione (ESC)";
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
      if(!PlaySound("gain.wav")) PlaySound("\\Audio\\gain.wav");
   }
   else
   {
      if(!PlaySound("stops.wav")) PlaySound("\\Audio\\stops.wav");
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

double CalcularPontosDoPeriodo(datetime tempoInicio)
{
   HistorySelect(tempoInicio, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   double totalPontos = 0.0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0 && HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
      {
         long tipoEntrada = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
         if(tipoEntrada == DEAL_ENTRY_OUT || tipoEntrada == DEAL_ENTRY_INOUT)
         {
            double precoSaida = HistoryDealGetDouble(ticketDeal, DEAL_PRICE);
            long posicaoID = HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID);
            
            for(int j = 0; j < totalDeals; j++)
            {
               ulong ticketEntrada = HistoryDealGetTicket(j);
               if(ticketEntrada > 0 && HistoryDealGetString(ticketEntrada, DEAL_SYMBOL) == _Symbol)
               {
                  if(HistoryDealGetInteger(ticketEntrada, DEAL_POSITION_ID) == posicaoID &&
                     HistoryDealGetInteger(ticketEntrada, DEAL_ENTRY) == DEAL_ENTRY_IN)
                  {
                     double precoEntrada = HistoryDealGetDouble(ticketEntrada, DEAL_PRICE);
                     long tipoPos = HistoryDealGetInteger(ticketEntrada, DEAL_TYPE); 
                     
                     if(tipoPos == 0) 
                        totalPontos += (precoSaida - precoEntrada) / _Point;
                     else             
                        totalPontos += (precoEntrada - precoSaida) / _Point;
                        
                     break;
                  }
               }
            }
         }
      }
   }
   return totalPontos;
}

double CalcularPontosDoDia()
{
   return CalcularPontosDoPeriodo(iTime(_Symbol, PERIOD_D1, 0));
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
            if(entradaDeal == DEAL_ENTRY_IN || entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               totalOps++;
            }
         }
      }
   }

   return totalOps;
}

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
   return CalcularPontosDoPeriodo(ObterInicioDoMes());
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
            if(entradaDeal == DEAL_ENTRY_IN || entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
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
   double pontosSL = 0, pontosTP = 0;
   ObterPontosAlvosFase(pontosSL, pontosTP);

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
      int posXDesejada = (int)(larguraGrafico - 75);
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

void CriarBotaoFase(string nome, string texto, int x, int y, int largura, int altura)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, nome, OBJPROP_CORNER, cantoPainelAtual);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, nome, OBJPROP_YSIZE, altura);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, 9);
}

void AtualizarPainelVisualEmTempoReal()
{
   double exSL = 0, exTP = 0;
   ObterPontosAlvosFase(exSL, exTP);
   int margemDireita = 380;  
   
   string textoPnLPainel = StringFormat("Posição (0 %s)", _Symbol);
   color corPnL = clrSilver;

   int maxOrdensPermitidas = InpMaxNegociosDia * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();
   color corStatus = clrDarkSlateGray;

   bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);
   bool limiteLossAtingido    = (pnlDiarioAtual <= TabelaFases[faseAtual].lossDiario);
   bool limiteGainAtingido    = (pnlDiarioAtual >= TabelaFases[faseAtual].gainDiario);

   if(limiteOrdensAtingido || limiteLossAtingido || limiteGainAtingido)
   {
      globalMensagemStatus = "Já deu por hoje";
      corStatus = clrBlack;
      ApagarLinhasProjecao();
   }
   else
   {
      if(globalMensagemStatus == "Já deu por hoje" && !PositionSelect(_Symbol))
      {
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
      }
   }

   if(PositionSelect(_Symbol))
   {
      posicaoEstavaAberta = true; 
      if(!limiteOrdensAtingido && !limiteLossAtingido && !limiteGainAtingido)
         globalMensagemStatus = "Ordem executada! (CTRL + Enter) para Zerar";

      long tipoPos = PositionGetInteger(POSITION_TYPE);
      double precoAberturaPos = PositionGetDouble(POSITION_PRICE_OPEN);
      double precoAtual = (tipoPos == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lucroFinanceiro = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
      
      double diffPontos = (tipoPos == POSITION_TYPE_BUY) ? (precoAtual - precoAberturaPos) / _Point : (precoAberturaPos - precoAtual) / _Point;

      string tipoStr = (tipoPos == POSITION_TYPE_BUY) ? "Compra" : "Venda";
      int volumePos = (int)PositionGetDouble(POSITION_VOLUME);
      
      string valorFormatado = DoubleToString(lucroFinanceiro, 2);
      StringReplace(valorFormatado, ".", ",");
      
      textoPnLPainel = StringFormat("(%s: %d %s) | PnL: R$ %s | %.0f pontos", tipoStr, volumePos, _Symbol, valorFormatado, diffPontos);
      
      if(lucroFinanceiro > 0.0) corPnL = clrLimeGreen;
      else if(lucroFinanceiro < 0.0) corPnL = clrRed;
      
      AtualizarLabelGraficoPreco(StringFormat("R$ %s", valorFormatado), corPnL, true);
   }
   else
   {
      if(posicaoEstavaAberta)
      {
         VerificarResultadoETocarSomSaida();
         if(!limiteOrdensAtingido && !limiteLossAtingido && !limiteGainAtingido)
            globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
      ObjectDelete(0, LABEL_PRECO_POSICAO);
   }

   double totalDoDia = CalcularResultadoFinanceiroDoDia();
   double totalPontosDia = CalcularPontosDoDia();
   string strTotalDia = DoubleToString(totalDoDia, 2); StringReplace(strTotalDia, ".", ",");
   string strPontosDia = DoubleToString(totalPontosDia, 0); StringReplace(strPontosDia, ".", ",");
   string textoTotalDia = StringFormat("PnL Diário: R$ %s | %s pts | Operações: %d/%d", strTotalDia, strPontosDia, operacoesFeitasHoje, maxOrdensPermitidas);
   color corTotalDia = (totalDoDia > 0.0) ? clrLimeGreen : (totalDoDia < 0.0 ? clrRed : clrSilver);

   double totalDoMes = CalcularResultadoFinanceiroDoMes();
   double totalPontosMes = CalcularPontosDoMes();
   string strTotalMes = DoubleToString(totalDoMes, 2); StringReplace(strTotalMes, ".", ",");
   string strPontosMes = DoubleToString(totalPontosMes, 0); StringReplace(strPontosMes, ".", ",");
   string textoTotalMes = StringFormat("PnL Mensal: R$ %s | %s pts | Operações: %d", strTotalMes, strPontosMes, CalcularOperacoesDoMes());
   color corTotalMes = (totalDoMes > 0.0) ? clrLimeGreen : (totalDoMes < 0.0 ? clrRed : clrSilver);

   StructFase faseInfo = TabelaFases[faseAtual];
   string strLossDiario = DoubleToString(faseInfo.lossDiario, 2); StringReplace(strLossDiario, ".", ",");
   string strGainDiario = DoubleToString(faseInfo.gainDiario, 2); StringReplace(strGainDiario, ".", ",");
   string strLFT        = DoubleToString(faseInfo.lft, 2);        StringReplace(strLFT, ".", ",");
   string strAcumProg   = DoubleToString(faseInfo.acumProg, 2);   StringReplace(strAcumProg, ".", ",");
   string strAcumReg    = DoubleToString(faseInfo.acumReg, 2);    StringReplace(strAcumReg, ".", ",");

   string textoFaseLabel   = StringFormat("Fase Atual: %d (Loss: R$ %s | Gain: R$ %s)", faseAtual, strLossDiario, strGainDiario);
   string textoLoteMax     = StringFormat("Lote Máximo Permitido: %d contratos", faseInfo.loteMax);
   string textoLFT         = StringFormat("Loss From Top (LFT): R$ %s", strLFT);
   string textoAcumProg    = StringFormat("Acúmulo Progressivo: R$ %s", strAcumProg);
   string textoAcumReg     = StringFormat("Acúmulo Regressivo: R$ %s", strAcumReg);
   string textoAlvosFase   = StringFormat("Alvos da Fase: SL = %.2f pts | TP = %.2f pts", exSL, exTP);

   // Criação dos botões de fase e alternância de canto (com setas ▲ e ▼)
   CriarBotaoFase("Btn_FaseMenos", "-", 95, 95, 25, 18);
   CriarBotaoFase("Btn_FaseMais",  "+", 65, 95, 25, 18);
   CriarBotaoFase("Btn_PainelCima",  "▲",95, 120, 25, 18);
   CriarBotaoFase("Btn_PainelBaixo", "▼", 65, 120, 25, 18);

   CriarTextoLabel(PREFIX_TXT+"5", globalMensagemStatus, margemDireita, 20, 9, corStatus, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"6", textoTotalDia, margemDireita, 35, 9, corTotalDia, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"7", textoTotalMes, margemDireita, 50, 9, corTotalMes, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"8", textoFaseLabel, margemDireita, 65, 9, clrDodgerBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"9", textoLoteMax, margemDireita, 80, 9, clrMediumSeaGreen, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"10", textoLFT, margemDireita, 95, 9, clrOrange, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"11", textoAcumProg, margemDireita, 110, 9, clrLimeGreen, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"12", textoAcumReg, margemDireita, 125, 9, clrTomato, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"4", textoAlvosFase, margemDireita, 140, 9, clrSteelBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"1", "-----------------------------------------------------------------------------------------", margemDireita, 153, 9, clrSilver, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"0", textoPnLPainel, margemDireita, 166, 9, corPnL, cantoPainelAtual);
   
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