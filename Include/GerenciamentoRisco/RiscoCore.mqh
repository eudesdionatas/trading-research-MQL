//+------------------------------------------------------------------+
//| RiscoCore.mqh                                                    |
//| Lógica compartilhada da boleta de Gerenciamento de Risco          |
//| (painel, ordens, watchdog, sons, PnL) - independente do ativo.    |
//| A diferença de comportamento entre ativos (WDO, WIN, ...) vem     |
//| inteiramente de cfgAtiva (ver RiscoConfigAtivos.mqh), nunca de    |
//| um "if" espalhado pelo código.                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

// Config do ativo detectado automaticamente (ou forçado) no OnInit - ver
// DetectarConfigAtivo() em RiscoConfigAtivos.mqh.
ConfigAtivo cfgAtiva;

//--- Parâmetros de Entrada
input group "--- Configurações Operacionais ---"
input int               InpFaseInicial       = 1;           // Fase Inicial do Trader (1 a 10)
input int               InpNegociosDiaInicial = 3;           // Negócios (pares C/V) permitidos por dia - deve ser ímpar

const string PREFIX_OBJ = "Proj_";
const int NEGOCIOS_DIA_MINIMO = 3; // piso mínimo de "Negócios por dia" - o botão "-2" nunca pode ir abaixo disso
const string PREFIX_TXT = "Painel_";
const string LABEL_PRECO_POSICAO = "LABEL_PRECO_POSICAO";

// Variáveis globais de controle de estado e fases
int  faseAtual = 1;
bool operacaoPendente = false;
int  tipoOperacao = 0; // 1 = Compra, 2 = Venda
bool usarPrecoDoClique = false;      // true quando a prévia usa um preço de referência diferente do Ask/Bid atual (clique/mouse)
double precoCliqueReferencia = 0.0;  // preço de referência da prévia (a ordem real ainda é a mercado)

// Controle do modo "armado por modificador": SHIFT (compra) ou CTRL (venda) armam a
// operação automaticamente enquanto ficam pressionados (sem precisar de clique), e
// desarmam sozinhos assim que a tecla é solta (detectado por polling - ver
// ProcessarModificadoresDeArme()). Isso é diferente de C/V, que ficam armados até
// Enter/ESC/clique, independente do estado de teclas.
bool armadoPorModificador = false;
int  modificadorTipoOperacao = 0; // 1 = compra (SHIFT), 2 = venda (CTRL)
int  ultimoMouseXPixel = -1;
int  ultimoMouseYPixel = -1;
string globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
bool posicaoEstavaAberta = false;

// Controle do som de saída (gain/stop): o fechamento de uma posição (manual ou por SL/TP)
// nem sempre aparece imediatamente em HistoryDealsTotal() no mesmo tick em que a posição
// já deixou de existir - por isso o som é tocado de forma assíncrona, com retentativas,
// e sempre casado com o ticket exato da posição (POSITION_IDENTIFIER), nunca com "o último
// deal do símbolo" (que poderia pertencer a outra operação).
ulong ultimoTicketPosicaoAberta = 0;
double ultimoLucroFlutuantePosicao = 0.0; // fallback: último P&L flutuante conhecido, caso o histórico não sincronize a tempo
bool  aguardandoSomSaida = false;
int   tentativasSomSaida = 0;
const int MAX_TENTATIVAS_SOM_SAIDA = 60; // ~60 * 50ms = 3 segundos antes de usar o fallback

// Watchdog de proteção: guarda o SL/TP (em preço) que DEVERIA estar aplicado na posição
// aberta pelo robô. A cada ciclo, verifica se a posição ainda tem esse SL/TP - se algo
// (falha silenciosa do PositionModify, corretora, etc.) tirar a proteção, o robô detecta
// e tenta reaplicar automaticamente, avisando o usuário.
double slAlvoPosicaoAtual = 0.0;
double tpAlvoPosicaoAtual = 0.0;
int    contadorCiclosSemProtecao = 0;
const int CICLOS_ENTRE_TENTATIVAS_PROTECAO = 20; // ~20 * 50ms = 1s entre tentativas de reaplicar
int    tentativasSomProtecaoFalha = 0;           // já tocou o som de erro nesta falha de proteção? (0 = não, 1 = sim)
const int MAX_TENTATIVAS_SOM_PROTECAO = 1;       // som toca só 1x por episódio - o painel (status) já avisa nas tentativas seguintes

// Variável de controle do canto do painel (Padrão: Superior Direito)
ENUM_BASE_CORNER cantoPainelAtual = CORNER_RIGHT_UPPER;

// Quantidade de linhas que o painel ocupou na última atualização (varia conforme existam
// ou não posições extra-gráfico sendo exibidas) - usada pelo cálculo do retângulo de
// colisão do reposicionamento automático (ObterRetanguloPainel), para a altura acompanhar
// o painel mesmo quando ele cresce/encolhe dinamicamente.
int totalLinhasPainelAtual = 12;

// Atalho CTRL+ESC+ENTER ("zera TODAS as posições suportadas") e botão "Zerar" (mesma ação
// via mouse, com ESC+Clique) - ESC tem TERMINAL_KEYSTATE_ESCAPE nativo no MQL5, então dá
// pra checar "está pressionada agora?" direto, sem precisar do truque de GetTickCount()
// que SPACE/E exigiam (por não terem um estado dedicado).

// Reset visual "atrasado" dos botões: em vez de voltar ao estado normal no mesmo instante
// do clique (rápido demais pra perceber), o botão clicado fica marcado como "pressionado"
// por DURACAO_VISUAL_CLIQUE_MS antes de ser resetado - dando um flash visual perceptível.
string botaoPendenteDeReset = "";
uint   tickBotaoPendenteDeReset = 0;
const uint DURACAO_VISUAL_CLIQUE_MS = 100;

// Fila de sons de gain/loss: como o PlaySound() só tem um canal de áudio, tocar dois sons
// muito próximos no tempo faz o segundo CORTAR o primeiro antes dele terminar (não fica
// represado, mas também não toca por completo) - isso fica evidente ao fechar várias
// posições de uma vez (ex.: CTRL+ESC+ENTER). Em vez de tocar na hora, essas chamadas
// entram numa fila e são liberadas uma de cada vez, respeitando um intervalo mínimo.
string filaSons[];
uint   proximoSomDaFilaLiberadoEm = 0;
const uint INTERVALO_ENTRE_SONS_MS = 1150; // gain.wav dura 1000ms, loss.wav dura ~1098ms - 1150ms cobre os dois com folga

// Variáveis das métricas do dia
double maiorAmplitudeGlobal = 0.0;
string horarioMaiorCandle = "";
int    totalCandlesDoDia = 0;

// Controles de gestão de risco / fase
int  papeisPorOperacao   = 1;     // "V" - quantidade de papéis usada em cada envio de ordem (<= loteMax da fase)
int  baseNegociosDia     = 3;     // "E" - quantidade de negócios (pares C/V) configurada pelo usuário (sempre ímpar)
bool bonusConcedidoHoje  = false; // Controla se o bônus de +1 negócio (dia muito bom / LFT) já foi concedido hoje
datetime ultimoDiaVerificado = 0;

// Prefixo das variáveis globais do terminal usadas para persistir o estado configurado pelo
// usuário (fase, papéis, negócios/dia, canto do painel) através de trocas de timeframe/símbolo
// no gráfico, que forçam o MetaTrader a descarregar e recarregar o EA (OnDeinit -> OnInit).
// Variáveis globais do terminal (GlobalVariable) sobrevivem a esse ciclo, diferente das
// variáveis normais do EA, que voltariam ao valor dos inputs a cada reinício.
string PrefixoEstadoPersistente()
{
   return "GR_EstadoFases_" + _Symbol + "_" + IntegerToString(ChartID()) + "_";
}

void SalvarEstadoPersistente()
{
   string p = PrefixoEstadoPersistente();
   GlobalVariableSet(p + "fase", (double)faseAtual);
   GlobalVariableSet(p + "papeis", (double)papeisPorOperacao);
   GlobalVariableSet(p + "negocios", (double)baseNegociosDia);
   GlobalVariableSet(p + "canto", (double)cantoPainelAtual);
}

void CarregarEstadoPersistente()
{
   string p = PrefixoEstadoPersistente();

   if(GlobalVariableCheck(p + "fase"))
      faseAtual = (int)GlobalVariableGet(p + "fase");

   if(GlobalVariableCheck(p + "negocios"))
      baseNegociosDia = MathMax(NEGOCIOS_DIA_MINIMO, (int)GlobalVariableGet(p + "negocios"));

   if(GlobalVariableCheck(p + "papeis"))
      papeisPorOperacao = (int)GlobalVariableGet(p + "papeis");

   if(GlobalVariableCheck(p + "canto"))
      cantoPainelAtual = (ENUM_BASE_CORNER)(int)GlobalVariableGet(p + "canto");
}

// StructFase, ConfigAtivo e a tabela de fases de cada ativo agora vivem em
// RiscoConfigAtivos.mqh, incluído antes deste arquivo.

//+------------------------------------------------------------------+
//| Layout do painel                                                 |
//+------------------------------------------------------------------+
int LINE_HEIGHT   = 16;
int BASE_MARGIN   = 20;
int MARGEM_DIREITA_TEXTO = 400;
int LARGURA_SEPARADOR = 369; // largura do separador em pixels (independe de fonte/caracteres)

// Retorna a coordenada Y da "linha lógica" i (0..10, onde 0 = linha 1 da especificação).
// Importante: o MetaTrader já mede o Y a partir do topo quando o canto é superior e a
// partir da base quando o canto é inferior - ou seja, usar a MESMA fórmula de distância
// para os dois cantos já produz o espelhamento visual (linha 0 fica perto do topo quando
// o painel está em cima, e perto da base quando está embaixo). Se invertêssemos a fórmula
// aqui também, as duas inversões se cancelariam e a ordem visual ficaria idêntica nos dois
// cantos - foi exatamente o bug reportado.
int GetLinhaY(int i)
{
   return BASE_MARGIN + i * LINE_HEIGHT;
}

// Escolhe automaticamente preto ou branco para texto que precisa de bom contraste contra
// a cor de fundo ATUAL do gráfico (o usuário pode trocar entre fundo claro/escuro a
// qualquer momento nas propriedades do gráfico) - usa a fórmula padrão de luminância
// percebida (YIQ) para decidir qual dos dois contrasta melhor.
color CorContrasteComFundo()
{
   long corFundo = 0;
   if(!ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0, corFundo))
      return clrBlack; // não conseguiu ler a cor de fundo - usa preto como padrão seguro

   int r = (int)(corFundo & 0xFF);
   int g = (int)((corFundo >> 8) & 0xFF);
   int b = (int)((corFundo >> 16) & 0xFF);

   double luminancia = (r * 299 + g * 587 + b * 114) / 1000.0; // 0 (preto) a 255 (branco)

   return (luminancia > 128) ? clrBlack : clrWhite;
}

// Converte um deslocamento "para baixo, na tela" em unidades de Y_DISTANCE, considerando
// que no canto inferior o Y_DISTANCE cresce para CIMA na tela (mede a partir da base) -
// logo o mesmo deslocamento precisa ter sinal invertido para continuar descendo visualmente.
int OffsetParaBaixo(int delta)
{
   return (cantoPainelAtual == CORNER_RIGHT_UPPER) ? delta : -delta;
}

//+------------------------------------------------------------------+
//| Reposicionamento automático do painel (topo <-> base)             |
//| Detecta se algum candle visível (inclusive o que está se formando |
//| em tempo real) está ocupando a mesma área de tela do painel e, se |
//| estiver, manda o painel para o canto oposto - usando exatamente o |
//| mesmo mecanismo do botão ▲/▼ (MoverPainelPara), então o botão      |
//| manual continua funcionando normalmente a qualquer momento.       |
//+------------------------------------------------------------------+

// Muda o canto do painel de forma centralizada - usada tanto pelo botão ▲/▼ quanto pelo
// reposicionamento automático, para garantir que os dois caminhos se comportem de forma
// idêntica (persistência do estado incluída).
void MoverPainelPara(ENUM_BASE_CORNER canto)
{
   if(cantoPainelAtual == canto) return;
   cantoPainelAtual = canto;
   SalvarEstadoPersistente();
}

