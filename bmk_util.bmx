SuperStrict

Import "bmk_config.bmx"
Import "bmk_ng.bmx"
Import "file_util.c"
Import "hash.c"

'OS X Nasm doesn't work? Used to produce incorrect reloc offsets - haven't checked for a while 
Const USE_NASM:Int=False

Const CC_WARNINGS:Int=False'True
Const IOS_HAS_MERGE:Int = False

Type TModOpt ' BaH
	Field cc_opts:String = ""
	Field ld_opts:TList = New TList
	Field cpp_opts:String = ""
	Field c_opts:String = ""
	Field asm_opts:String = ""
	
	Method addOption(qval:String, path:String)
		If qval.startswith("CC_OPTS") Then
			cc_opts:+ " " + setPath(ReQuote(qval[qval.find(":") + 1..].Trim()), path)
		ElseIf qval.startswith("CPP_OPTS") Then
			cpp_opts:+ " " + setPath(ReQuote(qval[qval.find(":") + 1..].Trim()), path)
		ElseIf qval.startswith("C_OPTS") Then
			c_opts:+ " " + setPath(ReQuote(qval[qval.find(":") + 1..].Trim()), path)
		ElseIf qval.startswith("ASM_OPTS") Then
			asm_opts:+ " " + setPath(ReQuote(qval[qval.find(":") + 1..].Trim()), path)
		ElseIf qval.startswith("LD_OPTS") Then
			Local opt:String = ReQuote(qval[qval.find(":") + 1..].Trim())
			
			If opt.startsWith("-L") Then
				opt = "-L" + CQuote(opt[2..])
			End If
			ld_opts.addLast opt
		ElseIf qval.startswith("CC_VOPT") Then
			setOption("cc_opts", qval)
		ElseIf qval.startswith("CPP_VOPT") Then
			setOption("cpp_opts", qval)
		ElseIf qval.startswith("C_VOPT") Then
			setOption("c_opts", qval)
		ElseIf qval.startswith("ASM_VOPT") Then
			setOption("asm_opts", qval)
		ElseIf qval.startswith("LD_VOPT") Then
			setOption("ld_opts", qval)
		End If
	End Method

	Function setOption(option:String, qval:String)
		Local opt:String = qval[qval.find(":") + 1..].Trim()
		Local parts:String[] = opt.Split("|")
		If parts.length = 2 Then
			globals.SetOption(option, parts[0].trim(), parts[1].Trim())
		End If
	End Function
	
	Method hasCCopt:Int(value:String)
		Return cc_opts.find(value) >= 0
	End Method

	Method hasCPPopt:Int(value:String)
		Return cpp_opts.find(value) >= 0
	End Method

	Method hasCopt:Int(value:String)
		Return c_opts.find(value) >= 0
	End Method

	Method hasASMopt:Int(value:String)
		Return asm_opts.find(value) >= 0
	End Method

	Method hasLDopt:Int(value:String)
		For Local opt:String = EachIn ld_opts
			If opt.find(value) >= 0 Then
				Return True
			End If
		Next
		Return False
	End Method

	Function setPath:String(value:String, path:String)
		If value.Contains("%PWD%") Then
			If FileType(path) = FILETYPE_FILE Then
				path = ExtractDir(path)
			End If
			Return value.Replace("%PWD%", path)
		End If
		
		' var replace
		Local s:Int = value.Find("%")
		If s >= 0 Then
			Local e:Int = value.Find("%", s + 1)
			If e >= 0 Then
				Local v:String = value[s+1..e]
				value = value[..s] + processor.option(v, "NA") + value[e+1..]
			End If
		End If
		
		Return value
	End Function
	
End Type

Global mod_opts:TModOpt ' BaH

Function Match:Int( ext$,pat$ )
	Return (";"+pat+";").Find( ";"+ext+";" )<>-1
End Function

Function HTTPEsc$( t$ )
	t=t.Replace( " ","%20" )
	Return t
End Function

Function Sys:Int( cmd$ )
	If opt_verbose
		Print cmd
	Else If opt_dumpbuild
		Local p$=cmd
		p=p.Replace( BlitzMaxPath()+"/","./" )
		WriteStdout p+"~n"
		Local t$="mkdir "
		If cmd.StartsWith( t ) And FileType( cmd[t.length..] ) Return 0
	EndIf
	Return system_( cmd )
End Function

Function Ranlib( dir$ )
	'
?MacOS
	If macos_version>=$1040 Return
?
	'
	For Local f$=EachIn LoadDir( dir )
		Local p$=dir+"/"+f
		Select FileType( p )
		Case FILETYPE_DIR
			Ranlib p
		Case FILETYPE_FILE
			If ExtractExt(f).ToLower()="a" Sys "ranlib "+p
		End Select
	Next
End Function

Function Assemble( src$,obj$ )
	processor.RunCommand("assemble", [src, obj])
End Function

Function AssembleNative( src$, obj$, opts:String )
	processor.RunCommand("assembleNative", [src, obj, opts])
End Function

Function Fasm2As( src$,obj$ )
	processor.RunCommand("fasm2as", [src, obj])
End Function

Function CompileC( src$,obj$,opts$ )
	processor.RunCommand("CompileC", [src, obj, opts])
End Function

Function CompileBMX( src$,obj$,opts$ )
	
	If processor.BCCVersion() <> "BlitzMax" Then
		opts :+ " -p " + processor.Platform()
	End If
	
	If opt_standalone opt_nolog = True
	
	processor.RunCommand("CompileBMX", [src, obj, opts])

	If opt_standalone opt_nolog = False

End Function

Function CreateMergeArc( path$ , arc_path:String )
	Local cmd$

	If processor.Platform() = "ios" Then
		Local proc:String = processor.CPU()
		Local opp:String
		Select proc
			Case "x86"
				proc = "i386"
				opp = "x86_64"
			Case "x64"
				proc = "x86_64"
				opp = "i386"
			Case "armv7"
				opp = "arm64"
			Case "arm64"
				opp = "armv7"
		End Select
		
		cmd = "lipo "

		If Not FileType(path) Then
			cmd :+ "-create -arch_blank " + opp + " -arch "
		Else
			cmd :+ CQuote(path)
			cmd :+ " -replace "
		End If
	
		cmd :+ proc + " " + CQuote(arc_path)
	
		cmd :+ " -output " + CQuote(path)
	End If

	If cmd And processor.MultiSys( cmd, path, Null, Null )
		DeleteFile path
		Throw "Build Error: Failed to merge archive " + path
	EndIf

End Function

