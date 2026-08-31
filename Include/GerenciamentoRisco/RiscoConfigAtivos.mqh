//+------------------------------------------------------------------+
//| RiscoConfigAtivos.mqh                                            |
//| Configuração por ativo da boleta de Gerenciamento de Risco.       |
//|                                                                    |
//| Este arquivo é o ÚNICO lugar que deve mudar quando você:          |
//|   - ajustar a tabela de fases de um ativo já suportado;           |
//|   - adicionar um novo ativo (basta uma nova entrada em             |
//|     ConfigsDisponiveis[] - o RiscoCore.mqh não muda).             |
//|                                                                    |
//| IMPORTANTE: as fórmulas de Acúmulo/LFT e a conversão de SL/TP são |
//| DIFERENTES por ativo por decisão testada e confirmada (não é bug):|
//|   WDO -> FORMULA_LOTE_MAX_FASE + CONV_DIRETA           (10,0 R$/pt)|
//|   CCM -> FORMULA_LOTE_MAX_FASE + CONV_MULTIPLICA_POINT (4,5 R$/pt)|
//|   WIN -> FORMULA_PAPEIS_USUARIO + CONV_MULTIPLICA_POINT           |
//|   Ações/ETF/FII -> FORMULA_LOTE_MAX_FASE + CONV_MULTIPLICA_POINT  |
//|                    (R$/pt e lote DINÂMICOS - vêm do símbolo, não   |
//|                    de um número fixo na tabela; ver campos         |
//|                    valorPorPontoDinamico/loteBaseadoEmVolumeMinimo)|
//| O multiplicador financeiro de FORMULA_LOTE_MAX_FASE vem sempre de |
//| valorPorPontoPorLote - por isso WDO e CCM usam a mesma fórmula no |
//| RiscoCore.mqh mesmo tendo constantes diferentes (10,0 vs 4,5).    |
//| Ao adicionar um ativo novo, valide com testes reais qual dos dois |
//| modos (ou um novo modo) corresponde ao comportamento correto      |
//| antes de ligar o EA em conta real.                                |
//+------------------------------------------------------------------+
#property strict

// Modo de conversão de "pontos" (como usados na tabela de fases) para a unidade de
// preço do símbolo:
//   CONV_DIRETA           -> usa o valor em pontos diretamente na conta de preço
//                             (validado para o WDO)
//   CONV_MULTIPLICA_POINT -> multiplica por _Point antes de somar/subtrair do preço
//                             (validado para o WIN)
enum ModoConversaoSLTP
{
   CONV_DIRETA,
   CONV_MULTIPLICA_POINT
};

// Modo das fórmulas de Acúmulo progressivo/regressivo e LFT:
//   FORMULA_LOTE_MAX_FASE  -> usa o Lote Max FIXO da fase (TabelaFases[fase].loteMax)
//                             (validado para o WDO)
//   FORMULA_PAPEIS_USUARIO -> usa a quantidade de papéis (V) escolhida pelo usuário,
//                             dividido por 50 (validado para o WIN)
enum ModoFormulaRisco
{
   FORMULA_LOTE_MAX_FASE,
   FORMULA_PAPEIS_USUARIO
};

// Como identificar se o símbolo do gráfico (ou de uma posição aberta) pertence a este
// ativo/classe:
//   DETECCAO_PREFIXO     -> casa pelo COMEÇO do símbolo (StringFind==0), ex.: "WDO",
//                            "WIN", "CCM" - um símbolo específico por config.
//   DETECCAO_SUFIXO_ACAO -> casa por PADRÃO (letras + 1-2 dígitos + "F" opcional no
//                            final), usado pela config genérica de Ações/ETF/FII, que
//                            precisa reconhecer QUALQUER ticker desse formato, não um
//                            símbolo específico.
enum ModoDeteccao
{
   DETECCAO_PREFIXO,
   DETECCAO_SUFIXO_ACAO
};

// Uma linha da tabela de fases (em PONTOS por operação, não total financeiro diário).
struct StructFase
{
   double gainPontos;   // GAIN (pontos) - alvo de ganho em pontos por operação
   double lossPontos;   // LOSS (pontos) - alvo de perda em pontos por operação (valor negativo)
   int    loteMax;      // Lote Max - quantidade máxima de papéis negociáveis no dia (fixo da fase)
};

