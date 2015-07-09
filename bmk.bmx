'
' Change History :
' 3.04 03/07/2015 - Added -quick app build option - skips building/checking required module if .a and .i present.
' 3.03 20/06/2015 - Legacy bcc installations can now use local MinGW32 dir.
' 3.02 10/06/2015 - Added standalone app build generation. Generates source and build script for bmk/bcc-less compile.
' 3.01 28/05/2015 - Reworked android stuff to work with standard setup.
'                   Fixed OS X sysroot issue, and enhanced OS X configuration.
'                   Improved support for mixed builds (compiling between legacy and ng)
' 3.00 05/05/2015 - "Chirpy Chipmunk"
'                 - Redesign of dependency processing - parallel build!
'                 - Added progress information.
'                 - Now uses thread pool.
' 2.25 15/02/2015 - Fix for preprocessor bmxng version check.
'                   Fixed Win32 pthread link order issue.
'                   Use Win32 pthread link for GCC 4.8+
' 2.24 22/01/2015 - Added support for emscripten target.
'                   Added platform/arch validation.
'                   Auto suffix .html for emscripten apps.
'                   Added opengles target platform preprocessor option.
'                   Added project-specific pre-processing - "<app file>.bmk".
'                   Added gdb debug generation option.
' 2.23 01/12/2014 - Added direct support for android and raspberrypi targets.
'                 - Added android configuration settings and project template.
' 2.22 02/10/2014 - Win32 NG will now prefer MINGW-located files (bin/lib), instead of BlitzMax bin/lib.
'                 - Use .exe suffixes for binaries on Windows.
'                 - Add MinGW/bin to PATH on Windows.
'                 - Handle quotes in Import strings.
'                 - Minimum OS-X version 10.5 (circa 2007).
'                 - Release builds are stripped by default. Can be overridden with 'stripsymbols' option.
' 2.21 28/08/2014 - Added support for 64-bit Win32 build options.
' 2.20 17/07/2014 - Improved target (cross-compile) options.
'                 - Fixed issue with Linux popen signature and old bcc.
' 2.19 05/06/2014 - Linux compilation fix for new bcc.
'                 - Architecture tweaks and documentation update.
'                 - Removed bb2bmx/convertbb option.
' 2.18 13/04/2014 - Added suport for 64-bit OS X build options.
'                 - Added new bcc c/c++ compiler definition : BMX_NG
' 2.17 25/02/2014 - Support multiple build systems.
'                 - Added Linux custom tool locations.
' 2.16 07/12/2013 - Support for pre-build scripts.
'                   Changes for OS X sandbox/codesign support.
'                   Return correct version when using clang as gcc compiler.
'                   Added configurable ld_opts settings.
'                   Enhanced inline pragma support.
'                   Fixed module hierarchical build issue.
' 2.15 04/12/2012 - Update to latest official changes.
' 2.14 05/10/2011 - Added recent official changes.
'                   Fixed mingw gcc 4.6+ build problems.
' 2.13 21/08/2011 - ModuleInfo quotes support.
' 2.12 30/07/2011 - OSX 10.7 (Lion) tweaks.
' 2.11 27/02/2011 - Use g++ instead of ld for linking on win32.
' 2.10 24/02/2011 - Added option for skipping module builds.
' 2.09 30/04/2010 - Fixed loadBMK to work for local app folder.
' 2.08 05/04/2010 - Added Tommo's include speedup fix.
'                   Fixed PPC universal link issue.
' 2.07 28/01/2010 - Fixed win32 linking to include libmingw32 both at the start and end of the list. (should cover 3.9.5 and 4.x gcc's)
' 2.06 30/12/2009 - Added APPID variable for scripts on Mac (useful for custom plists).
' 2.05 10/12/2009 - Added .cc file support.
'                   Fixed Linux optimization flag -Os always being set.
' 2.04 28/06/2009 - Tweaked thread error reporting.
'                   Small speedup with threading.
' 2.03 28/06/2009 - Improved custom options support for Universal builds.
'                   Fixed import ordering.
' 2.02 08/06/2009 - Fixed multiple defines problem.
' 2.01 07/06/2009 - Fixed dependency compilation issue - or lack of it!
'  BaH 26/05/2009 - Added multi-process (threading) support.
'                   Improved custom variable overriding.
'  BaH 18/05/2009 - Added Universal support (Mac) with -i parameter.
'                   Added cross-compile support with -l win32.
'  BaH 28/09/2007 - Added custom appstub compiles using -b parameter.
'                   Synched with current bmk source.
'
Strict