Function LinkApp( path$,lnk_files:TList,makelib:Int,opts$ )

	If processor.Platform() = "ios" Then

		PackageIOSApp(path, lnk_files, opts)

		Return
	End If

	DeleteFile path

	Local cmd$
	Local files$
	Local tmpfile$=BlitzMaxPath()+"/tmp/ld.tmp"
	
	Local sb:TStringBuffer = New TStringBuffer
	Local fb:TStringBuffer = New TStringBuffer
	
	If opt_standalone tmpfile = String(globals.GetRawVar("EXEPATH")) + "/ld." + processor.AppDet() + ".txt.tmp"
	
	If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
		sb.Append(processor.Option(processor.BuildName("gpp"), "g++"))

		Select processor.CPU()
			Case "ppc" 
				sb.Append(" -arch ppc" )
			Case "x86"
				sb.Append(" -arch i386 -read_only_relocs suppress")
			Case "x64"
				sb.Append(" -arch x86_64")
			Case "arm64"
				sb.Append(" -arch arm64")
		End Select
	
		If processor.Option(processor.BuildName("sysroot"), "") Then
			sb.Append(" -isysroot ").Append(processor.Option(processor.BuildName("sysroot"), ""))
		End If
	
		sb.Append(" -o ").Append(CQuote( path ))
	
		If opt_debug Or opt_gdbdebug Then
			sb.Append(" -g")
		End If

		If processor.BCCVersion() = "BlitzMax" Then
			sb.Append(" ").Append(CQuote("-L" +CQuote( BlitzMaxPath()+"/lib" ) ))
		End If
	
		If Not opt_dumpbuild Then
			sb.Append(" -filelist ").Append(CQuote( tmpfile ))
		End If

		For Local t$=EachIn lnk_files
			If opt_dumpbuild Or (t[..1]="-") Or (t[..1]="`")
				sb.Append(" ").Append(t) 
			Else
				fb.Append(t).Append(Chr(10))
			EndIf
		Next
		sb.Append(" -lSystem -framework CoreServices -framework CoreFoundation")

		If opts Then
			sb.Append(" ").Append(opts)
		End If
		
		If processor.CPU() = "ppc"
			sb.Append(" -lc -lgcc_eh")
		End If
		
	End If
	
	If processor.Platform() = "win32"
		Local ext:String = ""
?win32
		ext = ".exe"