// Retângulo aproximado (em pixels de tela, canto 0,0 = topo-esquerda do gráfico) ocupado
// pelo painel quando ele está no canto informado. Generoso de propósito (com folga extra
// em X e Y) para não deixar candle "quase" encostando passar despercebido.
void ObterRetanguloPainel(ENUM_BASE_CORNER canto, int &xEsq, int &xDir, int &yTopo, int &yBase)
{
   long larguraGrafico = ChartGetInteger(ChartID(), CHART_WIDTH_IN_PIXELS);
   long alturaGrafico  = ChartGetInteger(ChartID(), CHART_HEIGHT_IN_PIXELS);

   xDir = (int)larguraGrafico;
   xEsq = (int)larguraGrafico - MARGEM_DIREITA_TEXTO - LARGURA_SEPARADOR - 20; // folga de segurança

   // totalLinhasPainelAtual é recalculado a cada desenho do painel (pode crescer quando
   // aparecem posições de outros ativos suportados) - assim o retângulo de colisão
   // acompanha o tamanho real do painel em vez de assumir sempre 12 linhas fixas.
   int alturaPainel = GetLinhaY(totalLinhasPainelAtual) + 10; // + folga de segurança

   if(canto == CORNER_RIGHT_UPPER)
   {
      yTopo = 0;
      yBase = alturaPainel;
   }
   else // CORNER_RIGHT_LOWER
   {
      yBase = (int)alturaGrafico;
      yTopo = (int)alturaGrafico - alturaPainel;
   }
}

// Verifica se algum candle atualmente visível na tela (incluindo o que está se formando,
// e qualquer que seja a posição de rolagem do gráfico) invade o retângulo do painel no
// canto informado.
bool PainelInvadidoPorCandle(ENUM_BASE_CORNER canto)
{
   int xEsq, xDir, yTopo, yBase;
   ObterRetanguloPainel(canto, xEsq, xDir, yTopo, yBase);
   if(xEsq >= xDir || yTopo >= yBase) return false; // gráfico ainda sem tamanho válido (ex.: EA recém-carregado)

   int primeiraBarraVisivel = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int barrasVisiveis       = (int)ChartGetInteger(0, CHART_WIDTH_IN_BARS);

   // Largura aproximada (em pixels) de uma barra no zoom atual, usada como margem de
   // segurança no eixo X - sem isso, um candle "na borda" do painel poderia escapar da
   // checagem por a coordenada de referência (o horário da barra) cair um pixel fora.
   int larguraBarraPx = 6;
   int xRef1, yRef1, xRef2, yRef2;
   datetime tRef1 = iTime(_Symbol, _Period, 0);
   datetime tRef2 = iTime(_Symbol, _Period, 1);
   if(tRef1 > 0 && tRef2 > 0 &&
      ChartTimePriceToXY(ChartID(), 0, tRef1, iClose(_Symbol, _Period, 0), xRef1, yRef1) &&
      ChartTimePriceToXY(ChartID(), 0, tRef2, iClose(_Symbol, _Period, 1), xRef2, yRef2))
   {
      larguraBarraPx = (int)MathMax(2, MathAbs(xRef1 - xRef2));
   }

   for(int i = 0; i <= barrasVisiveis + 1; i++)
   {
      int idx = primeiraBarraVisivel - i;
      if(idx < 0) break;

      datetime tempoBarra = iTime(_Symbol, _Period, idx);
      double high = iHigh(_Symbol, _Period, idx);
      double low  = iLow(_Symbol, _Period, idx);
      if(tempoBarra == 0 || high <= 0 || low <= 0) continue;

      int xBarra, yTopoBarra, xBarraLow, yBaseBarra;
      if(!ChartTimePriceToXY(ChartID(), 0, tempoBarra, high, xBarra, yTopoBarra)) continue;
      if(!ChartTimePriceToXY(ChartID(), 0, tempoBarra, low, xBarraLow, yBaseBarra)) continue;

      bool overlapX = (xBarra + larguraBarraPx / 2 >= xEsq) && (xBarra - larguraBarraPx / 2 <= xDir);
      bool overlapY = (yBaseBarra >= yTopo) && (yTopoBarra <= yBase);

      if(overlapX && overlapY) return true;
   }

   return false;
}

// Chamada a cada ciclo (tick/timer) e também na rolagem/zoom do gráfico (CHARTEVENT_CHART_CHANGE).
// Se o canto atual estiver invadido por algum candle, manda o painel para o canto oposto -
// mas só se o canto oposto estiver livre, para não ficar oscilando quando os dois lados
// estiverem ocupados (ex.: candle muito alto ocupando quase toda a tela).
void VerificarEAutoReposicionarPainel()
{
   if(!PainelInvadidoPorCandle(cantoPainelAtual)) return;

   ENUM_BASE_CORNER cantoOposto = (cantoPainelAtual == CORNER_RIGHT_UPPER) ? CORNER_RIGHT_LOWER : CORNER_RIGHT_UPPER;
   if(PainelInvadidoPorCandle(cantoOposto)) return; // os dois lados ocupados - fica onde está

   MoverPainelPara(cantoOposto);
}