Framework brl.filesystem

Import "bmk_make.bmx"
Import "bmk_zap.bmx"

?MacOS
Import BRL.RamStream
Incbin "macos.icns"
?

If AppArgs.length<2 CmdError "Not enough parameters", True

Local cmd$=AppArgs[1],args$[]

args=ParseConfigArgs( AppArgs[2..] )

' validate the platform configuration
ValidatePlatformArchitecture()

' preload the default options
processor.RunCommand("default_cc_opts", Null)

' load any global custom options (in BlitzMax/bin)
LoadOptions

CreateDir BlitzMaxPath()+"/tmp"

Select cmd.ToLower()
Case "makeapp"
	SetConfigMung
	MakeApplication args,False
Case "makelib"
	SetConfigMung
	MakeApplication args,True
Case "makemods"
	opt_quickscan = False
	If opt_debug Or opt_release
		SetConfigMung
		MakeModules args
		If opt_universal
			SetConfigMung
			processor.ToggleCPU()
			LoadOptions(True) ' reload options for PPC
			MakeModules args
			processor.ToggleCPU()
			LoadOptions(True)
		End If
	
	Else
		opt_debug=True
		opt_release=False
		SetConfigMung
		MakeModules args
		If opt_universal
			SetConfigMung
			processor.ToggleCPU()
			LoadOptions(True) ' reload options for PPC
			MakeModules args
			processor.ToggleCPU()
			LoadOptions(True)
		End If
		opt_debug=False
		opt_release=True
		SetConfigMung
		MakeModules args
		If opt_universal
			SetConfigMung
			processor.ToggleCPU()
			LoadOptions(True) ' reload options for PPC
			MakeModules args
			processor.ToggleCPU()
			LoadOptions(True)
		End If
	EndIf

Case "cleanmods"
	CleanModules args
Case "zapmod"
	ZapModule args
Case "unzapmod"
	UnzapModule args
Case "listmods"
	ListModules args
Case "modstatus"
	ModuleStatus args
Case "syncmods" 
	SyncModules args
Case "ranlibdir"
	RanlibDir args
Case "-v"
	VersionInfo(processor.GCCVersion(), GetCoreCount())
Default
	CmdError "Unknown operation '" + cmd.ToLower() + "'"
End Select

Function SetConfigMung()
	If opt_release
		opt_debug=False
		opt_configmung="release"
		If opt_threaded opt_configmung:+".mt"
		opt_configmung="."+opt_configmung+"."+processor.Platform()+"."'+opt_arch
	Else
		opt_debug=True
		opt_release=False
		opt_configmung="debug"
		If opt_threaded opt_configmung:+".mt"
		opt_configmung="."+opt_configmung+"."+processor.Platform()+"."'+opt_arch
	EndIf
End Function

Function SetModfilter( t$ )

	opt_modfilter=t.ToLower()

	If opt_modfilter="*"
		opt_modfilter=""
	Else If opt_modfilter[opt_modfilter.length-1]<>"."  And opt_modfilter.Find(".") < 0 Then
		opt_modfilter:+"."
	EndIf
	
End Function

