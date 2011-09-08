
Strict

Import BRL.MaxUtil

Import Pub.MacOS

Const BMK_VERSION:String = "2.06"

Const ALL_SRC_EXTS$="bmx;i;c;m;h;cpp;cxx;mm;hpp;hxx;s;cc"

Global opt_modbuild
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

Global opt_dumpbuild

'Global cfg_platform$
Global macos_version

?MacOS

'cfg_platform="macos"
Gestalt Asc("s")Shl 24|Asc("y")Shl 16|Asc("s")Shl 8|Asc("v"),macos_version

?MacOsPPC
If is_pid_native(0) opt_arch="ppc" Else opt_arch="x86"

?MacOsX86
If is_pid_native(0) opt_arch="x86" Else opt_arch="ppc"

?Win32

opt_arch="x86"
'cfg_platform="win32"

?Linux

opt_arch="x86"
'cfg_platform="linux"

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
			' this is mac only... pah!
			opt_universal = True
?
		Case "l"
			n:+1
			If n=args.length CmdError "Missing arg for '-l'"
			opt_target_platform=args[n].ToLower()
			If opt_target_platform <> "win32" And opt_target_platform <> "mac" And opt_target_platform <> "linux" CmdError "Not valid platform : '" + opt_target_platform + "'"
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

Function CharIsDigit:Int( ch:Int )
	Return ch>=Asc("0") And ch<=Asc("9")
End Function

Function CharIsAlpha:Int( ch:Int )
	Return ch=Asc("_") Or (ch>=Asc("a") And ch<=Asc("z")) Or (ch>=Asc("A") And ch<=Asc("Z"))
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
		s:+ "~t-h~n"
		s:+ "~t~tBuild multithreaded version. (By default, the single threaded version is built.)"
		s:+ "~n~n"
		s:+ "~t-i~n"
		s:+ "~t~tCreates a Universal build on Mac x86 systems.~n"
		s:+ "~t~t(see documentation for full list of requirements)"
		s:+ "~n~n"
		s:+ "~t-l <target platfom>~n"
		s:+ "~t~tCross-compiles to the specific target platform.~n"
		s:+ "~t~tCurrently, only win32 is supported as a target platform on Mac and Linux systems.~n"
		s:+ "~t~t(see documentation for full list of requirements)"
		s:+ "~n~n"
		s:+ "~t-o <output file>~n"
		s:+ "~t~tSpecify output file. (makeapp only)~n"
		s:+ "~t~tBy default, the output file is placed into the same directory as the root source file."
		s:+ "~n~n"
		s:+ "~t-q~n"
		s:+ "~t~tQuiet build."
		s:+ "~n~n"
		s:+ "~t-r~n"
		s:+ "~t~tBuilds a release version."
		s:+ "~n~n"
		s:+ "~t-t <app type>~n"
		s:+ "~t~tSpecify application type. (makeapp only)~n"
		s:+ "~t~tShould be either 'console' or 'gui' (without single quote!).~n"
		s:+ "~t~tThe default is console."
		s:+ "~n~n"
		s:+ "~t-v~n"
		s:+ "~t~tVerbose (noisy) build."
		s:+ "~n~n"
		s:+ "~t-x~n"
		s:+ "~t~tExecute built application. (makeapp only)"
		s:+ "~n~n"
	End If
	
	Return s
End Function

Function VersionInfo()
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
?
	s:+ "-"
?x86
	s:+ "x86"
?ppc
	s:+ "ppc"
?
	Print s + "~n"
End Function

