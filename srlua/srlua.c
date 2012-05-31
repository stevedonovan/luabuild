/*
* srlua.c
* Lua interpreter for self-running programs
* Luiz Henrique de Figueiredo <lhf@tecgraf.puc-rio.br>
* 04 Dec 2011 20:15:50
* This code is hereby placed in the public domain.
*/

#define MAX_PATH 256
#ifdef _WIN32
#define PATHSEP ";"
#define DIRSEP '\\'
#define EXE ".exe"
#else
#define PATHSEP ":"
#define DIRSEP '/'
#define EXE ""
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "glue.h"
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

typedef struct
{
 FILE *f;
 size_t size;
 char buff[512];
} State;

static void fatal(const char* progname, const char* message)
{
 fprintf(stderr,"%s: %s\n",progname,message);
 exit(EXIT_FAILURE);
}

static const char *search_path(const char *name)
{
    static char buffer[MAX_PATH], xname[MAX_PATH];
    int len;
    if (name == NULL)
        return NULL;
    strcpy(xname,name);
#ifdef _WIN32
    if (! strchr(name,'.')) {
        strcat(xname,EXE);
    }
#endif
    if (strchr(name,DIRSEP)) { // absolute or relative path
        return xname;
    } else { // hunt in system path
        char path[2048];
        const char *dir;
        strcpy(path,getenv("PATH"));
#ifdef _WIN32
        // in Windows, current directory is on the path by default!
        strcat(path,";.");
#endif
        dir = strtok(path,PATHSEP);
        while (dir != NULL) {
            FILE *in;
            sprintf(buffer,"%s%c%s",dir,DIRSEP,xname);
            //printf("'%s'\n",buffer);
            in = fopen(buffer,"r");
            if (in != NULL) {
                fclose(in);
                return buffer;
            }
            dir = strtok(NULL,PATHSEP);
        }
    }
    return NULL;
}

static const char *myget(lua_State *L, void *data, size_t *size)
{
 State* s=data;
 size_t n;
 (void)L;
 n=(sizeof(s->buff)<=s->size)? sizeof(s->buff) : s->size;
 n=fread(s->buff,1,n,s->f);
 s->size-=n;
 *size=n;
 return (n>0) ? s->buff : NULL;
}

#define cannot(x) luaL_error(L,"cannot %s %s: %s",x,name,strerror(errno))

static void load(lua_State *L, const char *name)
{
 Glue t;
 State S;
 FILE *f=fopen(name,"rb");
 if (f==NULL) cannot("open");
 if (fseek(f,-sizeof(t),SEEK_END)!=0) cannot("seek");
 if (fread(&t,sizeof(t),1,f)!=1) cannot("read");
 if (memcmp(t.sig,GLUESIG,GLUELEN)!=0) luaL_error(L,"no Lua program found in %s",name);
 if (fseek(f,t.size1,SEEK_SET)!=0) cannot("seek");
 S.f=f; S.size=t.size2;
 if (lua_load(L,myget,&S,"=",NULL)!=0) lua_error(L);
 fclose(f);
}

static int pmain(lua_State *L)
{
 int argc=lua_tointeger(L,1);
 char** argv=lua_touserdata(L,2);
 int i;
 const char *name = search_path(argv[0]);
 if (name==NULL) fatal("srlua","cannot locate this executable");

 lua_gc(L,LUA_GCSTOP,0);
 luaL_openlibs(L);
 lua_gc(L,LUA_GCRESTART,0);
 load(L,name);
 lua_createtable(L,argc,1);
 for (i=0; i<argc; i++)
 {
  lua_pushstring(L,argv[i]);
  lua_rawseti(L,-2,i);
 }
 lua_setglobal(L,"arg");
 luaL_checkstack(L,argc,"too many arguments to script");
 for (i=1; i<argc; i++)
 {
  lua_pushstring(L,argv[i]);
 }
 lua_call(L,argc-1,0);
 return 0;
}



int main(int argc, char *argv[])
{
 lua_State *L;
 L=luaL_newstate();
 if (L==NULL) fatal(argv[0],"not enough memory for state");
 lua_pushcfunction(L,&pmain);
 lua_pushinteger(L,argc);
 lua_pushlightuserdata(L,argv);
 if (lua_pcall(L,2,0,0)!=0) fatal(argv[0],lua_tostring(L,-1));
 lua_close(L);
 return EXIT_SUCCESS;
}