Function MakeModules( args$[] )

	If opt_standalone CmdError "Standalone build not available for makemods"

	If args.length>1 CmdError "Expecting only 1 argument for makemods"
	
	Local mods:TList
	
	If args.length Then
		Local m:String = args[0]
		If m.find(".") > 0 And m[m.length-1]<>"." Then
			' full module name?
			mods = New TList
			mods.AddLast(m)
			SetModfilter m
		Else
			SetModfilter m
			mods = EnumModules()
		End If
	Else
		opt_modfilter=""
		mods = EnumModules()
	End If
	
	BeginMake

	Local buildManager:TBuildManager = New TBuildManager

	buildManager.MakeMods(mods, opt_all)
	buildManager.DoBuild()
	
End Function

Function CleanModules( args$[] )

	If args.length>1 CmdError "Expecting only 1 argument for cleanmods"
	
	If args.length SetModfilter args[0] Else opt_modfilter=""
	
	Local mods:TList=EnumModules()

	Local name$
	For name=EachIn mods
	
		If (name+".").Find(opt_modfilter)<>0 Continue
		
		Print "Cleaning:"+name

		Local path$=ModulePath(name)
		
		DeleteDir path+"/.bmx",True
		
		If Not opt_kill Continue
		
		For Local f$=EachIn LoadDir( path )
		
			Local p$=path+"/"+f
			Select FileType(p)
			Case FILETYPE_DIR
				If f<>"doc"
					DeleteDir p,True
				EndIf
			Case FILETYPE_FILE
				Select ExtractExt(f).tolower()
				Case "i","a","txt","htm","html"
					'nop
				Default
					DeleteFile p
				End Select
			End Select

		Next
	Next

End Function