?
		Local version:Int = Int(processor.GCCVersion(True))
		Local usingLD:Int = False

		Local options:TStringBuffer = fb
		If processor.HasClang() Then
			options = sb
		End If

		' always use g++ instead of LD...
		' uncomment if we want to change to only use LD for GCC's < 4.x
		'If version < 40000 Then
		'	usingLD = True
		'End If
		' or we can override in the config...
		If globals.Get("link_with_ld") Or (version >= 40600 And version < 60000) Then
			usingLD = True
		End If
		
		Local blitzMaxLibDir:String = "/lib"
		If processor.CPU()="x64" Then
			blitzMaxLibDir = "/lib64"
		End If

		If usingLD Then
			sb.Append(CQuote(processor.Option("path_to_ld", processor.MinGWBinPath()+ "/ld" + ext))).Append(" -stack 4194304")

			If Not opt_debug And Not opt_gdbdebug Then
				sb.Append(processor.option("strip.debug", " -s "))
			End If

			If opt_apptype="gui" Then
				sb.Append(" -subsystem windows")
			End If
		Else
			Local prefix:String = processor.MinGWExePrefix()
			sb.Append(CQuote(processor.Option("path_to_gpp", processor.MinGWBinPath() + "/" + prefix + "g++" + ext)))

			If Not processor.HasClang() Then
				If version < 60000 Then
					sb.Append(" --stack=4194304")
				Else
					sb.Append(" -Wl,--stack,4194304")
				End If
			End If

			If Not opt_debug And Not opt_gdbdebug Then
				sb.Append(processor.option("strip.debug", " -s "))
			End If
			If opt_apptype="gui"
				If version < 60000 Then
					sb.Append(" --subsystem,windows -mwindows")
				Else
					sb.Append(" -Wl,--subsystem,windows -mwindows")
				End If
			Else
				If Not makelib
					sb.Append(" -mconsole")
				End If
			End If
			
			If opt_threaded Then
				If version < 60000 Then
					sb.Append(" -mthread")
				Else
					sb.Append(" -mthreads")
				End If
			End If
		End If
		If makelib Then
			sb.Append(" -shared")
			If processor.Platform() = "win32" Then
				sb.Append(" -static-libgcc")
			End If
		Else
			sb.Append(" -static")
			
			If opt_gprof Then
				sb.Append(" -pg")
			End If
		End If
		
		sb.Append(" -o ").Append(CQuote( path ))
		If usingLD Then
			If processor.CPU()="x86"
				sb.Append(" ").Append(processor.MinGWLinkPaths()) ' the BlitzMax lib folder
				
				' linking for x86 when using mingw64 binaries
				If processor.HasTarget("x86_64") Then
					sb.Append(" -mi386pe")
				End If
			Else
				sb.Append(" ").Append(processor.MinGWLinkPaths()) ' the BlitzMax lib folder 
			End If

			If globals.Get("path_to_mingw_lib") Then
				sb.Append(" ").Append(CQuote( "-L"+CQuote( RealPath(processor.Option("path_to_mingw_lib", BlitzMaxPath()+"/lib") ) ) ))
			End If
			If globals.Get("path_to_mingw_lib2") Then
				sb.Append(" ").Append(CQuote( "-L"+CQuote( RealPath(processor.Option("path_to_mingw_lib2", BlitzMaxPath()+"/lib") ) ) ))
			End If
			If globals.Get("path_to_mingw_lib3") Then
				sb.Append(" ").Append(CQuote( "-L"+CQuote( RealPath(processor.Option("path_to_mingw_lib3", BlitzMaxPath()+"/lib") ) ) ))
			End If
		End If
	
		If makelib
			Local def$=StripExt(path)+".def"
			Local imp$=StripExt(path)+".a"

			If FileType( def )<>FILETYPE_FILE Then
				Print "Warning: Cannot locate .def file (" + def + "). Exporting ALL symbols."
			Else
				sb.Append(" ").Append(CQuote( def ))
			End If
			
			If version < 60000 Then
				sb.Append(" --out-implib ").Append(CQuote( imp ))
				If usingLD Then
					options.Append(" ").Append(CQuote( RealPath(processor.Option("path_to_mingw_lib", processor.MinGWDLLCrtPath()) + "/dllcrt2.o" ) ))
				End If
			Else
				sb.Append(" -Wl,--out-implib,").Append(CQuote( imp ))
			End If
		Else
			If usingLD
				fb.Append(" ").Append(CQuote( RealPath(processor.Option("path_to_mingw_lib2", processor.MinGWCrtPath()) + "/crtbegin.o" ) ))
				fb.Append(" ").Append(CQuote( RealPath(processor.Option("path_to_mingw_lib", processor.MinGWDLLCrtPath()) + "/crt2.o" ) ))
			End If
		EndIf
	
		Local xpmanifest$
		For Local f$=EachIn lnk_files
			Local t$=CQuote( f )
			If processor.HasClang() Then
				If f.StartsWith("-l") Then
					f = f.Replace(" ", "~n")
				End If
				t = f.Replace("\", "/").Replace(" ", "\ ").Replace("'", "\'")
			End If
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				sb.Append(" ").Append(t)
			Else
				If f.EndsWith( "/win32maxguiex.mod/xpmanifest.o" )
					xpmanifest=t
				Else
					If processor.HasClang() Then
						fb.Append("~n").Append(t)
					Else
						fb.Append(" ").Append(t)
					End If
				EndIf
			EndIf
		Next
		If xpmanifest Then
			If processor.HasClang() Then
				fb.Append("~n").Append(xpmanifest)
			Else
				fb.Append(" ").Append(xpmanifest)
			End If
		End If
		
		sb.Append(" ")
		If processor.HasClang() Then
			sb.Append("@")
		End If
		sb.Append(CQuote( tmpfile ))
	
		options.Append(" -lgdi32 -lwsock32 -lwinmm -ladvapi32")

		' add any user-defined linker options
		options.Append(" ").Append(opts)

		If usingLD
			If opts.Find("stdc++") = -1 Then
				options.Append(" -lstdc++")
			End If

			options.Append(" -lmingwex")
			
		
		' for a native Win32 runtiime of mingw 3.4.5, this needs to appear early.
		'If Not processor.Option("path_to_mingw", "") Then
		options.Append(" -lmingw32")
		'End If

			If opts.Find("gcc") = -1 Then
				options.Append(" -lgcc")
			End If

			' if using 4.8+ or mingw64, we need to link to pthreads
			If version >= 40800 Or processor.HasTarget("x86_64") Or processor.HasClang() Then
				options.Append(" -lwinpthread ")
				
				If processor.CPU()="x86" Then
					options.Append(" -lgcc")
				End If
			End If
			
			options.Append(" -lmoldname -lmsvcrt ")
		End If

		options.Append(" -luser32 -lkernel32 ")

		'If processor.Option("path_to_mingw", "") Then
			' for a non-native Win32 runtime, this needs to appear last.
			' (Actually, also for native gcc 4.x, but I dunno how we'll handle that yet!)
		If usingLD
			options.Append(" -lmingw32 ")
		End If

		' add any user-defined linker options, again - just to cover whether we missed dependencies before.
		options.Append(" ").Append(opts)

		'End If
		
		If Not makelib
			If usingLD
				options.Append(" ").Append(CQuote( processor.Option("path_to_mingw_lib2", processor.MinGWCrtPath()) + "/crtend.o" ))
			End If
		EndIf
		
		If Not processor.HasClang() Then
			fb.Insert(0,"INPUT(").Append(")")
		End If
	End If
	
	If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi" Or processor.Platform() = "haiku"
		sb.Append(processor.Option(processor.BuildName("gpp"), "g++"))
		'cmd:+" -m32 -s -Os -pthread"
		If processor.Platform() <> "raspberrypi" And processor.Platform() <> "haiku" Then
			If processor.CPU() = "x86" Or processor.CPU() = "arm" Then
				sb.Append(" -m32")
			End If
			If processor.CPU() = "x64" Then
				sb.Append(" -m64")
			End If
		End If
		If opt_static Then
			sb.Append(" -static")
		End If
		If processor.Platform() <> "haiku" And Not opt_nopie Then
			sb.Append(" -no-pie -fpie")
		End If
		If opt_gprof Then
			sb.Append(" -pg")
		End If
		
		If processor.Platform() <> "haiku" Then
			sb.Append(" -pthread")
		Else
			sb.Append(" -lpthread")
		End If
		
		sb.Append(" -o ").Append(CQuote( path ))
		sb.Append(" ").Append(CQuote( tmpfile ))
		
		If processor.Platform() <> "haiku" Then
			If processor.CPU() = "x86" Then
				sb.Append(" -L").Append(processor.Option(processor.BuildName("lib32"), "/usr/lib32"))
			End If
			sb.Append(" -L").Append(processor.Option(processor.BuildName("x11lib"), "/usr/X11R6/lib"))
			sb.Append(" -L").Append(processor.Option(processor.BuildName("lib"), "/usr/lib"))
		Else
			sb.Append(" -L").Append(CQuote( "/boot/system/develop/lib" ))
			sb.Append(" -L").Append(CQuote( BlitzMaxPath()+"/lib" ))
		End If
	
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l") Or (t[..1]="`")
				sb.Append(" ").Append(t)
			Else
				fb.Append(" ").Append(t)
			EndIf
		Next
	
		fb.Insert(0,"INPUT(").Append(")")
	End If
	
	If processor.Platform() = "android" Then
		sb.Append(processor.Option(processor.BuildName("gpp"), "g++"))
		
		Local libso:String = StripDir(path)
		sb.Append(" -fPIC -shared ")
		
		' for stlport shared lib
		sb.Append(" -L").Append(AndroidSTLPortDir())
		
		sb.Append(" -Wl,-soname,lib").Append(libso).Append(".so ")
		sb.Append(" -Wl,--export-dynamic -rdynamic ")
		sb.Append(" -o ").Append(CQuote( ExtractDir(path) + "/lib" + libso + ".so" ))
		sb.Append(" ").Append(CQuote( tmpfile ))
		sb.Append(" ").Append(processor.Option("android.platform.sysroot", ""))
		
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				sb.Append(" ").Append(t)
			Else
				fb.Append(" ").Append(t)
			EndIf
		Next
	
		sb.Append(" -Wl,-Bdynamic -lGLESv2 -lGLESv1_CM ")
		' libstlport
		sb.Append(" -lstlport_shared")
		sb.Append(" -llog -ldl -landroid ")
	
		fb.Insert(0,"INPUT(").Append(")")
	End If

	If processor.Platform() = "emscripten"
		sb.Append(processor.Option(processor.BuildName("gpp"), "em++"))

		' cmd:+" -pthread" ' No threading support yet...
		sb.Append(" -o ").Append(CQuote( path ))
		'cmd:+" -filelist "+CQuote( tmpfile )
		
		sb.Append(" ").Append(opts)
		
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			'If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				sb.Append(" ").Append(t)
			'Else
			'	files:+" "+t
			'EndIf
		Next
	
		fb.Insert(0,"INPUT(").Append(")")
	End If
	
	If processor.Platform() = "nx" Then
		sb.Append(processor.Option(processor.BuildName("gpp"), "g++"))
		
		Local libso:String = StripDir(path)
		sb.Append(" -MMD -MP -MF ")
		sb.Append(" -march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIE ")
		
		sb.Append(" -specs=").Append(processor.Option("nx.devkitpro", "")).Append("/libnx/switch.specs")
		sb.Append(" -g")
		'sb.Append(" -Wl,-Map,").Append(StripExt(path)).Append(".map")
		
		sb.Append(" -L").Append(NXLibDir())
	
		sb.Append(" -o ").Append(CQuote( path ))
		sb.Append(" ").Append(CQuote( tmpfile ))
		
		Local endLinks:TList = New TList
		
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l") Or (t[..1]="`")
				sb.Append(" ").Append(t)
			Else
				If t.Contains("appstub") Or t.Contains("blitz.mod") Then
					endLinks.AddLast(t)
					Continue
				End If
				fb.Append(" ").Append(t)
			EndIf
		Next

		fb.Append(" -lnx -lm")
		For Local t:String = EachIn endLinks
			fb.Append(" ").Append(t)
		Next

		fb.Insert(0,"INPUT(").Append(")")
	End If

	Local t$=getenv_( "BMK_LD_OPTS" )
	If t 
		sb.Append(" ").Append(t)
	EndIf
	
	cmd = sb.ToString()
	files = fb.ToString()

	If Not opt_standalone Then
		Local stream:TStream=WriteStream( tmpfile )
		stream.WriteBytes files.ToCString(),files.length
		stream.Close
	End If

	If processor.Sys( cmd ) Throw "Build Error: Failed to link "+path

	If opt_standalone
		Local stream:TStream=WriteStream( StripExt(tmpfile) )
		Local f:String = processor.FixPaths(files)
		stream.WriteBytes f.ToCString(),f.length
		stream.Close
	End If