void SetObjVisivel(string nome, bool visivel)
{
   if(ObjectFind(0, nome) >= 0)
      ObjectSetInteger(0, nome, OBJPROP_TIMEFRAMES, visivel ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

//+------------------------------------------------------------------+
int OnInit()
{
   // Detecta automaticamente a config do ativo pelo símbolo do gráfico (ver
   // RiscoConfigAtivos.mqh). Se o símbolo não for reconhecido, o EA recusa-se a
   // inicializar - rodar com a fórmula/tabela erradas por engano é pior do que não rodar.
   if(!DetectarConfigAtivo(_Symbol, cfgAtiva))
   {
      Alert("[ERRO] Ativo '", _Symbol, "' não reconhecido em RiscoConfigAtivos.mqh. EA não inicializado.");
      return(INIT_FAILED);
   }
   Print("[SISTEMA] Config detectada para ", _Symbol, ": ", cfgAtiva.nomeAtivo);

   faseAtual = MathMin(10, MathMax(1, InpFaseInicial));

   // Desativa a "Navegação rápida" nativa do MetaTrader - por padrão, pressionar ENTER
   // ou ESPAÇO no gráfico abre uma barrinha de busca (com cursor de texto piscando) para
   // pular para datas/símbolos. Como o robô usa ENTER e CTRL+ENTER pesadamente como
   // atalhos, o próprio MetaTrader intercepta essas teclas para abrir essa busca em vez
   // de entregá-las ao robô - a documentação da MetaQuotes recomenda explicitamente
   // desativar isso quando o programa processa ENTER/ESPAÇO, exatamente o nosso caso.
   ChartSetInteger(0, CHART_QUICK_NAVIGATION, false);

   // Detecta automaticamente o modo de preenchimento (Fill Policy) aceito pela corretora/ativo.
   // Sem isso, o CTrade usa FOK por padrão, que muitas corretoras/ativos rejeitam silenciosamente
   // (trade.Buy()/Sell() retorna false e nenhuma ordem é enviada, sem nenhum aviso visível).
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   baseNegociosDia = MathMax(NEGOCIOS_DIA_MINIMO, InpNegociosDiaInicial);
   if(baseNegociosDia % 2 == 0) baseNegociosDia++; // garante número ímpar
   papeisPorOperacao = cfgAtiva.tabelaFases[faseAtual].loteMax;
   bonusConcedidoHoje = false;
   ultimoDiaVerificado = 0;

   // Restaura fase, papéis, negócios/dia e canto do painel de uma sessão anterior neste
   // mesmo gráfico, se existirem - assim uma troca de timeframe (que reinicia o EA) não
   // reseta o que o usuário configurou nos botões. Os valores acima servem só de padrão
   // para a primeira vez que o robô roda neste gráfico.
   CarregarEstadoPersistente();

   // Se já existe uma posição aberta neste símbolo (ex.: o EA acabou de ser recarregado por
   // uma troca de timeframe), recupera o SL/TP atual dela como alvo do watchdog de proteção -
   // sem isso, o watchdog perderia a referência do que deveria estar aplicado.
   slAlvoPosicaoAtual = 0.0;
   tpAlvoPosicaoAtual = 0.0;
   contadorCiclosSemProtecao = 0;
   if(PositionSelect(_Symbol))
   {
      slAlvoPosicaoAtual = PositionGetDouble(POSITION_SL);
      tpAlvoPosicaoAtual = PositionGetDouble(POSITION_TP);
   }

   EventSetMillisecondTimer(50);

   // Necessário para receber CHARTEVENT_MOUSE_MOVE - usado para a prévia (SHIFT/CTRL)
   // acompanhar o cursor do mouse pelo gráfico.
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   armadoPorModificador = false;
   modificadorTipoOperacao = 0;

   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, PREFIX_TXT+"EXTRA_SEP_A");
   ObjectDelete(0, PREFIX_TXT+"EXTRA_PNL_TOTAL");
   ObjectDelete(0, PREFIX_TXT+"EXTRA_INSTR");
   ObjectDelete(0, PREFIX_TXT+"EXTRA_SEP_B");
   ObjectDelete(0, PREFIX_TXT+"SEP_STATUS");
   for(int i=0; i<ArraySize(ConfigsDisponiveis)-1; i++) ObjectDelete(0, PREFIX_TXT+"EXTRA_POS"+IntegerToString(i));
   ObjectDelete(0, "Btn_FaseMenos");
   ObjectDelete(0, "Btn_FaseMais");
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
   ObjectDelete(0, "Btn_ZerarTudo");

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
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   ApagarLinhasProjecao();
   Comment("");

   ObjectDelete(0, LABEL_PRECO_POSICAO);
   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, PREFIX_TXT+"EXTRA_SEP_A");
   ObjectDelete(0, PREFIX_TXT+"EXTRA_PNL_TOTAL");
   ObjectDelete(0, PREFIX_TXT+"EXTRA_INSTR");
   ObjectDelete(0, PREFIX_TXT+"EXTRA_SEP_B");
   ObjectDelete(0, PREFIX_TXT+"SEP_STATUS");
   for(int i=0; i<ArraySize(ConfigsDisponiveis)-1; i++) ObjectDelete(0, PREFIX_TXT+"EXTRA_POS"+IntegerToString(i));
   ObjectDelete(0, "Btn_FaseMenos");
   ObjectDelete(0, "Btn_FaseMais");
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
   ObjectDelete(0, "Btn_ZerarTudo");
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

// Trava contra reentrância: ProcessarRotinasDeAtualizacao() é chamada tanto pelo OnTick()
// (a cada novo preço) quanto pelo OnTimer() (a cada ~50ms) - e também, indiretamente, por
// CHARTEVENT_CHART_CHANGE. Normalmente o MQL5 processa esses eventos em fila, um de cada
// vez, mas ChartRedraw() dentro dessa função pode, em certas condições, disparar um novo
// CHARTEVENT_CHART_CHANGE antes da chamada atual terminar - reentrando na mesma função
// enquanto ela ainda está no meio da execução, mexendo nas mesmas variáveis/objetos globais
// ao mesmo tempo. Essa trava garante que só uma chamada esteja "dentro" por vez; qualquer
// tentativa de entrar de novo enquanto já está rodando é simplesmente ignorada (o próximo
// tick/timer tenta de novo, já com a chamada anterior terminada).
bool processandoRotinasDeAtualizacao = false;

void ProcessarRotinasDeAtualizacao()
{
   if(processandoRotinasDeAtualizacao) return;
   processandoRotinasDeAtualizacao = true;

   VerificarTrocaDeDia();
   CalcularMetricasDoDia();
   ProcessarModificadoresDeArme();

   if(operacaoPendente)
   {
      AtualizarLinhasCustomizadas();
   }

   AtualizarPainelVisualEmTempoReal();
   ProcessarSomDeSaidaPendente();
   GarantirProtecaoDaPosicao();
   ProcessarFilaDeSons();
   ProcessarResetVisualDeBotoes();

   processandoRotinasDeAtualizacao = false;
}

void VerificarTrocaDeDia()
{
   datetime inicioHoje = iTime(_Symbol, PERIOD_D1, 0);
   if(inicioHoje != ultimoDiaVerificado)
   {
      bonusConcedidoHoje = false;
      ultimoDiaVerificado = inicioHoje;
   }
}

int NegociosDiaEfetivo()
{
   return baseNegociosDia + (bonusConcedidoHoje ? 1 : 0);
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
      // Todo botão deve voltar ao estado normal em algum momento (sem isso, o OBJ_BUTTON do
      // MQL5 fica "preso" com a aparência pressionada) - mas resetar no mesmo instante do
      // clique é rápido demais pra perceber. Em vez disso, enfileira o reset pra acontecer
      // ~150ms depois (ProcessarResetVisualDeBotoes), dando um flash visual perceptível.
      // Genérico pra qualquer "Btn_*" (inclusive futuros); Btn_ZerarTudo é tratado à parte
      // mais abaixo, porque seu reset depende de 'E' ter sido pressionada ou não.
      if(StringFind(sparam, "Btn_") == 0 && sparam != "Btn_ZerarTudo")
      {
         botaoPendenteDeReset = sparam;
         tickBotaoPendenteDeReset = GetTickCount();
      }

      if(sparam == "Btn_FaseMenos")
      {
         if(faseAtual > 1) faseAtual--;
         papeisPorOperacao = cfgAtiva.tabelaFases[faseAtual].loteMax;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_FaseMais")
      {
         if(faseAtual < 10) faseAtual++;
         papeisPorOperacao = cfgAtiva.tabelaFases[faseAtual].loteMax;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PapelMenos")
      {
         papeisPorOperacao = (int)MathMax(1, papeisPorOperacao - 1);
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PapelMais")
      {
         papeisPorOperacao = (int)MathMin(cfgAtiva.tabelaFases[faseAtual].loteMax, papeisPorOperacao + 1);
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_NegMenos")
      {
         baseNegociosDia = MathMax(NEGOCIOS_DIA_MINIMO, baseNegociosDia - 2);
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_NegMais")
      {
         baseNegociosDia = baseNegociosDia + 2;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelCima")
      {
         MoverPainelPara(CORNER_RIGHT_UPPER);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelBaixo")
      {
         MoverPainelPara(CORNER_RIGHT_LOWER);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_ZerarTudo")
      {
         // Segurança equivalente ao CTRL+ESC+ENTER, só que via mouse: o clique só age se
         // a tecla 'ESC' estiver pressionada no instante do clique - clicar nesse botão
         // sem segurar 'ESC' não faz nada, de propósito.
         bool escPressionado = (TerminalInfoInteger(TERMINAL_KEYSTATE_ESCAPE) < 0);
         if(escPressionado && ExisteQualquerPosicaoAbertaSuportada())
            FecharTodasAsPosicoesSuportadas();

         // O MQL5 marca o botão como "pressionado" (mudando sua cor) automaticamente em
         // QUALQUER clique, mesmo sem 'ESC'. Só deixa o flash visual acontecer quando
         // 'ESC' estava realmente pressionada (mesmo reset atrasado dos demais botões, pra
         // dar tempo de perceber); sem 'ESC', volta ao normal na hora - não chega a "piscar".
         if(escPressionado)
         {
            botaoPendenteDeReset = "Btn_ZerarTudo";
            tickBotaoPendenteDeReset = GetTickCount();
         }
         else
         {
            ObjectSetInteger(0, "Btn_ZerarTudo", OBJPROP_STATE, false);
         }
         ChartRedraw(0);
      }
   }

   if(id == CHARTEVENT_KEYDOWN)
   {
      int tecla = (int)lparam;

      // (CTRL+ENTER) zera a posição aberta OU cancela a ordem pendente, não importa como
      // foi armada (C, V ou SHIFT/CTRL) - tem prioridade sobre "enviar uma nova ordem"
      // sempre que já existir uma posição/ordem pendente. Funciona mesmo com os limites
      // diários já atingidos.
      //
      // (CTRL+ESC+ENTER) zera TODAS as posições abertas em ativos suportados (WDO/WIN/
      // CCM), inclusive as de outros papéis exibidas no painel - checado ANTES do CTRL+
      // Enter "normal", já que é o combo mais específico dos dois.
      if(tecla == 13)
      {
         bool ctrlPressionado = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);
         bool escPressionado  = (TerminalInfoInteger(TERMINAL_KEYSTATE_ESCAPE) < 0);

         if(ctrlPressionado && escPressionado && ExisteQualquerPosicaoAbertaSuportada())
         {
            FecharTodasAsPosicoesSuportadas();
            return;
         }

         if(ctrlPressionado && ExistePosicaoOuOrdemPendente())
         {
            FecharPosicaoAberta();
            return;
         }
      }

      // Sozinho, ESC cancela uma ordem armada (prévia de entrada/SL/TP). Mas ESC também é
      // modificador do combo CTRL+ESC+ENTER - se CTRL estiver pressionado junto, é sinal de
      // que o usuário está tentando esse combo, não cancelar uma prévia. Nesse caso, deixa o
      // ESC passar direto (sem cancelar nada aqui) até o ENTER decidir o que fazer.
      if(tecla == 27) // Tecla 'ESC'
      {
         bool ctrlJuntoComEsc = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);
         if(!ctrlJuntoComEsc)
         {
            ApagarLinhasProjecao();
            globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
         }
         return;
      }

      if(tecla == 67 || tecla == 99) // Tecla 'C'
      {
         if(BloqueadoPorLimiteDiario()) return;
         ArmarOperacao(1, false, 0.0);
      }
      else if(tecla == 86 || tecla == 118) // Tecla 'V'
      {
         if(BloqueadoPorLimiteDiario()) return;
         ArmarOperacao(2, false, 0.0);
      }
      else if(tecla == 13 && operacaoPendente) // Tecla 'ENTER' - envia a ordem armada (por C, V ou SHIFT/CTRL)
      {
         if(BloqueadoPorLimiteDiario()) return;
         EnviarOrdemMercado();
      }
   }

   // O mouse move atualiza a posição da prévia (entrada/loss/gain) para acompanhar o
   // cursor ENQUANTO a operação estiver armada por SHIFT/CTRL (ver ProcessarModificadoresDeArme).
   // Precisa de CHART_EVENT_MOUSE_MOVE habilitado no OnInit().
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      ultimoMouseXPixel = (int)lparam;
      ultimoMouseYPixel = (int)dparam;

      if(armadoPorModificador && operacaoPendente)
      {
         int subJanela = 0;
         datetime tempoMouse = 0;
         double precoMouse = 0;
         if(ChartXYToTimePrice(0, ultimoMouseXPixel, ultimoMouseYPixel, subJanela, tempoMouse, precoMouse) && subJanela == 0)
         {
            usarPrecoDoClique = true;
            precoCliqueReferencia = precoMouse;
            AtualizarLinhasCustomizadas();
         }
      }
   }

   // Clique esquerdo agora só ENVIA a ordem armada por SHIFT/CTRL - operações armadas por
   // C/V (teclado) só são enviadas com ENTER, não mais por clique. Nota técnica: o MQL5
   // só expõe eventos de clique para o botão ESQUERDO; o direito é reservado pela
   // plataforma para o menu de contexto nativo do gráfico.
   if(id == CHARTEVENT_CLICK)
   {
      int xPixel = (int)lparam;
      int yPixel = (int)dparam;

      // Log de diagnóstico: mostra se o CHARTEVENT_CLICK está chegando e o estado no
      // momento. Se aparecer "faltou clique" no comportamento mas NADA aparecer aqui no
      // log (aba Experts), o problema é o próprio MetaTrader não estar gerando o evento
      // de clique (ex.: ferramenta "Mira/Crosshair" ativa na barra de ferramentas do
      // gráfico consome o clique antes de chegar ao EA) - trocar para a ferramenta
      // "Cursor" (seta) resolve isso.
      Print("[CLIQUE] x=", xPixel, " y=", yPixel, " operacaoPendente=", operacaoPendente,
            " usarPrecoDoClique=", usarPrecoDoClique, " armadoPorModificador=", armadoPorModificador);

      if(!operacaoPendente)
      {
         // O polling (ProcessarModificadoresDeArme) roda a cada ~50ms; se o usuário
         // pressionar SHIFT/CTRL e clicar quase ao mesmo tempo, o clique pode chegar
         // ANTES do próximo ciclo de polling ter armado a operação - nesse caso, sem
         // este bloco, o clique simplesmente não faria nada (era a causa de "às vezes
         // preciso de vários cliques"). Aqui, o próprio clique checa o estado atual de
         // SHIFT/CTRL e arma na hora, usando a posição exata do clique como referência.
         bool shiftAgora = (TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT) < 0);
         bool ctrlAgora   = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);
         if(shiftAgora == ctrlAgora)
         {
            Print("[CLIQUE] Ignorado: nenhum modificador pressionado (ou os dois juntos).");
            return;
         }

         int subJanela = 0;
         datetime tempoClique = 0;
         double precoClique = 0;
         if(!ChartXYToTimePrice(0, xPixel, yPixel, subJanela, tempoClique, precoClique) || subJanela != 0)
         {
            Print("[CLIQUE] Ignorado: ChartXYToTimePrice falhou ou clique fora da janela principal.");
            return;
         }

         if(BloqueadoPorLimiteDiario())
         {
            Print("[CLIQUE] Ignorado: BloqueadoPorLimiteDiario() retornou true.");
            return;
         }

         int tipo = shiftAgora ? 1 : 2;
         ArmarOperacao(tipo, true, precoClique);
         armadoPorModificador = true;
         modificadorTipoOperacao = tipo;
         Print("[CLIQUE] Armado na hora do clique. tipo=", tipo, " preco=", DoubleToString(precoClique, _Digits));
      }
      else if(usarPrecoDoClique)
      {
         // Já armado - recalcula o preço exatamente na posição do clique (em vez de
         // confiar no último preço atualizado pelo MOUSE_MOVE, que pode estar levemente
         // defasado) - garante que a ordem seja enviada para o local exato do clique.
         int subJanela = 0;
         datetime tempoClique = 0;
         double precoClique = 0;
         if(ChartXYToTimePrice(0, xPixel, yPixel, subJanela, tempoClique, precoClique) && subJanela == 0)
            precoCliqueReferencia = precoClique;
      }

      if(!operacaoPendente)
      {
         Print("[CLIQUE] Nada foi enviado: operacaoPendente continua false após a tentativa de armar.");
         return; // ainda nada armado (ex.: bloqueado por limite diário)
      }

      if(!usarPrecoDoClique)
      {
         // Operação armada por C/V (teclado) - o clique não envia mais nessa modalidade,
         // só o ENTER. O clique só envia quando a operação foi armada por SHIFT/CTRL.
         Print("[CLIQUE] Ignorado: operação armada por C/V - use ENTER para enviar.");
         return;
      }

      if(BloqueadoPorLimiteDiario()) return;
      EnviarOrdemMercado();
   }
}

// Retorna o ticket da ordem pendente (Limit/Stop) deste símbolo, se existir alguma; ou 0.
ulong TicketDaOrdemPendente()
{
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol)
         return ticket;
   }
   return 0;
}

bool ExistePosicaoOuOrdemPendente()
{
   if(PositionSelect(_Symbol)) return true;
   return (TicketDaOrdemPendente() > 0);
}

// Verifica os limites diários (ordens/loss/gain, já considerando a extensão pelo LFT) e
// se já existe uma posição aberta OU uma ordem pendente (Limit/Stop) aguardando o preço.
// Retorna true (e já mostra a mensagem/apaga a prévia) se algo estiver bloqueado - usado
// antes de armar uma nova operação (C, V, SHIFT/CTRL) ou enviar (ENTER/clique). A checagem
// é a mesma para qualquer forma de armar a operação, exatamente para impedir abrir mais de
// uma ordem (executada ou pendente) ao mesmo tempo.
bool BloqueadoPorLimiteDiario()
{
   if(ExistePosicaoOuOrdemPendente())
   {
      // Já existe posição aberta ou ordem pendente - não deixa armar nem enviar outra.
      return true;
   }

   int E = NegociosDiaEfetivo();
   int maxOrdensPermitidas = E * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

   double acumProgAtual = CalcularAcumProg(faseAtual, E, papeisPorOperacao);
   double acumRegAtual  = CalcularAcumReg(faseAtual, E, papeisPorOperacao);
   double lftAtual      = CalcularLFT(faseAtual, E, papeisPorOperacao);
   bool   todosGanhosHoje = CondicaoAtivacaoLFT(pnlDiarioAtual, acumProgAtual);

   double limiteLossEfetivo = todosGanhosHoje ? (pnlDiarioAtual - lftAtual) : acumRegAtual;

   bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);
   bool limiteLossAtingido    = (pnlDiarioAtual <= limiteLossEfetivo);
   bool limiteGainAtingido    = (pnlDiarioAtual >= acumProgAtual);

   if(limiteOrdensAtingido || limiteLossAtingido || limiteGainAtingido)
   {
      globalMensagemStatus = "Basta por hoje! (Limite diário atingido)";
      ApagarLinhasProjecao();
      return true;
   }
   return false;
}

