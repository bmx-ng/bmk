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

args=ParseConfigArgs( AppArgs[2..], processor.BCCVersion() = "BlitzMax" )

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
Case "makebootstrap"
	' copy sources
	'   pub ->
	'          stdc, lua, win32, zlib, freeprocess
	'
	'   brl ->
	'          blitz, appstub, stream, filesystem, bank, ramstream, map, linkedlist, system, systemdefault, threads, stringbuilder, standardio
	'
	'   bah ->
	'          libcurl, mbedtls, libarchive, libxml, xz, libiconv
	'
	'
	' create folder in src -> bootstrap
	' create sub folders as per blitzmax layout
	' copy required mod sources
	' copy bmk/bcc/etc sources
	' make standalone's for each app, for all required target platforms.
	opt_boot = True
	MakeBootstrap
Case "compile"
	SetConfigMung
	MakeApplication args,False,True
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
		If processor.BCCVersion() = "BlitzMax" Then
			If opt_threaded opt_configmung:+".mt"
		End If
		opt_configmung="."+opt_configmung+"."+processor.Platform()+"."'+opt_arch
	Else
		opt_debug=True
		opt_release=False
		opt_configmung="debug"
		If processor.BCCVersion() = "BlitzMax" Then
			If opt_threaded opt_configmung:+".mt"
		End If
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
	buildManager.DoBuild(False)

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

Function MakeApplication( args$[],makelib:Int,compileOnly:Int = False )

	If opt_execute And Not compileOnly
		If Len(args)=0 CmdError "Execute requires at least 1 argument"
	Else
		If Len(args)<>1 Then
			If compileOnly Then
				CmdError "Expecting only 1 argument for compile"
			Else
				CmdError "Expecting only 1 argument for makeapp"
			End If
		End If
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
	If processor.Platform() = "macos" And opt_apptype="gui" And Not compileOnly Then
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

	If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
		If opt_apptype="gui" And Not compileOnly

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


	If processor.Platform() = "emscripten" Then
		If ExtractExt(opt_outfile).ToLower()<>"html" opt_outfile:+".html"
	End If

	If processor.Platform() = "nx" Then
		If ExtractExt(opt_outfile).ToLower()<>"elf" opt_outfile:+".elf"
	End If

	BeginMake

	'MakeApp Main,makelib

	Local buildManager:TBuildManager = New TBuildManager

	' "android-project" check and copy
	If processor.Platform() = "android" And Not compileOnly Then
		DeployAndroidProject()
	End If

	buildManager.MakeApp(Main, makelib, compileOnly)
	buildManager.DoBuild(makelib, Not compileOnly)

	If opt_universal And processor.Platform() = "ios" Then

		processor.ToggleCPU()
		LoadOptions(True) ' reload options for PPC

		BeginMake

		Local buildManager:TBuildManager = New TBuildManager
		buildManager.MakeApp(Main, makelib, compileOnly)
		buildManager.DoBuild(False, True)

		processor.ToggleCPU()
		LoadOptions(True)
	End If

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

	If processor.Platform() = "nx" And Not compileOnly Then
		BuildNxDependencies()
	End If

	If opt_standalone And Not compileOnly

		Local suffix:String = ".build"
		If processor.Platform() = "win32" Then
			suffix :+ ".bat"
		End If

		Local buildScript:String = String(globals.GetRawVar("EXEPATH")) + "/" + StripExt(StripDir( app_main )) + "." + opt_apptype + opt_configmung + processor.CPU() + suffix

		Local stream:TStream = WriteStream(buildScript)

		If processor.Platform() <> "win32" Then
			Local ldScript:String = "$APP_ROOT/ld." + processor.AppDet() + ".txt"

			stream.WriteString("echo ~qBuilding " + String(globals.GetRawVar("OUTFILE")) + "...~q~n~n")

			stream.WriteString("if [ -z ~q${APP_ROOT}~q ]; then~n")
			If opt_boot Then
				stream.WriteString("~tAPP_ROOT=`pwd`~n")
			Else
				stream.WriteString("~tAPP_ROOT=" + String(globals.GetRawVar("EXEPATH")) + "~n")
			End If
			stream.WriteString("fi~n~n")

			stream.WriteString("if [ -z ~q${BMX_ROOT}~q ]; then~n")
			If opt_boot Then
				stream.WriteString("~tBMX_ROOT=$(dirname $(dirname `pwd`))~n")
			Else
				stream.WriteString("~tBMX_ROOT=" + BlitzMaxPath() + "~n")
			End If
			stream.WriteString("fi~n")
			stream.WriteString("~n~n")

			stream.WriteString("cp " + ldScript + " " + ldScript + ".tmp~n")

			stream.WriteString("sed -i -- 's=\$BMX_ROOT='$BMX_ROOT'=g' " + ldScript + ".tmp~n")
			stream.WriteString("sed -i -- 's=\$APP_ROOT='$APP_ROOT'=g' " + ldScript + ".tmp~n")

			stream.WriteString("~n~n")
		Else
			Local ldScript:String = "%APP_ROOT%/ld." + processor.AppDet() + ".txt"

			stream.WriteString("@ECHO OFF~n")
			stream.WriteString("SETLOCAL ENABLEEXTENSIONS~n")
			stream.WriteString("SET PARENT=%~~dp0~n~n")

			stream.WriteString("echo Building " + String(globals.GetRawVar("OUTFILE")) + "...~n")

			stream.WriteString("If Not DEFINED APP_ROOT (~n")
			If opt_boot Then
				stream.WriteString("~tSET APP_ROOT=%PARENT%~n")
			Else
				stream.WriteString("~tSET APP_ROOT=" + String(globals.GetRawVar("EXEPATH")) + "~n")
			End If
			stream.WriteString(")~n~n")

			stream.WriteString("If Not DEFINED BMX_ROOT (~n")
			If opt_boot Then
				stream.WriteString("~tSET BMX_ROOT=%PARENT%..\..~n")
			Else
				stream.WriteString("~tSET BMX_ROOT=" + BlitzMaxPath() + "~n")
			End If
			stream.WriteString(")~n~n")

			stream.WriteString("set PATH=%PATH%;" + processor.FixPaths(processor.MinGWBinPath()) + "~n~n");

			stream.WriteString("%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe -Command ~q((get-content \~q" + ldScript + "\~q) -replace '%%BMX_ROOT%%','%BMX_ROOT%') | set-content \~q" + ldScript + ".tmp\~q~q~n~n")
		End If

		If processor.buildLog Then
			For Local s:String = EachIn processor.buildLog
				stream.WriteString(s + "~n")
			Next
		End If

		If processor.Platform() <> "win32" Then
			stream.WriteString("unset APP_ROOT~n")
			stream.WriteString("~necho ~qFinished.~q~n")

		Else
			stream.WriteString("echo Finished.~n")
			stream.WriteString("ENDLOCAL~n")
			stream.WriteString("Goto :Eof~n")
		End If

		stream.Close()

	End If

	If opt_execute And Not compileOnly

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