End Function

Function MergeApp(file1:String, file2:String, outputFile:String)

	If Not opt_quiet Print "[100%] Merging:"+StripDir(file1) + " + " + StripDir(file2) + " > " + StripDir(outputFile)

	Local cmd:String = "lipo -create ~q" + file1 + "~q ~q" + file2 + "~q -output ~q" + outputFile + "~q"
	
	If processor.Sys( cmd ) Throw "Merge Error: Failed to merge " + file1 + " and " + file2 + " into " + outputFile
	
	DeleteFile file1
	DeleteFile file2

End Function

Function DeployAndroidProject()
	Local appId:String = StripDir(StripExt(opt_outfile))
	If opt_debug And opt_outfile.EndsWith(".debug") Then
		appId :+ ".debug"
	End If

	Local buildDir:String = ExtractDir(opt_outfile)

	' eg. android-project-test_01
	Local projectDir:String = buildDir + "/android-project-" + appId '+ "-" + processor.CPU()

	' check for dir
	If Not FileType(projectDir) Then
		' doesn't exist. create it

		Local resourceProject:String = BlitzMaxPath() + "/resources/android/android-project"
		If Not FileType(resourceProject) Then
			Throw "Missing resources folder for Android build : " + resourceProject
		End If
		
		CopyDir(resourceProject, projectDir)
	End If
	
	' check for valid dir
	If FileType(projectDir) <> FILETYPE_DIR Then
		Throw "Error creating project dir '" + projectDir + "'"
	End If
	
	' create assets dir if missing
	Local assetsDir:String = projectDir + "/assets"
	
	If opt_all Then
		' remove assets if we are doing a full build
		DeleteDir(assetsDir, True)
	End If
	
	If FileType(assetsDir) <> FILETYPE_DIR Then
		CreateDir(assetsDir)

		If FileType(assetsDir) <> FILETYPE_DIR Then
			Throw "Error creating assests dir '" + assetsDir + "'"
		End If
	End If

	' create libs/abi dir if missing
	Local abiDir:String = projectDir + "/libs"

	If FileType(abiDir) <> FILETYPE_DIR Then
		CreateDir(abiDir)

		If FileType(abiDir) <> FILETYPE_DIR Then
			Throw "Error creating libs dir '" + abiDir + "'"
		End If
	End If
	
	abiDir :+ "/" + GetAndroidArch()

	If FileType(abiDir) <> FILETYPE_DIR Then
		CreateDir(abiDir)

		If FileType(abiDir) <> FILETYPE_DIR Then
			Throw "Error creating libs abi dir '" + abiDir + "'"
		End If
	End If
	
	' copy stlport
	Local stlportDest:String = abiDir + "/libstlport_shared.so"
	
	If opt_all Or Not FileType(stlportDest) Then
		Local stlportSrc:String = AndroidSTLPortDir() + "/libstlport_shared.so"
		
		CopyFile(stlportSrc, stlportDest)
		
		If Not FileType(stlportDest) Then
			Throw "Error copying libstlport_shared.so from '" + stlportSrc + "'"
		End If
	End If
	
	Local projectSettings:TMap = ParseApplicationIniFile()
	
	Local appPackage:String = String(projectSettings.ValueForKey("app.package"))
	
	Local packagePath:String = projectDir + "/src/" + PathFromPackage(appPackage)
	
	' create the package
	If Not FileType(packagePath) Then
		CreateDir(packagePath, True)
	
		If FileType(packagePath) <> FILETYPE_DIR Then
			Throw "Error creating package '" + packagePath + "'"
		End If
	End If
	
	' copy/create java
	Local gameClassFile:String = packagePath+ "/BlitzMaxApp.java"
	
	If Not FileType(gameClassFile) Then
		CopyFile(projectDir + "/BlitzMaxApp.java", gameClassFile)
		
		If Not FileType(gameClassFile) Then
			Throw "Error creating class file '" + gameClassFile + "'"
		End If
	End If
	
	' merge project data
	'     update AndroidManifest.xml
	MergeFile(projectDir, "AndroidManifest.xml", projectSettings)
	
	'     update BlitzMaxApp.java
	MergeFile(packagePath, "BlitzMaxApp.java", projectSettings)
	
	Local javaApp:String = LoadString( gameClassFile )
	' set the package
	javaApp = ReplaceBlock( javaApp, "app.package","package " + appPackage + ";" )
	' lib imports
	javaApp = ReplaceBlock( javaApp, "lib.imports", GetAndroidLibImports() )
	SaveString(javaApp, gameClassFile)

	'     update strings.xml
	MergeFile(projectDir + "/res/values", "strings.xml", projectSettings)

	'     update build.xml
	MergeFile(projectDir, "build.xml", projectSettings)

	' set the sdk target
	Local projectPropertiesFile:String = projectDir + "/project.properties"
	Local projectProperties:String = LoadString( projectPropertiesFile )
	projectProperties = ReplaceBlock( projectProperties, "sdk.target","target=android-" + processor.option("android.sdk.target", ""), "~n#")
	SaveString(projectProperties, projectPropertiesFile)

	' copy resources to assets
	CopyAndroidResources(buildDir, assetsDir)
End Function

Function GetAndroidLibImports:String()
	Local imports:String
	
	imports = "System.loadLibrary( ~qstlport_shared~q);~n"
	
	' TODO : others imported via project...
	
	Return imports
End Function

Function GetAndroidArch:String()
	Local arch:String
	Select processor.CPU()
		Case "x86"
			arch = "x86"
		Case "x64"
			arch = "x86_64"
		Case "arm"
			arch = "armeabi-v7a"
		Case "armeabi"
			arch = "armeabi"
		Case "armeabiv7a"
			arch = "armeabi-v7a"
		Case "arm64v8a"
			arch = "arm64-v8a"
		Default
			Throw "Not a valid architecture '" + processor.CPU() + "'"
	End Select
	Return arch
End Function

Function AndroidSTLPortDir:String()
	Return processor.Option("android.ndk", "") + "/sources/cxx-stl/stlport/libs/" + GetAndroidArch()
End Function

Function CopyAndroidResources(buildDir:String, assetsDir:String)

	Local paths:String[] = SplitPaths(String(globals.GetRawVar("resource_path")))
	
	If paths Then
		For Local dir:String = EachIn paths
			Local resourceDir:String = buildDir + "/" + dir
			
			If Not FileType(resourceDir) Then
				Print "Warning : Defined resource_path '" + dir + "' not found"
			End If
			
			If FileType(resourceDir) = FILETYPE_DIR Then
				
				CopyDir assetsDir + "/" + dir, resourceDir
				
			End If
				
		Next
	End If

