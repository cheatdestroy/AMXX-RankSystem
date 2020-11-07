#include <amxmodx>
#include <hamsandwich>
#include <sqlx>

#if AMXX_VERSION_NUM < 183
#include <colorchat_mm>
#endif

#pragma semicolon 1

//Sumbits
#define SetBit(%0,%1) ((%0) |= (1 << (%1)))
#define ClearBit(%0,%1) ((%0) &= ~(1 << (%1)))
#define IsSetBit(%0,%1) ((%0) & (1 << (%1)))
#define InvertBit(%0,%1) ((%0) ^= (1 << (%1)))
#define IsNotSetBit(%0,%1) (~(%0) & (1 << (%1)))

#define PREFIX				"^1[^4RankSystem^1]"			//Префикс чат команд

#define OWNER_ACCESS	ADMIN_RCON	//Доступ к меню выдачи опыта/ранга, к командам обнуления топа.

#define USE_ONLY_NATIVES 	// Использовать только нативы? Отключает логику получения опыта в данном плагине.
#define STRIKE_SYSTEM		// Включить страйк убийств для увеличения полученного опыта

#define EXP 				1		//Опыт за убийство врага

#if defined STRIKE_SYSTEM
#define KILLS_TO_STRIKE_1	2		// Убийств для первого стрика
#define EXP_STRIKE_1		2		// Увеличение опыта за стрик (EXP + EXP_STRIKE_1)


#define KILLS_TO_STRIKE_2	3		// Убийств для второго стрика
#define EXP_STRIKE_2		3		// Увеличение опыта за стрик (EXP + EXP_STRIKE_2)
#endif

#define REWARD_1		4		// Уровень для получения доступа к ...
#define REWARD_2		9		// Уровень для получения доступа к ...
#define REWARD_3		10		// Уровень для получения доступа к ...
#define REWARD_4		10		// Уровень для получения доступа к ...
//======================= HUD ==========================//
#define R 255			// Reed
#define G 0				// Green
#define B 255			// Blue
#define X 0.01			// Cord X (0.0 - 1.0) (-1.0 - center)
#define Y 0.25			// Coord Y (0.0 - 1.0) (-1.0 - center)
#define EFFECT 1		// 0 - без эффектов, 1 - мерцание, 2 - печать
#define CHANNEL 4       // Channel
#define TASK_HUD 631269 
//======================================================//

//======================= DB ===========================//
#define USER_DB "user"
#define LOGIN_DB "login"
#define PASSWORD_DB "password"
#define NAME_DB "name"
//======================================================//

#define RANK_NAME_LENGHT 32		// Макс. длина названия ранга

enum _:Rewards
{
	R_1,
	R_2,
	R_3,
	R_4,
};

static const g_sRankName[][RANK_NAME_LENGHT] =		//Названия
{
	"Имя ранга 1",	// 0
	"Имя ранга 2",	// 1
	"Имя ранга 3",
	"Имя ранга 4",
	"Имя ранга 5",
	"Имя ранга 6",
	"Имя ранга 7",
	"Имя ранга 8",
	"Имя ранга 9",
	"Имя ранга 10",
	"Имя ранга 11"
};

const g_iMaxRank = charsmax(g_sRankName);

static const g_iRankExp[g_iMaxRank+1] =		//Опыт // Расчёт опыта (опыт нового звания - опыт текущего)
{
	0,		// 0
	100,		// 1
	250,
	500,
	2000,
	5000,
	10000,
	15000,
	20000,
	25000,
	30000
};

//Битсуммы
new g_iBitReward[Rewards], g_iBitMaxRank;

#if defined STRIKE_SYSTEM
new g_iBitDoubleExp, g_iBitTripleExp;
new g_iKillStrike[MAX_PLAYERS];
#endif

new g_iPlayerExp[MAX_PLAYERS], g_iPlayerRank[MAX_PLAYERS], g_iDifferenceExp[MAX_PLAYERS], g_iDifferenceRank[MAX_PLAYERS];

//Меню
new g_iPlayerMenuPage[MAX_PLAYERS], g_PlayerInMenu[MAX_PLAYERS][32], g_iTargetIndex[MAX_PLAYERS];

