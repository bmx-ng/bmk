#include <utime.h>
#include "brl.mod/blitz.mod/blitz.h"

void bmx_setfiletimenow(BBString * path) {
	char * p = bbStringToUTF8String(path);
	struct utimbuf times;
	
	times.actime = time(NULL);
	times.modtime = time(NULL); 

	utime(p, &times);
	
	bbMemFree(p);
}