End Function

Function GetAndroidSDKTarget:String()
	Local sdkPath:String = processor.Option("android.sdk", "") + "/platforms"
	Local target:String = processor.Option("android.sdk.target", "")
	
	Local targetPath:String
	
	If target Then
		targetPath = sdkPath + "/android-" + target
		
		If FileType(targetPath) = FILETYPE_DIR Then
			Return target
		End If
		
	End If
	
	' find highest numbered target platform dir
	Local dirs:String[] = LoadDir(sdkPath, True)
	Local high:Int
	
	For Local dir:String = EachIn dirs
	
		Local index:Int = dir.Find("android-")
		
		If index >= 0 Then
			Local value:Int = dir[index + 8..].ToInt()
			high = Max(value, high)
		End If
	
	Next
	
	If high > 0 Then
		Return high
	End If
	
End Function

Function NXLibDir:String()
	Return processor.Option("nx.devkitpro", "") + "/libnx/lib"
End Function

Function NxToolsDir:String()
	Return processor.Option("nx.devkitpro", "") + "/tools/bin"
End Function

Function BuildNxDependencies()
	
	BuildNxNso()
	BuildNxNacp()
	BuildNxNro()
	
End Function

Function BuildNxNso()

	If Not opt_quiet Print "Building:" + StripDir(StripExt(opt_outfile)) + ".nso"

	Local elf2nso:String = NxToolsDir() + "/elf2nso"
?win32
	elf2nso :+ ".exe"
?
	If Not FileType(elf2nso) Then
		Throw "elf2nso tool not present at " + elf2nso
	End If

	Local app:String = StripExt(opt_outfile)
	
	Local cmd:String = elf2nso + " " + CQuote(app + ".elf")
	cmd :+ " " + CQuote(app + ".nso")
	
	Sys(cmd)
End Function

Function BuildNxNacp()

	If Not opt_quiet Print "Building:" + StripDir(StripExt(opt_outfile)) + ".nacp"

	Local nacptool:String = NxToolsDir() + "/nacptool"
?win32
	nacptool :+ ".exe"
?
	If Not FileType(nacptool) Then
		Throw "nacptool tool not present at " + nacptool
	End If

	Local app:String = StripExt(opt_outfile)
	
	Local cmd:String = nacptool + " --create"
	Local name:String = processor.AppSetting("app.name")
	If Not name Then
		name = StripDir(StripExt(opt_outfile))
	End If
	cmd :+ " " + CQuote(name)
	
	Local auth:String = processor.AppSetting("app.company")
	If Not auth Then
		auth = "Unspecified Author"
	End If
	cmd :+ " " + CQuote(auth)
	
	Local ver:String = processor.AppSetting("app.version.name")
	If Not ver Then
		ver = "1.0.0"
	End If
	cmd :+ " " + CQuote(ver)
	
	cmd :+ " " + CQuote(app + ".nacp")

	Sys(cmd)
End Function

Function BuildNxNro()

	If Not opt_quiet Print "Building:" + StripDir(StripExt(opt_outfile)) + ".nro"

	Local elf2nro:String = NxToolsDir() + "/elf2nro"
?win32
	elf2nro :+ ".exe"
?

	If Not FileType(elf2nro) Then
		Throw "elf2nro tool not present at " + elf2nro
	End If

	' get icon
	Local icon:String
	' app.jpg
	' TODO
	' icon.jpg
	' TODO
	' default icon
	If Not icon Then
		icon = processor.Option("nx.devkitpro", "") + "/libnx/default_icon.jpg"
		If Not FileType(icon) Then
			Throw "Default icon not found at " + icon
		End If
	End If
	
	Local app:String = StripExt(opt_outfile)
	
	Local cmd:String = elf2nro + " " + CQuote(app + ".elf")
	cmd :+ " " + CQuote(app + ".nro")
	cmd :+ " --icon=" + CQuote(icon)
	cmd :+ " --nacp=" + CQuote(app + ".nacp")
	
	Local romfsDir:String = ExtractDir(opt_outfile) + "/romfs"
	
	If FileType(romfsDir) = FILETYPE_DIR Then
		cmd :+ " --romfsdir=" + CQuote(romfsDir)
	End If
	
	Sys(cmd)	
End Function

Function PathFromPackage:String(package:String)
	Return package.Replace(".", "/")
End Function

Function MergeFile(dir:String, file:String, settings:TMap)
	Local s:String = LoadString(dir + "/" + file)
	s = ReplaceEnv(s, settings)
	SaveString(s, dir + "/" + file)
End Function

Function ReplaceEnv:String( str:String, settings:TMap )
	Local bits:TStringStack = New TStringStack

	Repeat
		Local i:Int = str.Find( "${" )
		If i=-1 Exit

		Local e:Int = str.Find( "}",i+2 ) 
		If e=-1 Exit
		
		If i>=2 And str[i-2..i] = "//" Then
			bits.AddLast str[..e+1]
			str = str[e+1..]
			Continue
		EndIf
		
		Local t:String = str[i+2..e]

		Local v:String = String(settings.ValueForKey(t))

		If Not v Then
			v = "${" + t + "}"
		End If

		bits.AddLast str[..i]
		bits.AddLast v
		
		str = str[e+1..]
	Forever
	If bits.IsEmpty() Then
		Return str
	End If
	
	bits.AddLast str
	Return bits.Join( "" )
End Function

Function ReplaceBlock:String( Text:String,tag:String,repText:String,mark:String="~n//" )

	'find begin tag
	Local beginTag:String = mark+"${start."+tag+"}"
	Local i:Int = Text.Find( beginTag )
	If i=-1 Throw "Error updating target project - can't find block begin tag '"+tag+"'."
	i :+ beginTag.Length
	While i < Text.Length And Text[i-1]<>10
		i :+ 1
	Wend
	
	'find end tag
	Local endTag:String = mark+"${end."+tag+"}"
	Local i2:Int = Text.Find( endTag,i-1 )
	If i2=-1 Throw "Error updating target project - can't find block end tag '"+tag+"'."
	If Not repText Or repText[repText.Length-1]=10 Then
		i2 :+ 1
	End If
	
	Return Text[..i]+repText+Text[i2..]
End Function

Function SplitPaths:String[](paths:String)
	Local split:String[] = New String[0]
	
	Local inQuote:Int
	Local token:String
	For Local i:Int = 0 Until paths.length
		Local char:Int = paths[i]
		If char = Asc("~q") Then
			inQuote = Not inQuote
		Else If char = Asc(" ") And Not inQuote Then
			token = token.Trim()
			If token Then
				split :+ [token]
			End If
			token = Null
		Else
			token :+ Chr(char)
		End If
	Next
	
	token = token.Trim()
	If token Then
		split :+ [token]
	End If
	
	Return split
End Function