// Configuração completa de um ativo - tudo que o RiscoCore.mqh precisa para operar
// corretamente naquele símbolo, sem nenhum "if" espalhado pelo código.
struct ConfigAtivo
{
   string             nomeAtivo;             // rótulo legível (ex.: "WDO - Minidólar")
   string             prefixoSimbolo;        // prefixo esperado do _Symbol (só usado com DETECCAO_PREFIXO)
   StructFase         tabelaFases[11];       // índice 0 não usado; fases 1..10
   double             valorPorPontoPorLote;  // R$ por ponto por papel - IGNORADO se valorPorPontoDinamico=true
   ModoConversaoSLTP  modoConversaoSLTP;
   ModoFormulaRisco   modoFormulaRisco;
   int                casasDecimaisFase;     // casas decimais ao exibir SL/TP da fase no painel (WDO=1, WIN=0, CCM=1)
   string             unidadePontosLabel;    // rótulo exibido no painel para "pontos" (WDO/WIN="pts", CCM="centavos")
   ModoDeteccao       modoDeteccao;          // como reconhecer o símbolo (prefixo fixo ou padrão de ação/ETF/FII)
   bool               valorPorPontoDinamico; // se true, ignora valorPorPontoPorLote e lê SYMBOL_TRADE_TICK_VALUE do símbolo
   bool               loteBaseadoEmVolumeMinimo; // se true, Lote Max final = tabela × SYMBOL_VOLUME_MIN do símbolo
   int                incrementoGrandePapeis; // se > 0, mostra um par extra de botões "-N/+N" pra "Papéis por operação" (0 = não mostra, comportamento padrão)
};

