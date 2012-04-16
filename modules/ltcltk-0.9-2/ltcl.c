/* ltcl.c
 *
 * bind tcl interpreter into lua
 *
 * Gunnar Zötl <gz@tset.de>, 2010
 * Released under MIT/X11 license. See file LICENSE for details.
 */

#define VERSION 0.9
#define REVISION 1

#include <stdio.h>	/* for NULL */
#include <string.h>	/* for strlen() */
#include <math.h>	/* for trunc() */

#include "lua.h"
#include "lauxlib.h"

#include "tcl.h"

#if LUA_VERSION_NUM > 501
#define lua_equal(L,i1,i2) lua_compare(L,i1,i2,LUA_OPEQ)
#define lua_objlen lua_rawlen
#endif

/*** basic tcl interpreter stuff ***/

/* name of the metatable to use for the userdata and also for the type */
#define LTCL "lTclInterpreter"
#define LTCL_VALS "lTclVals"
/* name of the table within the metatable that hold functions exported to tcl */
#define LTCL_FUNCS "__functions"
/* size of buffer to use for ltcl__toString */
#define TOSTRING_BUFSIZ 64
/* increment of entries to grow call argument list by */
#define CALL_ARGINC 8

/* tcl object type caching vars. These are just the types we care about.
 * I assume that these pointers are the same for all interpreter instances
 * derived from the same dll
 */
static int ltcl_initialized = 0;
static Tcl_ObjType *TclBooleanType = NULL;
static Tcl_ObjType *TclByteArrayType = NULL;
static Tcl_ObjType *TclDoubleType = NULL;
static Tcl_ObjType *TclIntType = NULL;
static Tcl_ObjType *TclListType = NULL;
static Tcl_ObjType *TclStringType = NULL;

/* The userdata holds a pointer to the interpreter
 */
typedef struct _ltcl_interpreter {
	Tcl_Interp *interp;
} lTcl;

/* The userdata for a tcl argument vals
 */
typedef struct _ltcl_vals {
	int objc;
	Tcl_Obj *objv[0];
} lTclVals;

/* function call argument list structure
 */
typedef struct _ltcl_ptrlist {
	int nalloc;
	int objc;
	void **objv;
} lTclPtrList;

/* Helper stuff for the call* and toTclObj functions: pointer list handling
 */

/* _ltcl_ptrlistnew
 *
 * create a new tcl argument vector structure and initialize it to initially hold CALL_ARGINC arguments.
 * Return that.
 *
 * Arguments:
 *	-
 */
static lTclPtrList *_ltcl_ptrlistnew()
{
	lTclPtrList *l = (lTclPtrList*)ckalloc(sizeof(lTclPtrList));
	l->nalloc = CALL_ARGINC;
	l->objc = 0;
	l->objv = (void**)ckalloc(l->nalloc * sizeof(void*));
	return l;
}

/* _ltcl_ptrlistpush
 *
 * push a value onto a tcl argument vector. Takes care of automatically growing
 * the argument vector if needed.
 *
 * Arguments:
 *	l	tcl argument vector
 *	obj	tcl object to push
 */
static void _ltcl_ptrlistpush(lTclPtrList *l, void *obj)
{
	if (l->objc == l->nalloc) {
		l->nalloc += CALL_ARGINC;
		l->objv = (void**)ckrealloc((char*)l->objv, l->nalloc * sizeof(void*));
	}
	l->objv[l->objc++] = obj;
}

/* _ltcl_ptrlistcheck
 * 
 * check wether obj is already present in the list. If so, returns 0, if not,
 * pushes obj at the end of the lTclPtrList and returns 1.
 * 
 * Arguments:
 *	l	pointer list
 *	obj	pointer to check and push
 */
int _ltcl_ptrlistcheck(lTclPtrList *l, void *obj)
{
	int i;
	for (i = 0; i < l->objc; ++i)
		if (l->objv[i] == obj)
			return 0;
	_ltcl_ptrlistpush(l, obj);
	return 1;
}

/* _ltcl_ptrlistfree
 *
 * dispose on a tcl argument vector.
 *
 * Arguments:
 *	l	tcl argument vector
 */
static void _ltcl_ptrlistfree(lTclPtrList *l)
{
	ckfree((char*)l->objv);
	ckfree((char*)l);
}

/*** ltcl interpreter basic userdata handling ***/

/* forward declaration of function to call lua functions from tcl
 */
static int ltcl_callLuaFunc(void *LS, Tcl_Interp *tcli, int objc,  Tcl_Obj * CONST objv[]);
static Tcl_Obj* ltcl_toTclObj(lua_State *L, int index, lTclPtrList *lst_in);

/* ltcl_toTclInterp
 *
 * If the value at the given acceptable index is a full userdata, returns its block address.
 * Otherwise, returns NULL. 
 *
 * Arguments:
 * 	L	Lua State
 *	index	stack index where the interpreter is expected
 */
static lTcl* ltcl_toTclInterp(lua_State *L, int index)
{
	lTcl *interp = (lTcl*) lua_touserdata(L, index);
	return interp;
}

/* ltcl_checkTclInterp
 *
 * Checks whether the function argument narg is a userdata of the type LTCL. If so, returns
 * its block address, else throw an error.
 *
 * Arguments:
 * 	L	Lua State
 *	index	stack index where the interpreter is expected
 */
static lTcl* ltcl_checkTclInterp(lua_State *L, int index)
{
	lTcl *interp = (lTcl*) luaL_checkudata(L, index, LTCL);
	return interp;
}

/* ltcl_pushTclInterp
 *
 * create a new, empty tcl interpreter userdata and push it to the stack.
 *
 * Arguments:
 *	L	Lua state
 */
static lTcl* ltcl_pushTclInterp(lua_State *L)
{
	lTcl *interp = (lTcl*) lua_newuserdata(L, sizeof(lTcl));
	luaL_getmetatable(L, LTCL);
	lua_setmetatable(L, -2);
	return interp;
}

/* ltcl_new
 *
 * create a new tcl interpreter, initialize it, put it into a userdata and
 * return it to the user.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	-
 *
 * Lua Returns:
 *	+1	the tcl interpreter userdata
 */
static int ltcl_new(lua_State *L)
{
	Tcl_Interp *tclinterp = Tcl_CreateInterp();
	if (Tcl_Init(tclinterp) == TCL_ERROR) {
		return luaL_error(L, "tcl initialisation failed.");
	}
	lTcl *interp = ltcl_pushTclInterp(L);
	interp->interp = tclinterp;

	Tcl_CreateObjCommand(tclinterp, "lua", ltcl_callLuaFunc, (ClientData)L, NULL);

	if (!ltcl_initialized) {
		TclBooleanType = Tcl_GetObjType("boolean");
		TclByteArrayType = Tcl_GetObjType("bytearray");
		TclDoubleType = Tcl_GetObjType("double");
		TclIntType = Tcl_GetObjType("int");
		TclListType = Tcl_GetObjType("list");
		TclStringType = Tcl_GetObjType("string");
		ltcl_initialized = 1;
	}

	return 1;
}