Function PackageIOSApp( path$, lnk_files:TList, opts$ )

	Local templatePath:String = BlitzMaxPath() + "/resources/ios/template"
	
	If Not FileType(templatePath) Then
		Throw "iOS template dir is missing. Expecting it at '" + templatePath + "'"
	End If
	
	Local appId:String = StripDir(StripExt(opt_outfile))
	Local appPath:String = ExtractDir(opt_outfile)
	
	Local appProjectDir:String = appPath + "/" + appId + ".xcodeproj"

	If opt_all Then
		DeleteDir appProjectDir, True
	End If

	If Not FileType(appProjectDir) Then
		CopyDir templatePath + "/project.xcodeproj", appProjectDir
	End If
	
	
	Local projectPath:String = appProjectDir + "/project.pbxproj"
	
	Local uuid:String = "5CABB1EFACE"

	Local fileMap:TFileMap = New TFileMap
	
	For Local f:String = EachIn lnk_files
		Local kind:Int
		Select ExtractExt(f)
			Case "a"
				kind = TFileID.TYPE_ARC
			Case "o"
				kind = TFileID.TYPE_OBJ
			Case "dylib"
				kind = TFileID.TYPE_DYL
		Default
			If f.StartsWith("-l") Then
				kind = TFileID.TYPE_DYL
			End If
			If f.StartsWith("-framework") Then
				kind = TFileID.TYPE_FRM
			End If
		End Select
		fileMap.FileId(f, uuid, TFileMap.BUILD, kind)
	Next
	
	' add project-specific resource paths?
	Local paths:String[] = SplitPaths(String(globals.GetRawVar("resource_path")))
	If paths Then
		For Local f:String = EachIn paths
			fileMap.FileId(f, uuid, TFileMap.BUILD, TFileID.TYPE_DIR)
		Next
	End If

	Local project:String = LoadString(projectPath)

	' clean project
	project = iOSProjectClean(project, uuid)
	
	project = iOSProjectAppendFiles(project, uuid, fileMap)

	project = project.Replace("${PROJECT}", appId)
	project = project.Replace("${PROJECT_STRIPPED}", iOSFixAppId(appId))
	project = project.Replace("${COMPANY_IDENTIFIER}", processor.option("company_identifier", "com.mycompany"))
	project = project.Replace("${TEAM_ID}", processor.option("developer_team_id", "developer_team_id"))
	
	SaveString(project, projectPath)
	
	iOSCopyDefaultFiles(templatePath, appPath)
	
End Function

Function iOSFixAppId:String(id:String)
	id = id.Replace(" ", "") ' no spaces
	id = id.Replace("_", "") ' no underscores
	Return id
End Function

Function iOSCopyDefaultFiles(templatePath:String, appPath:String)

	Local iconSrc:String = templatePath + "/Icon.png"
	Local iconDest:String = appPath + "/Icon.png"
	
	Local defaultSrc:String = templatePath + "/Default.png"
	Local defaultDest:String = appPath + "/Default.png"

	Local default2Src:String = templatePath + "/Default-568h@2x.png"
	Local default2Dest:String = appPath + "/Default-568h@2x.png"

	Local plistSrc:String = templatePath + "/Info.plist"
	Local plistDest:String = appPath + "/Info.plist"
	
	If opt_all Or Not FileType(iconDest) Then
		CopyFile iconSrc, iconDest
	End If

	If opt_all Or Not FileType(defaultDest) Then
		CopyFile defaultSrc, defaultDest
	End If

	If opt_all Or Not FileType(default2Dest) Then
		CopyFile default2Src, default2Dest
	End If

	If opt_all Or Not FileType(plistDest) Then
		CopyFile plistSrc, plistDest
	End If

End Function

Function iOSProjectClean:String(Text:String, uuid:String)
	
	Local stack:TStringStack = New TStringStack
	
	For Local line:String = EachIn Text.Split("~n")
	
		If Not line.Trim().StartsWith(uuid) Then
			stack.AddLast(line)
		End If
	
	Next

	Return stack.Join("~n")
End Function

Function iOSProjectAppendFiles:String(Text:String, uuid:String, fileMap:TFileMap)
	
	Local offset:Int = -1
	
	offset = FindEol(Text, "/* Begin PBXBuildFile section */")
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectBuildFiles(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin PBXFileReference section */")
	If offset  = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectFileRefs(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXFrameworksBuildPhase section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Frameworks */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"files = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectFrameworksBuildPhase(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXResourcesBuildPhase section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Resources */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"files = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectResourcesBuildPhase(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Resources */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectResourcesGroup(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Frameworks */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectFrameworksGroup(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* libs */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectLibsGroup(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Objects */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectObjectsGroup(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin XCBuildConfiguration section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Debug */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"LIBRARY_SEARCH_PATHS = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectLibSearchPaths(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin XCBuildConfiguration section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Release */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"LIBRARY_SEARCH_PATHS = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectLibSearchPaths(uuid, fileMap) + Text[offset..]

	Return Text
End Function

Function iOSProjectBuildFiles:String(uuid:String, fileMap:TFileMap)

	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local id:String = f.id
		Local fileRef:String = fileMap.FileId(path, uuid, TFileMap.REF, f.kind)
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)

		If path.StartsWith("-framework") Then
			name = path[11..]
		End If
		
		Select f.kind
			Case TFileId.TYPE_ARC, TFileId.TYPE_OBJ, TFileId.TYPE_DYL
				stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXBuildFile; fileRef = " + fileRef + "; };"
			Case TFileId.TYPE_DIR
				stack.AddLast "~t~t" + id + " /* " + name + " in Resources */ = {isa = PBXBuildFile; fileRef = " + fileRef + "; };"
			Case TFileId.TYPE_LIB, TFileId.TYPE_FRM
				stack.AddLast "~t~t" + id + " /* " + name + " in Frameworks */ = {isa = PBXBuildFile; fileRef = " + fileRef + "; };"
		End Select
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join("~n")
End Function

Function iOSProjectFileRefs:String(uuid:String, fileMap:TFileMap)

	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Local fid:TFileId = fileMap.GetBuildFileIdForPath(path)
		
		Select fid.kind
			Case TFileId.TYPE_ARC
				stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXFileReference; lastKnownFileType = archive.ar; name = " + name + "; path = ~q" + path + "~q; sourceTree = ~q<absolute>~q; };"
			Case TFileId.TYPE_OBJ
				stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXFileReference; lastKnownFileType = ~qcompiled.mach-o.objfile~q; name = " + name + "; path = ~q" + path + "~q; sourceTree = ~q<absolute>~q; };"
			Case TFileId.TYPE_DYL
				stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXFileReference; lastKnownFileType = ~qcompiled.mach-o.dylib~q; name = " + name + "; path = ~q" + path + "~q; sourceTree = ~q<absolute>~q; };"
			Case TFileId.TYPE_DIR
				stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = folder; path = ~q" + path + "~q; sourceTree = SOURCE_ROOT; };"

			Case TFileId.TYPE_LIB
				name = "lib" + path[2..] + ".a"
				Local found:Int = False
				' path should be provided as a -L...
				For Local p:String = EachIn fileMap.refFiles.Keys()
					If p.StartsWith("-L") Then
						Local libPath:String = p[2..].Replace("~q", "") + "/" + name
						If FileType(libPath) Then
							found = True
							stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXFileReference; lastKnownFileType = archive.ar; name = " + name + "; path = ~q" + libPath + "~q; sourceTree = ~q<absolute>~q; };"
							Exit
						End If
					End If
				Next
				If Not found Then
					Print "WARNING : could not find file for library import '" + path + "'. Maybe LD_OPTS: -L...  was not defined?"
				End If

			Case TFileId.TYPE_FRM
				name = path[11..]
				stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = " + name + ".framework; path = System/Library/Frameworks/" + name + ".framework; sourceTree = SDKROOT; };"
		End Select

	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join("~n")
