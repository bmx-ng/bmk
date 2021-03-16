
Strict

Import BRL.MaxUtil
Import BRL.StandardIO
?macos
Import Pub.MacOS
?
Import brl.map

Import "stringbuffer_core.bmx"

Const BMK_VERSION:String = "3.46"

Const ALL_SRC_EXTS$="bmx;i;c;m;h;cpp;cxx;mm;hpp;hxx;s;cc;asm;S"

Global opt_arch$
Global opt_arch_set=False
Global opt_outfile$
Global opt_infile:String
Global opt_framework$
Global opt_apptype$="console"
Global opt_debug=False
Global opt_threaded=False
Global opt_release=False
Global opt_configmung$=""
Global opt_kill=False
Global opt_modfilter$="."
Global opt_all=False
Global opt_quiet=False
Global opt_verbose=False
Global opt_execute=False
Global opt_appstub$="brl.appstub" ' BaH 28/9/2007
Global opt_universal=False
Global opt_target_platform:String
Global opt_target_platform_set=False
Global opt_gdbdebug=False
Global opt_gdbdebug_set=False
Global opt_standalone=False
Global opt_standalone_set=False
Global opt_nolog
Global opt_quickscan=False
Global opt_quickscan_set=False
Global opt_nostrictupgrade=False
Global opt_nostrictupgrade_set=False
Global opt_warnover=False
Global opt_warnover_set=False
Global opt_musl=False
Global opt_musl_set=False
Global opt_static=False
Global opt_static_set=False
Global opt_boot:Int
Global opt_manifest:Int = True
Global opt_single:Int
Global opt_nodef:Int
Global opt_nohead:Int
Global opt_require_override:Int
Global opt_override_error:Int
Global opt_nopie:Int
Global opt_nopie_set:Int
Global opt_upx:Int
Global opt_userdefs:String
Global opt_gprof:Int
Global opt_hi:Int

Global opt_dumpbuild

'Global cfg_platform$
Global macos_version:Int=2784 ' 10.14

Global app_main$
Global app_type$

?MacOS

Function GetVersion:Int()
	Local major:Int
	Local minor:Int
	Local patch:Int
	NSOSVersion(major, minor, patch)
	Return major Shl 8 | minor Shl 4 | patch
End Function

macos_version = GetVersion()

?MacOsPPC
If is_pid_native(0) opt_arch="ppc" Else opt_arch="x86"

?MacOsX86
If is_pid_native(0) opt_arch="x86" Else opt_arch="ppc"

?MacOsx64
opt_arch="x64"

?MacOsarm64
opt_arch="arm64"

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
?raspberrypiarm64
opt_arch="arm64"
?haikux86
opt_arch="x86"
?haikux64
opt_arch="x64"
?

TStringBuffer.initialCapacity = 128

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

Function MissingArg(arg:String)
	CmdError "Missing arg for '-" + arg + "'"
End Function

Function ParseConfigArgs$[]( args$[], legacyMax:Int = False )

	Local n

	If getenv_( "BMKDUMPBUILD" )
		opt_dumpbuild=1
		opt_quiet=True
	EndIf

	For n=0 Until args.length
		Local arg$=args[n]
		If arg[..1]<>"-" Exit
		Local argv:String = arg[1..]
		Select argv
		Case "a", "all"
			opt_all=True
		Case "q"
			opt_quiet=True
		Case "v"
			opt_verbose=True
		Case "x"
			opt_execute=True
		Case "d", "debug"
			opt_debug=True
			opt_release=False
		Case "r", "release"
			opt_debug=False
			opt_release=True
		Case "h"
			opt_threaded=True
		Case "k"
			opt_kill=True
		Case "g", "arch"
			n:+1
			If n=args.length MissingArg(argv)
			opt_arch=args[n].ToLower()
			ValidateArch(opt_arch)
			opt_arch_set = True
		Case "t", "type"
			n:+1
			If n=args.length MissingArg(argv)
			opt_apptype=args[n].ToLower()
		Case "o", "output"
			n:+1
			If n=args.length MissingArg(argv)
			opt_outfile=args[n]
		Case "f", "framework"
			n:+1
			If n=args.length MissingArg(argv)
			opt_framework=args[n]
		Case "b"
			n:+1
			If n=args.length MissingArg(argv)
			opt_appstub=args[n]
		Case "i"
?macos
			' this is mac/ios only... pah!
			opt_universal = True