/*** Housekeeping metamethods ***/

/* ltcl_gc
 *
 * __gc metamethod for the tcl interpreter userdata.
 * Destroys the interpreter.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter object
 */
static int ltcl__gc(lua_State *L)
{
	lTcl *interp = ltcl_toTclInterp(L, 1);
	if (interp) Tcl_DeleteInterp(interp->interp);
	return 0;
}

/* ltcl_toString
 *
 * __tostring metamethod for the tcl interpreter userdata.
 * Returns a string representation of the tcl interpreter
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 */
static int ltcl__toString(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	char buf[TOSTRING_BUFSIZ];
	/* length of type name + length of hex pointer rep + '0x' + ' ()' + '\0' */
	if (strlen(LTCL) + (sizeof(void*) * 2) + 2 + 4 > TOSTRING_BUFSIZ)
		return luaL_error(L, "Whoopsie... the string representation seems to be too long.");
		/* this should not happen, just to be sure! */
	sprintf(buf, "%s (%p)", LTCL, interp);
	lua_pushstring(L, buf);
	return 1;
}

/* metamethods for the tcl interpreter userdata
 */
static const luaL_Reg ltcl_meta[] = {
	{"__gc", ltcl__gc},
	{"__tostring", ltcl__toString},
	{0, 0}
};

/*** ltcl argument tuple userdata handlung stuff ***/

/* ltcl argument tuples are used only with the call* methods.
 * lTclVals userdata can be stored in lua variables, but as there is no way to do anything with it
 * other than the just mentioned use case, this would be of limited use.
 *
 * lTclVals objects contain references into the Tcl interpreter, which are protected by calls to
 * Tcl_Preserve. This means that as long as there is one such objet alive within the lua state,
 * the tcl interpreter will not be destroyed, even if there is no more reference to it from lua
 * and thus the lua tcl interpreter object has been destroyed.
 */

/* ltcl_vals
 *
 * lua function to create a tcl argument tuple
 *
 * Arguments:
 *	L	lua state
 *
 * Lua Stack:
 *	1	tcl interpreter object
 *	...	Arguments to put into the tcl argument vals, must be at least 1
 *
 * Lua Returns:
 *	+1	tcl argument vals userdata
 */
static int ltcl_vals(lua_State *L)
{
	int nargs = lua_gettop(L);
	lTclVals *vals;
	int i;
	lTcl *interp;

	if (nargs == 1)
		return luaL_error(L, "not enough arguments");

	interp = ltcl_checkTclInterp(L, 1);
	vals = (lTclVals*) lua_newuserdata(L, sizeof(lTclVals) + (nargs - 1) * sizeof(Tcl_Obj*));
	luaL_getmetatable(L, LTCL_VALS);
	lua_setmetatable(L, -2);
	vals->objc = nargs-1;
	/* using Tcl_Preserve ensures that the tcl interpreter is not deleted until all of
	 * our valss are removed from lua. */
	for (i = 2; i <= nargs; ++i) {
		vals->objv[i-2] = ltcl_toTclObj(L, i, NULL);
		Tcl_Preserve(vals->objv[i-2]);
		Tcl_IncrRefCount(vals->objv[i-2]);
	}

	return 1;
}

/* ltcl_toTclVals
 *
 * If the value at the given acceptable index is a full userdata of type LTCL_VALS, returns
 * its block address. Otherwise, returns NULL. 
 *
 * Arguments:
 * 	L	Lua State
 *	index	stack index where the vals is expected
 */
static lTclVals* ltcl_toTclVals(lua_State *L, int index)
{
	lTclVals *vals = (lTclVals*) lua_touserdata(L, index);
	return vals;
}

/* ltcl_checkTclVals
 *
 * Checks whether the function argument narg is a userdata of the type LTCL_VALS. If so, returns
 * its block address, else throw an error.
 *
 * Arguments:
 * 	L	Lua State
 *
 * Lua Stack:
 *	index	stack index where the vals is expected
 */
static lTclVals* ltcl_checkTclVals(lua_State *L, int index)
{
	lTclVals *vals = (lTclVals*) luaL_checkudata(L, index, LTCL_VALS);
	return vals;
}

/* ltcl_isTclVals
 *
 * returns 1 of the item at the position index of the lua stack is a userdata of type LTCL_VALS,
 * 0 otherwise.
 *
 * Arguments:
 * 	L	Lua State
 *
 * Lua Stack:
 *	index	stack index where the vals is expected
 */
static int ltcl_isTclVals(lua_State *L, int index)
{
	int res = 0;
	if (lua_isuserdata(L, index)) {
		/* is there a better way than this? */
		lua_getmetatable(L, index);
		luaL_getmetatable(L, LTCL_VALS);
		res = lua_equal(L, -1, -2);
		lua_pop(L, 2);
	}
	return res;
}

/* ltcl__valsgc
 *
 * __gc metamethod for the tcl vals userdata.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl vals object
 */
static int ltcl__valsgc(lua_State *L)
{
	lTclVals *vals = ltcl_toTclVals(L, 1);
	if (vals) {
		int i;
		/* release stored tcl objects */
		for (i = 0; i < vals->objc; ++i) {
			if (vals->objv[i]) {
				Tcl_Release(vals->objv[i]);
				Tcl_DecrRefCount(vals->objv[i]);
			}
		}
	}
	return 0;
}

/* ltcl__valstoString
 *
 * __tostring metamethod for the tcl vals userdata.
 * Returns a string representation of the tcl vals
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl vals object
 */
static int ltcl__valstoString(lua_State *L)
{
	lTclVals *vals = ltcl_checkTclVals(L, 1);
	char buf[TOSTRING_BUFSIZ];
	/* length of type name + length of hex pointer rep + '0x' + ': ' + '\0' */
	if (strlen(LTCL_VALS) + (sizeof(void*) * 2) + 2 + 3 > TOSTRING_BUFSIZ)
		return luaL_error(L, "Whoopsie... the string representation seems to be too long.");
		/* this should not happen, just to be sure! */
	sprintf(buf, "%s: %p", LTCL_VALS, vals);
	lua_pushstring(L, buf);
	return 1;
}

/* metamethods for the tcl vals userdata
 */
static const luaL_Reg LTCL_VALSmeta[] = {
	{"__gc", ltcl__valsgc},
	{"__tostring", ltcl__valstoString},
	{NULL, NULL}
};

/*** interaction lua -> tcl ***/