// Arma uma operação pendente (compra ou venda) e desenha a prévia. Se usarClique for true,
// a prévia usa precoClique como referência (posição do mouse no gráfico); caso contrário,
// usa o preço de mercado atual (Ask/Bid).
void ArmarOperacao(int tipo, bool usarClique, double precoClique)
{
   operacaoPendente = true;
   tipoOperacao = tipo;
   usarPrecoDoClique = usarClique;
   precoCliqueReferencia = usarClique ? precoClique : 0.0;

   AtualizarLinhasCustomizadas();

   string nomeOperacao = (tipo == 1) ? "compra" : "venda";
   globalMensagemStatus = StringFormat("Modo %s ativo! (ENTER) Envia | (ESC) Cancela", nomeOperacao);
}

// Arma a operação já usando a última posição conhecida do mouse sobre o gráfico (se
// disponível), em vez de cair no preço de mercado atual - evita que a prévia fique
// "grudada" acompanhando o mercado no instante entre o rearme automático (tecla ainda
// pressionada após enviar uma ordem) e o próximo movimento real do mouse.
void ArmarOperacaoNoPrecoDoMouse(int tipo)
{
   if(ultimoMouseXPixel >= 0 && ultimoMouseYPixel >= 0)
   {
      int subJanela = 0;
      datetime tempoMouse = 0;
      double precoMouse = 0;
      if(ChartXYToTimePrice(0, ultimoMouseXPixel, ultimoMouseYPixel, subJanela, tempoMouse, precoMouse) && subJanela == 0)
      {
         ArmarOperacao(tipo, true, precoMouse);
         return;
      }
   }
   // Sem posição conhecida do mouse ainda (ex.: mouse nunca passou pelo gráfico nesta
   // sessão) - cai no preço de mercado como último recurso; o próximo MOUSE_MOVE corrige.
   ArmarOperacao(tipo, false, 0.0);
}

// Roda a cada ciclo (tick/timer). Detecta SHIFT/CTRL pressionados por polling (o MQL5 não
// tem evento de "tecla solta"), e arma/desarma automaticamente o modo compra/venda:
//   - SHIFT pressionado e nada armado por modificador ainda -> arma compra
//   - CTRL pressionado e nada armado por modificador ainda -> arma venda
//   - SHIFT e CTRL juntos -> ambíguo, ignora (não arma nada)
//   - Modificador estava armado e a tecla foi solta -> desarma automaticamente
// Não interfere com operações armadas por C/V (essas só saem por ENTER/ESC/clique).
void ProcessarModificadoresDeArme()
{
   bool shiftAgora = (TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT) < 0);
   bool ctrlAgora   = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);

   if(shiftAgora && ctrlAgora) { shiftAgora = false; ctrlAgora = false; } // ambíguo: ignora os dois

   if(!armadoPorModificador)
   {
      if(shiftAgora)
      {
         if(BloqueadoPorLimiteDiario()) return;
         ArmarOperacaoNoPrecoDoMouse(1);
         armadoPorModificador = true;
         modificadorTipoOperacao = 1;
         globalMensagemStatus = "Modo compra ativo (SHIFT)! Clique para enviar";
      }
      else if(ctrlAgora)
      {
         if(BloqueadoPorLimiteDiario()) return;
         ArmarOperacaoNoPrecoDoMouse(2);
         armadoPorModificador = true;
         modificadorTipoOperacao = 2;
         globalMensagemStatus = "Modo venda ativo (CTRL)! Clique para enviar";
      }
   }
   else if(!shiftAgora && !ctrlAgora)
   {
      // O modificador que armou a operação foi solto - desarma automaticamente.
      ApagarLinhasProjecao();
      globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
   }
}

// Converte "pontos" (como usados nas tabelas de fase) para a mesma unidade do preço
// do símbolo. Alguns ativos (ex.: WDO) já têm _Point na mesma escala usada pela tabela
// de fases (conversão direta); outros (ex.: WIN) precisam multiplicar por _Point. Ver
// cfgAtiva.modoConversaoSLTP, testado e confirmado por ativo em RiscoConfigAtivos.mqh.
double ConverterPontosParaPreco(double pontos)
{
   return (cfgAtiva.modoConversaoSLTP == CONV_MULTIPLICA_POINT) ? (pontos * _Point) : pontos;
}

// Inversa de ConverterPontosParaPreco(): converte uma VARIAÇÃO DE PREÇO (ex.: preço de
// saída menos preço de entrada de um trade) para "pontos" na mesma unidade usada pela
// tabela de fases e por toda a gestão de risco. Sem isso, o cálculo de pontos do
// dia/mês ficava sempre dividindo por _Point (correto só para ativos CONV_MULTIPLICA_POINT,
// como o WIN) - no WDO (CONV_DIRETA) isso inflava o resultado em milhares de vezes, porque
// o _Point do WDO (a resolução de exibição do preço, ex.: 0.001) não tem relação nenhuma
// com o tamanho do "ponto" usado na tabela de fases (que já é o próprio preço).
double ConverterPrecoParaPontos(double deltaPreco)
{
   return (cfgAtiva.modoConversaoSLTP == CONV_MULTIPLICA_POINT) ? (deltaPreco / _Point) : deltaPreco;
}

double ArredondarParaPassoDoPreco(double pontos)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return pontos;
   return MathRound(pontos / tickSize) * tickSize;
}

// Agora os alvos já são dados diretamente em pontos por operação pela tabela de fases
double ObterPontosAlvosFase(double &slOut, double &tpOut)
{
   slOut = ArredondarParaPassoDoPreco(MathAbs(cfgAtiva.tabelaFases[faseAtual].lossPontos));
   tpOut = ArredondarParaPassoDoPreco(MathAbs(cfgAtiva.tabelaFases[faseAtual].gainPontos));
   return slOut;
}

// Garante que a distância (em pontos) respeita o mínimo exigido pela corretora/símbolo
// (SYMBOL_TRADE_STOPS_LEVEL). Se o SL/TP calculado pela fase for menor que esse mínimo,
// o PositionModify() é rejeitado pela corretora - e, sem essa checagem, a posição fica
// sem proteção real sem que o usuário perceba (foi o que causou o bug relatado).
double AjustarPontosParaStopsLevel(double pontos)
{
   long stopsLevelPontos = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevelPontos <= 0) return pontos;

   double margemSeguranca = 2; // pontos extras de folga além do mínimo exigido
   double minimoNecessario = stopsLevelPontos + margemSeguranca;

   if(pontos < minimoNecessario)
   {
      Print("[AVISO] Distância de ", pontos, " pts é menor que o mínimo da corretora (",
            stopsLevelPontos, " pts) - ajustando para ", minimoNecessario, " pts.");
      return minimoNecessario;
   }
   return pontos;
}

// Igual a ObterPontosAlvosFase(), mas também trava o SL pelo LFT quando a próxima ordem
// for a "operação-bônus" concedida por já ter acertado todos os trades do dia - usado
// tanto na linha de projeção (antes de enviar) quanto no envio real da ordem, para que
// a prévia mostrada na tela sempre bata com o que será efetivamente enviado.
double ObterPontosAlvosEfetivos(double &slOut, double &tpOut, bool &ehOperacaoBonus)
{
   ObterPontosAlvosFase(slOut, tpOut);
   ehOperacaoBonus = false;

   int E = NegociosDiaEfetivo();
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   bool todosGanhosHoje = TodosTradesForamGain();

   ehOperacaoBonus = (todosGanhosHoje && bonusConcedidoHoje && operacoesFeitasHoje >= (baseNegociosDia * 2));

   if(ehOperacaoBonus && papeisPorOperacao > 0)
   {
      double lftAtual = CalcularLFT(faseAtual, E, papeisPorOperacao);
      double pontosMaxPermitidoPeloLFT = MathFloor(lftAtual / (papeisPorOperacao * cfgAtiva.valorPorPontoPorLote));

      if(pontosMaxPermitidoPeloLFT > 0 && pontosMaxPermitidoPeloLFT < slOut)
         slOut = ArredondarParaPassoDoPreco(pontosMaxPermitidoPeloLFT);
   }

   slOut = AjustarPontosParaStopsLevel(slOut);
   tpOut = AjustarPontosParaStopsLevel(tpOut);

   return slOut;
}

//+------------------------------------------------------------------+
//| Fórmulas de LFT / Acúmulos - dependem da fase, da quantidade de   |
//| negócios (E) configurada/permitida para o dia, e do MODO definido |
//| por cfgAtiva.modoFormulaRisco (testado e confirmado por ativo):   |
//|   FORMULA_LOTE_MAX_FASE  -> multiplica pelo Lote Max FIXO da fase |
//|                             (comportamento validado para o WDO)   |
//|   FORMULA_PAPEIS_USUARIO -> multiplica pela quantidade de papéis  |
//|                             (V) escolhida pelo usuário, dividido  |
//|                             por 50 (comportamento validado para   |
//|                             o WIN)                                |
//| As duas regras convivem sem "if" espalhado pelo código: cada      |
//| função abaixo ramifica UMA vez, no ponto exato da divergência.    |
//+------------------------------------------------------------------+

// Acúmulo progressivo
double CalcularAcumProg(int fase, int negociosDia, int papeis)
{
   if(cfgAtiva.modoFormulaRisco == FORMULA_LOTE_MAX_FASE)
      // multiplicador financeiro por ponto vem da config do ativo (10,0 p/ WDO, 4,5 p/ CCM, ...)
      return negociosDia * cfgAtiva.tabelaFases[fase].loteMax * cfgAtiva.tabelaFases[fase].gainPontos * cfgAtiva.valorPorPontoPorLote;
   else // FORMULA_PAPEIS_USUARIO
      return negociosDia * papeis * 10.0 * (cfgAtiva.tabelaFases[fase].gainPontos / 50.0);
}

// Acúmulo regressivo
double CalcularAcumReg(int fase, int negociosDia, int papeis)
{
   if(cfgAtiva.modoFormulaRisco == FORMULA_LOTE_MAX_FASE)
      return negociosDia * cfgAtiva.tabelaFases[fase].loteMax * cfgAtiva.tabelaFases[fase].lossPontos * cfgAtiva.valorPorPontoPorLote;
   else // FORMULA_PAPEIS_USUARIO
      return negociosDia * papeis * 10.0 * (cfgAtiva.tabelaFases[fase].lossPontos / 50.0);
}

// LFT (Loss From Top)
double CalcularLFT(int fase, int negociosDia, int papeis)
{
   int floorOrdens2 = (int)MathFloor(negociosDia / 2.0);
   if(cfgAtiva.modoFormulaRisco == FORMULA_LOTE_MAX_FASE)
      return floorOrdens2 * cfgAtiva.tabelaFases[fase].loteMax * cfgAtiva.valorPorPontoPorLote * (cfgAtiva.tabelaFases[fase].lossPontos * -1.0);
   else // FORMULA_PAPEIS_USUARIO
      return floorOrdens2 * papeis * 20.0 * ((cfgAtiva.tabelaFases[fase].lossPontos * -1.0) / 2.0 / 50.0);
}

// Verifica se todas as operações (pares de entrada/saída) já finalizadas hoje terminaram com ganho
// Agrupa os deals de saída de hoje por posição (POSITION_ID), somando o resultado
// financeiro de cada uma. Usado tanto por TodosTradesForamGain() quanto por
// ContarResultadosFechadosHoje(), para não duplicar a lógica de agrupamento.
void AgruparResultadosFechadosHoje(long &posIds[], double &posLucro[])
{
   ArrayResize(posIds, 0);
   ArrayResize(posLucro, 0);

   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal <= 0) continue;
      if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) != _Symbol) continue;

      long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
      if(entradaDeal != DEAL_ENTRY_OUT && entradaDeal != DEAL_ENTRY_INOUT) continue;

      long posId = HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID);
      double resultado = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT)
                        + HistoryDealGetDouble(ticketDeal, DEAL_SWAP)
                        + HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);

      int idx = -1;
      for(int j = 0; j < ArraySize(posIds); j++)
      {
         if(posIds[j] == posId) { idx = j; break; }
      }
      if(idx < 0)
      {
         ArrayResize(posIds, ArraySize(posIds) + 1);
         ArrayResize(posLucro, ArraySize(posLucro) + 1);
         idx = ArraySize(posIds) - 1;
         posIds[idx] = posId;
         posLucro[idx] = 0.0;
      }
      posLucro[idx] += resultado;
   }
}

