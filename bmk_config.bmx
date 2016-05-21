
Strict

Import BRL.MaxUtil
Import BRL.StandardIO
?macos
Import Pub.MacOS
?
Const BMK_VERSION:String = "3.13"

Const ALL_SRC_EXTS$="bmx;i;c;m;h;cpp;cxx;mm;hpp;hxx;s;cc"

Global opt_arch$
Global opt_server$
Global opt_outfile$
Global opt_framework$
Global opt_apptype$="console"
Global opt_debug=False
Global opt_threaded=False
Global opt_release=False
Global opt_configmung$=""
Global opt_kill=False
Global opt_username$="nobody"
Global opt_password$="anonymous"
Global opt_modfilter$="."
Global opt_all=False
Global opt_quiet=False
Global opt_verbose=False
Global opt_execute=False
Global opt_proxy$
Global opt_proxyport
Global opt_traceheaders
Global opt_appstub$="brl.appstub" ' BaH 28/9/2007
Global opt_universal=False
Global opt_target_platform:String
Global opt_gdbdebug=False
Global opt_standalone=False
Global opt_nolog
Global opt_quickscan=False
Global opt_nostrictupgrade=False
Global opt_warnover=False

Global opt_dumpbuild

'Global cfg_platform$
Global macos_version

Global app_main$
Global app_type$

?MacOS

'cfg_platform="macos"
Gestalt Asc("s")Shl 24|Asc("y")Shl 16|Asc("s")Shl 8|Asc("v"),macos_version

?MacOsPPC
If is_pid_native(0) opt_arch="ppc" Else opt_arch="x86"

?MacOsX86
If is_pid_native(0) opt_arch="x86" Else opt_arch="ppc"

?MacOsx64
opt_arch="x64"

?win32x64
opt_arch="x64"
?Win32x86
opt_arch="x86"
?Win32
'Fudge PATH so exec sees our MinGW first!
Local mingw$=getenv_( "MINGW" )
If mingw
	Local path$=getenv_( "PATH" )
	If path
		path=mingw+"\bin;"+path
		putenv_ "PATH="+path
	EndIf
EndIf
?Linuxx86
opt_arch="x86"
?linuxx64
opt_arch="x64"
?linuxarm
opt_arch="arm"
?linuxarm64
opt_arch="arm64"
?raspberrypi
opt_arch="arm"
?raspberrypi64
opt_arch="arm64"
?

ChangeDir LaunchDir

Function CmdError(details:String = Null, fullUsage:Int = False)
	Local s:String = "Command line error"
	If details Then
		s:+ " : " + details
	End If
	s:+ "~n"
	
	s:+ Usage(fullUsage)
	
	Throw s
End Function

Function ParseConfigArgs$[]( args$[] )

	Local n
	
	If getenv_( "BMKDUMPBUILD" )
		opt_dumpbuild=1
		opt_quiet=True
	EndIf
	
	For n=0 Until args.length
		Local arg$=args[n]
		If arg[..1]<>"-" Exit
		Select arg[1..]
		Case "a"
			opt_all=True
		Case "q"
			opt_quiet=True
		Case "v"
			opt_verbose=True
		Case "x"
			opt_execute=True
		Case "d"
			opt_debug=True
			opt_release=False
		Case "r"
			opt_debug=False
			opt_release=True
		Case "h"
			opt_threaded=True
		Case "k"
			opt_kill=True
		Case "z"
			opt_traceheaders=True
		Case "y"
			n:+1
			If n=args.length CmdError "Missing arg for '-y'"
			opt_proxy=args[n]
			Local i=opt_proxy.Find(":")
			If i<>-1
				opt_proxyport=Int( opt_proxy[i+1..] )
				opt_proxy=opt_proxy[..i]
			EndIf
		Case "g"
			n:+1
			If n=args.length CmdError "Missing arg for '-g'"
			opt_arch=args[n].ToLower()
			Select opt_arch
				Case "ppc"
				Case "x86"
				Case "x64"
				Case "arm"
				Case "armeabi"
				Case "armeabiv7a"
				Case "arm64v8a"
				Case "armv7"
				Case "arm64"
				Case "js"
				Default
					' oops
					CmdError "Not a valid architecture : '" + opt_arch + "'"
			End Select
		Case "t"
			n:+1
			If n=args.length CmdError "Missing arg for '-t'"
			opt_apptype=args[n].ToLower()
		Case "o"
			n:+1
			If n=args.length CmdError "Missing arg for '-o'"
			opt_outfile=args[n]
		Case "f"
			n:+1
			If n=args.length CmdError "Missing arg for '-f'"
			opt_framework=args[n]
		Case "s"
			n:+1
			If n=args.length CmdError "Missing arg for '-s'"
			opt_server=args[n]
		Case "u"
			n:+1
			If n=args.length CmdError "Missing arg for '-u'"
			opt_username=args[n]
		Case "p"
			n:+1
			If n=args.length CmdError "Missing arg for '-p'"
			opt_password=args[n]
		Case "b"
			n:+1
			If n=args.length CmdError "Missing arg for '-b'"
			opt_appstub=args[n]
		Case "i"
