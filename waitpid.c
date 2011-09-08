#include <stdio.h>
#include <sys/wait.h>

int bmx_waitpid(pid_t pid) {

	int status;
	pid_t p = waitpid(pid, &status, WUNTRACED);
	
	return WEXITSTATUS(status);
}

void bmx_system(const char * c) {
	int res = system(c);
	
	// don't ask..
	if (res) {
		res = 1;
	}

	exit(res);
}