bool TodosTradesForamGain()
{
   long   posIds[];
   double posLucro[];
   AgruparResultadosFechadosHoje(posIds, posLucro);

   int total = ArraySize(posIds);
   if(total == 0) return false;

   for(int i = 0; i < total; i++)
      if(posLucro[i] <= 0.0) return false;

   return true;
}

// Conta quantas operações já fechadas hoje terminaram com gain (> 0) e quantas com loss (< 0).
// Resultado exatamente 0 não entra em nenhuma das duas contagens.
void ContarResultadosFechadosHoje(int &gains, int &losses)
{
   gains = 0;
   losses = 0;

   long   posIds[];
   double posLucro[];
   AgruparResultadosFechadosHoje(posIds, posLucro);

   for(int i = 0; i < ArraySize(posIds); i++)
   {
      if(posLucro[i] > 0.0) gains++;
      else if(posLucro[i] < 0.0) losses++;
   }
}

// O LFT (e o bônus de +1 negócio que vem junto) só deve ser ativado quando as TRÊS
// condições abaixo forem verdadeiras ao mesmo tempo:
//   1) a quantidade de negócios especificada para o dia (baseNegociosDia) já foi
//      totalmente fechada - não apenas alguns dela;
//   2) TODAS essas operações fechadas foram gain (nenhum loss no meio);
//   3) o PnL do dia já alcançou o Máx gain (Acúmulo progressivo) da fase.
// Antes desta correção, bastava 1 única operação fechada em gain para ativar tudo isso
// prematuramente, mesmo faltando operações e mesmo sem ter batido o Máx gain.
bool CondicaoAtivacaoLFT(double pnlDiarioAtual, double acumProgAtual)
{
   if(!TodosTradesForamGain()) return false;

   int gains = 0, losses = 0;
   ContarResultadosFechadosHoje(gains, losses);
   int totalFechados = gains + losses;

   if(totalFechados < baseNegociosDia) return false;
   if(pnlDiarioAtual < acumProgAtual) return false;

   return true;
}

void EnviarOrdemMercado()
{
   // Camada extra de segurança: nunca envia uma nova ordem se já existe posição aberta ou
   // ordem pendente, mesmo que o chamador já devesse ter checado isso via BloqueadoPorLimiteDiario().
   if(ExistePosicaoOuOrdemPendente())
   {
      globalMensagemStatus = "Já existe posição/ordem pendente! (CTRL+Enter) para cancelar antes.";
      ApagarLinhasProjecao();
      return;
   }

   int E = NegociosDiaEfetivo();
   int maxOrdensPermitidas = E * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

   double acumProgAtual = CalcularAcumProg(faseAtual, E, papeisPorOperacao);
   double acumRegAtual  = CalcularAcumReg(faseAtual, E, papeisPorOperacao);
   double lftAtual      = CalcularLFT(faseAtual, E, papeisPorOperacao);
   bool   todosGanhosHoje = CondicaoAtivacaoLFT(pnlDiarioAtual, acumProgAtual);
   double limiteLossEfetivo = todosGanhosHoje ? (pnlDiarioAtual - lftAtual) : acumRegAtual;

   if(operacoesFeitasHoje >= maxOrdensPermitidas ||
      pnlDiarioAtual <= limiteLossEfetivo ||
      pnlDiarioAtual >= acumProgAtual)
   {
      globalMensagemStatus = "Basta por hoje! (Limites diários atingidos)";
      ApagarLinhasProjecao();
      return;
   }

   double pontosSL = 0, pontosTP = 0;
   bool operacaoBonusLFT = false;
   ObterPontosAlvosEfetivos(pontosSL, pontosTP, operacaoBonusLFT);

   if(operacaoBonusLFT)
   {
      Print("[LFT] Operação-bônus: SL travado em ", pontosSL, " pts (normal da fase seria ",
            cfgAtiva.tabelaFases[faseAtual].lossPontos, " pts) para não ultrapassar o LFT de R$ ",
            DoubleToString(lftAtual, 2), ".");
   }

   // Quando armada por SHIFT/CTRL (preço específico do mouse), a ordem fica PENDENTE
   // (Limit ou Stop) naquele preço, em vez de ser enviada a mercado imediatamente.
   if(usarPrecoDoClique)
   {
      EnviarOrdemPendente(pontosSL, pontosTP);
      return;
   }

   int loteParaEnviar = papeisPorOperacao;
   bool ordemOk = false;

   // A ordem é enviada SEM SL/TP - eles são calculados e aplicados logo abaixo, com base
   // no preço real de EXECUÇÃO da posição (POSITION_PRICE_OPEN), e não no preço de mercado
   // no instante em que a ordem foi enviada (que pode divergir por slippage/requote).
   if(tipoOperacao == 1)
   {
      ordemOk = trade.Buy(loteParaEnviar, _Symbol, 0.0, 0.0, 0.0, "Compra Fase " + IntegerToString(faseAtual));
   }
   else if(tipoOperacao == 2)
   {
      ordemOk = trade.Sell(loteParaEnviar, _Symbol, 0.0, 0.0, 0.0, "Venda Fase " + IntegerToString(faseAtual));
   }

   if(ordemOk)
   {
      if(PositionSelect(_Symbol))
      {
         double precoExecucao = PositionGetDouble(POSITION_PRICE_OPEN);
         long   tipoPosAberta = PositionGetInteger(POSITION_TYPE);
         double slFinal = 0, tpFinal = 0;

         if(tipoPosAberta == POSITION_TYPE_BUY)
         {
            slFinal = NormalizeDouble(precoExecucao - ConverterPontosParaPreco(pontosSL), _Digits);
            tpFinal = NormalizeDouble(precoExecucao + ConverterPontosParaPreco(pontosTP), _Digits);
         }
         else
         {
            slFinal = NormalizeDouble(precoExecucao + ConverterPontosParaPreco(pontosSL), _Digits);
            tpFinal = NormalizeDouble(precoExecucao - ConverterPontosParaPreco(pontosTP), _Digits);
         }

         // Guarda o alvo de SL/TP desta posição para o watchdog (ProcessarSomDeSaidaPendente
         // e GarantirProtecaoDaPosicao) continuar garantindo que ele permaneça aplicado -
         // mesmo que a tentativa abaixo falhe agora, o watchdog vai insistir nos próximos ticks.
         slAlvoPosicaoAtual = slFinal;
         tpAlvoPosicaoAtual = tpFinal;
         contadorCiclosSemProtecao = 0;

         // Até 3 tentativas imediatas (situações transitórias, ex.: preço se moveu entre a
         // execução e esta chamada); se ainda assim falhar, o watchdog assume a partir daqui.
         bool slTpOk = false;
         for(int tentativa = 0; tentativa < 3 && !slTpOk; tentativa++)
         {
            slTpOk = trade.PositionModify(_Symbol, slFinal, tpFinal);
            if(!slTpOk) Sleep(150);
         }

         if(!slTpOk)
         {
            Print("[ALERTA] Ordem executada, mas falhou ao definir SL/TP após 3 tentativas. Retcode: ",
                  trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription(),
                  " | O robô vai continuar tentando automaticamente até conseguir.");
            globalMensagemStatus = "ALERTA: Posição SEM SL/TP! Corrigindo automaticamente...";
            if(!PlaySound("errorPlacingOrder.wav")) PlaySound("\\Audio\\errorPlacingOrder.wav");
            ApagarLinhasProjecao();
            return;
         }
      }

      ApagarLinhasProjecao();
      globalMensagemStatus = operacaoBonusLFT ? "Ordem bônus (LFT)! SL travado. (ESC)" : "Ordem enviada! Pressione (ESC)";
   }
   else
   {
      Print("[ERRO] Falha ao enviar ordem. Retcode: ", trade.ResultRetcode(),
            " - ", trade.ResultRetcodeDescription(), " | GetLastError: ", GetLastError());
      globalMensagemStatus = StringFormat("Falha ao enviar ordem! (retcode %d)", trade.ResultRetcode());
      if(!PlaySound("errorPlacingOrder.wav")) PlaySound("\\Audio\\errorPlacingOrder.wav");
      ApagarLinhasProjecao();
   }
}

// Envia uma ordem PENDENTE (Limit ou Stop, decidido dinamicamente conforme o preço alvo
// está abaixo ou acima do mercado atual) no preço exato indicado pelo SHIFT/CTRL+mouse -
// diferente de EnviarOrdemMercado(), que envia a mercado imediatamente. O SL/TP já são
// calculados a partir do próprio preço alvo (que será o preço de execução, quando a ordem
// for acionada), e são carregados automaticamente pelo MetaTrader para a posição quando
// a ordem pendente for preenchida.
void EnviarOrdemPendente(double pontosSL, double pontosTP)
{
   // O preço vindo do clique/mouse (ChartXYToTimePrice) tem precisão "contínua" - mas a
   // corretora só aceita preços múltiplos do tick size do contrato (ex.: 5 em 5 pontos no
   // WIN). Sem este arredondamento, a ordem é rejeitada com retcode 10015 (invalid price).
   double precoAlvo = NormalizeDouble(ArredondarParaPassoDoPreco(precoCliqueReferencia), _Digits);
   string comentario = StringFormat("%s pendente Fase %d", (tipoOperacao == 1 ? "Compra" : "Venda"), faseAtual);

   double sl = 0, tp = 0;
   bool ordemOk = false;

   if(tipoOperacao == 1) // compra
   {
      double precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(precoAlvo - ConverterPontosParaPreco(pontosSL), _Digits);
      tp = NormalizeDouble(precoAlvo + ConverterPontosParaPreco(pontosTP), _Digits);

      if(precoAlvo < precoAtual)
         ordemOk = trade.BuyLimit(papeisPorOperacao, precoAlvo, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comentario);
      else if(precoAlvo > precoAtual)
         ordemOk = trade.BuyStop(papeisPorOperacao, precoAlvo, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comentario);
      else // preço alvo == preço atual (raro): envia a mercado diretamente
         ordemOk = trade.Buy(papeisPorOperacao, _Symbol, 0.0, sl, tp, comentario);
   }
   else if(tipoOperacao == 2) // venda
   {
      double precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(precoAlvo + ConverterPontosParaPreco(pontosSL), _Digits);
      tp = NormalizeDouble(precoAlvo - ConverterPontosParaPreco(pontosTP), _Digits);

      if(precoAlvo > precoAtual)
         ordemOk = trade.SellLimit(papeisPorOperacao, precoAlvo, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comentario);
      else if(precoAlvo < precoAtual)
         ordemOk = trade.SellStop(papeisPorOperacao, precoAlvo, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comentario);
      else
         ordemOk = trade.Sell(papeisPorOperacao, _Symbol, 0.0, sl, tp, comentario);
   }

   if(ordemOk)
   {
      ApagarLinhasProjecao();
      globalMensagemStatus = StringFormat("Ordem pendente em %s! (CTRL+Enter) Cancela", DoubleToString(precoAlvo, _Digits));
   }
   else
   {
      Print("[ERRO] Falha ao enviar ordem pendente em ", DoubleToString(precoAlvo, _Digits),
            ". Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription(),
            " | GetLastError: ", GetLastError());
      globalMensagemStatus = StringFormat("Falha ao enviar ordem pendente! (retcode %d)", trade.ResultRetcode());
      if(!PlaySound("errorPlacingOrder.wav")) PlaySound("\\Audio\\errorPlacingOrder.wav");
      ApagarLinhasProjecao();
   }
}