new bool:g_bAtrIsRank[MAX_PLAYERS];
new g_iAdminStep[MAX_PLAYERS], g_iIndexStep[MAX_PLAYERS];

new const g_iMenuStepRank[] = 
{
	0,
	1,
	2,
	3,
	4,
	5,
	6,
	7,
	8,
	9,
	10
};

new const g_iMenuStepExp[] = 
{
	10,
	50,
	100,
	200,
	300,
	400,
	500,
	1000,
	2000,
	5000,
	10000
};


//Бд
new Handle:g_SqlTuple, szQuery[512];

public plugin_init()
{
	register_plugin("Rank System", "1.1.3", "CheaT");

	#if defined USE_ONLY_NATIVES
	RegisterHam(Ham_Killed, "player", "Event_PlayerDeath");
	#endif

	register_menucmd(register_menuid("RankSystemMenu"), (1<<0|1<<1|1<<2|1<<3|1<<4|1<<5|1<<6|1<<7|1<<8|1<<9), "Handle_RankSystemMenu");
	register_menucmd(register_menuid("SelectAction"), (1<<0|1<<1|1<<2|1<<3|1<<8|1<<9), "Handle_SelectAction");

	register_clcmd("say /rankmenu", "RankSystemMenu", OWNER_ACCESS); // Меню выдачи рангов/опыта
	register_concmd("rs_reset_ranks", "SQL_ResetRanks", OWNER_ACCESS); // Обнуляет таблицу с рангами (обнуляет все ранги всех игроков)
	register_concmd("rs_update_ranks", "ReUpdateRanks", OWNER_ACCESS); // Обновляет звания текущих игроков на сервере. (Берет их значения из бд и заменяет серверные)

	SQL_SetAffinity("mysql");
	g_SqlTuple = SQL_MakeDbTuple(USER_DB, LOGIN_DB, PASSWORD_DB, NAME_DB);
	set_task(0.1, "SQL_ConnectDB");
}

public plugin_end()
{
	SQL_FreeHandle(g_SqlTuple);
}

public client_disconnect(id)
{
	if(!is_user_bot(id))
		SQL_SaveRank(id);

	if(task_exists(id+TASK_HUD))
		remove_task(id+TASK_HUD);

	ClearBit(g_iBitReward[R_1], id);
	ClearBit(g_iBitReward[R_2], id);
	ClearBit(g_iBitReward[R_3], id);
	ClearBit(g_iBitReward[R_4], id);
	ClearBit(g_iBitMaxRank, id);

	#if defined STRIKE_SYSTEM
	ClearBit(g_iBitDoubleExp, id);
	ClearBit(g_iBitTripleExp, id);
	#endif

	#if defined STRIKE_SYSTEM
	g_iKillStrike[id] = 0;
	#endif
}

public client_putinserver(id)
{
	g_iPlayerRank[id] = 0;
	g_iPlayerExp[id] = 0;
	g_iDifferenceRank[id] = 0;
	g_iDifferenceExp[id] = 0;

	set_task(1.0, "SQL_LoadRank", id);
}

#if defined USE_ONLY_NATIVES
public Event_PlayerDeath(victim, attacker, effect)
{
	if(attacker == victim || !attacker)
		return HAM_IGNORED;

	#if defined STRIKE_SYSTEM
	if(is_user_connected(victim) && g_iKillStrike[victim])
	{
		g_iKillStrike[victim] = 0;
		ClearBit(g_iBitDoubleExp, victim);
		ClearBit(g_iBitTripleExp, victim);
	}
	#endif

	if(is_user_connected(attacker) && !is_user_bot(attacker) && IsNotSetBit(g_iBitMaxRank, attacker))
	{
		#if defined STRIKE_SYSTEM
		g_iKillStrike[attacker]++;
		CheckStrike(attacker);

		if(IsSetBit(g_iBitDoubleExp, attacker))
			g_iPlayerExp[attacker] += (EXP * EXP_STRIKE_1);
		else if(IsSetBit(g_iBitTripleExp, attacker))
			g_iPlayerExp[attacker] += (EXP * EXP_STRIKE_2);
		else g_iPlayerExp[attacker] += EXP;
		#else
		g_iPlayerExp[attacker] += EXP;
		#endif

		CheckRank(attacker);
	}

	return PLUGIN_HANDLED;
}
#endif

