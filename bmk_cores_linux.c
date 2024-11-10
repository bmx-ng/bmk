#include <stdio.h>

int bmx_get_core_count() {
    int cores = 0;
    char buffer[1024];

    FILE * fp = popen("cat /proc/cpuinfo |grep -c '^processor'", "r");

    if (fp == NULL) {
        printf("Failed to run command\n" );
        return 1;
    }

    while (fgets(buffer, sizeof(buffer), fp) != NULL) {
        cores = atoi(buffer);
    }

    pclose(fp);

    return cores;
}