// Tenta localizar o deal de saída da posição informada (por POSITION_IDENTIFIER) e tocar
// o som correspondente ao resultado. Retorna true se encontrou (e já tocou o som), ou
// false se o deal ainda não apareceu no histórico (para tentar de novo no próximo tick).
// IMPORTANTE: se não encontrar, NÃO toca nenhum som - evita o bug de tocar "loss.wav"
// por padrão quando o histórico ainda não sincronizou o deal de um TP recém-executado.
// Adiciona um som na fila em vez de tocar na hora - ver comentário da declaração de
// filaSons acima. O fallback "\\Audio\\..." (para quando o arquivo não está direto na
// pasta Sounds) só é resolvido no momento em que o som realmente toca, não aqui.
void EnfileirarSom(string nomeArquivo)
{
   int n = ArraySize(filaSons);
   ArrayResize(filaSons, n + 1);
   filaSons[n] = nomeArquivo;
}

// Chamada a cada ciclo (tick/timer, ~50ms). Libera no máximo um som da fila por vez,
// respeitando INTERVALO_ENTRE_SONS_MS desde o último som tocado - assim o próximo só
// começa depois que o anterior teve tempo de terminar, em vez de cortá-lo.
// Chamada a cada ciclo (~50ms). Se algum botão estiver com o reset visual pendente e já
// tiver passado DURACAO_VISUAL_CLIQUE_MS desde o clique, volta ele ao estado normal.
void ProcessarResetVisualDeBotoes()
{
   if(botaoPendenteDeReset == "") return;
   if(GetTickCount() - tickBotaoPendenteDeReset < DURACAO_VISUAL_CLIQUE_MS) return;

   ObjectSetInteger(0, botaoPendenteDeReset, OBJPROP_STATE, false);
   botaoPendenteDeReset = "";
   ChartRedraw(0);
}

void ProcessarFilaDeSons()
{
   if(ArraySize(filaSons) == 0) return;
   if(GetTickCount() < proximoSomDaFilaLiberadoEm) return;

   string arquivo = filaSons[0];
   for(int i = 0; i < ArraySize(filaSons) - 1; i++)
      filaSons[i] = filaSons[i + 1];
   ArrayResize(filaSons, ArraySize(filaSons) - 1);

   if(!PlaySound(arquivo)) PlaySound("\\Audio\\" + arquivo);
   proximoSomDaFilaLiberadoEm = GetTickCount() + INTERVALO_ENTRE_SONS_MS;
}

bool TentarTocarSomSaida(ulong ticketPosicao)
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal <= 0) continue;
      if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) != _Symbol) continue;

      long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
      if(entradaDeal != DEAL_ENTRY_OUT && entradaDeal != DEAL_ENTRY_INOUT) continue;

      if(ticketPosicao != 0 && (ulong)HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID) != ticketPosicao)
         continue;

      double lucro    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
      double swap     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
      double comissao = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);
      double resultado = lucro + swap + comissao;

      if(resultado > 0.0)
      {
         EnfileirarSom("gain.wav");
      }
      else
      {
         EnfileirarSom("loss.wav");
      }
      return true;
   }

   return false;
}

// Chama esta função a cada tick/timer enquanto aguardandoSomSaida estiver ativo,
// até localizar o deal (ou desistir após MAX_TENTATIVAS_SOM_SAIDA tentativas).
void ProcessarSomDeSaidaPendente()
{
   if(!aguardandoSomSaida) return;

   if(TentarTocarSomSaida(ultimoTicketPosicaoAberta))
   {
      aguardandoSomSaida = false;
      return;
   }

   tentativasSomSaida++;
   if(tentativasSomSaida >= MAX_TENTATIVAS_SOM_SAIDA)
   {
      Print("[AVISO] Deal de saída da posição ", ultimoTicketPosicaoAberta,
            " não sincronizou a tempo no histórico - usando o último P&L flutuante conhecido (R$ ",
            DoubleToString(ultimoLucroFlutuantePosicao, 2), ") como referência para o som.");

      if(ultimoLucroFlutuantePosicao > 0.0)
      {
         EnfileirarSom("gain.wav");
      }
      else
      {
         EnfileirarSom("loss.wav");
      }
      aguardandoSomSaida = false;
   }
}

// Watchdog de proteção: roda a cada ciclo (tick/timer). Se o robô abriu uma posição e
// definiu um alvo de SL/TP (slAlvoPosicaoAtual/tpAlvoPosicaoAtual), verifica se esse SL/TP
// ainda está de fato aplicado na posição. Se sumir por qualquer motivo (falha silenciosa
// anterior, ação externa, etc.), tenta reaplicar automaticamente e alerta o usuário -
// evita o cenário relatado de uma posição ficar sem proteção nenhuma sem ninguém perceber.
void GarantirProtecaoDaPosicao()
{
   if(slAlvoPosicaoAtual == 0.0 && tpAlvoPosicaoAtual == 0.0) return; // nada a proteger

   if(!PositionSelect(_Symbol))
   {
      // Posição já não existe mais (foi fechada) - nada mais a proteger.
      slAlvoPosicaoAtual = 0.0;
      tpAlvoPosicaoAtual = 0.0;
      contadorCiclosSemProtecao = 0;
      tentativasSomProtecaoFalha = 0;
      return;
   }

   double slAtual = PositionGetDouble(POSITION_SL);
   double tpAtual = PositionGetDouble(POSITION_TP);

   bool faltaSL = (slAlvoPosicaoAtual != 0.0 && slAtual == 0.0);
   bool faltaTP = (tpAlvoPosicaoAtual != 0.0 && tpAtual == 0.0);

   if(!faltaSL && !faltaTP)
   {
      contadorCiclosSemProtecao = 0; // proteção ok, nada a fazer
      tentativasSomProtecaoFalha = 0;
      return;
   }

   contadorCiclosSemProtecao++;
   if(contadorCiclosSemProtecao % CICLOS_ENTRE_TENTATIVAS_PROTECAO != 0) return; // evita martelar a corretora

   globalMensagemStatus = "ALERTA: Posição SEM SL/TP! Corrigindo automaticamente...";

   if(trade.PositionModify(_Symbol, slAlvoPosicaoAtual, tpAlvoPosicaoAtual))
   {
      Print("[PROTEÇÃO] SL/TP reaplicados com sucesso (estavam ausentes na posição).");
      globalMensagemStatus = "Proteção restaurada! SL/TP reaplicados.";
      tentativasSomProtecaoFalha = 0;
   }
   else
   {
      Print("[ALERTA] Posição AINDA SEM SL/TP! Nova tentativa falhou. Retcode: ", trade.ResultRetcode(),
            " - ", trade.ResultRetcodeDescription(), " | Verifique manualmente!");
      // Continua tentando corrigir indefinidamente, mas o som só repete até
      // MAX_TENTATIVAS_SOM_PROTECAO vezes por episódio, para não martelar o alerta sonoro.
      if(tentativasSomProtecaoFalha < MAX_TENTATIVAS_SOM_PROTECAO)
      {
         tentativasSomProtecaoFalha++;
         if(!PlaySound("errorPlacingOrder.wav")) PlaySound("\\Audio\\errorPlacingOrder.wav");
      }
   }
}

//+------------------------------------------------------------------+
//| Posições em outros ativos suportados (WDO/WIN/CCM, o que não for  |
//| o do gráfico atual) - exibição no painel e fechamento em massa.   |
//+------------------------------------------------------------------+

// Verdadeiro se QUALQUER posição aberta na conta pertence a algum ativo configurado em
// ConfigsDisponiveis[] (WDO, WIN, CCM, ...) - inclui a do gráfico atual e as de outros.
bool ExisteQualquerPosicaoAbertaSuportada()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string simb = PositionGetString(POSITION_SYMBOL);
      for(int c = 0; c < ArraySize(ConfigsDisponiveis); c++)
         if(StringFind(simb, ConfigsDisponiveis[c].prefixoSimbolo) == 0)
            return true;
   }
   return false;
}

// Fecha TODAS as posições abertas em ativos suportados - a do gráfico atual (reaproveitando
// FecharPosicaoAberta(), pra manter o mesmo tratamento de estado/som do CTRL+Enter comum) e,
// em seguida, as de qualquer outro ativo configurado que tenha posição aberta no momento.
void FecharTodasAsPosicoesSuportadas()
{
   if(PositionSelect(_Symbol))
      FecharPosicaoAberta();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      string simb = PositionGetString(POSITION_SYMBOL);
      if(simb == _Symbol) continue; // essa já foi tratada acima (ou não é do ativo atual, segue a checagem)

      bool suportado = false;
      for(int c = 0; c < ArraySize(ConfigsDisponiveis); c++)
         if(StringFind(simb, ConfigsDisponiveis[c].prefixoSimbolo) == 0) { suportado = true; break; }
      if(!suportado) continue;

      double lucroFlutuante = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(trade.PositionClose(ticket))
      {
         if(lucroFlutuante > 0.0) { EnfileirarSom("gain.wav"); }
         else                      { EnfileirarSom("loss.wav"); }
      }
      else
      {
         Print("[ERRO] Falha ao fechar posição de ", simb, " (ticket ", ticket, "). Retcode: ",
               trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         if(!PlaySound("errorPlacingOrder.wav")) PlaySound("\\Audio\\errorPlacingOrder.wav");
      }
   }
}

// Uma linha de posição extra-gráfico já formatada para exibição no painel.
struct InfoPosicaoExtra
{
   string texto;
   color  cor;
};

// Varre a conta procurando, para cada ativo suportado DIFERENTE do gráfico atual, uma
// posição aberta - se achar, monta a linha de texto (com PnL) pro painel. No máximo uma
// posição por ativo é considerada (é o comportamento normal de conta netting).
int ColetarPosicoesExtraGrafico(InfoPosicaoExtra &out[])
{
   ArrayResize(out, 0);

   for(int c = 0; c < ArraySize(ConfigsDisponiveis); c++)
   {
      if(StringFind(_Symbol, ConfigsDisponiveis[c].prefixoSimbolo) == 0) continue; // é o ativo do gráfico atual - já exibido acima

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;

         string simb = PositionGetString(POSITION_SYMBOL);
         if(StringFind(simb, ConfigsDisponiveis[c].prefixoSimbolo) != 0) continue;

         long   tipoPos     = PositionGetInteger(POSITION_TYPE);
         double vol         = PositionGetDouble(POSITION_VOLUME);
         double lucro       = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         int    volSinal    = (tipoPos == POSITION_TYPE_BUY) ? (int)vol : -(int)vol;

         string valorFmt = DoubleToString(lucro, 2); StringReplace(valorFmt, ".", ",");

         InfoPosicaoExtra info;
         info.texto = StringFormat("Posição %s (%d %s) | PnL R$ %s",
                         (tipoPos == POSITION_TYPE_BUY ? "comprada" : "vendida"), volSinal, simb, valorFmt);
         info.cor = (lucro > 0.0) ? clrLightGreen : (lucro < 0.0 ? clrLightSalmon : clrGainsboro );

         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = info;
         break; // já achou a posição desse ativo - vai para o próximo ativo configurado
      }
   }

   return ArraySize(out);
}

void FecharPosicaoAberta()
{
   if(PositionSelect(_Symbol))
   {
      ulong ticketAntesDeFechar = PositionGetInteger(POSITION_IDENTIFIER);
      if(trade.PositionClose(_Symbol))
      {
         ultimoTicketPosicaoAberta = ticketAntesDeFechar;
         aguardandoSomSaida = true;
         tentativasSomSaida = 0;
         slAlvoPosicaoAtual = 0.0;
         tpAlvoPosicaoAtual = 0.0;
         contadorCiclosSemProtecao = 0;
         globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
         posicaoEstavaAberta = false;
      }
      return;
   }

   // Sem posição aberta - mas pode existir uma ordem PENDENTE (Limit/Stop) esperando o
   // preço, criada por SHIFT/CTRL. CTRL+Enter também cancela essa ordem pendente.
   ulong ticketPendente = TicketDaOrdemPendente();
   if(ticketPendente > 0)
   {
      if(trade.OrderDelete(ticketPendente))
      {
         globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
         if(!PlaySound("cancelPendingOrder.wav")) PlaySound("\\Audio\\cancelPendingOrder.wav");
      }
      else
      {
         Print("[ERRO] Falha ao cancelar ordem pendente ", ticketPendente, ". Retcode: ",
               trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         globalMensagemStatus = "Falha ao cancelar ordem pendente!";
         if(!PlaySound("errorPlacingOrder.wav")) PlaySound("\\Audio\\errorPlacingOrder.wav");
      }
      return;
   }

   globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
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

      maiorAmplitudeGlobal = NormalizeDouble(ConverterPrecoParaPontos(maiorAmplitude), cfgAtiva.casasDecimaisFase);
      horarioMaiorCandle = TimeToString(dataHoraCandle, TIME_MINUTES);
   }
}

