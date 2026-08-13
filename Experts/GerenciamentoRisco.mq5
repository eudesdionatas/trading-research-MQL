//+------------------------------------------------------------------+
//|         GerenciamentoRisco.mq5                                    |
//|         Boleta de Gerenciamento de Risco - multi-ativo            |
//|         (detecta WDO/WIN automaticamente pelo símbolo do gráfico) |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.0"
#property strict
#property description "Boleta de gerenciamento de risco por fases. Suporta CCM, WDO, WIN, "
#property description "detectando o ativo automaticamente pelo símbolo do gráfico."

// A ordem dos includes importa: RiscoConfigAtivos.mqh define StructFase/ConfigAtivo,
// que RiscoCore.mqh usa. Para adicionar um novo ativo, edite só o primeiro arquivo.
#include <GerenciamentoRisco/RiscoConfigAtivos.mqh>
#include <GerenciamentoRisco/RiscoCore.mqh>

// OnInit, OnDeinit, OnTick, OnTimer e OnChartEvent estão definidos dentro de
// RiscoCore.mqh - não precisam ser repetidos aqui.