#if defined STRIKE_SYSTEM
public CheckStrike(id)
{
	if(g_iKillStrike[id] >= KILLS_TO_STRIKE_2 && IsNotSetBit(g_iBitTripleExp, id))
	{
		client_print_color(id, print_team_blue, "%s ^1Вы получили ^3x%d Опыт ^1за стрик из ^4%d ^1убийств.", PREFIX, EXP_STRIKE_2, KILLS_TO_STRIKE_2);
		ClearBit(g_iBitDoubleExp, id);
		SetBit(g_iBitTripleExp, id);
	}
	else if(g_iKillStrike[id] >= KILLS_TO_STRIKE_1 && IsNotSetBit(g_iBitDoubleExp, id) && IsNotSetBit(g_iBitTripleExp, id))
	{
		client_print_color(id, print_team_blue, "%s ^1Вы получили ^3x%d Опыт ^1за стрик из ^4%d ^1убийств.", PREFIX, EXP_STRIKE_1, KILLS_TO_STRIKE_1);
		SetBit(g_iBitDoubleExp, id);
	}
}
#endif

public CheckRank(iPlayer)
{
	if(IsSetBit(g_iBitMaxRank, iPlayer))
		return PLUGIN_HANDLED;

	if(g_iPlayerExp[iPlayer] >= g_iRankExp[g_iPlayerRank[iPlayer] + 1])
	{
		Event_NewRank(iPlayer, ++g_iPlayerRank[iPlayer]);
		Event_NewReward(iPlayer);
	}

	return PLUGIN_HANDLED;
}

public Event_ChangeExp(iPlayer)
{
	for(new i = g_iMaxRank; i >= 0; i--)
	{
		if(g_iPlayerExp[iPlayer] >= g_iRankExp[i])
		{
			g_iPlayerRank[iPlayer] = i;
			Event_NewRank(iPlayer, g_iPlayerRank[iPlayer]);
			break;
		}
	}
}

public Event_NewRank(iPlayer, iRank)
{
	client_print_color(iPlayer, print_team_blue, "%s ^1Поздравляем! Вы получили новое звание ^3%s", PREFIX, g_sRankName[g_iPlayerRank[iPlayer]]);
	Event_NewReward(iPlayer);
	SQL_UpdateRank(iPlayer);
	if(g_iPlayerRank[iPlayer] >= g_iMaxRank)
	{
		client_print_color(iPlayer, print_team_red, "%s ^1Вы достигли ^3максимальное ^1звание!", PREFIX);
		SetBit(g_iBitMaxRank, iPlayer);
	}
	else
	{
		client_print_color(iPlayer, print_team_default, "%s ^1До следующего звание ^4%d ^1опыта", PREFIX, abs(g_iPlayerExp[iPlayer] - g_iRankExp[g_iPlayerRank[iPlayer] + 1]));
		ClearBit(g_iBitMaxRank, iPlayer);
	}
}

public Event_NewReward(iPlayer)
{
	LoadRewards(iPlayer);
	if(g_iPlayerRank[iPlayer] == REWARD_1)
		client_print_color(iPlayer, print_team_red, "%s ^1Награда за новый ранг: ^3доступ к ...", PREFIX);
	if(g_iPlayerRank[iPlayer] == REWARD_2)
		client_print_color(iPlayer, print_team_red, "%s ^1Награда за новый ранг: ^3доступ к ...", PREFIX);
	if(g_iPlayerRank[iPlayer] == REWARD_3)
		client_print_color(iPlayer, print_team_red, "%s ^1Награда за новый ранг: ^3доступ к ...", PREFIX);
	if(g_iPlayerRank[iPlayer] == REWARD_4)
		client_print_color(iPlayer, print_team_red, "%s ^1Награда за новый ранг: ^3доступ к ...", PREFIX);
}