End Function

Function iOSProjectFrameworksBuildPhase:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local id:String = f.id
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select ExtractExt(name)
			Case "a", "o"
				stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End Select
		
		If path.StartsWith("-l") Then
			name = "lib" + path[2..] + ".a"
			stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End If

		If path.StartsWith("-framework") Then
			name = path[11..]
			stack.AddLast "~t~t~t~t" + id + " /* " + name + ".framework in Frameworks */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectResourcesBuildPhase:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local id:String = f.id
		
		If f.kind = TFileId.TYPE_DIR Then
			stack.AddLast "~t~t~t~t" + id + " /* " + path + " in Resources */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectResourcesGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		
		Local fid:TFileId = fileMap.GetBuildFileIdForPath(path)
		
		If fid.kind = TFileId.TYPE_DIR Then
			stack.AddLast "~t~t~t~t" + id + " /* " + path + " */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectFrameworksGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		
		If path.StartsWith("-framework") Then
			Local name:String = path[11..]
			stack.AddLast "~t~t~t~t" + id + " /* " + name + ".framework in Frameworks */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectLibsGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select ExtractExt(name)
			Case "a"
				stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End Select

		If path.StartsWith("-l") Then
			name = "lib" + path[2..] + ".a"
			stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectObjectsGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select ExtractExt(name)
			Case "o"
				stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End Select
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectLibSearchPaths:String(uuid:String, fileMap:TFileMap)

	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)

		Select ExtractExt(name)
			Case "a"
				stack.AddLast "~t~t~t~t~q" + EscapeSpaces(dir) + "~q"
		End Select
		
		If path.StartsWith("-L") Then
			stack.AddLast("~t~t~t~t~q" + EscapeSpaces(path[2..]) + "~q")
		End If
		
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function MakeUpx()
	If processor.Platform() = "emscripten" Or processor.Platform() = "nx" Or processor.Platform() = "ios" Then
		Return
	End If
	
	Local upx:String = BlitzMaxPath() + "/bin/upx"
?win32
	upx :+ ".exe"
?
	If Not opt_quiet Then
		Print "Packing:" + StripDir(opt_outfile)
	End If
	
	If FileType(upx) <> FILETYPE_FILE Then
		If Not opt_quiet Then
			Print "WARNING: Missing UPX : " + upx
		End If
		Return
	End If
	
	Local cmd:String = upx + " -9 "
	If Not opt_verbose Then
		cmd :+ "-qqq "
	Else
		cmd :+ "-qq "
	End If
	
	cmd :+ CQuote(opt_outfile)
	
	Sys(cmd)
End Function

Function FindEOL:Int(Text:String, substr:String, start:Int = 0)
	Local i:Int = Text.Find(substr, start)
	If i = -1 Then
		Return -1
	End If
	i :+ substr.Length
	Local eol:Int = Text.Find("~n", i) + 1
	If eol = 0 Then
		Return Text.Length
	End If
	Return eol
End Function

Function ConcatString:String(a1:String, a2:String, a3:String, a4:String, a5:String = Null, a6:String = Null, a7:String = Null)
?bmxng
	Local s:TStringBuffer = New TStringBuffer(128)
?Not bmxng
	TStringBuffer.initialCapacity = 128
	Local s:TStringBuffer = New TStringBuffer
?
	s.Append(a1).Append(a2).Append(a3).Append(a4)
	If a5 s.Append(a5)
	If a6 s.Append(a6)
	If a7 s.Append(a7)
	Return s.ToString()
End Function

Type TStringStack Extends TList

	Method Join:String(s:String)
		Local arr:String[] = New String[count()]
		Local index:Int
		For Local t:String = EachIn Self
			arr[index] = t
			index :+ 1
		Next
		
		Return s.Join(arr)
	End Method

End Type

Type TFileId

	Const TYPE_OBJ:Int = 1
	Const TYPE_ARC:Int = 2
	Const TYPE_DYL:Int = 3
	Const TYPE_LIB:Int = 4
	Const TYPE_FRM:Int = 5
	Const TYPE_DIR:Int = 6

	Field path:String
	Field id:String
	
	Field kind:Int
End Type

Type TFileMap

	Const BUILD:Int = 0
	Const REF:Int = 1

	Field lastId:Int = 0

	Field refFiles:TMap = New TMap
	Field buildFiles:TList = New TList
	
	Method FileId:String(path:String, uuid:String, kind:Int = BUILD, fileKind:Int = 0)
	
		Local id:String
		If kind = BUILD Then
			Local f:TFileId = GetBuildFileIdForPath(path)
			If f Then
				id = f.id
			End If
		Else
			id = String(refFiles.ValueForKey(path))
		End If
		
		If id Then 
			Return id
		End If
		
		Local file:String = "0000000000000" + lastId
		
		id = uuid + file[file.length - 13..]
		
		If kind = BUILD Then
			Local f:TFileId = New TFileId
			f.path = path
			f.id = id
			f.kind = fileKind
			buildFiles.AddLast(f)
		Else
			refFiles.Insert(path, id)
		End If
		
		lastId :+ 1
		
		Return id
	End Method
	
	Method GetBuildFileIdForPath:TFileId(path:String)
		For Local f:TFileId = EachIn buildFiles
			If f.path = path Then
				Return f
			End If
		Next
	End Method

End Type

Type TOrderedMap Extends TMap

	Field _keys:TList = New TList

	Method Insert( key:Object,value:Object )
		If Not Contains(key) Then
			_keys.AddLast(key)
		End If
		Super.Insert(key, value)
	End Method
	
	Method Remove:Int( key:Object )
		_keys.Remove(key)
		Return Super.Remove(key)
	End Method

	Method OrderedKeys:TList()
		Return _keys
	End Method

End Type