// Mesma lógica de CalcularResultadoFinanceiroDoDia(), mas filtrando por PREFIXO do símbolo
// em vez do _Symbol exato do gráfico atual - usada para somar o resultado do dia de outros
// ativos suportados (WDO/WIN/CCM) no "PnL diário GERAL" do painel, sem depender de haver
// uma posição aberta selecionada naquele ativo (funciona só com o histórico de negócios).
double CalcularResultadoFinanceiroDoDiaPorPrefixo(string prefixo)
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
         if(StringFind(ativoDeal, prefixo) == 0)
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
                        totalPontos += ConverterPrecoParaPontos(precoSaida - precoEntrada);
                     else
                        totalPontos += ConverterPrecoParaPontos(precoEntrada - precoSaida);

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

// Preço de referência para a PRÉVIA (linhas de entrada/SL/TP) quando ela foi armada por C/V
// (sem clique de mouse). Normalmente é o Ask/Bid ao vivo - mas em ativos menos líquidos
// (ex.: CCM) pode não ter chegado nenhum tick ainda desde que o gráfico foi aberto, e
// SYMBOL_ASK/SYMBOL_BID fica em 0, fazendo a prévia não ser desenhada. Nesse caso, cai para
// o último preço negociado (SYMBOL_LAST) e, se nem esse existir, para o fechamento da última
// barra já plotada - só para a prévia nunca ficar "sem desenhar nada" silenciosamente.
// IMPORTANTE: usada só na prévia. O envio real da ordem (EnviarOrdemMercado/Pendente)
// continua lendo Ask/Bid ao vivo diretamente, sem esse fallback - lá, se não houver
// cotação, é correto que a ordem realmente não seja enviada.
double ObterPrecoReferenciaMercado(bool compra)
{
   double preco = compra ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(preco > 0.0) return preco;

   preco = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(preco > 0.0) return preco;

   return iClose(_Symbol, _Period, 0); // último recurso - pode ainda vir 0 se não houver histórico algum
}