public LoadRewards(id)
{
	if(g_iPlayerRank[id] >= REWARD_1)
	{
		if(IsNotSetBit(g_iBitReward[R_1], id))
			SetBit(g_iBitReward[R_1], id);
	}
	else
	{
		if(IsSetBit(g_iBitReward[R_1], id))
			ClearBit(g_iBitReward[R_1], id);
	}

	if(g_iPlayerRank[id] >= REWARD_2)
	{
		if(IsNotSetBit(g_iBitReward[R_2], id))
			SetBit(g_iBitReward[R_2], id);
	}
	else
	{
		if(IsSetBit(g_iBitReward[R_2], id))
			ClearBit(g_iBitReward[R_2], id);
	}

	if(g_iPlayerRank[id] >= REWARD_3)
	{
		if(IsNotSetBit(g_iBitReward[R_3], id))
			SetBit(g_iBitReward[R_3], id);
	}
	else
	{
		if(IsSetBit(g_iBitReward[R_3], id))
			ClearBit(g_iBitReward[R_3], id);
	}

	if(g_iPlayerRank[id] >= REWARD_4)
	{
		if(IsNotSetBit(g_iBitReward[R_4], id))
			SetBit(g_iBitReward[R_4], id);
	}
	else
	{
		if(IsSetBit(g_iBitReward[R_4], id))
			ClearBit(g_iBitReward[R_4], id);
	}
}

public Set_HudInfo(taskid)
{
	new id = taskid - TASK_HUD;
	if(!is_user_alive(id))
		return;

	set_hudmessage(R, G, B, X, Y, EFFECT, 0.5, 1.0, 0.1, 0.0, CHANNEL);
	if(g_iPlayerRank[id] < g_iMaxRank)
	{
		show_hudmessage(id, "Ранг: %s^nОпыт: %d^nОпыта до след. ранга: %d", 
			g_sRankName[g_iPlayerRank[id]], g_iPlayerExp[id], abs(g_iPlayerExp[id] - g_iRankExp[g_iPlayerRank[id] + 1]));
	}
	else
	{
		show_hudmessage(id, "Ранг: %s^nОпыт: %d^nМаксимальный ранг!", 
			g_sRankName[g_iPlayerRank[id]], g_iPlayerExp[id]);
	}
}

public RankSystemMenu(id, iPage)
{
	if(!(get_user_flags(id) & OWNER_ACCESS))
		return PLUGIN_HANDLED;
		
	if(iPage < 0)
		return PLUGIN_HANDLED;
	
	new szMenu[512], iKeys = (1<<9), iLen = formatex(szMenu, charsmax(szMenu), "\yRankSystem Меню^n^n");
	
	new iStart, iEnd;
	new Players[32], Count, i, name[32], iPlayer;
	get_players(Players, Count, "ch");
	
	i = min(iPage * 8, Count);
	iStart = i - (i % 8);
	
	iEnd = min(iStart + 8, Count);
	iPage = iStart / 8;
	
	g_PlayerInMenu[id] = Players;
	g_iPlayerMenuPage[id] = iPage;
	
	new iItem;
	
	for(i = iStart; i < iEnd; i++)
	{
		iPlayer = Players[i];
		get_user_name(iPlayer, name, charsmax(name));

		iKeys |= (1<<iItem);
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r%d\y] \w%s^n",++iItem, name);
	}
	
	if(iEnd < Count)
	{
		iKeys |= (1<<8);
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y[\r9\y] \wДалее");
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y[\r0\y] \w%s", iPage ? "Назад" : "Выход");
	}
	else
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y[\r0\y] \w%s", iPage ? "Назад" : "Выход");
	}
		
	return show_menu(id, iKeys, szMenu, -1, "RankSystemMenu");
}

public Handle_RankSystemMenu(id, iKey)
{
	switch(iKey)
	{
		case 8:
		{
			return RankSystemMenu(id, ++g_iPlayerMenuPage[id]);
		}
		case 9:
		{
			return RankSystemMenu(id, --g_iPlayerMenuPage[id]);
		}
		default:
		{
			new pPlayer = g_PlayerInMenu[id][(g_iPlayerMenuPage[id] * 8) + iKey];
			g_iTargetIndex[id] = pPlayer;
			return SelectAction(id);
		}
	}
	return PLUGIN_HANDLED;
}