?macos
			' this is mac/ios only... pah!
			opt_universal = True
?
		Case "l"
			n:+1
			If n=args.length CmdError "Missing arg for '-l'"
			opt_target_platform=args[n].ToLower()
			Select opt_target_platform
				Case "win32"
				Case "macos"
				Case "osx"
				Case "ios"
				Case "linux"
				Case "android"
				Case "raspberrypi"
				Case "emscripten"
				Default
					' oops
					CmdError "Not valid platform : '" + opt_target_platform + "'"
			End Select
		Case "gdb"
			opt_gdbdebug = True
		Case "standalone"
			opt_standalone = True
		Case "quick"
			opt_quickscan = True
		Case "nostrictupgrade"
			opt_nostrictupgrade = True
		Case "w"
			opt_warnover = True
		Default
			CmdError "Invalid option '" + arg[1..] + "'"
		End Select
	Next
	
	Return args[n..]

End Function


Function CQuote$( t$ )
	If t And t[0]=Asc("-") Return t
	For Local i=0 Until t.length
		If t[i]=Asc(".") Continue
		If t[i]=Asc("/") Continue
'If processor.Platform() = "win32"
		If t[i]=Asc("\") Continue
'End If
		If t[i]=Asc("_") Or t[i]=Asc("-") Continue
		If t[i]>=Asc("0") And t[i]<=Asc("9") Continue
		If t[i]>=Asc("A") And t[i]<=Asc("Z") Continue
		If t[i]>=Asc("a") And t[i]<=Asc("z") Continue
		Return "~q"+t+"~q"
	Next
	Return t
End Function

Function ReQuote:String(t:String)
	Return t.Replace("~~q", "~q")
End Function

Function CharIsDigit:Int( ch:Int )
	Return ch>=Asc("0") And ch<=Asc("9")
End Function

Function CharIsAlpha:Int( ch:Int )
	Return ch=Asc("_") Or (ch>=Asc("a") And ch<=Asc("z")) Or (ch>=Asc("A") And ch<=Asc("Z"))
End Function

Function EscapeSpaces:String(path:String)
	Return path.Replace(" ", "\\ ")
End Function

Function Usage:String(fullUsage:Int = False)
	Local s:String = "~nUsage: bmk <operation> [options] source~n~n"

	If Not fullUsage Then
		s:+ "(start bmk with no parameters for more usage information)~n~n"
	Else
		s:+ "Operations :~n"
		s:+ "~tmakeapp~n"
		s:+ "~t~tBuilds an application from a single root source file."
		s:+ "~n~n"
		s:+ "~tmakemods~n"
		s:+ "~t~tBuilds a set of modules."
		s:+ "~n~n"
		s:+ "Options :~n"
		s:+ "~t-a~n"
		s:+ "~t~tRecompile all source/modules regardless of timestamp. By default, only those modified~n" + ..
		    "~t~tsince the last build are recompiled."
		s:+ "~n~n"
		s:+ "~t-b <custom appstub module>~n"
		s:+ "~t~tBuilds an app using a custom appstub (i.e. not BRL.Appstub).~n"
		s:+ "~t~tThis can be useful when you want more control over low-level application state."
		s:+ "~n~n"
		s:+ "~t-d~n"
		s:+ "~t~tBuilds a debug version. (This is the default for makeapp)."
		s:+ "~n~n"
		s:+ "~t-g <architecture>~n"
		s:+ "~t~tCompiles to the specified architecture. (the default is the native for this binary - "
?x86
		s:+ "x86"
?x64
		s:+ "x64"
?ppc
		s:+ "ppc"
?arm
		s:+ "arm"
?arm64
		s:+ "arm64"
?armeabi
		s:+ "armeabi"
?armeabiv7a
		s:+ "armeabiv7a"
?arm64v8a
		s:+ "arm64v8a"
?js
		s:+ "js"
?
		s:+ ")~n"
		s:+ "~t~tOptions vary depending on the current OS/architecture/installed toolchain and version of bcc.~n"
		s:+ "~t~t~tMacOS : x86, x64~n"
		s:+ "~t~t~tWin32 : x86, x64~n"
		s:+ "~t~t~tLinux : x86, x64, arm, arm64~n"
		s:+ "~t~t~tiOS : x86, x64 (simulator), armv7, arm64~n"
		s:+ "~t~t~tAndroid : x86, x64, arm, armeabi, armeabiv7a, arm64v8a~n"
		s:+ "~t~t~tRaspberryPi : arm, arm64~n"
		s:+ "~t~t~tEmscripten : js~n"
		s:+ "~n~n"
		s:+ "~t-gdb~n"
		s:+ "~t~tGenerates line mappings suitable for GDB debugging.~n"
		s:+ "~t~tBacktrace (etc.) will show .bmx relative source lines rather than that of the generated code."
		s:+ "~n~n"
		s:+ "~t-h~n"
		s:+ "~t~tBuild multithreaded version. (By default, the single threaded version is built.)"
		s:+ "~n~n"
		s:+ "~t-i~n"
		s:+ "~t~tCreates a Universal build for supported platforms.~n"
		s:+ "~t~t(see documentation for full list of requirements)"
		s:+ "~n~n"
		s:+ "~t-l <target platfom>~n"
		s:+ "~t~tCross-compiles to the specific target platform.~n"
		s:+ "~t~tValid targets are win32, linux, macos, ios, android, raspberrypi and emscripten.~n"
		s:+ "~t~t(see documentation for full list of requirements)"
		s:+ "~n~n"
		s:+ "~t-nostrictupgrade~n"
		s:+ "~t~tDon't upgrade strict method void return types, if required. (NG only)~n"
		s:+ "~t~tIf a Strict sub type overrides the method of a SuperStrict type and the return type is void,~n"
		s:+ "~t~tdon't upgrade the return type to void (i.e. none), and default it to Int."
		s:+ "~n~n"
		s:+ "~t-o <output file>~n"
		s:+ "~t~tSpecify output file. (makeapp only)~n"
		s:+ "~t~tBy default, the output file is placed into the same directory as the root source file."
		s:+ "~n~n"
		s:+ "~t-q~n"
		s:+ "~t~tQuiet build."
		s:+ "~n~n"
		s:+ "~t-quick~n"
		s:+ "~t~tQuick build.~n"
		s:+ "~t~tDoes not scans modules for changes. May result in quicker build times on some systems.~n"
		s:+ "~t~tThe default behaviour is to scan and build all requirements for the application,~n"
		s:+ "~t~tincluding modules."
		s:+ "~n~n"
		s:+ "~t-r~n"
		s:+ "~t~tBuilds a release version."
		s:+ "~n~n"
		s:+ "~t-standalone~n"
		s:+ "~t~tGenerate but do not compile into binary form.~n"
		s:+ "~t~tUseful for creating ready-to-build source for a different platform/architecture."
		s:+ "~n~n"
		s:+ "~t-t <app type>~n"
		s:+ "~t~tSpecify application type. (makeapp only)~n"
		s:+ "~t~tShould be either 'console' or 'gui' (without single quote!).~n"
		s:+ "~t~tThe default is console."
		s:+ "~n~n"
		s:+ "~t-v~n"
		s:+ "~t~tVerbose (noisy) build."
		s:+ "~n~n"
		s:+ "~t-w~n"
		s:+ "~t~tWarn about function argument casting issues rather than error. (NG only)~n"
		s:+ "~t~tWith this warning enabled you may have issues with method overloading."
		s:+ "~n~n"
		s:+ "~t-x~n"
		s:+ "~t~tExecute built application. (makeapp only)"
		s:+ "~n~n"
	End If
	
	Return s
End Function

Function VersionInfo(gcc:String, cores:Int)
	Local s:String = "bmk "
	s:+ BMK_VERSION + " "
?threaded
	s:+ "mt-"
?
?win32
	s:+ "win32"
?linux
	s:+ "linux"
?macos
	s:+ "macos"
?osx
	s:+ "-osx"
?ios
	s:+ "-ios"
?android
	s:+ "-android"
?raspberrypi
	s:+ "-raspberrypi"
?emscripten
	s:+ "-emscripten"
?
	s:+ "-"
?x86
	s:+ "x86"
?ppc
	s:+ "ppc"
?x64
	s:+ "x64"
?arm
	s:+ "arm"
?arm64
	s:+ "arm64"
?armeabi
	s:+ "armeabi"
?armeabiv7a
	s:+ "armeabiv7a"
?arm64v8a
	s:+ "arm64v8a"
?js
	s:+ "js"
?
	s:+ " / " + gcc

	s:+ " (cpu x" + cores + ")"
	
	Print s + "~n"
End Function
