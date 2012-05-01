#ifndef SIGNAMES_H
#define SIGNAMES_H

#include <signal.h>

struct signame {
    int sig;
    const char* name;
};

static const struct signame sigs[] =
{
#ifdef SIGABRT
    {SIGABRT,   "ABRT"},
#endif
#ifdef SIGALRM
    {SIGALRM,   "ALRM"},
#endif
#ifdef SIGBUS
    {SIGBUS,    "BUS"},
#endif
#ifdef SIGCHLD
    {SIGCHLD,   "CHLD"},
#endif
#ifdef SIGCLD
    {SIGCLD,    "CLD"},
#endif
#ifdef SIGCONT
    {SIGCONT,   "CONT"},
#endif
#ifdef SIGEMT
    {SIGEMT,    "EMT"},
#endif
#ifdef SIGFPE
    {SIGFPE,    "FPE"},
#endif
#ifdef SIGHUP
    {SIGHUP,    "HUP"},
#endif
#ifdef SIGILL
    {SIGILL,    "ILL"},
#endif
#ifdef SIGINFO
    {SIGINFO,   "INFO"},
#endif
#ifdef SIGINT
    {SIGINT,    "INT"},
#endif
#ifdef SIGIO
    {SIGIO,     "IO"},
#endif
#ifdef SIGIOT
    {SIGIOT,    "IOT"},
#endif
#ifdef SIGKILL
    {SIGKILL,   "KILL"},
#endif
#ifdef SIGLOST
    {SIGLOST,   "LOST"},
#endif
#ifdef SIGPIPE
    {SIGPIPE,   "PIPE"},
#endif
#ifdef SIGPOLL
    {SIGPOLL,   "POLL"},
#endif
#ifdef SIGPROF
    {SIGPROF,   "PROF"},
#endif
#ifdef SIGPWR
    {SIGPWR,    "PWR"},
#endif
#ifdef SIGQUIT
    {SIGQUIT,   "QUIT"},
#endif
#ifdef SIGSEGV
    {SIGSEGV,   "SEGV"},
#endif
#ifdef SIGSTKFLT
    {SIGSTKFLT, "STKFLT"},
#endif
#ifdef SIGSTOP
    {SIGSTOP,   "STOP"},
#endif
#ifdef SIGSYS
    {SIGSYS,    "SYS"},
#endif
#ifdef SIGTERM
    {SIGTERM,   "TERM"},
#endif
#ifdef SIGTRAP
    {SIGTRAP,   "TRAP"},
#endif
#ifdef SIGTSTP
    {SIGTSTP,   "TSTP"},
#endif
#ifdef SIGTTIN
    {SIGTTIN,   "TTIN"},
#endif
#ifdef SIGTTOU
    {SIGTTOU,   "TTOU"},
#endif
#ifdef SIGUNUSED
    {SIGUNUSED, "UNUSED"},
#endif
#ifdef SIGURG
    {SIGURG,    "URG"},
#endif
#ifdef SIGUSR1
    {SIGUSR1,   "USR1"},
#endif
#ifdef SIGUSR2
    {SIGUSR2,   "USR2"},
#endif
#ifdef SIGVTALRM
    {SIGVTALRM, "VTALRM"},
#endif
#ifdef SIGWINCH
    {SIGWINCH,  "WINCH"},
#endif
#ifdef SIGXCPU
    {SIGXCPU,   "XCPU"},
#endif
#ifdef SIGXFSZ
    {SIGXFSZ,   "XFSZ"},
#endif
};

int name_to_sig(const char* name);
const char* sig_to_name(int sig);

#endif