/* probablyutf8seq
 * 
 * checks wether a sequence of bytes is a reasonably(*) valid utf8 character
 * sequence. Returns 1 if the sequence is valid utf8, 0 otherwise.
 * 
 * Reasonably valid means that it contains only valid utf8 byte sequences. No
 * attempt is made to check wether these sequences actually represent valid
 * characters.
 * 
 * These patterns from rfc2279 are used:
 * 0000 0000-0000 007F   0xxxxxxx
 * 0000 0080-0000 07FF   110xxxxx 10xxxxxx
 * 0000 0800-0000 FFFF   1110xxxx 10xxxxxx 10xxxxxx
 * 0001 0000-001F FFFF   11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
 * 0020 0000-03FF FFFF   111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
 * 0400 0000-7FFF FFFF   1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
 * 
 * Arguments:
 * 	seq	sequence of bytes
 *  len	length of sequence to check. If seq is a \0 terminated string,
 * 		must not include the terminating \0.
 *
 * Note: this also flags a string as not being valid Utf8 is it contains
 * a \0 character, which actually is valid. This is because Tcl does not
 * want to see \0 chars in strings.
 */
static int probablyutf8seq(const char *seq, int len)
{
	int pos = 0;
	int ok = 1;
	char c;
	if (len < 0) return 0;
	if (len == 0) return 1;
	while (ok && (pos < len)) {
		c = seq[pos++];
		if (c == 0) {	/* if this is used for sth other than Tcl, remove this first test. */
			ok = 0;
		} else if ((c & 0x80) != 0) { /* ASCII char and thus ok if == 0 */
			if ((c & 0xE0) == 0xC0) { /* 2 byte sequence */
				if (pos < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else if ((c & 0xF0) == 0xE0) { /* 3 byte sequence */
				if (pos+1 < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else if ((c & 0xF8) == 0xF0) { /* 4 byte sequence */
				if (pos+2 < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else if ((c & 0xFC) == 0xF8) { /* 5 byte sequence */
				if (pos+3 < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else if ((c & 0xFE) == 0xFC) { /* 6 byte sequence */
				if (pos+4 < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else
				ok = 0;
		}
	}
	return ok;
}

/* ltcl_pushTclObj
 *
 * converts a tcl object to a lua value and pushes the result onto the stack. Returns the
 * amount of values pushed (i.e. 1)
 *
 * Arguments:
 *	L	Lua State
 *	tclobj	tcl object
 *
 * Notes:
 *	anything we can't cope with will be returned as a string.
 *	The lua value is owned by the lua state.
 */
static int ltcl_pushTclObj(lua_State *L, Tcl_Obj *tclobj)
{
	char *str;
	int len;
	if (tclobj == NULL) {
		lua_pushnil(L); /* should probably never happen */
	} else if (tclobj->typePtr == TclIntType) {
		lua_pushinteger(L, tclobj->internalRep.longValue);
	} else if (tclobj->typePtr == TclDoubleType) {
		lua_pushnumber(L, tclobj->internalRep.doubleValue);
	} else if (tclobj->typePtr == TclBooleanType) {
		/* I intended this to convert to booleans first, but tcl 8.5 returns bools as
		 * integers all the time, so in order to ensure that skripts written for
		* lua+tcl8.4 would also work on lua+tcl8.5, I decided to always returns bools
		* as ints to lua.
		*/
		lua_pushinteger(L, tclobj->internalRep.longValue);
	} else if (tclobj->typePtr == TclByteArrayType) {
		str = (char *) Tcl_GetByteArrayFromObj(tclobj, &len);
		lua_pushlstring(L, str, len);
	} else if (tclobj->typePtr == TclListType) {
		int objc, i;
		Tcl_Obj **objv;
		Tcl_ListObjGetElements(NULL, tclobj, &objc, &objv);
		lua_createtable(L, objc, 0);
		if (objc > 0) {
			for (i = 0; i < objc; ++i) {
				ltcl_pushTclObj(L, objv[i]);
				lua_rawseti(L, -2, i + 1);
			}
		}
	} else {
		/* Anything else (including Strings) is converted to a string. It is helpful that
		 * everything has a string representation in tcl.
		 * tcl owns strings returned from Tcl_GetStringFromObj(), so no need to free it
		 * after copying it to lua.
		 */
		str = (char *) Tcl_GetStringFromObj(tclobj, &len);
		lua_pushlstring(L, str, len);
	}
	return 1;
}

/* ltcl_toTclObj
 *
 * convert a lua value to a tcl object and return a pointer to it.
 *
 * Arguments:
 *	L	Lua State
 *	index	stack index of the lua value to be converted
 *	lst_in	helper list to find recursive tables
 *
 * Notes:
 *	only native lua data types are converted. Anything else throws an error.
 *	You may need to increment the objects refcount or else it may get deleted
 *	by tcl.
 */
static Tcl_Obj* ltcl_toTclObj(lua_State *L, int index, lTclPtrList *lst_in)
{
	int type = lua_type(L, index);
	lTclPtrList *lst = lst_in;

	if (type == LUA_TNIL) {
		return Tcl_NewObj(); /* no nil in tcl */
	} else if (type == LUA_TSTRING) {
		/* lua owns strings returned from lua_tolstring(), so no need to free it */
		size_t len;
		const char *str = lua_tolstring(L, index, &len);
		/* Tcl strings must be valid utf8 strings, anything else is "just" a byte array. */
		if (probablyutf8seq(str, len))
			return Tcl_NewStringObj(str, len);
		else
			return Tcl_NewByteArrayObj((unsigned char*)str, len);
	} else if (type == LUA_TBOOLEAN) {
		return Tcl_NewBooleanObj(lua_toboolean(L, index));
	} else if (type == LUA_TNUMBER) {
		lua_Number n = lua_tonumber(L, index);
		int i = (int)n; /* evil trick to determine wether n fits in an integer. */
		if (n == i) {
			return Tcl_NewIntObj(lua_tointeger(L, index));
		} else {
			return Tcl_NewDoubleObj(n);
		}
	} else if (type == LUA_TTABLE) {
		/* the indexed members from 1 .. #table become a list */
		/* take care of recursive tables */
		if (!lst) lst = _ltcl_ptrlistnew();
		/* this can not happen on the initial table */
		if (!_ltcl_ptrlistcheck(lst, (void*)lua_topointer(L, index)))
			return NULL;
		int tlen = lua_objlen(L, index);
		int i, oobjc;
		Tcl_Obj *list = Tcl_NewListObj(0, (Tcl_Obj**) NULL);
		Tcl_Obj *item;
		for (i = 1; i <= tlen; ++i) {
			oobjc = lst->objc;
			lua_rawgeti(L, index, i);
			item = ltcl_toTclObj(L, -1, lst);
			if (item) {
				Tcl_ListObjAppendElement(NULL, list, item);
				lua_pop(L, 1);
				lst->objc = oobjc;
			} else {
				/* recursive table */
				lua_pop(L, 1);
				if (!lst_in) {
					_ltcl_ptrlistfree(lst);
					luaL_error(L, "can not convert recursive table to Tcl object.");
					/* as there is no reference to the Tcl list, it should get
					 * collected automatically by the Tcl interpreter.
					 */
				}
				return NULL;
			}
		}
		if (!lst_in) _ltcl_ptrlistfree(lst);
		return list;
	} else {
		luaL_error(L, "can not convert lua value with type '%s' to Tcl object.", luaL_typename(L, index));
		return NULL; /* never gets here */
	}
}

/* ltcl_returnFromTcl
 *
 * fetches the return value from a tcl interpreter and pushed it onto the lua stack.
 *
 * Arguments:
 *	L	Lua State
 *	interp	tcl interpreter whose result should be returned.
 */
static int ltcl_returnFromTcl(lua_State *L, Tcl_Interp *interp)
{
	Tcl_Obj *o = Tcl_GetObjResult(interp);
	if (o == NULL)
		return 0;
	else
		return ltcl_pushTclObj(L, o);
}

/* ltcl_returnToTcl
 *
 * fetches the return value from a lua stack and stores it in the result field of the tcl interpreter.
 *
 * Arguments:
 *	L	Lua State. The value to be returned must be at the top of the stack.
 *	interp	tcl interpreter whose result should be returned.
 *
 * Notes:
 *	either tcl assigns the returned value to a variable, or ignores it. We should not need to
 *	manage its refcount
 */
static void ltcl_returnToTcl(lua_State *L, Tcl_Interp *interp)
{
	Tcl_Obj *o = NULL;
	o = ltcl_toTclObj(L, -1, NULL);
	Tcl_SetObjResult(interp, o);
}

/* ltcl_eval
 *
 * evaluate a single expression and return its result.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	the command to evaluate
 *	3	(opt) flags
 *
 * Lua Returns:
 *	+1	the result of the evaluation
 */
static int ltcl_eval(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *cmd;
	int flags, base = 2;
	size_t cmdlen;

	/* flags are at the second position, but optional. */
	if (lua_isnumber(L, base)) {
		flags = luaL_checkint(L, base);
		base += 1;
	}
	cmd = luaL_checklstring(L, base, &cmdlen);

	Tcl_ResetResult(tcli);
	if (Tcl_EvalEx(tcli, cmd, cmdlen, flags) != TCL_OK)
		return luaL_error(L, Tcl_GetStringResult(tcli));
	return ltcl_returnFromTcl(L, tcli);
}

/* ltcl_pushTclVals
 */
static int _ltcl_ptrlistpushvals(lTclPtrList *l, lTclVals *vals)
{
	Tcl_Obj *o;
	int i;
	for (i = 0; i < vals->objc; ++i) {
		o = vals->objv[i];
		_ltcl_ptrlistpush(l, o);
		Tcl_IncrRefCount(o);
	}
	return vals->objc;
}

/* ltcl_call
 *
 * call a tcl function with pre-parsed (i.e. converted from lua) arguments
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	(opt) flags
 *	2 or 3	function name, at 2 when no options are given, 3 otherwise. Must be string!
 *	...	function arguments
 *
 * Lua Returns:
 *	+1	the result of the evaluation
 *
 * Notes:
 *	We must increment the refcount on our created values or they may get collected. Just
 *	remember to decrement when we're done.
 */
static int ltcl_call(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	Tcl_Obj *o;
	int flags, base = 2;
	int nargs = lua_gettop(L) - 1;
	lTclPtrList *args = _ltcl_ptrlistnew();
	int i, res;
	lTclVals *vals;

	/* flags are at the second position, but optional. */
	if (lua_isnumber(L, 2)) {
		flags = luaL_checkint(L, 2);
		nargs -= 1;
		base += 1;
	}

	/* function name must be string */
	luaL_checkstring(L, base);
	/* ok, now fill tcl objectvector, remember to increment the objects refcount, and call ahead */
	Tcl_ResetResult(tcli);
	for (i = 0; i < nargs; ++i) {
		if (ltcl_isTclVals(L, base + i)) {
			vals = ltcl_toTclVals(L, base + i);
			_ltcl_ptrlistpushvals(args, vals);
		} else {
			o = ltcl_toTclObj(L, base + i, NULL);
			_ltcl_ptrlistpush(args, o);
			Tcl_IncrRefCount(o);
		}
	}
	res = Tcl_EvalObjv(tcli, args->objc, (Tcl_Obj**)args->objv, flags);
	/* have tcl free all of our objects and then dispose */
	for (i = 0; i < args->objc; ++i)
		Tcl_DecrRefCount((Tcl_Obj*)args->objv[i]);
	
	_ltcl_ptrlistfree(args);

	/* then return */
	if (res != TCL_OK)
		return luaL_error(L, Tcl_GetStringResult(tcli));
	return ltcl_returnFromTcl(L, tcli);
}

/* ltcl_callt
 *
 * call a tcl function with an array pre-parsed (i.e. converted from lua) arguments
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	(opt) flags
 *	+1	function name, at 2 when no options are given, 3 otherwise. Must be string!
 *	+1	table of function arguments
 *
 * Lua Returns:
 *	+1	the result of the evaluation
 *
 * Notes:
 *	As with call we must handle the refcount of our arguments.
 *	Both the array and the hash part of a table are converted. First come the array part
 *	elements from 1 to #array. After that come the hash part elements, of which both key
 *	_and_ value are added as arguments. The key will be preceded with a '-' before adding.
 */
static int ltcl_callt(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	int flags, base = 2;
	lTclPtrList *args = _ltcl_ptrlistnew();
	Tcl_Obj *o;
	int i, tlen, res;
	lTclVals *vals;

	/* flags are at the second position, but optional. */
	if (lua_isnumber(L, 2)) {
		flags = luaL_checkint(L, 2);
		base += 1;
	}

	/* function name must be string */
	luaL_checkstring(L, base);
	o = ltcl_toTclObj(L, base++, NULL);
	_ltcl_ptrlistpush(args, o);
	Tcl_IncrRefCount(o);

	if (!lua_isnoneornil(L, base)) {
		/* base now must point to the table with the arguments */
		luaL_checktype(L, base, LUA_TTABLE);

		/* convert table to argument list */
		tlen = lua_objlen(L, base);
		for (i = 1; i <= tlen; ++i) {
			lua_rawgeti(L, base, i);
			if (ltcl_isTclVals(L, -1)) {
				vals = ltcl_toTclVals(L, -1);
				_ltcl_ptrlistpushvals(args, vals);
			} else {
				o = ltcl_toTclObj(L, -1, NULL);
				_ltcl_ptrlistpush(args, o);
				Tcl_IncrRefCount(o);
			}
			lua_pop(L, 1);
		}
	}

	res = Tcl_EvalObjv(tcli, args->objc, (Tcl_Obj**)args->objv, flags);

	/* clean up */
	for (i = 0; i < args->objc; ++i)
		Tcl_DecrRefCount((Tcl_Obj*)args->objv[i]);
	_ltcl_ptrlistfree(args);
		
	if (res != TCL_OK)
		return luaL_error(L, Tcl_GetStringResult(tcli));

	return ltcl_returnFromTcl(L, tcli);
}

/* ltcl_makearglist
 * 
 * make a tcl argument list from the table passed as an argument. First the
 * table members from 1 to #table are inserted into the result table, then all
 * the key/value pairs, where key is not numeric, are inserted with the key
 * prefixed by a '-' first and then the value. So {1, opt=2} would be converted
 * to {1, '-opt', 2}
 * This is explicitely intended to be used for ltk!
 * 
 * Arguments:
 * 	L	lua State
 * 
 * Lua Stack:
 * 	1	tcl interpreter
 * 	2	argument table
 * 
 * Lua Returns:
 * 	+1	result table
 */
static int ltcl_makearglist(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	int top = lua_gettop(L);
	int tlen, i;
	int sbufs = 100;
	char *sbuf = NULL;
	const char *tmps;
	size_t tmpl;
	interp = interp; /* use interp */

	lua_newtable(L);	/* at top+1 */

	if (!lua_isnoneornil(L, 2)) {
		sbuf = ckalloc(sbufs);
		luaL_checktype(L, 2, LUA_TTABLE);

		/* first process the array part */
		tlen = lua_objlen(L, 2);
		for (i = 1; i <= tlen; ++i) {
			lua_rawgeti(L, 2, i);
			lua_rawseti(L, top+1, i);
		}

		/* now do the hash part */
		lua_pushnil(L);  /* first key */
		while (lua_next(L, 2) != 0) {
			if (!lua_isnumber(L, -2)) { /* skip numerical indices */
				
				/* key */
				luaL_checktype(L, -2, LUA_TSTRING);
				tmps = lua_tolstring(L, -2, &tmpl);
				if (tmpl+1 >= sbufs) {
					while (tmpl+1 >= sbufs)
						sbufs = 2 * sbufs;
					sbuf = ckrealloc(sbuf, sbufs);
				}
				sprintf(sbuf, "-%s", tmps);
				lua_pushlstring(L, sbuf, tmpl+1);
				lua_rawseti(L, top+1, i++);

				/* value */
				lua_pushvalue(L, -1);
				lua_rawseti(L, top+1, i++);
			}
			/* removes 'value'; keeps 'key' for next iteration */
			lua_pop(L, 1);
		}
		ckfree(sbuf);
	}

	return 1;
}

/* ltcl_getarray
 *
 * get value of a variable and push it onto the lua stack.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of variable
 *	3	if not nil, gives the index into an array. variable must refer to an array.
 *	4	(opt) flags
 *
 * Lua Returns:
 *	+1	converted value of tcl variable
 */
static int ltcl_getarray(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *vn1 = luaL_checkstring(L, 2);
	const char *vn2 = NULL;
	/* we always want to know what went wrong */
	const int flags = luaL_optint(L, 4, 0) | TCL_LEAVE_ERR_MSG;
	if (!lua_isnil(L, 3))
		vn2 = luaL_checkstring(L, 3);
	Tcl_Obj *tclobj = Tcl_GetVar2Ex(tcli, vn1, vn2, flags);
	if (tclobj == NULL)
		return luaL_error(L, Tcl_GetStringResult(tcli));
	return ltcl_pushTclObj(L, tclobj);
}

/* ltcl_getvar
 *
 * get value of a variable and push it onto the lua stack.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of variable
 *	3	(opt) flags
 *
 * Lua Returns:
 *	+1	converted value of tcl variable
 *
 * Notes:
 *	inserts nil as array index name and calls ltcl_getarray
 * 	We use the fact that Tcl_GetVar2Ex behaves like Tcl_GetVarEx if the array
 * 	index is null.
 */
static int ltcl_getvar(lua_State *L)
{
	int ret = 0, i = -2;
	lua_pushnil(L);
	if (lua_gettop(L) == 4) {
		lua_insert(L, -2);
		i = -3;
	}
	ret = ltcl_getarray(L);
	lua_remove(L, i); /* stack hygienie */
	return ret;
}

/* ltcl_setarray
 *
 * set value of a variable.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of variable
 *	3	if not nil, gives the index into an array. variable must refer to an array.
 *	4	value to set variable to, will be converted to a tcl value
 *	5	(opt) flags
 *
 * Lua Returns:
 *	+1	converted value of tcl variable
 *
 * Notes:
 *	when we assign the created Tcl_Obj to a tcl variable, the variable takes ownership. So
 *	no need to manage the refcount.
 */
static int ltcl_setarray(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *vn1 = luaL_checkstring(L, 2);
	const char *vn2 = NULL;
	Tcl_Obj *tclobj;
	Tcl_Obj *val = ltcl_toTclObj(L, 4, NULL);
	/* we always want to know what went wrong */
	const int flags = luaL_optint(L, 5, 0) | TCL_LEAVE_ERR_MSG;
	if (!lua_isnil(L, 3))
		vn2 = luaL_checkstring(L, 3);
	tclobj = Tcl_SetVar2Ex(tcli, vn1, vn2, val, flags);
	if (tclobj == NULL)
		return luaL_error(L, Tcl_GetStringResult(tcli));
	return ltcl_pushTclObj(L, tclobj);
}

/* ltcl_setvar
 *
 * set value of a variable.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of variable
 *	3	value to set variable to, will be converted to a tcl value
 *	4	(opt) flags
 *
 * Lua Returns:
 *	-
 *
 * Notes:
 *	inserts nil as array index name and calls ltcl_setarray.
 * 	We use the fact that Tcl_SetVar2Ex behaves like Tcl_SetVarEx if the array
 * 	index is null.
 */
static int ltcl_setvar(lua_State *L)
{
	int i, res;
	lua_pushnil(L);
	if (lua_gettop(L) == 5) i = -3; else i = -2;
	lua_insert(L, i);
	res = ltcl_setarray(L);
	lua_remove(L, i); /* stack hygienie */
	return res;
}

/* ltcl_unsetarray
 * 
 * get value of a variable and push it onto the lua stack.
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of variable to unset
 *	3	if not nil, gives the index into an array. variable must refer to an array.
 *	4	(opt) flags
 *
 * Lua Returns:
 *	-
 */
static int ltcl_unsetarray(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *vn1 = luaL_checkstring(L, 2);
	const char *vn2 = NULL;
	/* we always want to know what went wrong */
	const int flags = luaL_optint(L, 4, 0) | TCL_LEAVE_ERR_MSG;
	if (!lua_isnil(L, 3))
		vn2 = luaL_checkstring(L, 3);
	int ok = Tcl_UnsetVar2(tcli, vn1, vn2, flags);
	if (ok != TCL_OK)
		return luaL_error(L, Tcl_GetStringResult(tcli));
	return 0;
}

/* ltcl_unsetvar
 * 
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of variable to unset
 *	3	(opt) flags
 *
 * Lua Returns:
 *	-
 *
 * Notes:
 *	inserts nil as array index name and calls ltcl_unsetarray
 * 	We use the fact that Tcl_UnsetVar2 behaves like Tcl_UnsetVar if the array
 * 	index is null.
 */
static int ltcl_unsetvar(lua_State *L)
{
	int ret = 0, i = -2;
	lua_pushnil(L);
	if (lua_gettop(L) == 4) {
		lua_insert(L, -2);
		i = -3;
	}
	ret = ltcl_unsetarray(L);
	lua_remove(L, i); /* stack hygienie */
	return ret;
}

/*** tcl -> lua ***/

/* wrapper for information necessary to call a lua function from tcl */
typedef struct ltcl_clientData {
	lua_State *L;
	const char *fname;
} ltclClientData;

/* ltcl_callLuaFunc
 *
 * Tcl function to call a lua function by name
 *
 * Arguments:
 *	LS	Lua State disguised as ClientData
 *	tcli	tcl inerpreter
 *	objc	number of arguments to lua function
 *	objv	argument vector
 */
static int ltcl_callLuaFunc(void *LS, Tcl_Interp *tcli, int objc,  Tcl_Obj * CONST objv[])
{
	lua_State *L = (lua_State*) LS;
	int i, callres = 0;

	/* only enter here if there is actually a function to call */
	if (objc >= 2) {
		/* now fetch the metatable then the function table then our function there */
		ltcl_pushTclObj(L, objv[1]);	/* 1 function name */
#if LUA_VERSION_NUM > 501
        lua_rawgeti(L,LUA_REGISTRYINDEX,LUA_RIDX_GLOBALS);
        lua_insert(L,-2);
        lua_rawget(L,-2);
#else
		lua_rawget(L, LUA_GLOBALSINDEX); /* 1 function */
#endif

		/* push arguments */
		lua_checkstack(L, objc);
		for (i = 2; i < objc; ++i)
			ltcl_pushTclObj(L, objv[i]);

		/* call functions */
		callres = lua_pcall(L, objc-2, 1, 0); /* 1 return value if any */

		/* prepare return value and clean stack */
		Tcl_ResetResult(tcli);

		ltcl_returnToTcl(L, tcli);
		lua_pop(L, 1);
	}
	/* return */
	return callres ? TCL_ERROR : TCL_OK;

}

/* ltcl_luaFunctionWrapper
 *
 * a wrapper for tcl to call lua functions and get proper results from them.
 *
 * Arguments:
 *	cdata	the ClientData stuff we passed when registering the function.
 *	interp	tcl interpreter
 *	objc	number of arguments
 *	objv	arguments
 *
 * Returns:
 *
 */
static int ltcl_luaFunctionWrapper(ClientData cdata, Tcl_Interp *tcli, int objc,  Tcl_Obj * CONST objv[])
{
	ltclClientData *lcd = (ltclClientData*)cdata;
	lua_State *L = lcd->L;
	const char *fname = lcd->fname;
	int i, callres, stop;

	/* now fetch the metatable then the function table then our function there */
	luaL_getmetatable(L, LTCL);
	lua_pushliteral(L, LTCL_FUNCS);
	lua_rawget(L, -2);		/* 2 metatable */
	stop = lua_gettop(L);
	lua_pushstring(L, fname);
	lua_rawget(L, -2);		/* 3 function */

	/* push arguments */
	lua_checkstack(L, objc);
	for (i = 1; i < objc; ++i)
		ltcl_pushTclObj(L, objv[i]);

	/* call functions */
	callres = lua_pcall(L, objc-1, 1, 0); /* 3 return value if any */

	/* prepare return value and clean stack */
	Tcl_ResetResult(tcli);

	ltcl_returnToTcl(L, tcli);
	lua_pop(L, 3);

	/* return */
	return callres ? TCL_ERROR : TCL_OK;
}

/* ltcl_deleteProc
 *
 * called from the tcl interpreter when the function is deleted.
 *
 * Arguments:
 *	cdata	the ClientData stuff we passed when registering the function.
 */
static void ltcl_deleteProc(ClientData cdata)
{
	ltclClientData *lcd = (ltclClientData*)cdata;
	lua_State *L = lcd->L;
	const char *fname = lcd->fname;

	/* now fetch the metatable then the function table then delete our function there */
	luaL_getmetatable(L, LTCL);
	lua_pushliteral(L, LTCL_FUNCS);
	lua_rawget(L, -2);
	lua_pushstring(L, fname);
	lua_pushnil(L);
	lua_rawset(L, -3);
	lua_pop(L, 2);
	/* that should be it. Now dispose of our ClientData and be done. */
	ckfree((char*)lcd);
}

/* ltcl_register
 *
 * register a lua function for use from tcl
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of funtion to register
 *	3	function to register
 *
 * Lua Returns:
 *	-
 */
static int ltcl_register(lua_State *L)
{
	ltclClientData *lcd = (ltclClientData*)ckalloc(sizeof(ltclClientData));
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *fname = luaL_checkstring(L, 2);
	luaL_argcheck(L, lua_isfunction(L, 3), 3, NULL);

	lcd->L = L;
	lcd->fname = fname;

	/* Tcl_CreateObjCommand() calls deletefunc before registering if a function with this name
	 * is already registered. So registering with our function table must be done after registering
	 * with tcl.
	 */
	Tcl_Command cmd = Tcl_CreateObjCommand(tcli, fname, ltcl_luaFunctionWrapper, (ClientData)lcd, ltcl_deleteProc);
	if (cmd == NULL)
		luaL_error(L, Tcl_GetStringResult(tcli));

	/* now fetch the metatable then the function table then enter our function there */
	lua_getmetatable(L, 1);
	lua_pushliteral(L, LTCL_FUNCS);
	lua_rawget(L, -2);
	lua_pushstring(L, fname);
	lua_pushvalue(L, 3);
	lua_rawset(L, -3);
	lua_pop(L, 2);

	return 0;
}

/* ltcl_unregister
 *
 * unregister a previously registered lua function for use from tcl
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	name of funtion to register
 *
 * Lua Returns:
 *	-
 *
 * Notes:
 *	if the function does not exist, we silently do nothing.
 */
static int ltcl_unregister(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *fname = luaL_checkstring(L, 2);

	Tcl_DeleteCommand(tcli, fname);
	/* ltcl_DeleteProc, as registered with the function, does the rest */

	return 0;
}

/* ltcl_tracewrapper
 * 
 * a wrapper around lua function calls for use by ltcl_tracevar. Returns 0 if
 * the lua trace function returned null, a string with the error message otherwise.
 * 
 * Arguments:
 * 	cdata	the clientdata stuff we passed when registering the trace function
 * 	tcli	tcl interpreter
 * 	name1	name of variable to trace
 *  name2	index into var1 to trace. When this is not nil, name1 must refer to an array
 *  flags	flags passed from Tcl to the trace function
 */
static char *ltcl_tracewrapper(ClientData cdata, Tcl_Interp *tcli, const char *name1, const char *name2, int flags)
{
	ltclClientData *lcd = (ltclClientData*)cdata;
	lua_State *L = lcd->L;
	const char *fname = lcd->fname;
	int callres, stop;
	char *saveresult;
	Tcl_FreeProc *saveproc;
	char *traceres = NULL;
	const char *s;
	size_t l;

	if (flags & TCL_INTERP_DESTROYED)
		return NULL;
		
	/* else if the variable and thus the trace is destroyed, we just re-establish the trace.
	 */
	if (flags & TCL_TRACE_DESTROYED) {
		int ok = Tcl_TraceVar2(tcli, name1, name2, flags, ltcl_tracewrapper, (ClientData)lcd);

		if (ok != TCL_OK) {
			s = Tcl_GetStringResult(tcli);
			l = strlen(s);
		}
	} else {
	/* otherwise call the handler function.
	 */
		/* fetch the metatable then the function table then our function name */
		luaL_getmetatable(L, LTCL);
		lua_pushliteral(L, LTCL_FUNCS);
		lua_rawget(L, -2);		/* 2 metatable */
		stop = lua_gettop(L);
		lua_pushstring(L, fname);
		lua_rawget(L, -2);		/* 3 function */

		/* push arguments */
		lua_pushstring(L, name1);
		if (name2)
			lua_pushstring(L, name2);
		else
			lua_pushnil(L);
		lua_pushinteger(L, flags);

		/* save Tcl_Interp result and freeProc */
		saveresult = tcli->result;
		saveproc = tcli->freeProc;
		tcli->freeProc = NULL;

		/* call functions */
		callres = lua_pcall(L, 3, 1, 0); /* 3 return value if any */

		/* restore saved tcl interpreter data */
		Tcl_SetResult(tcli, saveresult, saveproc);

		s = lua_tolstring(L, -1, &l);
	}

	if (s) {
		traceres = ckalloc(l+1);
		strcpy(traceres, s);
	}
	lua_pop(L, 3);

	/* return */
	return traceres;
}

/* ltcl_tracevar
 * 
 *
 * Adds a function to call whenever an array index is accessed
 * 
 * Arguments:
 * 	L	Lua State
 * 
 * Lua Stack:
 * 	1	tcl interpreter
 * 	2	name of variable to trace
 * 	3	index into array to trace, may be nil
 * 	4	flags for the trace func
 * 	5	function to call for the trace
 * 
 * Lua Returns:
 * 	-
 * 
 * Note:
 * 	the construction of the function name ensures that any function is registered only once.
 */
static int ltcl_tracevar(lua_State *L)
{
	ltclClientData *lcd = (ltclClientData*)ckalloc(sizeof(ltclClientData));
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	const char *vn1 = luaL_checkstring(L, 2);
	const char *vn2 = NULL;
	if (!lua_isnil(L, 3))
		vn2 = luaL_checkstring(L, 3);
	/* if we return something, it is a dynamically allocated string. */
	const int flags = luaL_checkint(L, 4) | TCL_TRACE_RESULT_DYNAMIC;
	luaL_argcheck(L, lua_isfunction(L, 5), 5, NULL);
	/* enough room to hold "_tracefunc" + '0x' + 8 digits pointer + \0 */
	char *fname = ckalloc(20 + 2*sizeof(void*));

	sprintf(fname, "_tracefunc%p", lua_topointer(L, 5));
	lcd->L = L;
	lcd->fname = fname;

	int ok = Tcl_TraceVar2(tcli, vn1, vn2, flags, ltcl_tracewrapper, (ClientData)lcd);

	if (ok != TCL_OK)
		return luaL_error(L, Tcl_GetStringResult(tcli));

	/* now fetch the metatable then the function table then enter our function there */
	lua_getmetatable(L, 1);
	lua_pushliteral(L, LTCL_FUNCS);
	lua_rawget(L, -2);
	lua_pushstring(L, fname);
	lua_pushvalue(L, 5);
	lua_rawset(L, -3);
	lua_pop(L, 2);

	return 0;
}

/*** utility methods ***/

/* ltcl_fetchTclEncoding
 *
 * fetch a Tcl_Encoding for the encoding name passed as an argument. Returns eiter a Tcl_Encoding,
 * if the name referred to an internal or a loadable encoding, or NULL if the name was NULL. If the
 * encoding name is not null bot does not refer to a valid encoding, an error is thrown.
 *
 * Arguments:
 *	L	Lua State
 *	tcli	tcl interpreter
 *	enc	name of encoding to fetch
 */
static Tcl_Encoding ltcl_fetchTclEncoding(lua_State *L, Tcl_Interp *tcli, const char *encoding)
{
	Tcl_Encoding enc = NULL;
	if (encoding) {
		enc = Tcl_GetEncoding(tcli, encoding);
		if (enc == NULL) {
			/* this weird construction is necessary because tcl apparently does not
			 * reset its result in case of calling this. In the spirit of creating
			 * the least amount of surprise when interacting with a tcl interpreter,
			 * we also won't reset it unless an error occurs. In that case we reset
			 * the result, perform the offendng call again, all in order to get a
			 * proper error mesage.
			 */
			Tcl_ResetResult(tcli);
			enc = Tcl_GetEncoding(tcli, encoding);
			luaL_error(L, Tcl_GetStringResult(tcli));
			return NULL; /* never gets here */
		}
	}
	return enc;
}

/* ltcl_utf8ToExternal
 *
 * converts a string from utf8 to local encoding
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	utf8 encoded string to convert
 *	3	(opt) name of encoding of destination string. if omitted, the current system encoding will be used
 *
 * Lua Returns:
 *	+1	the converted string
 */
static int ltcl_utf8ToExternal(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	size_t utflen;
	const char *utf = luaL_checklstring(L, 2, &utflen);
	const char *encoding = luaL_optstring(L, 3, NULL);
	int extlen = 4 * utflen; /* just to be on the safe side */
	char *ext = ckalloc(extlen);
	int reslen;
	Tcl_Encoding enc = ltcl_fetchTclEncoding(L, tcli, encoding);

	Tcl_UtfToExternal(tcli, enc, utf, utflen, 0, NULL, ext, extlen, NULL, NULL, &reslen);

	lua_pushlstring(L, ext, reslen);
	ckfree(ext);

	return 1;
}

/* ltcl_externalToUtf8
 *
 * converts a string from local to utf8 encoding
 *
 * Arguments:
 *	L	Lua State
 *
 * Lua Stack:
 *	1	tcl interpreter
 *	2	string to convert to utf8
 *	3	(opt) name of encoding of source string. if omitted, the current system encoding will be used
 *
 * Lua Returns:
 *	+1	the converted string
 */
static int ltcl_externalToUtf8(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	size_t extlen;
	const char *ext = luaL_checklstring(L, 2, &extlen);
	const char *encoding = luaL_optstring(L, 3, NULL);
	int utflen = 4 * extlen; /* just to be on the safe side */
	char *utf = ckalloc(utflen);
	int reslen;
	Tcl_Encoding enc = ltcl_fetchTclEncoding(L, tcli, encoding);

	Tcl_ExternalToUtf(tcli, enc, ext, extlen, 0, NULL, utf, utflen, NULL, NULL, &reslen);

	lua_pushlstring(L, utf, reslen);
	ckfree(utf);

	return 1;
}

/* ltcl_listEncodings
 *
 * return a list of names of loadable and internal encodings usable by tcl.
 *
 * Arguments
 *	L	lua_State
 *
 * Lua Stack:
 *	-
 *
 * Lua Returns:
 *	+1	table of encoding names
 */
static int ltcl_getEncodings(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	Tcl_Interp *tcli = interp->interp;
	Tcl_GetEncodingNames(tcli);
	return ltcl_returnFromTcl(L, tcli);
}

/* ltcl_checkflags
 * 
 * returns all flags that are set in flags (first argument) from the list of
 * flags starting at the third argument.
 * 
 * Arguments:
 * 	L	lua State
 * 
 * Lua Stack:
 * 	1	tcl interpreter
 * 	2	flags value to check against
 * 	...	flags to test against flags
 * 
 * Lua Returns:
 * 	the value of any flag from argument 3 onwards that is set in flags, nil for
 * 	any flag that is not set in flags
 */
static int ltcl_checkflags(lua_State *L)
{
	lTcl *interp = ltcl_checkTclInterp(L, 1);
	int flag;
	int top = lua_gettop(L);
	int flags = luaL_checkint(L, 2);
	int arg;
	interp = interp; /* use interp */

	for (arg = 3; arg <= top; ++arg) {
		luaL_checktype(L, arg, LUA_TNUMBER);
		flag = lua_tointeger(L, arg);
		if ((flags & flag) == flag)
			lua_pushinteger(L, flag);
		else
			lua_pushnil(L);
	}
	return top - 2;
}

/* ltcl functions / metamethods
 */
static const luaL_Reg ltcl_lib[] = {
	{"new", ltcl_new},
	{"eval", ltcl_eval},
	{"call", ltcl_call},
	{"callt", ltcl_callt},
	{"makearglist", ltcl_makearglist},
	{"getvar", ltcl_getvar},
	{"getarray", ltcl_getarray},
	{"setvar", ltcl_setvar},
	{"setarray", ltcl_setarray},
	{"unsetvar", ltcl_unsetvar},
	{"unsetarray", ltcl_unsetarray},
	{"tracevar", ltcl_tracevar},
	{"register", ltcl_register},
	{"unregister", ltcl_unregister},
	{"fromutf8", ltcl_utf8ToExternal},
	{"toutf8", ltcl_externalToUtf8},
	{"getencs", ltcl_getEncodings},
	{"vals", ltcl_vals},
	{"checkflags", ltcl_checkflags},
	{NULL, NULL}
};

/* luaopen_ltcl
 *
 * init tcl module
 *
 * Arguments:
 *	L	Lua_State
 *
 * Lua Stack:
 *	-
 *
 * Lua Returns:
 *	+1	tcl module table
 */
int luaopen_ltcl(lua_State *L)
{
	int major, minor;
	char buf[16];
#if LUA_VERSION_NUM > 501
    lua_newtable(L);
    luaL_setfuncs(L,ltcl_lib,0);
    lua_pushvalue(L,-1);
    lua_setglobal(L,"ltcl");
#else    
	luaL_register(L, "ltcl", ltcl_lib);
#endif

	/* add lTclVals userdata metatable */
	luaL_newmetatable(L, LTCL_VALS);
#if LUA_VERSION_NUM > 501    
    luaL_setfuncs(L,LTCL_VALSmeta,0);
#else
	luaL_register(L, 0, LTCL_VALSmeta);
#endif
	lua_pop(L, 1);

	/* add lTcl userdata metatable */
	luaL_newmetatable(L, LTCL); /* should check return value */
#if LUA_VERSION_NUM > 501    
    luaL_setfuncs(L,ltcl_meta,0);
#else    
	luaL_register(L, 0, ltcl_meta);
#endif
	/* methods */
	lua_pushliteral(L, "__index");
	lua_pushvalue(L, -3);
	lua_rawset(L, -3);

	/* exported functions */
	lua_pushliteral(L, LTCL_FUNCS);
	lua_newtable(L);
	lua_rawset(L, -3);
	lua_pop(L, 1); /* pop metatable */

	/* register constants */

	/* ltcl version */
	lua_pushliteral(L, "_VERSION");
	lua_pushnumber(L, VERSION);
	lua_rawset(L, -3);

	lua_pushliteral(L, "_REVISION");
	lua_pushnumber(L, REVISION);
	lua_rawset(L, -3);

	/* tcl interpreter version into metatable */
	Tcl_GetVersion(&major, &minor, NULL, NULL);
	lua_pushliteral(L, "_TCLVERSION");
	snprintf(buf, 16, "%d.%d", major, minor);
	lua_pushstring(L, buf);
	lua_rawset(L, -3);

	/* eval flags */
	lua_pushliteral(L, "EVAL_GLOBAL");
	lua_pushnumber(L, TCL_EVAL_GLOBAL);
	lua_rawset(L, -3);

	/* get*&set* flags */
	lua_pushliteral(L, "GLOBAL_ONLY");
	lua_pushnumber(L, TCL_GLOBAL_ONLY);
	lua_rawset(L, -3);

	lua_pushliteral(L, "NAMESPACE_ONLY");
	lua_pushnumber(L, TCL_NAMESPACE_ONLY);
	lua_rawset(L, -3);

	lua_pushliteral(L, "APPEND_VALUE");
	lua_pushnumber(L, TCL_APPEND_VALUE);
	lua_rawset(L, -3);

	lua_pushliteral(L, "LIST_ELEMENT");
	lua_pushnumber(L, TCL_LIST_ELEMENT);
	lua_rawset(L, -3);
	
	/* trace* flags */
	lua_pushliteral(L, "TRACE_READS");
	lua_pushnumber(L, TCL_TRACE_READS);
	lua_rawset(L, -3);
	
	lua_pushliteral(L, "TRACE_WRITES");
	lua_pushnumber(L, TCL_TRACE_WRITES);
	lua_rawset(L, -3);

	lua_pushliteral(L, "TRACE_UNSETS");
	lua_pushnumber(L, TCL_TRACE_UNSETS);
	lua_rawset(L, -3);

	lua_pushliteral(L, "TRACE_ARRAY");
	lua_pushnumber(L, TCL_TRACE_ARRAY);
	lua_rawset(L, -3);

	return 1;
}

