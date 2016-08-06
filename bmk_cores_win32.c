#include "windows.h"


int bmx_GetSystemInfo_dwNumberOfProcessors() {
	SYSTEM_INFO info;
	GetSystemInfo(&info);
	return info.dwNumberOfProcessors;
}
