
void NSOSVersion(int * major, int * minor, int * patch) {
	NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
	*major = version.majorVersion;
	*minor = version.minorVersion;
	*patch = version.patchVersion;
}