Function MakeApplication( args$[],makelib )

	If opt_execute
		If Len(args)=0 CmdError "Execute requires at least 1 argument"
	Else
		If Len(args)<>1 CmdError "Expecting only 1 argument for makeapp"
	EndIf

	Local Main$=RealPath( args[0] )
	
	Select ExtractExt(Main).ToLower()
	Case ""
		Main:+".bmx"
	Case "c","cpp","cxx","mm","bmx"
	Default
		Throw "Unrecognized app source file type:"+ExtractExt(Main)
	End Select

	If FileType(Main)<>FILETYPE_FILE Throw "Unable to open source file '"+Main+"'"
	
	If Not opt_outfile Then
		opt_outfile = StripExt( Main )
	Else
		opt_outfile = RealPath(opt_outfile)
	End If

	' set some useful global variables
	globals.SetVar("BUILDPATH", ExtractDir(opt_outfile))
	globals.SetVar("EXEPATH", ExtractDir(opt_outfile))
	globals.SetVar("OUTFILE", StripDir(StripExt(opt_outfile)))
	
	
	' some more useful globals
	If processor.Platform() = "macos" And opt_apptype="gui" Then
		Local appId$=StripDir( opt_outfile )
		
		globals.SetVar("APPID", appId)
		' modify for bundle
		globals.SetVar("EXEPATH", ExtractDir(opt_outfile+".app/Contents/MacOS/"+appId))
		
		
		' make bundle dirs
		Local exeDir$=opt_outfile+".app",d$

		d=exeDir+"/Contents/MacOS"
		Select FileType( d )
		Case FILETYPE_NONE
			CreateDir d,True
			If FileType( d )<>FILETYPE_DIR
				Throw "Unable to create application directory"
			EndIf
		Case FILETYPE_FILE
			Throw "Unable to create application directory"
		Case FILETYPE_DIR
		End Select
		
		d=exeDir+"/Contents/Resources"
		Select FileType( d )
		Case FILETYPE_NONE
			CreateDir d
			If FileType( d )<>FILETYPE_DIR
				Throw "Unable to create resources directory"
			EndIf
		Case FILETYPE_FILE
			Throw "Unable to create resources directory"
		Case FILETYPE_DIR
		End Select
		
		
	End If
	
	
	' generic pre process
	LoadBMK(ExtractDir(Main) + "/pre.bmk")
	
	' project-specific pre process
	LoadBMK(ExtractDir(Main) + "/" + StripDir( opt_outfile ) + ".bmk")
	
	If processor.Platform() = "win32" Then
		If makelib
			If ExtractExt(opt_outfile).ToLower()<>"dll" opt_outfile:+".dll"
		Else
			If ExtractExt(opt_outfile).ToLower()<>"exe" opt_outfile:+".exe"
		EndIf
	EndIf

	If processor.Platform() = "macos" Then
		If opt_apptype="gui"
	
			'Local appId$=StripDir( opt_outfile )
			Local appId$ = globals.Get("APPID")
	
			Local exeDir$=opt_outfile+".app",d$,t:TStream
	Rem
			d=exeDir+"/Contents/MacOS"
			Select FileType( d )
			Case FILETYPE_NONE
				CreateDir d,True
				If FileType( d )<>FILETYPE_DIR
					Throw "Unable to create application directory"
				EndIf
			Case FILETYPE_FILE
				Throw "Unable to create application directory"
			Case FILETYPE_DIR
			End Select
			
			d=exeDir+"/Contents/Resources"
			Select FileType( d )
			Case FILETYPE_NONE
				CreateDir d
				If FileType( d )<>FILETYPE_DIR
					Throw "Unable to create resources directory"
				EndIf
			Case FILETYPE_FILE
				Throw "Unable to create resources directory"
			Case FILETYPE_DIR
			End Select
	End Rem
			t=WriteStream( exeDir+"/Contents/Info.plist" )
			If Not t Throw "Unable to create Info.plist"
			t.WriteLine "<?xml version=~q1.0~q encoding=~qUTF-8~q?>"
			t.WriteLine "<!DOCTYPE plist PUBLIC ~q-//Apple Computer//DTD PLIST 1.0//EN~q ~qhttp://www.apple.com/DTDs/PropertyList-1.0.dtd~q>"
			t.WriteLine "<plist version=~q1.0~q>"
			t.WriteLine "<dict>"
			t.WriteLine "~t<key>CFBundleExecutable</key>"
			t.WriteLine "~t<string>"+appId+"</string>"
			t.WriteLine "~t<key>CFBundleIconFile</key>"
			t.WriteLine "~t<string>"+appId+"</string>"
			t.WriteLine "~t<key>CFBundlePackageType</key>"
			t.WriteLine "~t<string>APPL</string>"
			If globals.Get("custom_plist") Then
				t.WriteLine "~t" + globals.Get("custom_plist")
			End If
			t.WriteLine "</dict>"
			t.WriteLine "</plist>"
			t.Close
	
			t=WriteStream( exeDir+"/Contents/Resources/"+appId+".icns" )
			If Not t Throw "Unable to create icons"
			Local in:TStream=ReadStream( "incbin::macos.icns" )
			CopyStream in,t
			in.Close
			t.Close
			
			opt_outfile=exeDir+"/Contents/MacOS/"+appId
			
			' Mac GUI exepath is in the bundle...
			'globals.SetVar("EXEPATH", ExtractDir(opt_outfile))
			'globals.SetVar("APPID", appId)
			
		EndIf
	End If
	
	' "android-project" check and copy
	If processor.Platform() = "android" Then
		DeployAndroidProject()
	End If
	
	If processor.Platform() = "emscripten" Then
		If ExtractExt(opt_outfile).ToLower()<>"html" opt_outfile:+".html"
	End If
	
	BeginMake
	
	'MakeApp Main,makelib

	Local buildManager:TBuildManager = New TBuildManager

	buildManager.MakeApp(Main, makelib)
	buildManager.DoBuild(True)