?
		Case "l", "platform"
			n:+1
			If n=args.length MissingArg(argv)
			opt_target_platform=args[n].ToLower()
			ValidatePlatform(opt_target_platform)
			opt_target_platform_set = True
		Case "gdb"
			opt_gdbdebug = True
			opt_gdbdebug_set = True
		Case "standalone"
			opt_standalone = True
			opt_standalone_set = True
		Case "quick"
			opt_quickscan = True
			opt_quickscan_set = True
		Case "nostrictupgrade"
			opt_nostrictupgrade = True
			opt_nostrictupgrade_set = True
		Case "w"
			opt_warnover = True
			opt_warnover_set = True
		Case "musl"
			opt_musl = True
			opt_musl_set = True
		Case "static"
			opt_static = True
			opt_static_set = True
		Case "nomanifest"
			opt_manifest = False
		Case "single"
			opt_single = True
		Case "nodef"
			opt_nodef = True
		Case "nohead"
			opt_nohead = True
		Case "override"
			opt_require_override = True
		Case "overerr"
			opt_override_error = True
		Case "no-pie"
			opt_nopie = True
			opt_nopie_set = True
		Case "upx"
			opt_upx = True
		Case "ud"
			n:+1
			If n=args.length MissingArg(argv)
			opt_userdefs=args[n]
		Case "gprof"
			opt_gprof = True
		Case "hi"
			opt_hi = True
		Default
			CmdError "Invalid option '" + argv + "'"
		End Select
	Next

	If Not legacyMax Then
		If opt_threaded And opt_verbose Then
			Print "Note: NG builds are threaded by default."
		End If
		opt_threaded=True
	End If

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
		s:+ "~tmakelib~n"
		s:+ "~t~tBuilds a shared library/DLL file from a single root source file."
		s:+ "~n~n"
		s:+ "~tmakemods~n"
		s:+ "~t~tBuilds a set of modules."
		s:+ "~n~n"
		s:+ "Options :~n"
		s:+ "~t-a | -all~n"
		s:+ "~t~tRecompile all source/modules regardless of timestamp. By default, only those modified~n" + ..
		    "~t~tsince the last build are recompiled."
		s:+ "~n~n"
		s:+ "~t-b <custom appstub module>~n"
		s:+ "~t~tBuilds an app using a custom appstub (i.e. not BRL.Appstub).~n"
		s:+ "~t~tThis can be useful when you want more control over low-level application state."
		s:+ "~n~n"
		s:+ "~t-d | -debug~n"
		s:+ "~t~tBuilds a debug version. (This is the default for makeapp)."
		s:+ "~n~n"
		s:+ "~t-g <architecture> | -arch <architecture>~n"
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
		s:+ "~t~t~tMacOS : x86, x64, arm64~n"
		s:+ "~t~t~tWin32 : x86, x64~n"
		s:+ "~t~t~tLinux : x86, x64, arm, arm64~n"
		s:+ "~t~t~tiOS : x86, x64 (simulator), armv7, arm64~n"
		s:+ "~t~t~tAndroid : x86, x64, arm, armeabi, armeabiv7a, arm64v8a~n"
		s:+ "~t~t~tRaspberryPi : arm, arm64~n"
		s:+ "~t~t~tnx : arm64~n"
		s:+ "~t~t~thaiku : x86, x64~n"
		s:+ "~n~n"
		s:+ "~t-gdb~n"
		s:+ "~t~tGenerates line mappings suitable for GDB debugging.~n"
		s:+ "~t~tBacktrace (etc.) will show .bmx relative source lines rather than that of the generated code."
		s:+ "~n~n"
		s:+ "~t-gprof~n"
		s:+ "~t~tCompiles for gprof profiling.~n"
		s:+ "~n~n"
		s:+ "~t-h~n"
		s:+ "~t~tBuild multithreaded version. (This is the default on NG)~n"
		s:+ "~t~tThe default on legacy BlitzMax is to build non-threaded. On legacy, using this option will also~n"
		s:+ "~t~tadd a .mt suffix to the executable."
		s:+ "~n~n"
		s:+ "~t-hi~n"
		s:+ "~t~tSpecifies that the application supports high-resolution screens (HiDPI). (GUI only)~n"
		s:+ "~t~tThis will, for example, configure the macOS bundle with the appropriate plist settings."
		s:+ "~n~n"
		s:+ "~t-i~n"
		s:+ "~t~tCreates a Universal build for supported platforms.~n"
		s:+ "~t~t(see documentation for full list of requirements)"
		s:+ "~n~n"
		s:+ "~t-l <target platfom> | -platform <target platform>~n"
		s:+ "~t~tCross-compiles to the specific target platform.~n"
		s:+ "~t~tValid targets are win32, linux, macos, ios, android, raspberrypi and haiku.~n"
		s:+ "~t~t(see documentation for full list of requirements)"
		s:+ "~n~n"
		s:+ "~t-musl~n"
		s:+ "~t~tEnable musl libc compatibility. (Linux NG only)"
		s:+ "~n~n"
		s:+ "~t-nomanifest~n"
		s:+ "~t~tDon't add an automatically generated manifest and resources to a Win32 application. (Win32 only)~n"
		s:+ "~t~tName .ico file as <app name>.ico to be included in the the resource.~n"
		s:+ "~t~tConfigurable application details are placed in the file <app name>.settings"
		s:+ "~n~n"
		s:+ "~t-nostrictupgrade~n"
		s:+ "~t~tDon't upgrade strict method void return types, if required. (NG only)~n"
		s:+ "~t~tIf a Strict sub type overrides the method of a SuperStrict type and the return type is void,~n"
		s:+ "~t~tdon't upgrade the return type to void (i.e. none), and default it to Int."
		s:+ "~n~n"
		s:+ "~t-o <output file> | -output <output file>~n"
		s:+ "~t~tSpecify output file. (makeapp only)~n"
		s:+ "~t~tBy default, the output file is placed into the same directory as the root source file."
		s:+ "~n~n"
		s:+ "~t-override~n"
		s:+ "~t~tWarn if overriding methods are not declared with Override property (NG only)~n"
		s:+ "~n~n"
		s:+ "~t-overerr~n"
		s:+ "~t~tUpgrades -override warnings to errors. (NG only)~n"
		s:+ "~n~n"
		s:+ "~t-no-pie~n"
		s:+ "~t~tDisables option to compile position independent executables. (NG & Linux only)~n"
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
		s:+ "~t-r | -release~n"
		s:+ "~t~tBuilds a release version."
		s:+ "~n~n"
		s:+ "~t-standalone~n"
		s:+ "~t~tGenerate but do not compile into binary form.~n"
		s:+ "~t~tUseful for creating ready-to-build source for a different platform/architecture."
		s:+ "~n~n"
		s:+ "~t-static~n"
		s:+ "~t~tStatically link binary. (Linux NG only)"
		s:+ "~n~n"
		s:+ "~t-t <app type> | -type <app type>~n"
		s:+ "~t~tSpecify application type. (makeapp only)~n"
		s:+ "~t~tShould be either 'console' or 'gui' (without single quote!).~n"
		s:+ "~t~tThe default is console."
		s:+ "~n~n"
		s:+ "~t-ud <definitions>~n"
		s:+ "~t~tAdd user defined compiler options. (NG only).~n"
		s:+ "~t~tA comma-separated list of compiler options that can be used in addition to the defaults.~n"
		s:+ "~t~tAlternatively, the option 'adddef' can be used in build scripts to provide the same.~n"
		s:+ "~n~n"
		s:+ "~t-upx~n"
		s:+ "~t~tPack binary using UPX. (makeapp only)."
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

