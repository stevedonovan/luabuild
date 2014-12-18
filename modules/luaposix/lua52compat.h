/*
 * Lua 5.2 compatibility
 * (c) Reuben Thomas (maintainer) <rrt@sc3d.org> 2010-2011
 * This file is in the public domain.
*/

#if LUA_VERSION_NUM > 501
#define luaL_reg luaL_Reg
#define lua_objlen lua_rawlen
#define lua_strlen lua_rawlen
#define luaL_openlib(L,n,l,nup) luaL_setfuncs((L),(l),(nup))
#define luaL_register(L,n,l) luaL_newlib((L),(l))

#if LUA_VERSION_NUM > 502
#define luaL_checkint(L,n) (int)luaL_checkinteger(L,n)
#define luaL_optint(L,n,d) (int)luaL_optinteger(L,n,d)
#endif

#include <assert.h>
static int luaL_typerror(lua_State *L, int narg, const char *tname)
{
	const char *msg = lua_pushfstring(L, "%s expected, got %s",
					  tname, luaL_typename(L, narg));
	return luaL_argerror(L, narg, msg);
}
#endif
