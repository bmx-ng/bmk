#include <kernel/OS.h>

int bmx_get_system_info_cpu_count() {
	system_info info;
	get_system_info(&info);
	return info.cpu_count;
}