Function VersionInfo(gcc:String, cores:Int, xcode:String)
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
?haiku
	s:+ "haiku"
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
	
	If xcode Then
		s:+ " / xcode " + xcode
	End If

	s:+ " (cpu x" + cores + ")"

	Print s + "~n"
End Function

Function AsConfigurable:Int(key:String, value:String)
	Local config:Int = False
	Local set:Int = 0
	Select key
		Case "opt_warnover"
			If Not opt_warnover_set Then
				opt_warnover = Int(value)
				set = 1
			Else
				If opt_warnover <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_quickscan"
			If Not opt_quickscan_set Then
				opt_quickscan = Int(value)
				set = 1
			Else
				If opt_quickscan <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_gdbdebug"
			If Not opt_gdbdebug_set Then
				opt_gdbdebug = Int(value)
				set = 1
			Else
				If opt_gdbdebug <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_standalone"
			If Not opt_standalone_set Then
				opt_standalone = Int(value)
				set = 1
			Else
				If opt_standalone <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_nostrictupgrade"
			If Not opt_nostrictupgrade_set Then
				opt_nostrictupgrade = Int(value)
				set = 1
			Else
				If opt_nostrictupgrade <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_arch"
			If Not opt_arch_set Then
				opt_arch = value.ToLower()
				ValidateArch(opt_arch)
				set = 1
			Else
				If opt_arch <> value.ToLower() Then
					set = 2
				End If
			End If
			config = True
		Case "opt_target_platform"
			If Not opt_target_platform_set Then
				opt_target_platform = value.ToLower()
				ValidatePlatform(opt_target_platform)
				set = 1
			Else
				If opt_target_platform <> value.ToLower() Then
					set = 2
				End If
			End If
			config = True
		Case "opt_musl"
			If Not opt_musl_set Then
				opt_musl = Int(value)
				set = 1
			Else
				If opt_musl <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_static"
			If Not opt_static_set Then
				opt_static = Int(value)
				set = 1
			Else
				If opt_static <> Int(value) Then
					set = 2
				End If
			End If
			config = True
		Case "opt_nopie"
			If Not opt_nopie_set Then
				opt_nopie = Int(value)
				set = 1
			Else
				If opt_nopie <> Int(value) Then
					set = 2
				End If
			End If
			config = True
	End Select
	If set And opt_verbose Then
		If set = 1 Then
			Print "Using " + key.ToUpper() + " = " + value
		Else
			Print "Config " + key.ToUpper() + " = " + value + "  was NOT used because command-line arguments override it"
		End If
	End If
	Return config