//+------------------------------------------------------------------+
//| Tabela de fases - WDO (Minidólar)                                 |
//+------------------------------------------------------------------+
StructFase TabelaFasesWDO[11] =
{
   { 0.0, 0.0,  0 },   // Índice 0 (Não usado)
   { 2.5, -2.5,  1 },   // Fase 1
   { 3.0, -3.0,  2 },   // Fase 2
   { 3.5, -3.5,  3 },   // Fase 3
   { 4.0, -3.5,  4 },   // Fase 4
   { 4.5, -4.0,  5 },   // Fase 5
   { 5.0, -4.5,  6 },   // Fase 6
   { 5.5, -5.0,  7 },   // Fase 7
   { 6.0, -5.0,  8 },   // Fase 8
   { 6.5, -5.5,  9 },   // Fase 9
   { 7.0, -6.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Tabela de fases - WIN (Miniíndice)                                |
//+------------------------------------------------------------------+
StructFase TabelaFasesWIN[11] =
{
   {   0.0,    0.0,  0 },   // Índice 0 (Não usado)
   { 150.0, -150.0,  1 },   // Fase 1
   { 200.0, -200.0,  2 },   // Fase 2
   { 250.0, -250.0,  3 },   // Fase 3
   { 300.0, -250.0,  4 },   // Fase 4
   { 350.0, -300.0,  5 },   // Fase 5
   { 400.0, -350.0,  6 },   // Fase 6
   { 450.0, -400.0,  7 },   // Fase 7
   { 500.0, -400.0,  8 },   // Fase 8
   { 550.0, -450.0,  9 },   // Fase 9
   { 600.0, -500.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Tabela de fases - CCM (Milho)                                     |
//| "Pontos" aqui equivalem a CENTAVOS (R$ 0,01) - por isso o ativo   |
//| usa CONV_MULTIPLICA_POINT: o _Point do CCM (0,01) já É o centavo. |
//+------------------------------------------------------------------+
StructFase TabelaFasesCCM[11] =
{
   {  0.0,  0.0,  0 },   // Índice 0 (Não usado)
   {  5.0, -5.0,  1 },   // Fase 1
   {  6.0, -6.0,  2 },   // Fase 2
   {  7.0, -7.0,  3 },   // Fase 3
   {  8.0, -7.0,  4 },   // Fase 4
   {  9.0, -8.0,  5 },   // Fase 5
   { 10.0, -9.0,  6 },   // Fase 6
   { 11.0,-10.0,  7 },   // Fase 7
   { 12.0,-10.0,  8 },   // Fase 8
   { 13.0,-11.0,  9 },   // Fase 9
   { 14.0,-12.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Tabela de fases - Ações / ETF / FII (genérica, qualquer papel)    |
//| Mesma estrutura de fórmula do CCM (FORMULA_LOTE_MAX_FASE); "R$/pt"|
//| e "Lote Max" aqui são valores ABSTRATOS da tabela - o R$/pt real  |
//| vem de SYMBOL_TRADE_TICK_VALUE e o lote real de SYMBOL_VOLUME_MIN,|
//| lidos em tempo real do símbolo, não daqui.                        |
//+------------------------------------------------------------------+
StructFase TabelaFasesAcoes[11] =
{
   {  0.0,  0.0,  0 },   // Índice 0 (Não usado)
   { 10.0, -10.0,  1 },   // Fase 1
   { 12.0, -12.0,  4 },   // Fase 2
   { 14.0, -14.0,  7 },   // Fase 3
   { 16.0, -14.0, 11 },   // Fase 4
   { 18.0, -16.0, 15 },   // Fase 5
   { 20.0, -18.0, 19 },   // Fase 6
   { 22.0, -20.0, 23 },   // Fase 7
   { 24.0, -20.0, 28 },   // Fase 8
   { 26.0, -22.0, 32 },   // Fase 9
   { 28.0, -24.0, 37 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Tabela de fases - GOLD11 (ETF de ouro)                            |
//| Ativo ESPECÍFICO (não a config genérica de Ações/ETF/FII): "Lote  |
//| Max" aqui já é a quantidade FINAL de cotas por fase (não um valor |
//| abstrato multiplicado depois), e o R$/ponto é FIXO (0,01), não    |
//| lido do símbolo em tempo real - validado uma vez, como WDO/CCM.   |
//+------------------------------------------------------------------+
StructFase TabelaFasesGOLD11[11] =
{
   {  0.0,  0.0,    0 },   // Índice 0 (Não usado)
   { 10.0, -10.0,  500 },   // Fase 1
   { 12.0, -12.0,  600 },   // Fase 2
   { 14.0, -14.0,  700 },   // Fase 3
   { 16.0, -14.0,  800 },   // Fase 4
   { 18.0, -16.0,  900 },   // Fase 5
   { 20.0, -18.0, 1000 },   // Fase 6
   { 22.0, -20.0, 1100 },   // Fase 7
   { 24.0, -20.0, 1200 },   // Fase 8
   { 26.0, -22.0, 1300 },   // Fase 9
   { 28.0, -24.0, 1400 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Registro central de ativos suportados.                            |
//| Para adicionar um novo ativo específico (símbolo único): crie sua |
//| StructFase[11] acima e adicione uma linha aqui com DETECCAO_PREFIXO.|
//| A entrada "Ações/ETF/FII" é genérica (DETECCAO_SUFIXO_ACAO) e deve|
//| continuar sendo a ÚLTIMA da lista, pra nunca ser checada antes dos|
//| ativos específicos (evita, por exemplo, "CCMU26" ser confundido   |
//| com um ticker de ação por terminar em 2 dígitos).                 |
//+------------------------------------------------------------------+
ConfigAtivo ConfigsDisponiveis[] =
{
   { "WDO - Minidólar",   "WDO",  {}, 10.00, CONV_DIRETA,           FORMULA_LOTE_MAX_FASE,   1, "pts",      DETECCAO_PREFIXO,     false, false, 0  },
   { "WIN - Miniíndice",  "WIN",  {},  0.20, CONV_MULTIPLICA_POINT, FORMULA_PAPEIS_USUARIO,  0, "pts",      DETECCAO_PREFIXO,     false, false, 0  },
   { "CCM - Milho",       "CCM",  {},  4.50, CONV_MULTIPLICA_POINT, FORMULA_LOTE_MAX_FASE,   1, "centavos", DETECCAO_PREFIXO,     false, false, 0  },
   { "GOLD11 - ETF Ouro", "GOLD", {},  0.01, CONV_MULTIPLICA_POINT, FORMULA_LOTE_MAX_FASE,   1, "centavos", DETECCAO_PREFIXO,     false, false, 10 },
   { "Ações/ETF/FII",     "",     {},  0.00, CONV_MULTIPLICA_POINT, FORMULA_LOTE_MAX_FASE,   1, "centavos", DETECCAO_SUFIXO_ACAO, true,  true,  0  }
};

// Copia a tabela de fases correta para dentro de cada ConfigAtivo. Feito em uma função
// (chamada uma vez, do DetectarConfigAtivo) em vez de inicializar o array de structs
// diretamente, porque o MQL5 não permite inicializar um membro array-de-struct dentro
// de um inicializador de array de structs.
void PrepararTabelasDosAtivos()
{
   ArrayCopy(ConfigsDisponiveis[0].tabelaFases, TabelaFasesWDO);
   ArrayCopy(ConfigsDisponiveis[1].tabelaFases, TabelaFasesWIN);
   ArrayCopy(ConfigsDisponiveis[2].tabelaFases, TabelaFasesCCM);
   ArrayCopy(ConfigsDisponiveis[3].tabelaFases, TabelaFasesGOLD11);
   ArrayCopy(ConfigsDisponiveis[4].tabelaFases, TabelaFasesAcoes);
}

// Reconhece um ticker de ação/ETF/FII pelo PADRÃO do nome, não por lista fechada de
// empresas: letras (pelo menos 3) seguidas de 1 ou 2 dígitos, com um "F" opcional no
// final (mercado fracionário - ex.: "VALE3F", "PETR4F"). Cobre ON/PN/UNIT/ETF/FII de
// qualquer terminação (3, 4, 5, 6, 11, ...) sem precisar saber o número de antemão.
// Deliberadamente NÃO tenta diferenciar ação de ETF de FII - só "isso parece um papel
// negociado em lote de bolsa", que é tudo que o robô precisa saber pra aplicar a mesma
// tabela genérica.
bool EhTickerDeAcaoEtfFii(string simbolo)
{
   string base = simbolo;
   int len = StringLen(base);
   if(len < 4) return false;

   // Remove o "F" de mercado fracionário, se houver, antes de analisar o resto.
   if(StringGetCharacter(base, len - 1) == 'F')
   {
      base = StringSubstr(base, 0, len - 1);
      len--;
   }
   if(len < 4) return false;

   // Os últimos 1 ou 2 caracteres precisam ser dígitos.
   int qtdDigitos = 0;
   for(int i = len - 1; i >= 0 && qtdDigitos < 2; i--)
   {
      ushort c = StringGetCharacter(base, i);
      if(c >= '0' && c <= '9') qtdDigitos++;
      else break;
   }
   if(qtdDigitos == 0) return false;

   int qtdLetras = len - qtdDigitos;
   if(qtdLetras < 3) return false; // precisa de pelo menos 3 letras antes do número

   for(int i = 0; i < qtdLetras; i++)
   {
      ushort c = StringGetCharacter(base, i);
      bool ehLetra = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
      if(!ehLetra) return false;
   }

   return true;
}

// Verdadeiro se "simbolo" pertence à config informada - centraliza a checagem (prefixo
// fixo ou padrão de ação/ETF/FII) num único lugar, usado tanto pra detectar o ativo do
// gráfico atual quanto pra varrer posições abertas de outros ativos suportados.
bool SimboloBateComConfig(string simbolo, const ConfigAtivo &config)
{
   if(config.modoDeteccao == DETECCAO_PREFIXO)
      return (StringFind(simbolo, config.prefixoSimbolo) == 0);
   return EhTickerDeAcaoEtfFii(simbolo);
}

// Detecta a config correta a partir do símbolo do gráfico atual. Ativos com
// DETECCAO_PREFIXO usam StringFind(...)==0 (casa pelo início do nome) para que contratos
// futuros com sufixo de vencimento (ex.: "WDOF26", "WINZ25") continuem sendo reconhecidos
// sem precisar atualizar esta lista a cada troca de mês; a config genérica de Ações/ETF/FII
// (DETECCAO_SUFIXO_ACAO) é sempre checada por último, então nunca compete com um ativo
// específico já cadastrado.
// Retorna false se nenhum ativo da lista bater com o símbolo - o chamador (OnInit) deve
// tratar isso como falha de inicialização, nunca como "usar uma config qualquer".
bool DetectarConfigAtivo(string simbolo, ConfigAtivo &configOut)
{
   PrepararTabelasDosAtivos();

   for(int i = 0; i < ArraySize(ConfigsDisponiveis); i++)
   {
      if(SimboloBateComConfig(simbolo, ConfigsDisponiveis[i]))
      {
         configOut = ConfigsDisponiveis[i];
         return true;
      }
   }
   return false;
}