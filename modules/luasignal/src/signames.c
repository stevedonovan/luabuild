#include "signames.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char* sig_to_name(int sig)
{
    static char signame[7];

#ifdef SIGRTMIN
    if (sig >= SIGRTMIN && sig <= SIGRTMAX) {
        snprintf(signame, 7, "RT%d", sig - SIGRTMIN);

        return signame;
    }
    else {
#endif
        int i;

        for (i = 0; i < sizeof(sigs) / sizeof(sigs[0]); ++i) {
            if (sigs[i].sig == sig) {
                return sigs[i].name;
            }
        }

        return NULL;
#ifdef SIGRTMIN
    }
#endif
}

int name_to_sig(const char* name)
{
#ifdef SIGRTMIN
    if (strncmp(name, "RT", 2) == 0) {
        int rtsig;

        rtsig = atoi(name + 2);

        return rtsig + SIGRTMIN;
    }
    else {
#endif
        int i;

        for (i = 0; i < sizeof(sigs) / sizeof(sigs[0]); ++i) {
            if (strcmp(sigs[i].name, name) == 0) {
                return sigs[i].sig;
            }
        }

        return -1;
#ifdef SIGRTMIN
    }
#endif
}