void DefaultAtualizarLinhasCustomizadas()
{
   double pontosSL = 0, pontosTP = 0;
   bool operacaoBonusLFT = false;
   ObterPontosAlvosEfetivos(pontosSL, pontosTP, operacaoBonusLFT);

   double precoReferencia = 0;
   double slProjetado = 0;
   double tpProjetado = 0;
   color corEntrada = clrNONE;

   if(tipoOperacao == 1)
   {
      precoReferencia = usarPrecoDoClique ? ArredondarParaPassoDoPreco(precoCliqueReferencia) : ObterPrecoReferenciaMercado(true);
      slProjetado     = precoReferencia - ConverterPontosParaPreco(pontosSL);
      tpProjetado     = precoReferencia + ConverterPontosParaPreco(pontosTP);
      corEntrada      = clrLimeGreen;
   }
   else if(tipoOperacao == 2)
   {
      precoReferencia = usarPrecoDoClique ? ArredondarParaPassoDoPreco(precoCliqueReferencia) : ObterPrecoReferenciaMercado(false);
      slProjetado     = precoReferencia + ConverterPontosParaPreco(pontosSL);
      tpProjetado     = precoReferencia - ConverterPontosParaPreco(pontosTP);
      corEntrada      = clrCrimson;
   }

   if(precoReferencia <= 0) return;

   DesenharLinhaH(PREFIX_OBJ+"Entrada", precoReferencia, corEntrada, STYLE_SOLID, 1);
   DesenharLinhaH(PREFIX_OBJ+"Loss",    slProjetado, C'252,70,70', STYLE_DOT, 1);
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

//+------------------------------------------------------------------+
//| Painel principal - 12 linhas, ordem espelhada conforme o canto   |
//+------------------------------------------------------------------+
void AtualizarPainelVisualEmTempoReal()
{
   VerificarEAutoReposicionarPainel();

   int E = NegociosDiaEfetivo();
   int maxOrdensPermitidas = E * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

   double acumProgAtual = CalcularAcumProg(faseAtual, E, papeisPorOperacao);
   double acumRegAtual  = CalcularAcumReg(faseAtual, E, papeisPorOperacao);
   double lftAtual       = CalcularLFT(faseAtual, E, papeisPorOperacao);
   bool   todosGanhosHoje = CondicaoAtivacaoLFT(pnlDiarioAtual, acumProgAtual);

   // Concede o bônus de +1 negócio uma única vez por dia, apenas quando: a quantidade de
   // negócios especificada para o dia foi totalmente fechada, todos em gain, e o Máx gain
   // (Acúmulo progressivo) da fase foi efetivamente alcançado.
   if(todosGanhosHoje && !bonusConcedidoHoje)
   {
      bonusConcedidoHoje = true;
      E = NegociosDiaEfetivo();
      maxOrdensPermitidas = E * 2;
   }

   double limiteLossEfetivo = todosGanhosHoje ? (pnlDiarioAtual - lftAtual) : acumRegAtual;

   bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);
   bool limiteLossAtingido    = (pnlDiarioAtual <= limiteLossEfetivo);
   bool limiteGainAtingido    = (pnlDiarioAtual >= acumProgAtual);
   bool algumLimiteAtingido   = (limiteOrdensAtingido || limiteLossAtingido || limiteGainAtingido);

   if(algumLimiteAtingido)
   {
      string motivo = limiteOrdensAtingido ? IntegerToString(maxOrdensPermitidas) + " ordens" :
                       (limiteGainAtingido ? "ganho" : "perda");
      globalMensagemStatus = "Basta por hoje! (Limite de " + motivo + " atingido)";
      ApagarLinhasProjecao();
   }
   else
   {
      if(globalMensagemStatus.Find("Basta por hoje") >= 0 && !PositionSelect(_Symbol))
      {
         globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
      }
   }

   // ---- Posição / status do preço na tela ----
   string textoPosicao = StringFormat("Posição zerada (0 %s)", _Symbol);
   color corPosicao = clrDarkGray;

   if(PositionSelect(_Symbol))
   {
      if(!posicaoEstavaAberta)
      {
         // Acabou de detectar a posição pela primeira vez (ordem a mercado executada, ou
         // ordem pendente preenchida) - toca o som de ordem aberta.
         if(!PlaySound("openedOrder.wav")) PlaySound("\\Audio\\openedOrder.wav");
      }
      posicaoEstavaAberta = true;
      ultimoTicketPosicaoAberta = PositionGetInteger(POSITION_IDENTIFIER);
      if(!algumLimiteAtingido)
         globalMensagemStatus = "Ordem executada! (CTRL + Enter) para Zerar";

      // Se ainda não há um alvo de SL/TP registrado para o watchdog (ex.: esta posição veio
      // do preenchimento de uma ordem PENDENTE, não de uma ordem a mercado enviada por
      // EnviarOrdemMercado()), adota o SL/TP que a própria posição já traz - o MetaTrader
      // já carrega automaticamente o SL/TP da ordem pendente para a posição resultante.
      if(slAlvoPosicaoAtual == 0.0 && tpAlvoPosicaoAtual == 0.0)
      {
         double slAtualPos = PositionGetDouble(POSITION_SL);
         double tpAtualPos = PositionGetDouble(POSITION_TP);
         if(slAtualPos != 0.0 || tpAtualPos != 0.0)
         {
            slAlvoPosicaoAtual = slAtualPos;
            tpAlvoPosicaoAtual = tpAtualPos;
         }
      }

      long tipoPos = PositionGetInteger(POSITION_TYPE);
      double precoAberturaPos = PositionGetDouble(POSITION_PRICE_OPEN);
      double precoAtual = (tipoPos == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lucroFinanceiro = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ultimoLucroFlutuantePosicao = lucroFinanceiro;

      string tipoStr = (tipoPos == POSITION_TYPE_BUY) ? "Compra" : "Venda";
      int volumePos = (int)PositionGetDouble(POSITION_VOLUME);
      int volumePosSinal = (tipoPos == POSITION_TYPE_BUY) ? volumePos : -volumePos;

      string valorFormatado = DoubleToString(lucroFinanceiro, 2);
      StringReplace(valorFormatado, ".", ",");

      textoPosicao = StringFormat("Posição %s (%d %s) | PnL R$ %s", (tipoPos == POSITION_TYPE_BUY ? "comprada" : "vendida"), volumePosSinal, _Symbol, valorFormatado);
      corPosicao = (lucroFinanceiro > 0.0) ? clrLimeGreen : (lucroFinanceiro < 0.0 ? C'252,70,70' : clrDarkGray);

      color corPnLGrafico = (lucroFinanceiro > 0.0) ? clrLimeGreen : (lucroFinanceiro < 0.0 ? C'252,70,70' : clrDarkGray);
      AtualizarLabelGraficoPreco(StringFormat("R$ %s", valorFormatado), corPnLGrafico, true);
   }
   else
   {
      if(posicaoEstavaAberta)
      {
         aguardandoSomSaida = true;
         tentativasSomSaida = 0;
         if(!algumLimiteAtingido)
            globalMensagemStatus = "(C ou SHIFT) Compra | (V ou CTRL) Venda";
         posicaoEstavaAberta = false;
      }
      ObjectDelete(0, LABEL_PRECO_POSICAO);
   }

   // ---- PnL diário ----
   double totalDoDia = pnlDiarioAtual;
   double totalPontosDia = CalcularPontosDoDia();
   int operacoesDiaCount = operacoesFeitasHoje;
   string strTotalDia = DoubleToString(totalDoDia, 2); StringReplace(strTotalDia, ".", ",");
   string strPontosDia = DoubleToString(totalPontosDia, cfgAtiva.casasDecimaisFase); StringReplace(strPontosDia, ".", ",");
   string textoPnLDiario = StringFormat("PnL diário: R$ %s | %s %s | Ordens: %d", strTotalDia, strPontosDia, cfgAtiva.unidadePontosLabel, operacoesDiaCount);
   color corPnLDiario = (totalDoDia > 0.0) ? clrLimeGreen : (totalDoDia < 0.0 ? C'252,70,70' : clrDarkGray);

   // ---- PnL mensal ----
   double totalDoMes = CalcularResultadoFinanceiroDoMes();
   double totalPontosMes = CalcularPontosDoMes();
   string strTotalMes = DoubleToString(totalDoMes, 2); StringReplace(strTotalMes, ".", ",");
   string strPontosMes = DoubleToString(totalPontosMes, cfgAtiva.casasDecimaisFase); StringReplace(strPontosMes, ".", ",");
   string textoPnLMensal = StringFormat("PnL mensal: R$ %s | %s %s | Ordens: %d", strTotalMes, strPontosMes, cfgAtiva.unidadePontosLabel, CalcularOperacoesDoMes());
   color corPnLMensal = (totalDoMes > 0.0) ? clrLimeGreen : (totalDoMes < 0.0 ? C'252,70,70' : clrDarkGray);

   // ---- Fase / SL / TP ----
   double exSL = 0, exTP = 0;
   ObterPontosAlvosFase(exSL, exTP);
   string strExSL = DoubleToString(exSL, cfgAtiva.casasDecimaisFase); StringReplace(strExSL, ".", ",");
   string strExTP = DoubleToString(exTP, cfgAtiva.casasDecimaisFase); StringReplace(strExTP, ".", ",");
   string textoFase = StringFormat("Fase %d - SL: %s %s | TP: %s %s", faseAtual, strExSL, cfgAtiva.unidadePontosLabel, strExTP, cfgAtiva.unidadePontosLabel);

   // ---- Papéis por operação ----
   string textoPapeis = StringFormat("Máx papéis por operação: %d", papeisPorOperacao);

   // ---- LFT ----
   string strLFT = DoubleToString(lftAtual, 2); StringReplace(strLFT, ".", ",");
   string textoLFT = StringFormat("Loss from top: R$ %s", strLFT);
   color corLFT = todosGanhosHoje ? clrLimeGreen : clrDarkGray;

   // ---- Acúmulos ----
   string strAcumReg  = DoubleToString(acumRegAtual, 2);  StringReplace(strAcumReg, ".", ",");
   string strAcumProg = DoubleToString(acumProgAtual, 2); StringReplace(strAcumProg, ".", ",");
   string textoAcumulos = StringFormat("Máx loss: R$ %s | Máx gain: R$ %s", strAcumReg, strAcumProg);

   // ---- Negócios por dia ----
   int gainsFechadosHoje = 0, lossesFechadosHoje = 0;
   ContarResultadosFechadosHoje(gainsFechadosHoje, lossesFechadosHoje);
   string textoNegocios = StringFormat("Máx negócios/dia: %d | Fechados: %d gain, %d loss", E, gainsFechadosHoje, lossesFechadosHoje);

   // Separadores agora são desenhados como retângulos finos (ver CriarSeparador), com
   // largura controlada por LARGURA_SEPARADOR - veja mais abaixo.

   // ---- Status (linha 11) ----
   string textoStatus = globalMensagemStatus;
   color corStatus = CorContrasteComFundo();

   // ---- Atalhos fixos (linha 12, nova) - sempre ao lado da linha de status, e espelha
   // junto com ela por já usar o mesmo esquema de GetLinhaY() - some quando o limite
   // diário é atingido, já que nesse momento não faz sentido convidar a enviar nova ordem.
   string textoAtalhos = "(Para C ou V: Enter) Envia | (CTRL+Enter) Zera";

   // Índices 0..11 correspondem às linhas 1..12 da especificação, na ordem do painel "em cima".
   // Quando o painel está embaixo, o próprio canto (CORNER_RIGHT_LOWER) já inverte a
   // direção em que o Y cresce, espelhando a ordem visual das linhas automaticamente.
   CriarTextoLabel(PREFIX_TXT+"0",  textoPnLMensal, MARGEM_DIREITA_TEXTO, GetLinhaY(0), 10, corPnLMensal, cantoPainelAtual);
   CriarSeparador(PREFIX_TXT+"1",   MARGEM_DIREITA_TEXTO, GetLinhaY(1)+OffsetParaBaixo(7), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"2",  textoFase,       MARGEM_DIREITA_TEXTO, GetLinhaY(2), 10, clrDodgerBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"3",  textoPapeis,     MARGEM_DIREITA_TEXTO, GetLinhaY(3), 10, clrDodgerBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"4",  textoLFT,        MARGEM_DIREITA_TEXTO, GetLinhaY(4), 10, corLFT, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"5",  textoAcumulos,   MARGEM_DIREITA_TEXTO, GetLinhaY(5), 10, clrSteelBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"6",  textoNegocios,   MARGEM_DIREITA_TEXTO, GetLinhaY(6), 10, clrSteelBlue, cantoPainelAtual);
   CriarSeparador(PREFIX_TXT+"7",   MARGEM_DIREITA_TEXTO, GetLinhaY(7)+OffsetParaBaixo(7), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);
   // ---- Posições de outros ativos suportados (WDO/WIN/CCM, o que não for o do gráfico
   // atual) - só aparecem (com separadores e o texto de instrução do atalho) quando há
   // pelo menos uma posição aberta em outro ativo. Esse bloco agora vem LOGO ANTES da
   // posição do gráfico atual/PnL diário (invertido em relação à ordem original), então é
   // calculado primeiro, e tudo que vem depois (PnL diário, posição, status, atalhos) é
   // deslocado dinamicamente pela altura que ele ocupar.
   InfoPosicaoExtra posicoesExtra[];
   int qtdExtras = ColetarPosicoesExtraGrafico(posicoesExtra);
   int maxExtrasPossivel = ArraySize(ConfigsDisponiveis) - 1; // no máximo, todos os outros ativos configurados

   // PnL diário GERAL = PnL diário do gráfico atual + PnL diário (realizado) de cada outro
   // ativo suportado, buscado por PREFIXO no histórico - funciona mesmo sem posição aberta
   // naquele ativo no momento (basta ter havido negócio hoje).
   double pnlDiarioTotalTodos = pnlDiarioAtual;
   for(int c = 0; c < ArraySize(ConfigsDisponiveis); c++)
   {
      if(StringFind(_Symbol, ConfigsDisponiveis[c].prefixoSimbolo) == 0) continue; // já contado acima
      pnlDiarioTotalTodos += CalcularResultadoFinanceiroDoDiaPorPrefixo(ConfigsDisponiveis[c].prefixoSimbolo);
   }
   string strPnLTotal = DoubleToString(pnlDiarioTotalTodos, 2); StringReplace(strPnLTotal, ".", ",");
   string textoPnLTotal = StringFormat("PnL diário GERAL: R$ %s", strPnLTotal);
   color corPnLTotal = (pnlDiarioTotalTodos > 0.0) ? clrLimeGreen : (pnlDiarioTotalTodos < 0.0 ? C'252,70,70' : clrDarkGray);

   // O separador do índice 7 (logo acima) já serve de fronteira entre a seção Máx
   // papéis/Fase e este bloco - por isso o bloco de extras NÃO tem separador próprio no
   // topo (EXTRA_SEP_A foi removido, ficava colado ao separador do índice 7).
   //
   // Layout deste bloco (sempre nesta ordem, de cima pra baixo quando o painel está no
   // canto superior): PnL diário GERAL (SEMPRE visível) -> posições extra-gráfico (só se
   // houver alguma aberta) -> instrução + botão "Zerar" na mesma linha (só se houver
   // posição extra-gráfico aberta) -> separador (sempre, fronteira com o bloco seguinte).
   int linhaBaseExtras = 8; // linha do "PnL diário GERAL", sempre presente
   int linhasOcupadasPorExtras = 1 /*PnL diário GERAL*/ + (qtdExtras > 0 ? (qtdExtras + 1 /*instrução*/) : 0) + 1 /*separador*/;

   ObjectDelete(0, PREFIX_TXT+"EXTRA_SEP_A"); // não existe mais - remove eventual resíduo de uma versão anterior

   CriarTextoLabel(PREFIX_TXT+"EXTRA_PNL_TOTAL", textoPnLTotal,
                    MARGEM_DIREITA_TEXTO, GetLinhaY(linhaBaseExtras), 10, corPnLTotal, cantoPainelAtual);

   if(qtdExtras > 0)
   {
      // Todas as posições extras em linhas normais, uma por uma.
      for(int i = 0; i < qtdExtras; i++)
         CriarTextoLabel(PREFIX_TXT+"EXTRA_POS"+IntegerToString(i), posicoesExtra[i].texto,
                          MARGEM_DIREITA_TEXTO, GetLinhaY(linhaBaseExtras+1+i), 10, posicoesExtra[i].cor, cantoPainelAtual);

      // Instrução + botão "Zerar" na última linha do bloco. Alternativa ao CTRL+ESC+ENTER
      // pra quem prefere mouse; o clique só age com 'ESC' pressionada (ver
      // CHARTEVENT_OBJECT_CLICK) - sem 'ESC', não faz nada.
      CriarTextoLabel(PREFIX_TXT+"EXTRA_INSTR", "(ESC+Clique ou CTRL+ESC+Enter) Zera TUDO",
                       MARGEM_DIREITA_TEXTO, GetLinhaY(linhaBaseExtras+1+qtdExtras), 10, CorContrasteComFundo(), cantoPainelAtual);
      CriarBotaoFase("Btn_ZerarTudo", "Zerar", 72, GetLinhaY(linhaBaseExtras+1+qtdExtras), 40, 18);
   }
   else
   {
      ObjectDelete(0, PREFIX_TXT+"EXTRA_INSTR");
      ObjectDelete(0, "Btn_ZerarTudo");
   }
   // Separador de baixo do bloco - SEMPRE presente agora (o PnL diário GERAL também é
   // sempre mostrado, então o bloco nunca fica totalmente vazio).
   CriarSeparador(PREFIX_TXT+"EXTRA_SEP_B", MARGEM_DIREITA_TEXTO, GetLinhaY(linhaBaseExtras+linhasOcupadasPorExtras-1)+OffsetParaBaixo(7), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);

   // Remove objetos de posições extras que existiam num ciclo anterior mas não existem mais
   // agora (ex.: fechou a posição do WDO e só sobrou a do CCM) - evita "lixo" gráfico.
   for(int i = qtdExtras; i < maxExtrasPossivel; i++)
      ObjectDelete(0, PREFIX_TXT+"EXTRA_POS"+IntegerToString(i));

   // PnL diário + Posição do gráfico atual agora vêm DEPOIS do bloco de extras (antes vinham
   // antes) - a linha exata depende de quantas linhas o bloco de extras ocupou acima.
   int linhaPnLDiario  = linhaBaseExtras + linhasOcupadasPorExtras;
   int linhaPosicao    = linhaPnLDiario + 1;
   int linhaSepStatus  = linhaPosicao + 1; // separador entre a posição/PnL diário e o status/atalhos
   int linhaStatus     = linhaSepStatus + 1;
   int linhaAtalhos    = linhaStatus + 1;

   CriarTextoLabel(PREFIX_TXT+"8",  textoPnLDiario,  MARGEM_DIREITA_TEXTO, GetLinhaY(linhaPnLDiario), 10, corPnLDiario, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"9",  textoPosicao,    MARGEM_DIREITA_TEXTO, GetLinhaY(linhaPosicao), 10, corPosicao, cantoPainelAtual);
   CriarSeparador(PREFIX_TXT+"SEP_STATUS", MARGEM_DIREITA_TEXTO, GetLinhaY(linhaSepStatus)+OffsetParaBaixo(7), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);

   totalLinhasPainelAtual = linhaAtalhos + 1; // usado por ObterRetanguloPainel no próximo ciclo

   CriarTextoLabel(PREFIX_TXT+"10", textoStatus,     MARGEM_DIREITA_TEXTO, GetLinhaY(linhaStatus), 10, corStatus, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"11", textoAtalhos,    MARGEM_DIREITA_TEXTO, GetLinhaY(linhaAtalhos), 10, CorContrasteComFundo(), cantoPainelAtual);
   SetObjVisivel(PREFIX_TXT+"11", !algumLimiteAtingido);

   // Botões da linha 3 (índice 2) - troca de fase
   CriarBotaoFase("Btn_FaseMenos", "-", 89, GetLinhaY(2)-1, 28, 16);
   CriarBotaoFase("Btn_FaseMais",  "+", 60,  GetLinhaY(2)-1, 28, 16);

   // Botões da linha 4 (índice 3) - papéis por operação
   CriarBotaoFase("Btn_PapelMenos", "-", 89, GetLinhaY(3), 28, 16);
   CriarBotaoFase("Btn_PapelMais",  "+", 60,  GetLinhaY(3), 28, 16);

   // Botões da linha 7 (índice 6) - negócios por dia (+2/-2)
   CriarBotaoFase("Btn_NegMenos", "-2", 89, GetLinhaY(6), 28, 16);
   CriarBotaoFase("Btn_NegMais",  "+2", 60,  GetLinhaY(6), 28, 16);

   // Botões de mover painel para cima/baixo (apenas um visível por vez) - ficam na linha do
   // PnL diário, que agora é dinâmica (o bloco de posições extra-gráfico pode empurrá-la).
   CriarBotaoFase("Btn_PainelBaixo", "▼", 60, GetLinhaY(linhaPnLDiario), 28, 16);
   CriarBotaoFase("Btn_PainelCima",  "▲", 60, GetLinhaY(linhaPnLDiario), 28, 16);
   SetObjVisivel("Btn_PainelBaixo", cantoPainelAtual == CORNER_RIGHT_UPPER);
   SetObjVisivel("Btn_PainelCima",  cantoPainelAtual == CORNER_RIGHT_LOWER);

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
   ObjectSetString(0, nome, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
}

// Separador desenhado como um retângulo fino (OBJ_RECTANGLE_LABEL), com largura em pixels
// controlada diretamente pelo parâmetro "largura" - não depende de fonte nem de caracteres,
// e por isso não sofre o corte (clipping) que acontecia com a string de traços.
void CriarSeparador(string nome, int x, int y, int largura, color cor, ENUM_BASE_CORNER canto)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nome, OBJPROP_BACK, false);
      ObjectSetInteger(0, nome, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, nome, OBJPROP_CORNER, canto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, nome, OBJPROP_YSIZE, 1);
   ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
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
   usarPrecoDoClique = false;
   precoCliqueReferencia = 0.0;
   armadoPorModificador = false;
   modificadorTipoOperacao = 0;
   ObjectDelete(0, PREFIX_OBJ+"Entrada");
   ObjectDelete(0, PREFIX_OBJ+"Loss");
   ObjectDelete(0, PREFIX_OBJ+"Gain");
   ChartRedraw(0);
}