#include <stdio.h>

#ifndef __WIN32
#include <stddef.h>
#include <sys/wait.h>
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>
#endif

int bmx_system(const char * c) {
#ifdef __WIN32
	return system(c);
#else
	int status;
	pid_t pid = fork();
	if (pid == 0) {
		execl("/bin/sh", "/bin/sh", "-c", c, NULL);
		_exit(-1);
	} else if (pid < 0) {
		status = -1;
	} else {
		if (waitpid(pid, &status, 0) != pid) {
			status = -1;
		}
	}
	return status;
#endif
}