public SelectAction(id)
{
	if(!is_user_connected(g_iTargetIndex[id]))
		return PLUGIN_HANDLED;

	new target[32];
	get_user_name(g_iTargetIndex[id], target, charsmax(target));
	new szMenu[512], iKeys = (1<<2|1<<3|1<<8|1<<9), iLen = formatex(szMenu, charsmax(szMenu), "\yИгрок: \r%s^n\dРанг: \r%d (%s) \d| Опыт: \r%d^n^n", target, g_iPlayerRank[g_iTargetIndex[id]], g_sRankName[g_iPlayerRank[g_iTargetIndex[id]]], g_iPlayerExp[g_iTargetIndex[id]]);
	if(g_bAtrIsRank[id])
	{
		if(g_iPlayerRank[g_iTargetIndex[id]] != g_iAdminStep[id])
		{
			iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r1\y] \wВыдать - \d[\r%d ранг\d]^n^n^n", g_iAdminStep[id]);
			iKeys |= (1<<0);
		}
		else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d[1] Выдать - [%d ранг]^n^n^n", g_iAdminStep[id]);
	}
	else
	{
		if(IsNotSetBit(g_iBitMaxRank, g_iTargetIndex[id]))
		{
			iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r1\y] \wДобавить - \d[\r%d опыта\d]^n", g_iAdminStep[id]);
			iKeys |= (1<<0);
		}
		else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d[1] Добавить - \d[\r%d опыта\d]^n", g_iAdminStep[id]);
		if(g_iPlayerExp[g_iTargetIndex[id]] > 0)
		{
			iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r2\y] \wОтнять^n^n");
			iKeys |= (1<<1);
		}
		else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d[2] Отнять^n^n");
	}
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r3\y] \wАтрибут - \d[\r%s\d]^n", g_bAtrIsRank[id] ? "Ранг" : "Опыт");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r4\y] \w%s - \d[\r%d\d]^n^n", g_bAtrIsRank[id] ? "Ранг" : "Опыт", g_iAdminStep[id]);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r9\y] \wНазад^n");
	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[\r0\y] \wВыход^n");
	return show_menu(id, iKeys, szMenu, -1, "SelectAction");
}

public Handle_SelectAction(id, iKey)
{
	if(!is_user_connected(g_iTargetIndex[id]))
		return PLUGIN_HANDLED;

	switch(iKey)
	{
		case 0:
		{
			if(g_bAtrIsRank[id])
			{
				g_iPlayerExp[g_iTargetIndex[id]] = g_iRankExp[g_iAdminStep[id]];
				Event_ChangeExp(g_iTargetIndex[id]);
			}
			else
			{
				if(IsNotSetBit(g_iBitMaxRank, g_iTargetIndex[id]) && g_iPlayerExp[g_iTargetIndex[id]] + g_iAdminStep[id] <= g_iRankExp[g_iMaxRank])
				{
					g_iPlayerExp[g_iTargetIndex[id]] += g_iAdminStep[id];
					Event_ChangeExp(g_iTargetIndex[id]);
				}
				else
				{
					g_iPlayerExp[g_iTargetIndex[id]] = g_iRankExp[g_iMaxRank];
					Event_ChangeExp(g_iTargetIndex[id]);
				}
			}
		}
		case 1:
		{
			if(!g_bAtrIsRank[id])
			{
				if(g_iPlayerExp[g_iTargetIndex[id]] - g_iAdminStep[id] >= 0)
				{
					g_iPlayerExp[g_iTargetIndex[id]] -= g_iAdminStep[id];
					Event_ChangeExp(g_iTargetIndex[id]);
				}
				else
				{
					g_iPlayerExp[g_iTargetIndex[id]] = 0;
					Event_ChangeExp(g_iTargetIndex[id]);
				}
			}
		}
		case 2:
		{
			g_bAtrIsRank[id] = !g_bAtrIsRank[id];
			if(g_bAtrIsRank[id])
			{
				g_iAdminStep[id] = g_iMenuStepRank[0];
				g_iIndexStep[id] = 0;
			}
			else
			{
				g_iAdminStep[id] = g_iMenuStepExp[0];
				g_iIndexStep[id] = 0;
			}
		}
		case 3:
		{
			if(g_bAtrIsRank[id])
			{
				if(g_iIndexStep[id] >= charsmax(g_iMenuStepRank))
				{
					g_iAdminStep[id] = g_iMenuStepRank[0];
					g_iIndexStep[id] = 0;
				}
				else
				{
					g_iIndexStep[id]++;
					g_iAdminStep[id] = g_iMenuStepRank[g_iIndexStep[id]];
				}
			}
			else
			{
				if(g_iIndexStep[id] >= charsmax(g_iMenuStepExp))
				{
					g_iAdminStep[id] = g_iMenuStepExp[0];
					g_iIndexStep[id] = 0;
				}
				else
				{
					g_iIndexStep[id]++;
					g_iAdminStep[id] = g_iMenuStepExp[g_iIndexStep[id]];
				}
			}
		}
		case 8: return RankSystemMenu(id, g_iPlayerMenuPage[id]);
		case 9: return PLUGIN_HANDLED;
	}
	return SelectAction(id);
}