End Function

Function ValidateArch(arch:String)
	Select arch
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
			CmdError "Not a valid architecture : '" + arch + "'"
	End Select
End Function

Function ValidatePlatform(platform:String)
	Select platform
		Case "win32"
		Case "macos"
		Case "osx"
		Case "ios"
		Case "linux"
		Case "android"
		Case "raspberrypi"
		Case "emscripten"
		Case "nx"
		Case "haiku"
		Default
			' oops
			CmdError "Not valid platform : '" + platform + "'"
	End Select
End Function

Function ParseApplicationIniFile:TMap()
	Local ids:String[] = [StripDir(StripExt(opt_outfile)), StripDir(StripExt(opt_infile))]

	Local appId:String = ids[0]
	Local buildDir:String = ExtractDir(opt_infile)

	Local path:String
	Local found:Int
	Local settings:TMap = New TMap
	
	For Local id:String = EachIn ids
		path = buildDir + "/" + id + ".settings"

		If Not FileType(path) Then
			If opt_verbose Then
				Print "Not Found : application settings file '" + id + ".settings'."
			End If
			Continue
		End If
		
		found = True
		Exit
	Next
	
	If Not found Then
		If opt_verbose Then
			Print "Using defaults."
		End If
		Return DefaultApplicationSettings()
	End If

	Local file:TStream = ReadFile(path)
	If Not file
		Return Null
	EndIf

	Local line:String
	Local pos:Int
	While Not Eof(file)
		line = ReadLine(file).Trim()

		If line.Find("#") = 0 Then
			Continue
		End If

		pos = line.Find("=")

		If pos = -1 Then
			Continue
		End If

		settings.Insert(line[..pos], line[pos+1..])
	Wend

	file.Close()

	Local id:String = StripDir(StripExt(opt_outfile))
	If opt_debug And opt_outfile.EndsWith(".debug") Then
		id :+ ".debug"
	End If
	settings.Insert("app.id", id)
	
	If Not settings.Contains("app.version.major") Then
		Local version:String = String(settings.ValueForKey("app.version.name"))
		If version Then
			Local parts:String[] = version.Split(".")
			For Local i:Int = 0 Until parts.length
				Select i
					Case 0
						settings.Insert("app.version.major", String.FromInt(parts[i].ToInt()))
					Case 1
						settings.Insert("app.version.minor", String.FromInt(parts[i].ToInt()))
					Case 2
						settings.Insert("app.version.patch", String.FromInt(parts[i].ToInt()))
					Case 3
						settings.Insert("app.version.build", String.FromInt(parts[i].ToInt()))
				End Select
			Next
		End If
	End If

	Return settings
End Function

Function DefaultApplicationSettings:TMap()
	Local appId:String = StripDir(StripExt(opt_outfile))
	If opt_debug And opt_outfile.EndsWith(".debug") Then
		appId :+ ".debug"
	End If

	Local settings:TMap = New TMap
	settings.Insert("app.package", "com.blitzmax.app")
	settings.Insert("app.version.code", "1")
	settings.Insert("app.version.name", "1.0.0")
	settings.Insert("app.name", appId)
	settings.Insert("app.orientation", "landscape")
	settings.Insert("app.comments", "BlitzMax Application")
	settings.Insert("app.company", "My company")
	settings.Insert("app.description", appId)
	settings.Insert("app.copyright", "Copyright")
	settings.Insert("app.trademarks", "All rights reserved")

	settings.Insert("app.id", appId)
	Return settings
End Function

