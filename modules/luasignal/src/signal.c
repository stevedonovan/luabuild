#include "queue.h"
#include "signames.h"
#include <lua.h>
#include <lauxlib.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#define REG_TABLE "luasignal"
#define VERSION "LuaSignal 0.1"

static lua_State* gL = NULL;
static lua_Hook old_hook = NULL;
static int old_mask = 0;
static int old_count = 0;
static queue q;
/* hardcoding 256 here is not great... is there a better way to get the highest
 * numbered signal? */
static struct sigaction lua_handlers[256];

static void lua_signal_handler(lua_State* L, lua_Debug* D)
{
    sigset_t sset, oldset;
    int sig;

    lua_sethook(gL, old_hook, old_mask, old_count);

    sigfillset(&sset);
    sigprocmask(SIG_BLOCK, &sset, &oldset);

    while ((sig = dequeue(&q)) != -1) {
        const char* signame;

        signame = sig_to_name(sig);
        lua_getfield(gL, LUA_REGISTRYINDEX, REG_TABLE);
        lua_getfield(gL, -1, signame);
        lua_pushstring(gL, signame);
        sigprocmask(SIG_SETMASK, &oldset, NULL);
        lua_call(gL, 1, 0);
        sigprocmask(SIG_BLOCK, &sset, &oldset);
    }

    sigprocmask(SIG_SETMASK, &oldset, NULL);
}

static void signal_handler(int sig)
{
    if (q.size == 0) {
        old_hook  = lua_gethook(gL);
        old_mask  = lua_gethookmask(gL);
        old_count = lua_gethookcount(gL);
        lua_sethook(gL, lua_signal_handler,
                    LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
    }

    enqueue(&q, sig);
}

static int l_signal(lua_State* L)
{
    const char* signame;
    int sig;
    struct sigaction sa;
    sigset_t sset;
    void (*handler)(int) = NULL;

    gL = L;

    luaL_checktype(L, 1, LUA_TSTRING);
    signame = lua_tostring(L, 1);
    sig = name_to_sig(signame);
    if (sig == -1) {
        lua_pushfstring(L, "signal() called with invalid signal name: %s", signame);
        lua_error(L);
    }

    if (lua_isfunction(L, 2)) {
        handler = signal_handler;
        lua_getfield(L, LUA_REGISTRYINDEX, REG_TABLE);
        lua_pushvalue(L, 2);
        lua_setfield(L, -2, signame);
    }
    else if (lua_isstring(L, 2)) {
        const char* pseudo_handler;

        pseudo_handler = lua_tostring(L, 2);
        if (strcmp(pseudo_handler, "ignore") == 0) {
            handler = SIG_IGN;
        }
        else if (strcmp(pseudo_handler, "cdefault") == 0) {
            handler = SIG_DFL;
        }
        else if (strcmp(pseudo_handler, "default") == 0) {
            if (lua_handlers[sig].sa_handler != NULL) {
                handler = lua_handlers[sig].sa_handler;
            }
            else {
                return 0;
            }
        }
        else {
            lua_pushstring(L, "Must pass a valid handler to signal()");
            lua_error(L);
        }
    }
    else {
        lua_pushstring(L, "Must pass a handler to signal()");
        lua_error(L);
    }
    sa.sa_handler = handler;
    sigfillset(&sset);
    sa.sa_mask = sset;
    sa.sa_flags = 0;
    if (lua_handlers[sig].sa_handler == NULL) {
        sigaction(sig, &sa, &(lua_handlers[sig]));
    }
    else {
        sigaction(sig, &sa, NULL);
    }

    return 0;
}

static int l_alarm(lua_State* L)
{
    int time;

    time = luaL_checkint(L, 1);
    lua_pushinteger(L, alarm(time));

    return 1;
}

static int check_signal_name(lua_State *L, int idx) {
    const char* signame;
    int sig;
    luaL_checktype(L, 2, LUA_TSTRING);
    signame = lua_tostring(L, 2);
    if ((sig = name_to_sig(signame)) == -1) {
        if (strcmp(signame, "test") == 0) {
            sig = 0;
        }
        else {
            lua_pushstring(L, "kill(): invalid signal name");
            lua_error(L);
        }
    }
    return sig;
}

static int l_kill(lua_State* L)
{
    int pid, sig;

    pid = luaL_checkint(L, 1);
    sig = check_signal_name(L, 2);

    lua_pushinteger(L, kill(pid, sig));

    return 1;
}

static int l_raise(lua_State* L)
{
    int sig;
    
    sig = check_signal_name(L, 1);
    
    lua_pushinteger(L, raise(sig));

    return 1;
}

const luaL_Reg reg[] = {
    { "signal",  l_signal  },
    { "alarm",   l_alarm   },
    { "kill",    l_kill    },
    { "raise",   l_raise   },
    {  NULL,     NULL      },
};

int luaopen_signal(lua_State* L)
{
    queue_init(&q, 4);

    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, REG_TABLE);
#if LUA_VERSION_NUM > 501
    lua_newtable(L);
    luaL_setfuncs(L,reg,0);
#else
    luaL_register(L, "signal", reg);
#endif
    lua_pushstring(L, VERSION);
    lua_setfield(L, -2, "_VERSION");

    return 1;
}