Type TBootstrapConfig
	Field assets:TBootstrapAsset[]
	Field targets:TBootstrapTarget[]
	
	Method CopyAssets(dest:String)
	
		For Local asset:TBootstrapAsset = EachIn assets
		
			Print "processing " + asset.name
			
			Local basePath:String
			
			Select asset.assetType
				Case "m"
					basePath = "mod/" + asset.name.Replace(".",".mod/")+".mod"
				Case "a"
					basePath = "src/" + asset.name
				Default
					Continue
			End Select

			Local maxBase:String = BlitzMaxPath() + "/" + basePath
			
			If Not FileType(maxBase) Throw "Expected dir missing : " + basePath
			If FileType(maxBase) <> FILETYPE_DIR Throw "Not a dir : " + basePath
			
			Local destBase:String = dest + "/" + basePath
			If Not CreateDir(destBase, True) Throw "Error creating " + basePath
			
			For Local part:String = EachIn asset.parts
				
				If part.StartsWith("*") Then
					' copy files
					FileCopy(maxBase, destBase, part[1..])
				Else
					' copy dir
					Local srcDir:String = maxBase + "/" + part
					Local destDir:String = destBase + "/" + part
					
					DirCopy(srcDir, destDir)
				End If
				
			Next
			
		Next
	
	End Method
	
	Method DirCopy(src:String, dest:String)
		If Not FileType(src) Throw "Source dir not found : " + src
		If Not CreateDir(dest, True) Throw "Unable to create " + dest
		
		If Not CreateDir(dest + "/.bmx") Throw "Unable to create " + dest + "/.bmx"
	
		For Local file:String = EachIn LoadDir( src )
			If file.EndsWith(".bmx") Then
				Continue
			End If
			
			Local filePath:String = src + "/" + file
			
			Select FileType( filePath )
				Case FILETYPE_DIR
					DirCopy( filePath, dest + "/" + file )
				Case FILETYPE_FILE
					CopyFile( filePath, dest + "/" + file )
			End Select
		Next
		
		If LoadDir(dest + "/.bmx").Length = 0 Then
			CreateFile(dest + "/.bmx/.gitkeep")
		End If
	End Method
	
	Method FileCopy(src:String, dest:String, suffix:String)
		
		If Not CreateDir(dest + "/.bmx") Throw "Unable to create " + dest + "/.bmx"
	
		For Local file:String = EachIn LoadDir( src )
			If Not file.EndsWith(suffix) Then
				Continue
			End If
			
			Local filePath:String = src + "/" + file
			
			If FileType(filePath) = FILETYPE_FILE Then
				CopyFile(filePath, dest + "/" + file)
			End If
		Next
	End Method
	
	Method CopySources(dest:String, sources:TList)
		Local bmxRoot:String = "$BMX_ROOT"
		If processor.Platform() = "win32" Then
			bmxRoot = "%BMX_ROOT%"
		End If
	
		For Local path:String = EachIn sources
			Local srcPath:String = path.Replace(bmxRoot, BlitzMaxPath())
			Local destPath:String = path.Replace(bmxRoot, dest)
			
			CreateDir(ExtractDir(destPath), True)
			
			If Not FileType(srcPath) Throw "Not found : " + srcPath
			
			CopyFile(srcPath, destPath)
		Next
	End Method
	
	Method CopyScripts(dest:String, app:TBootstrapAsset)
		dest = dest + "/src/" + app.name
		Local src:String = BlitzMaxPath() + "/src/" + app.name
		
		Local ld:String = "/ld." + processor.AppDet() + ".txt"
		Local build:String = "/" + processor.AppDet() + ".build"
		
		Local ldSrcPath:String = src + ld
		Local buildSrcPath:String = src + build
		
		If Not FileType(ldSrcPath) Throw "ld script missing : " + ldSrcPath
		If Not FileType(buildSrcPath) Throw "build script missing : " + buildSrcPath
		
		CopyFile(ldSrcPath, dest + ld)
		CopyFile(buildSrcPath, dest + build)
	End Method
	
End Type

Type TBootstrapAsset
	Field assetType:String
	Field name:String
	Field parts:String[]
End Type

Type TBootstrapTarget
	Field platform:String
	Field arch:String
End Type

Function LoadBootstrapConfig:TBootstrapConfig()
	Const CONFIG:String = "bin/bootstrap.cfg"
	
	Local file:String = BlitzMaxPath() + "/" + CONFIG
	If Not FileType(file) Then
		Throw CONFIG + " not found"
	End If
	
	Local cfg:String = LoadText(file).Trim()
	If cfg Then
		Local LINES:String[] = cfg.Split("~n")
		Local assets:String[]
		
		For Local line:String = EachIn LINES
			line = line.Trim()
			If line And Not line.StartsWith("#") Then
				assets :+ [line]
			End If
		Next
		
		Local boot:TBootstrapConfig = New TBootstrapConfig
		'boot.assets = New TBootstrapAsset[assets.length]
		
		'Local i:Int
		For Local assetLine:String = EachIn assets
			Local parts:String[] = SplitByWhitespace(assetLine)
			If parts And parts.length > 1 Then
				Select parts[0]
					Case "t"
						Local target:TBootstrapTarget = New TBootstrapTarget
						target.platform = parts[1]
						target.arch = parts[2]
						
						boot.targets :+ [target]
					Default
						Local asset:TBootstrapAsset = New TBootstrapAsset
						asset.assetType = parts[0]
						asset.name = parts[1]
						If parts.length > 2 Then
							asset.parts = parts[2..]
						End If
						
						boot.assets :+ [asset]
						
						'i :+ 1
				End Select
			End If
		Next
		
		Return boot
	Else
		Throw "Could not load " + CONFIG
	End If
	
End Function

Function SplitByWhitespace:String[](input:String)
    Local result:String[] = New String[0]
    Local tempString:String = ""
    
    For Local i:Int = 0 Until input.Length
        Local char:Int = input[i]

		If char = 32 Or char = 9 Or char = 10 Or char = 13 Then

			If tempString.Length > 0 Then
                result :+ [tempString]
                tempString = ""
            End If
        Else
            tempString :+ Chr(char)
        End If
    Next
    
    If tempString.Length > 0 Then
        result :+ [tempString]
    End If
    
    Return result
End Function


Extern
	Function bmx_setfiletimenow(path:String)

	Function bmx_hash_createState:Byte Ptr()
	Function bmx_hash_reset(state:Byte Ptr)
	Function bmx_hash_update(state:Byte Ptr, data:Byte Ptr, length:Int)
	Function bmx_hash_digest:String(state:Byte Ptr)
	Function bmx_hash_free(state:Byte Ptr)
End Extern

Function SetFileTimeNow(path:String)
	bmx_setfiletimenow(path)
End Function

Type TFileHash

	Field statePtr:Byte Ptr
	
	Method Create:TFileHash()
		statePtr = bmx_hash_createState()
		Return Self
	End Method
	
	Method CalculateHash:String(stream:TStream)
		Const BUFFER_SIZE:Int = 8192
	
	
		bmx_hash_reset(statePtr)
		
		Local data:Byte[BUFFER_SIZE]
		
		While True
			Local read:Int = stream.Read(data, BUFFER_SIZE)

			bmx_hash_update(statePtr, data, read)
			
			If read < BUFFER_SIZE Then
				Exit
			End If

		Wend
		
		Return bmx_hash_digest(statePtr)
		
	End Method
	
	Method Free()
		bmx_hash_free(statePtr)
	End Method

End Type

Function CalculateFileHash:String(path:String)
	
	If FileType(path) = FILETYPE_FILE Then

		Local fileHasher:TFileHash = New TFileHash.Create()

		Local stream:TStream = ReadStream(path)
		Local fileHash:String = fileHasher.CalculateHash(stream)
		stream.Close()
		
		fileHasher.Free()
		
		Return fileHash
	End If
	
	Return Null
End Function