public SQL_ConnectDB()
{
	new data[2];
	formatex(szQuery, charsmax(szQuery),
		"CREATE TABLE IF NOT EXISTS `rank_system` ( \
		`id` int UNSIGNED NOT NULL AUTO_INCREMENT, \
		`steamid` varchar(32) NOT NULL, \
		`rank` int DEFAULT 0 NOT NULL, \
		`exp` int DEFAULT 0 NOT NULL, \
		PRIMARY KEY (`id`), \
		UNIQUE KEY `UNIQUE` (`steamid`) USING BTREE, \
		KEY `steamid` (`steamid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8");
	SQL_ThreadQuery(g_SqlTuple, "SQL_RankSHandler", szQuery, data, sizeof(data));
}

public SQL_SaveRank(id)
{
	new steamid[25], data[2], iLen;
	get_user_authid(id, steamid, charsmax(steamid));
	iLen = formatex(szQuery, charsmax(szQuery), "INSERT INTO `rank_system` (`steamid`, `rank`, `exp`) ");
	iLen += formatex(szQuery[iLen], charsmax(szQuery) - iLen, "VALUES ('%s', '%d', '%d') ", steamid, g_iPlayerRank[id], g_iPlayerExp[id]);
	iLen += formatex(szQuery[iLen], charsmax(szQuery) - iLen, "ON DUPLICATE KEY UPDATE `rank`=VALUES(`rank`), `exp`=VALUES(`exp`)");
	data[0] = id;
	SQL_ThreadQuery(g_SqlTuple, "SQL_RankSHandler", szQuery, data, sizeof(data));
}

public SQL_LoadRank(id)
{
	new steamid[25], data[2];
	get_user_authid(id, steamid, charsmax(steamid));
	formatex(szQuery, charsmax(szQuery),
	"SELECT * FROM `rank_system` WHERE `steamid` = '%s'", steamid);
	data[0] = id;
	SQL_ThreadQuery(g_SqlTuple, "SQL_LoadRankHandler", szQuery, data, sizeof(data));
}

public SQL_UpdateRank(id)
{
	new steamid[25], data[2];
	get_user_authid(id, steamid, charsmax(steamid));
	formatex(szQuery, charsmax(szQuery),
	"UPDATE `rank_system` SET `rank` = `rank` + '%d', `exp` = `exp` + '%d' WHERE `rank_system`.`steamid` = '%s'", 
	g_iPlayerRank[id] - g_iDifferenceRank[id], g_iPlayerExp[id] - g_iDifferenceExp[id], steamid);
	data[0] = id;
	SQL_ThreadQuery(g_SqlTuple, "SQL_RankSHandler", szQuery, data, sizeof(data));
}

public ReUpdateRanks(id)
{
	if(!(get_user_flags(id) & OWNER_ACCESS))
		return;

	new iPlayers[32], iNum, iPlayer;
	get_players(iPlayers, iNum, "ch");
	for(new i = 0; i < iNum; i++)
	{
		iPlayer = iPlayers[i];
		SQL_LoadRank(iPlayer);
	}
}

public ReResetRanks()
{
	new iPlayers[32], iNum, iPlayer;
	get_players(iPlayers, iNum, "ch");
	for(new i = 0; i < iNum; i++)
	{
		iPlayer = iPlayers[i];
		g_iPlayerRank[iPlayer] = 0;
		g_iPlayerExp[iPlayer] = 0;
	}
}