Function MakeBootstrap()

	Local config:TBootstrapConfig = LoadBootstrapConfig()

	Local bootstrapPath:String = BlitzMaxPath() + "/dist/bootstrap"

	If Not CreateDir(bootstrapPath, True) Throw "Error creating bootstrap folder"

	If Not CreateDir(bootstrapPath + "/bin") Throw "Error creating boostrap/bin folder"
	If Not CreateDir(bootstrapPath + "/mod") Throw "Error creating boostrap/mod folder"
	If Not CreateDir(bootstrapPath + "/src") Throw "Error creating boostrap/src folder"

	config.CopyAssets(bootstrapPath)

	opt_release = True

	For Local target:TBootstrapTarget = EachIn config.targets
		For Local app:TBootstrapAsset = EachIn config.assets
			If app.assetType <> "a" Then
				Continue
			End If

			Local appPath:String = BlitzMaxPath() + "/src/" + app.name + "/" + app.name + ".bmx"

			If Not FileType(appPath) Throw "App not found : " + app.name

			opt_outfile = Null
			opt_standalone = True
			opt_warnover = True

			opt_target_platform = target.platform
			opt_arch = target.arch

			Print "Generating " + app.name + " : " + target.platform + "/" + target.arch

			Local args:String[] = [appPath]

			processor.Reset()

			SetConfigMung
			LoadOptions(True)
			MakeApplication args,False

			config.CopySources(bootstrapPath, processor.sourceList)
			config.CopyScripts(bootstrapPath, app)
		Next
	Next

End Function