Rem
	If opt_universal

		Local previousOutfile:String = opt_outfile
		processor.ToggleCPU()
		LoadOptions(True) ' reload options for PPC
		opt_outfile :+ "." + processor.CPU()
		BeginMake
		MakeApp Main,makelib
		processor.ToggleCPU()
		LoadOptions(True)
		
		MergeApp opt_outfile, previousOutfile
		
		opt_outfile = previousOutfile
	End If
End Rem
	If opt_standalone
		Local buildScript:String = String(globals.GetRawVar("EXEPATH")) + "/" + StripExt(StripDir( app_main )) + "." + opt_apptype + opt_configmung + processor.CPU() + ".build"
		Local ldScript:String = "$APP_ROOT/ld." + processor.AppDet() + ".txt"
		
		Local stream:TStream = WriteStream(buildScript)
		
		stream.WriteString("echo ~qBuilding " + String(globals.GetRawVar("OUTFILE")) + "...~q~n~n")
		
		stream.WriteString("if [ -z ~q${APP_ROOT}~q ]; then~n")
		stream.WriteString("~tAPP_ROOT=" + String(globals.GetRawVar("EXEPATH")) + "~n")
		stream.WriteString("fi~n~n")

		stream.WriteString("if [ -z ~q${BMX_ROOT}~q ]; then~n")
		stream.WriteString("~tBMX_ROOT=" + BlitzMaxPath() + "~n")
		stream.WriteString("fi~n")
		stream.WriteString("~n~n")
		
		stream.WriteString("cp " + ldScript + " " + ldScript + ".tmp~n")
		
		stream.WriteString("sed -i -- 's=\$BMX_ROOT='$BMX_ROOT'=g' " + ldScript + ".tmp~n")
		stream.WriteString("sed -i -- 's=\$APP_ROOT='$APP_ROOT'=g' " + ldScript + ".tmp~n")
		
		stream.WriteString("~n~n")

		If processor.buildLog Then
			For Local s:String = EachIn processor.buildLog
				stream.WriteString(s + "~n")
			Next
		End If
		
		stream.WriteString("~n")
		stream.WriteString("echo ~qFinished.~q~n")
		
		stream.Close()
		
	End If

	If opt_execute

?Not android
		Print "Executing:"+StripDir( opt_outfile )

		Local cmd$=CQuote( opt_outfile )
		For Local i=1 Until args.length
			cmd:+" "+CQuote( args[i] )
		Next
		
		Sys cmd
?android
		' on android we'll deploy the apk

?

		
	EndIf

End Function

Function ZapModule( args$[] )
	If Len(args)<>2 CmdError "Both module name and outfile required"

	Local modname$=args[0].ToLower()
	Local outfile$=RealPath( args[1] )

	Local stream:TStream=WriteStream( outfile )
	If Not stream Throw "Unable to open output file"
	
	ZapMod modname,stream
	
	stream.Close
End Function

Function UnzapModule( args$[] )
	If Len(args)<>1 CmdError "Expecting 1 argument for unzapmod"
	
	Local infile$=args[0]
	
	Local stream:TStream=ReadStream( infile )
	If Not stream Throw "Unable to open input file"
	
	UnzapMod stream
	
	stream.Close
End Function

Function ListModules( args$[],modid$="" )
	If Len(args)<>0 CmdError
	
	Throw "Todo!"

End Function

Function ModuleStatus( args$[] )
	If Len(args)<>1 CmdError
	
	ListModules Null,args[0]

End Function

Function SyncModules( args$[] )
	If args.length CmdError
	
	If Sys( BlitzMaxPath()+"/bin/syncmods" ) Throw "SyncMods error"
	
End Function

Function RanlibDir( args$[] )
	If args.length<>1 CmdError "Expecting 1 argument for ranlibdir"
	
	Ranlib args[0]

End Function

Function LoadOptions(reload:Int = False)
	If reload Then
		' reset the options to default
		processor.RunCommand("default_cc_opts", Null)
	End If
	LoadBMK(AppDir + "/custom.bmk")
End Function