public SQL_ResetRanks(id)
{
	if(!(get_user_flags(id) & OWNER_ACCESS))
		return;

	ReResetRanks();
	formatex(szQuery, charsmax(szQuery),
	"DELETE FROM `rank_system`");
	SQL_ThreadQuery(g_SqlTuple, "SQL_RankSHandler", szQuery);
}

// ==================================== Handlers ========================================= //
public SQL_RankSHandler(failstate, Handle:Query, error[], err, data[], size, Float:queuetime)
{
	if(failstate != TQUERY_SUCCESS)
	{
		log_amx("[RankSystem] MySQL Error: %d [%s]", err, error);
		return;
	}
}

public SQL_LoadRankHandler(failstate, Handle:Query, error[], err, data[], size, Float:queuetime)
{
	new id = data[0];
	if(SQL_NumResults(Query))
	{
		g_iPlayerRank[id] = g_iDifferenceRank[id] = SQL_ReadResult(Query, 2);
		g_iPlayerExp[id] = g_iDifferenceExp[id] = SQL_ReadResult(Query, 3);

		if(g_iPlayerRank[id] >= g_iMaxRank)
			SetBit(g_iBitMaxRank, id);

		LoadRewards(id);
	}
	else
	{
		if(!is_user_bot(id))
			SQL_SaveRank(id);
	}

	set_task(1.0, "Set_HudInfo", TASK_HUD+id, _, _, "ab");
}
////////////////////////////////////////////////////////////////////////////////////////////////////////

public plugin_natives()
{
	register_native("set_user_rank", "_native_set_user_rank", 1);
	register_native("set_user_exp", "_native_set_user_exp", 1);
	register_native("add_user_rank", "_native_add_user_rank", 1);
	register_native("add_user_exp", "_native_add_user_exp", 1);
	register_native("minus_user_rank", "_native_minus_user_rank", 1);
	register_native("minus_user_exp", "_native_minus_user_exp", 1);

	register_native("get_bit_reward1", "_native_get_bit_reward1", 1);
	register_native("get_bit_reward2", "_native_get_bit_reward2", 1);
	register_native("get_bit_reward3", "_native_get_bit_reward3", 1);
	register_native("get_bit_reward4", "_native_get_bit_reward4", 1);

	register_native("get_user_rank", "_native_get_user_rank", 1);
	register_native("get_user_exp", "_native_get_user_exp", 1);
	register_native("get_user_prefix", "_native_get_user_prefix");
}

public _native_set_user_rank(id, value)
{
	if(value < 0 && value > g_iMaxRank)
		return;

	g_iPlayerRank[id] = value;
}

public _native_set_user_exp(id, value)
{
	if(value < 0)
		return;

	g_iPlayerExp[id] = value;
}

public _native_add_user_rank(id, value)
{
	if(value < 0)
		return;

	if(g_iPlayerRank[id] + value > g_iMaxRank)
		return;

	g_iPlayerRank[id] += value;
}

public _native_add_user_exp(id, value)
{
	if(value < 0)
		return;

	g_iPlayerExp[id] += value;
}

public _native_minus_user_rank(id, value)
{
	if(value < 0)
		return;

	if(g_iPlayerRank[id] - value < 0)
		return;

	g_iPlayerRank[id] -= value;
}

public _native_minus_user_exp(id, value)
{
	if(value < 0)
		return;

	g_iPlayerExp[id] -= value;
}

public _native_get_bit_reward1(id)
{
	return IsSetBit(g_iBitReward[R_KNIFE], id);
}

public _native_get_bit_reward2(id)
{
	return IsSetBit(g_iBitReward[R_PARASHUT], id);
}

public _native_get_bit_reward3(id)
{
	return IsSetBit(g_iBitReward[R_MODELS], id);
}

public _native_get_bit_reward4(id)
{
	return IsSetBit(g_iBitReward[R_DUELS], id);
}

public _native_get_user_rank(id)
{
	return g_iPlayerRank[id];
}

public _native_get_user_exp(id)
{
	return g_iPlayerExp[id];
}

public _native_get_user_prefix()
{
	new id = get_param(1);
	new lenght = get_param(3);
	set_string(2, g_sRankName[g_iPlayerRank[id]], lenght);
}