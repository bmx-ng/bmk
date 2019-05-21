
SuperStrict

Import "bmk_modutil.bmx"

Global cc_opts$
Global bcc_opts$
Global cpp_opts$
Global c_opts$

Function BeginMake()
	cc_opts=Null
	cpp_opts=Null
	c_opts=Null
	bcc_opts=Null
	app_main=Null
	opt_framework=""
End Function

Function ConfigureAndroidPaths()
	CheckAndroidPaths()
	
	Local toolchain:String
	Local toolchainBin:String
	Local arch:String
	Local abi:String
	
	Select processor.CPU()
		Case "x86"
			toolchain = "x86-"
			toolchainBin = "i686-linux-android-"
			arch = "arch-x86"
			abi = "x86"
		Case "x64"
			toolchain = "x86_64-"
			toolchainBin = "x86_64-linux-android-"
			arch = "arch-x86_64"
			abi = "x86_64"
		Case "arm", "armeabi", "armeabiv7a"
			toolchain = "arm-linux-androideabi-"
			toolchainBin = "arm-linux-androideabi-"
			arch = "arch-arm"
			If processor.CPU() = "armeabi" Then
				abi = "armeabi"
			Else
				abi = "armeabi-v7a"
			End If
		Case "arm64v8a"
			toolchain = "aarch64-linux-android-"
			toolchainBin = "aarch64-linux-android-"
			arch = "arch-arm64"
			abi = "arm64-v8a"
	End Select
	
	Local native:String
?macos
	native = "darwin"
?linux
	native = "linux"
?win32
	native = "windows"
?

	Local toolchainDir:String = processor.Option("android.ndk", "") + "/toolchains/" + ..
			toolchain + processor.Option("android.toolchain.version", "") + "/prebuilt/" + native
	
	' look for 64 bit build first, then x86, then fallback to no architecture (generally on 32-bit dists)
	If FileType(toolchainDir + "-x86_64") = FILETYPE_DIR Then
		toolchainDir :+ "-x86_64"
	Else If FileType(toolchainDir + "-x86") = FILETYPE_DIR Then
		toolchainDir :+ "-x86"
	Else If FileType(toolchainDir) <> FILETYPE_DIR Then
		Throw "Cannot determine toolchain dir for '" + native + "', at '" + toolchainDir + "'"
	End If

	Local exe:String	
?win32
	exe = ".exe"
?
	
	Local gccPath:String = toolchainDir + "/bin/" + toolchainBin + "gcc" + exe
	Local gppPath:String = toolchainDir + "/bin/" + toolchainBin + "g++" + exe
	Local arPath:String = toolchainDir + "/bin/" + toolchainBin + "ar" + exe
	Local libPath:String = toolchainDir + "/lib"

	' check paths
	If Not FileType(RealPath(gccPath)) Then
		Throw "gcc not found at '" + gccPath + "'"
	End If

	If Not FileType(RealPath(gppPath)) Then
		Throw "g++ not found at '" + gppPath + "'"
	End If

	If Not FileType(RealPath(gccPath)) Then
		Throw "ar not found at '" + arPath + "'"
	End If
	
	globals.SetVar("android." + processor.CPU() + ".gcc", gccPath)
	globals.SetVar("android." + processor.CPU() + ".gpp", gppPath)
	globals.SetVar("android." + processor.CPU() + ".ar", arPath)
	globals.SetVar("android." + processor.CPU() + ".lib", "-L" + libPath)

	' platform
	Local platformDir:String = processor.Option("android.ndk", "") + "/platforms/android-" + ..
			processor.Option("android.platform", "") + "/" + arch

	If Not FileType(platformDir) Then
		Throw "Cannot determine platform dir for '" + arch + "' at '" + platformDir + "'"
	End If
	
	' platform sysroot
	globals.SetVar("android.platform.sysroot", "--sysroot " + platformDir)
	globals.AddOption("cc_opts", "android.platform.sysroot", "--sysroot " + platformDir)
	
	' abi
	globals.SetVar("android.abi", abi)
	
	' sdk target
	Local target:String = GetAndroidSDKTarget()

	If Not target Or Not FileType(processor.Option("android.sdk", "") + "/platforms/android-" + target) Then
		Local sdkPath:String = processor.Option("android.sdk.target", "")
		If sdkPath Then
			Throw "Cannot determine SDK target for '" + sdkPath + "'"
		Else
			Throw "Cannot determine SDK target dir. ANDROID_SDK_TARGET or android.sdk.target option is not set, and auto-lookup failed."
		End If
	End If

	globals.SetVar("android.sdk.target", target)

End Function

Function CheckAndroidPaths()
	' check envs and paths
	Local androidHome:String = processor.Option("android.home", getenv_("ANDROID_HOME")).Trim()
	If Not androidHome Then
		Throw "ANDROID_HOME or 'android.home' config option not set"
	End If
		
	putenv_("ANDROID_HOME=" + androidHome)
	globals.SetVar("android.home", androidHome)
	
	Local androidSDK:String = processor.Option("android.sdk", getenv_("ANDROID_SDK")).Trim()
	If Not androidSDK Then
		Throw "ANDROID_SDK or 'android.sdk' config option not set"
	End If
		
	putenv_("ANDROID_SDK=" + androidSDK)
	globals.SetVar("android.sdk", androidSDK)

	Local androidNDK:String = processor.Option("android.ndk", getenv_("ANDROID_NDK")).Trim()
	If Not androidNDK Then
		Throw "ANDROID_NDK or 'android.ndk' config option not set"
	End If
		
	putenv_("ANDROID_NDK=" + androidNDK)
	globals.SetVar("android.ndk", androidNDK)

	Local androidToolchainVersion:String = processor.Option("android.toolchain.version", getenv_("ANDROID_TOOLCHAIN_VERSION")).Trim()
	If Not androidToolchainVersion Then
		Throw "ANDROID_TOOLCHAIN_VERSION or 'android.toolchain.version' config option not set"
	End If
		
	putenv_("ANDROID_TOOLCHAIN_VERSION=" + androidToolchainVersion)
	globals.SetVar("android.toolchain.version", androidToolchainVersion)

	Local androidPlatform:String = processor.Option("android.platform", getenv_("ANDROID_PLATFORM")).Trim()
	If Not androidPlatform Then
		Throw "ANDROID_PLATFORM or 'android.platform' config option not set"
	End If
		
	putenv_("ANDROID_PLATFORM=" + androidPlatform.Trim())
	globals.SetVar("android.platform", androidPlatform)

	Local androidSDKTarget:String = processor.Option("android.sdk.target", getenv_("ANDROID_SDK_TARGET")).Trim()

	' NOTE : if not set, we'll try to determine the actual target later, and fail if required then.
	If androidSDKTarget Then
		putenv_("ANDROID_SDK_TARGET=" + androidSDKTarget)
		globals.SetVar("android.sdk.target", androidSDKTarget)
	End If
		
	Local antHome:String = processor.Option("ant.home", getenv_("ANT_HOME")).Trim()
	If Not antHome Then
		' as a further fallback, we can use the one from resources folder if it exists.
		Local antDir:String = RealPath(BlitzMaxPath() + "/resources/android/apache-ant")
		
		If FileType(antDir) <> FILETYPE_DIR Then
			Throw "ANT_HOME or 'ant.home' config option not set, and resources missing apache-ant."
		Else
			antHome = antDir
			globals.SetVar("ant.home", antHome)
		End If
	End If
		
	putenv_("ANT_HOME=" + antHome)
	globals.SetVar("ant.home", antHome)

?Not win32	
	Local pathSeparator:String = ":"
	Local dirSeparator:String = "/"
?win32
	Local pathSeparator:String = ";"
	Local dirSeparator:String = "\"
?
	Local path:String = getenv_("PATH")
	path = androidSDK + dirSeparator + "platform-tools" + pathSeparator + path
	path = androidSDK + dirSeparator + "tools" + pathSeparator + path
	path = androidNDK + pathSeparator + path
	path = antHome + dirSeparator + "bin" + pathSeparator + path
	putenv_("PATH=" + path)

End Function

Function ConfigureIOSPaths()

	Select processor.CPU() 
		Case "x86", "x64"
			Local path:String = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
			globals.SetVar("ios.sysroot", path)
			globals.SetVar("ios.syslibroot", path)
		Case "armv7", "arm64"
			Local path:String = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
			globals.SetVar("ios.sysroot", path)
			globals.SetVar("ios.syslibroot", path)
	End Select

End Function

Function ConfigureNXPaths()
	CheckNXPaths()
	
	Local toolchainBin:String
	
	Select processor.CPU()
		Case "arm64"
			toolchainBin = "aarch64-none-elf-"
	End Select

	Local toolchainDir:String = processor.Option("nx.devkitpro", "") + "/devkitA64/"
	
	If FileType(RealPath(toolchainDir)) <> FILETYPE_DIR Then
		Throw "Cannot determine toolchain dir for NX, at '" + toolchainDir + "'"
	End If

	Local exe:String	
?win32
	exe = ".exe"
?
	Local gccPath:String = toolchainDir + "/bin/" + toolchainBin + "gcc" + exe
	Local gppPath:String = toolchainDir + "/bin/" + toolchainBin + "g++" + exe
	Local arPath:String = toolchainDir + "/bin/" + toolchainBin + "ar" + exe
	Local libPath:String = toolchainDir + "/lib"

	' check paths
	If Not FileType(RealPath(gccPath)) Then
		Throw "gcc not found at '" + gccPath + "'"
	End If

	If Not FileType(RealPath(gppPath)) Then
		Throw "g++ not found at '" + gppPath + "'"
	End If

	If Not FileType(RealPath(gccPath)) Then
		Throw "ar not found at '" + arPath + "'"
	End If
	
	globals.SetVar("nx." + processor.CPU() + ".gcc", gccPath)
	globals.SetVar("nx." + processor.CPU() + ".gpp", gppPath)
	globals.SetVar("nx." + processor.CPU() + ".ar", arPath)
	globals.SetVar("nx." + processor.CPU() + ".lib", "-L" + libPath)

?Not win32	
	Local pathSeparator:String = ":"
	Local dirSeparator:String = "/"
?win32
	Local pathSeparator:String = ";"
	Local dirSeparator:String = "\"
?
	Local path:String = getenv_("PATH")
	path = toolchainDir + dirSeparator + "bin" + pathSeparator + path
	putenv_("PATH=" + path)

End Function

Function CheckNXPaths()
	' check envs and paths
	Local devkitpro:String = processor.Option("nx.devkitpro", getenv_("DEVKITPRO")).Trim()
	If Not devkitpro Then
		Throw "DEVKITPRO or 'nx.devkitpro' config option not set"
	End If
		
	putenv_("DEVKITPRO=" + devkitpro)
	globals.SetVar("nx.devkitpro", devkitpro)
		
End Function

Type TBuildManager Extends TCallback

	Field sources:TMap = New TMap
	
	Field buildAll:Int
	
	Field framework_mods:TList
	Field app_iface:String
	
	Method New()
		' pre build checks
		If processor.Platform() = "android" Then
			ConfigureAndroidPaths()
		Else If processor.Platform() = "ios" Then
			ConfigureIOSPaths()
		Else If processor.Platform() = "nx" Then
			ConfigureNXPaths()
		End If
		
		If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi" Then
			If opt_nopie Then
				globals.SetVar("nopie", "true")
			End If
		End If
		
		processor.callback = Self
	End Method

	Method MakeMods(mods:TList, rebuild:Int = False)

		For Local m:String = EachIn mods
			If (opt_modfilter And ((m).Find(opt_modfilter) = 0)) Or (Not opt_modfilter) Then
				GetMod(m, rebuild Or buildAll)
			End If
		Next
	End Method

	Method MakeApp(main_path:String, makelib:Int, compileOnly:Int = False)
		app_main = main_path

		Local source:TSourceFile = GetSourceFile(app_main, False, opt_all)

		If Not source Then
			Return
		End If

		Local build_path:String = ExtractDir(main_path) + "/.bmx"

		Local appType:String
		If Not compileOnly Or source.framewk Then
			appType = "." + opt_apptype
		End If
		
		source.obj_path = build_path + "/" + StripDir( main_path ) + appType + opt_configmung + processor.CPU() + ".o"
		source.obj_time = FileTime(source.obj_path)
		source.iface_path = StripExt(source.obj_path) + ".i"
		source.iface_time = FileTime(source.iface_path)
		
		app_iface = source.iface_path
	
		Local cc_opts:String
		source.AddIncludePath(" -I" + CQuote(ModulePath("")))
		If opt_release Then
			cc_opts :+ " -DNDEBUG"
		End If
	
		Local sb:TStringBuffer = New TStringBuffer
		sb.Append(" -g ").Append(processor.CPU())
		If opt_quiet sb.Append(" -q")
		If opt_verbose sb.Append(" -v")
		If opt_release sb.Append(" -r")
		If opt_threaded sb.Append(" -h")
		If opt_framework sb.Append(" -f ").Append(opt_framework)
		If processor.BCCVersion() <> "BlitzMax" Then
			If opt_gdbdebug Then
				sb.Append(" -d")
			End If
			If Not opt_nostrictupgrade Then
				sb.Append(" -s")
			End If
			If opt_warnover Then
				sb.Append(" -w")
			End If
			If opt_musl Then
				sb.Append(" -musl")
			End If
			If makelib Then
				sb.Append(" -makelib")
				If opt_nodef Then
					sb.append(" -nodef")
				End If
				If opt_nohead Then
					sb.append(" -nohead")
				End If
			End If
			If opt_require_override Then
				sb.Append(" -override")
				If opt_override_error Then
					sb.Append(" -overerr")
				End If
			End If
		End If

		source.cc_opts :+ cc_opts
		source.cpp_opts :+ cpp_opts
		source.c_opts :+ c_opts

		source.modimports.AddLast("brl.blitz")
		source.modimports.AddLast(opt_appstub)

		If source.framewk
			If opt_framework Then
				Throw "Framework already specified on commandline"
			End If
			opt_framework = source.framewk
			sb.Append(" -f ").Append(opt_framework)
			source.modimports.AddLast(opt_framework)
		Else
			framework_mods = New TList
			For Local t:String = EachIn EnumModules()
				If t.Find("brl.") = 0 Or t.Find("pub.") = 0 Then
					If t <> "brl.blitz" And t <> opt_appstub Then
						source.modimports.AddLast(t)
						framework_mods.AddLast(t)
					End If
				End If
			Next
		End If
		
		source.bcc_opts = sb.ToString()

		source.SetRequiresBuild(opt_all)

		CalculateDependencies(source, False, opt_all)

		source.bcc_opts :+ " -t " + opt_apptype
	
		' create bmx stages :
		Local gen:TSourceFile
		' for osx x86 on legacy, we need to convert asm
		If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
			Local fasm2as:TSourceFile = CreateFasm2AsStage(source)
			gen = CreateGenStage(fasm2as)
		Else
			gen = CreateGenStage(source)
		End If
		If Not compileOnly Then
			Local link:TSourceFile = CreateLinkStage(gen, STAGE_APP_LINK)
		End If
	End Method
	
	Method DoBuild(makelib:Int, app_build:Int = False)
		Local arc_order:TList = New TList
	
		Local files:TList = New TList
		For Local file:TSourceFile = EachIn sources.Values()
			files.AddLast(file)
		Next

		' get the list of parallelizable batches
		' each list of batches has no outstanding dependencies, and therefore
		' can be compiled in parallel.
		' the last list of batches requires all previous lists to have
		' been compiled.
		Local batches:TList = CalculateBatches(files)
		
		For Local batch:TList = EachIn batches
			Local s:String
			For Local m:TSourceFile = EachIn batch
				' sort archives for app linkage
				If m.modid Then
					Local path:String = m.arc_path
					If processor.Platform() = "ios" Then
						path = m.merge_path
					End If
					
					If Not arc_order.Contains(path) Then
						arc_order.AddFirst(path)
					End If
				End If

				Local build_path:String = ExtractDir(m.path) + "/.bmx"
				
				If Not FileType(build_path) Then
					CreateDir build_path
				End If
				
				If FileType(build_path) <> FILETYPE_DIR Then
					Throw "Unable to create temporary directory"
				End If

				' change dir, so relative commands work as expected
				' (eg. file processing in BMK-scripts called via pragma)
				ChangeDir ExtractDir( m.path )

				' bmx file
				If Match(m.ext, "bmx") Then
				
					Select m.stage
						Case STAGE_GENERATE

							If m.requiresBuild Or (m.time > m.gen_time Or m.iface_time < m.MaxIfaceTime() Or Not m.MaxIfaceTime()) Then

								If Not opt_quiet Then
									Print ShowPct(m.pct) + "Processing:" + StripDir(m.path)
								End If

								' process pragmas
								Local pragma_inDefine:Int, pragma_text:String, pragma_name:String		
								For Local pragma:String = EachIn m.pragmas
									processor.ProcessPragma(pragma, pragma_inDefine, pragma_text, pragma_name)		
								Next
								
								CompileBMX m.path, m.obj_path, m.bcc_opts

							End If

						Case STAGE_FASM2AS

							For Local s:TSourceFile = EachIn m.depsList
								If s.requiresBuild Then
									m.SetRequiresBuild(True)
									Exit
								End If
							Next

							If m.requiresBuild Or (m.time > m.obj_time Or m.iface_time < m.MaxIfaceTime()) Then
							
								m.SetRequiresBuild(True)

								If Not opt_quiet Then
									Print ShowPct(m.pct) + "Converting:" + StripDir(StripExt(m.obj_path) + ".s")
								End If
								
								Fasm2As m.path, m.obj_path
	
								m.asm_time = time_(Null)
					
							End If
							
						Case STAGE_OBJECT

							If m.requiresBuild Or (m.time > m.obj_time Or m.iface_time < m.MaxIfaceTime()) Then
							
								m.SetRequiresBuild(True)
								
								If processor.BCCVersion() <> "BlitzMax" Then

									Local csrc_path:String = StripExt(m.obj_path) + ".c"
									Local cobj_path:String = StripExt(m.obj_path) + ".o"

									If Not opt_quiet Then
										Local s:String = ShowPct(m.pct) + "Compiling:" + StripDir(csrc_path)
										If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
										Print s
									End If
									
									If opt_standalone And opt_boot Then
										processor.PushSource(csrc_path)
										processor.PushSource(StripExt(m.obj_path) + ".h")
									End If

									CompileC csrc_path,cobj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.c_opts
								Else
									' asm compilation

									Local src_path:String = StripExt(m.obj_path) + ".s"
									Local obj_path:String = StripExt(m.obj_path) + ".o"

									If Not opt_quiet Then
										Print ShowPct(m.pct) + "Compiling:" + StripDir(src_path)
									End If

									Assemble src_path, obj_path

								End If
								
								m.obj_time = time_(Null)

							End If
						Case STAGE_LINK

							Local max_obj_time:Int = m.MaxObjTime()

							If max_obj_time > m.arc_time And Not m.dontbuild Then
								Local objs:TList = New TList
								m.GetObjs(objs)
	
								If Not opt_quiet Then
									Local s:String = ShowPct(m.pct) + "Archiving:" + StripDir(m.arc_path)
									If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
									Print s
								End If

								Local at:TArcTask = New TArcTask.Create(m, m.arc_path, objs)
								
								?threaded
									If opt_single Then
										at.CreateArc()
									Else
										processManager.AddTask(TArcTask._CreateArc, at)
									End If
								?Not threaded
									at.CreateArc()
								?
								
							End If
						
						Case STAGE_APP_LINK

							' this probably should never happen.
							' may be a bad module?
							If Not opt_outfile Then
								Throw "Build Error: Did not expect to link against " + m.path
							End If

							' an app!
							Local max_lnk_time:Int = m.MaxLinkTime()
							
							' include settings and icon times in calculation
							If opt_manifest And processor.Platform() = "win32" And opt_apptype="gui" Then
								Local settings:String = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_outfile)) + ".settings"
								If Not FileType(settings) Then
									settings = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_infile)) + ".settings"
								End If
								max_lnk_time = Max(FileTime(settings), max_lnk_time)
								
								Local icon:String = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_outfile)) + ".ico"
								If Not FileType(icon) Then
									icon = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_infile)) + ".ico"
								End If
								max_lnk_time = Max(FileTime(icon), max_lnk_time)
							End If
						
							If max_lnk_time > FileTime(opt_outfile) Or opt_all Then

								' generate manifest for app
								If opt_manifest And processor.Platform() = "win32" And opt_apptype="gui" Then
									processor.RunCommand("make_win32_resource", Null)
									Local res:String = ExtractDir(opt_infile) + "/.bmx/" + StripDir(StripExt(opt_outfile)) + "." + processor.CPU() + ".res.o"
									If Not FileType(res) Then
										res = ExtractDir(opt_infile) + "/.bmx/" + StripDir(StripExt(opt_infile)) + "." + processor.CPU() + ".res.o"
									End If
									If FileType(res) = FILETYPE_FILE Then
										Local s:TSourceFile = New TSourceFile
										s.obj_path = res
										s.stage = STAGE_LINK
										s.exti = SOURCE_RES
										m.depslist.AddLast(s)
									End If
								End If

								If Not opt_quiet Then
									Local s:String = ShowPct(m.pct) + "Linking:" + StripDir(opt_outfile)
									If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
									Print s
								End If

								Local links:TList = New TList
								Local opts:TList = New TList
								m.GetLinks(links, opts)

								For Local arc:String = EachIn arc_order
									links.AddLast(arc)
								Next
								
								For Local o:String = EachIn opts
									links.AddLast(o)
								Next

								LinkApp opt_outfile, links, makelib, globals.Get("ld_opts")

								m.obj_time = time_(Null)
							End If

						Case STAGE_MERGE

							' a module?
							If m.modid Then
								Local max_obj_time:Int = m.MaxObjTime()

								If max_obj_time > m.merge_time And Not m.dontbuild Then
		
									If Not opt_quiet Then
										Print ShowPct(m.pct) + "Merging:" + StripDir(m.merge_path)
									End If

									CreateMergeArc m.merge_path, m.arc_path

									m.merge_time = time_(Null)
									
								End If
							End If
					End Select

				Else If Match(m.ext, "s") Then

					If m.time > m.obj_time Then ' object is older or doesn't exist
						m.SetRequiresBuild(True)
					End If

					If m.requiresBuild Then

						If Not opt_quiet Then
							Local s:String = ShowPct(m.pct) + "Compiling:" + StripDir(m.path)
							If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
							Print s
						End If
					
						If processor.BCCVersion() = "BlitzMax" Then
							Assemble m.path, m.obj_path
						Else
							CompileC m.path, m.obj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.c_opts
						End If
						
					End If
			
				Else
				
					If Not m.dontbuild Then
						' c/c++ source
						If m.time > m.obj_time Then ' object is older or doesn't exist
							m.SetRequiresBuild(True)
						End If
						
						If m.requiresBuild Then
	
							If Not opt_quiet Then
								Local s:String = ShowPct(m.pct) + "Compiling:" + StripDir(m.path)
								If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
								Print s
							End If

							If m.path.EndsWith(".cpp") Or m.path.EndsWith("cc") Then
								CompileC m.path, m.obj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.cpp_opts
							ElseIf m.path.EndsWith(".S") Or m.path.EndsWith("asm") Then
								AssembleNative m.path, m.obj_path
							Else
								CompileC m.path, m.obj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.c_opts
							End If
							
							m.obj_time = time_(Null)
						End If
					End If
				End If
				
			Next

?threaded
		If Not opt_single Then
			processManager.WaitForTasks()
		End If
?

		Next
	
		If app_build Then

			' post process
			LoadBMK(ExtractDir(app_main) + "/post.bmk")

			Select processor.Platform()
			Case "android"
				' create the apk
				
				' copy shared object
				Local androidABI:String = processor.Option("android.abi", "")
				
				Local appId:String = StripDir(StripExt(opt_outfile))
				If opt_debug And opt_outfile.EndsWith(".debug") Then
					appId :+ ".debug"
				End If
				Local buildDir:String = ExtractDir(opt_outfile)
				Local projectDir:String = buildDir + "/android-project-" + appId
		
				Local abiPath:String = projectDir + "/libs/" + androidABI
		
				Local sharedObject:String = "lib" + appId

				sharedObject :+ ".so"
				
				CopyFile(buildDir + "/" + sharedObject, abiPath + "/" + sharedObject)
		
				' build the apk :
				Local antHome:String = processor.Option("ant.home", "").Trim()
				Local cmd:String = "~q" + antHome + "/bin/ant"
?win32
				cmd :+ ".bat"
?
				cmd :+ "~q debug"
				
				Local dir:String = CurrentDir()
				
				ChangeDir(projectDir)
		
				If opt_dumpbuild Then
					Print cmd
				End If
				
				If Sys( cmd ) Then
					Throw "Error creating apk"
				End If
				
				ChangeDir(dir)
		
			'End If
		
			Case "ios"
			
				Local iosSimulator:Int = (processor.CPU() = "x86")
				
				' TODO - other stuff ?
			Case "nx"
			
				' TODO - build nro, nso, psf0 and nacp
				
			End Select
		End If
	End Method
	
	Method CalculateDependencies(source:TSourceFile, isMod:Int = False, rebuildImports:Int = False, isInclude:Int = False)
		If source And Not source.processed Then
			source.processed = True

			For Local m:String = EachIn source.modimports

				Local s:TSourceFile = GetMod(m)

				If s Then
					If Not source.moddeps Then
						source.moddeps = New TMap
					End If
					
					If Not source.moddeps.ValueForKey(m) Then
						source.moddeps.Insert(m, s)
						source.deps.Insert(s.GetSourcePath(), s)
					
						source.AddIncludePath(" -I" + CQuote(ExtractDir(s.path)))
					End If
				End If
			Next

			Local ib:TSourceFile
			If processor.BCCVersion() <> "BlitzMax" And Not source.incbins.IsEmpty() Then
				If source.owner_path Then
					ib = CreateIncBin(source, source.owner_path)
				Else
					ib = CreateIncBin(source, source.path)
				End If
			End If

			For Local f:String = EachIn source.imports
				If f[0] <> Asc("-") Then
					Local path:String = CheckPath(ExtractDir(source.path), f)

					Local s:TSourceFile = GetSourceFile(path, isMod)
					If s Then
	
						If rebuildImports Then
							s.SetRequiresBuild(rebuildImports)
						End If
	
						If Match(s.ext, "bmx") Then
							s.modimports.AddLast("brl.blitz")
							
							' app source files need framework/mod dependencies applied
							If Not isMod Then
								If opt_framework Then
									' add framework as dependency
									s.modimports.AddLast(opt_framework)
								Else
									' add all pub/brl mods as dependency
									If framework_mods Then
										For Local m:String = EachIn framework_mods
											s.modimports.AddLast(m)
										Next
									End If
								End If
							End If
	
							s.bcc_opts = source.bcc_opts
							s.cc_opts :+ source.cc_opts
							s.cpp_opts :+ source.cpp_opts
							s.c_opts :+ source.c_opts
							s.CopyIncludePaths(source.includePaths)
							
							CalculateDependencies(s, isMod, rebuildImports)
							
							' if file that we generate is missing, we need to rebuild
							If processor.BCCVersion() = "BlitzMax" Then
								If Not FileType(StripExt(s.obj_path) + ".s") Then
									s.SetRequiresBuild(True)
								End If
							Else
								If Not FileType(StripExt(s.obj_path) + ".c") Then
									s.SetRequiresBuild(True)
								End If
							End If
							
							Local gen:TSourceFile
							
							' for osx x86 on legacy, we need to convert asm
							If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
								Local fasm2as:TSourceFile = CreateFasm2AsStage(s)
								gen = CreateGenStage(fasm2as)
							Else
								gen = CreateGenStage(s)
							End If
							source.deps.Insert(gen.GetSourcePath(), gen)
	
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(gen)
						Else
							s.cc_opts = source.cc_opts
							s.cpp_opts = source.cpp_opts
							s.c_opts = source.c_opts
							s.CopyIncludePaths(source.includePaths)
							
							source.deps.Insert(s.GetSourcePath(), s)
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(s)
						End If
						
	
					Else

						Local ext:String = ExtractExt(path)
						
						If Match(ext, "h;hpp;hxx") Then ' header?
						
							source.AddIncludePath(" -I" + CQuote(ExtractDir(path)))
							
						Else If Match(ext, "o;a;lib") Then ' object or archive?
						
							Local s:TSourceFile = New TSourceFile
							s.time = FileTime(path)
							s.obj_time = s.time
							s.path = path
							s.obj_path = path
							s.modid = source.modid

							If s.time > source.time Then
								source.time = s.time
							End If
							
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(s)
						End If
						
					End If
				Else
					If Not source.ext_files Then
						source.ext_files = New TList
					End If
					
					source.ext_files.AddLast(f)
					
				End If
			Next
			
			For Local f:String = EachIn source.includes
				Local path:String = CheckPath(ExtractDir(source.path), f)

				Local s:TSourceFile = GetSourceFile(path, isMod, rebuildImports, True)
				If s Then
					s.owner_path = source.path
					
					' calculate included file dependencies
					CalculateDependencies(s, isMod, rebuildImports)

					' update our time to latest included time
					If s.time > source.time Then
						source.time = s.time
					End If
					
					If Not source.depsList Then
						source.depsList = New TList
					End If
					source.depsList.AddLast(s)
				End If
			Next

			For Local f:String = EachIn source.incbins
				Local path:String = CheckPath(ExtractDir(source.path), f)

				Local time:Int = FileTime(path)
				
				' update our time to the latest incbin time
				If time > source.time Then
					source.time = time
				End If
				
			Next
			
			' incbin file
			If ib Then
				' missing source.. generate and compile
				If Not ib.time Then
					ib.SetRequiresBuild(True)
					source.SetRequiresBuild(True)
				End If
				
				' sync timestamps
				If ib.time > source.time Then
					source.time = ib.time
				End If
				
				If ib.obj_time > source.time Then
					source.time = ib.obj_time
				End If
			End If
						
			If source.depsList Then			
				For Local s:TSourceFile = EachIn source.depsList
					If Not Match(s.ext, "bmx") Then
						s.cc_opts = source.cc_opts
						s.cpp_opts = source.cpp_opts
						s.c_opts = source.c_opts
						s.CopyIncludePaths(source.includePaths)
					End If
				Next
			End If
			
		End If

	End Method
	
	Method GetSourceFile:TSourceFile(source_path:String, isMod:Int = False, rebuild:Int = False, isInclude:Int = False)
		Local source:TSourceFile = TSourceFile(sources.ValueForKey(source_path))

		If Not source Then
			source = ParseSourceFile(source_path)
			
			If source Then
				Local ext:String = ExtractExt(source_path)
				If Match(ext, ALL_SRC_EXTS) Then

					If Not isInclude Then

						sources.Insert(source_path, source)

						Local sp:String
						If app_main = source_path Then
							sp = ConcatString(ExtractDir(source_path), "/.bmx/", StripDir(source_path), "." + opt_apptype, opt_configmung, processor.CPU())
						Else
							sp = ConcatString(ExtractDir(source_path), "/.bmx/", StripDir(source_path), opt_configmung, processor.CPU())
						End If
						
						source.obj_path = sp + ".o"
						source.obj_time = FileTime(source.obj_path)
						
						If Match(ext, "bmx") Then
							source.iface_path = sp + ".i"
							source.iface_path2 = source.iface_path + "2"
							source.iface_time = FileTime(source.iface_path2)
							
							' gen file times
							If processor.BCCVersion() <> "BlitzMax" Then
								Local p:String = sp + ".c"
								source.gen_time = FileTime(p)
								If source.gen_time Then
									p = sp + ".h"
									source.gen_time = Min(source.gen_time, FileTime(p))
								End If
							Else
								Local p:String = sp + ".s"
								source.gen_time = FileTime(p)
							End If
						End If
					Else
						source.isInclude = True
					End If
				End If
			End If
		End If
		
		Return source
	End Method

	Method GetISourceFile:TSourceFile(arc_path:String, arc_time:Int, iface_path:String, iface_time:Int, merge_path:String, merge_time:Int)
		Local source:TSourceFile
		
		If processor.Platform() = "ios" Then
			source = TSourceFile(sources.ValueForKey(merge_path))
		Else 
			source = TSourceFile(sources.ValueForKey(arc_path))
		End If

		If Not source Then
			Local iface_path2:String = iface_path + 2
		
			source = ParseISourceFile(iface_path2)
			
			If source Then
				source.arc_path = arc_path
				source.arc_time = arc_time
				source.iface_path = iface_path
				source.iface_path2 = iface_path2
				source.iface_time = iface_time
				source.merge_time = merge_time

				If processor.Platform() = "ios" Then
					sources.Insert(merge_path, source)
				Else
					sources.Insert(arc_path, source)
				End If
			End If
		End If
		
		Return source
	End Method
	
	Method GetMod:TSourceFile(m:String, rebuild:Int = False)

		If (opt_all And ((opt_modfilter And ((m).Find(opt_modfilter) = 0)) Or (Not opt_modfilter)) And Not app_main) Or (app_main And opt_standalone) Then
			rebuild = True
		End If
	
		Local path:String = ModulePath(m)
		Local id:String = ModuleIdent(m)
		
		Local mp:String = ConcatString(path, "/", id, opt_configmung, processor.CPU())

		' get the module interface and lib details
		Local arc_path:String = mp + ".a"
		Local arc_time:Int = FileTime(arc_path)
		Local iface_path:String = mp + ".i"
		Local iface_path2:String = iface_path + "2"
		Local iface_time:Int = FileTime(iface_path2)
		Local merge_path:String
		Local merge_time:Int
		
		If processor.Platform() = "ios" Then
			If processor.CPU() = "x86" Or processor.CPU() = "x64" Then
				merge_path = ConcatString(path, "/", id, opt_configmung, "sim.a")
			Else
				merge_path = ConcatString(path, "/", id, opt_configmung, "dev.a")
			End If
			merge_time = FileTime(merge_path)
		End If

		Local source:TSourceFile
		Local link:TSourceFile

		' do a quick scan only when building apps. For module builds we want to check required modules.
		If arc_time And iface_time And opt_quickscan And app_main Then

			source = GetISourceFile(arc_path, arc_time, iface_path, iface_time, merge_path, merge_time)
			
			If Not source Then
				Return Null
			End If
			
			If Not source.processed Then

				source.modid = m
				source.arc_path = arc_path
				source.arc_time = arc_time
				source.iface_path = iface_path
				source.iface_path2 = iface_path2
				source.iface_time = iface_time
				source.obj_path = arc_path
				source.merge_path = merge_path
				source.merge_time = merge_time
				
				CalculateDependencies(source, True, rebuild)

				source.dontbuild = True
				If processor.Platform() = "ios" Then
					source.stage = STAGE_MERGE
					sources.Insert(source.merge_path, source)
				Else
					source.stage = STAGE_LINK
					sources.Insert(source.arc_path, source)
				End If

			End If
			
			link = source
		Else

			Local src_path:String = ConcatString(path, "/", id, ".bmx")
			source = GetSourceFile(src_path, True, rebuild)
	
			If Not source Then
				Return Null
			End If
			
			' main module file without "Module" line?
			If Not source.modid Then
				Return Null
			End If
		End If
		
		If Not source.processed Then

			source.arc_path = arc_path
			source.arc_time = arc_time
			source.iface_path = iface_path
			source.iface_path2 = iface_path2
			source.iface_time = iface_time
			source.merge_path = merge_path
			source.merge_time = merge_time
			
			Local cc_opts:String
			source.AddIncludePath(" -I" + CQuote(path))
			source.AddIncludePath(" -I" + CQuote(ModulePath("")))
			If opt_release Then
				cc_opts :+ " -DNDEBUG"
			End If
			If opt_threaded Then
				cc_opts :+ " -DTHREADED"
			End If
			
			source.cc_opts = ""
			If source.mod_opts Then
				source.cc_opts :+ source.mod_opts.cc_opts
				source.cpp_opts :+ source.mod_opts.cpp_opts
				source.c_opts :+ source.mod_opts.c_opts
			End If
			source.cc_opts :+ cc_opts
			source.cpp_opts :+ cpp_opts
			source.c_opts :+ c_opts
	
			' Module BCC opts
			Local sb:TStringBuffer = New TStringBuffer
			sb.Append(" -g ").Append(processor.CPU())
			sb.Append(" -m ").Append(m)
			If opt_quiet sb.Append(" -q")
			If opt_verbose sb.Append(" -v")
			If opt_release sb.Append(" -r")
			If opt_threaded sb.Append(" -h")
			If processor.BCCVersion() <> "BlitzMax" Then
				If opt_gdbdebug Then
					sb.Append(" -d")
				End If
				If Not opt_nostrictupgrade Then
					sb.Append(" -s")
				End If
				If opt_warnover Then
					sb.Append(" -w")
				End If
				If opt_musl Then
					sb.Append(" -musl")
				End If
				If opt_require_override Then
					sb.Append(" -override")
					If opt_override_error Then
						sb.Append(" -overerr")
					End If
				End If
			End If
	
			source.bcc_opts = sb.ToString()
			
			source.SetRequiresBuild(rebuild)

			' interface is REQUIRED for compilation
			If Not iface_time Then
				source.SetRequiresBuild(True)
			End If

			If m <> "brl.blitz" Then	
				source.modimports.AddLast("brl.blitz")
			End If
			
			
			CalculateDependencies(source, True, rebuild)
			
			' create bmx stages :
			Local gen:TSourceFile
			
			' for osx x86 on legacy, we need to convert asm
			If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
				Local fasm2as:TSourceFile = CreateFasm2AsStage(source)
				gen = CreateGenStage(fasm2as)
			Else
				gen = CreateGenStage(source)
			End If
			
			If processor.Platform() <> "ios" Then
				link = CreateLinkStage(gen)
			Else
				Local realLink:TSourceFile = CreateLinkStage(gen)
				
				' create a fat archive
				link = CreateMergeStage(realLink)
			End If
		Else
			If processor.Platform() = "ios" Then
				link = TSourceFile(sources.ValueForKey(source.merge_path))
			Else
				link = TSourceFile(sources.ValueForKey(source.arc_path))
			End If
			If Not link Then
				Throw "Can't find link for : " + source.path
			End If
		End If
		
		Return link
	End Method

	Method CreateFasm2AsStage:TSourceFile(source:TSourceFile)
		Local fasm:TSourceFile = New TSourceFile
		
		source.CopyInfo(fasm)
		
		fasm.deps.Insert(source.path, source)
		fasm.stage = STAGE_FASM2AS
		fasm.processed = True
		fasm.depsList = New TList
		fasm.depsList.AddLast(source)		

		sources.Insert(StripExt(fasm.obj_path) + ".s", fasm)

		Return fasm
	End Method
	
	Method CreateGenStage:TSourceFile(source:TSourceFile)
		Local gen:TSourceFile = New TSourceFile
		
		source.CopyInfo(gen)
		
		If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
			gen.deps.Insert(StripExt(source.obj_path) + ".s", source)
		Else
			gen.deps.Insert(source.path, source)
		End If
		
		gen.stage = STAGE_OBJECT
		gen.processed = True
		gen.depsList = New TList
		gen.depsList.AddLast(source)		

		sources.Insert(StripExt(gen.obj_path) + ".c", gen)

		Return gen
	End Method

	Method CreateIncBin:TSourceFile(source:TSourceFile, sourcePath:String)
	
		Local path:String = StripDir(sourcePath) + opt_configmung +  processor.CPU() + ".incbin.c"

		Local ib:TSourceFile = GetSourceFile(path)
		
		If Not ib Then
			ib = New TSourceFile
			ib.path = ExtractDir(sourcePath) + "/.bmx/" + path
			ib.obj_path = StripExt(ib.path) + ".o"
			ib.ext = "c"
			ib.exti = String(processor.RunCommand("source_type", [ib.ext])).ToInt()

			source.imports.AddLast(".bmx/" + StripDir(path) )
		End If
		
		ib.time = FileTime(ib.path)
		ib.obj_time = FileTime(ib.obj_path)

		sources.Insert(ib.path, ib)

		Return ib
	End Method
	
	Method CreateLinkStage:TSourceFile(source:TSourceFile, stage:Int = STAGE_LINK)
		Local link:TSourceFile = New TSourceFile
		
		source.CopyInfo(link)
		
		link.deps.Insert(StripExt(link.obj_path) + ".c", source)
		link.stage = stage
		link.processed = True
		link.depsList = New TList
		link.depsList.AddLast(source)		

		If processor.Platform() = "ios" Then
			sources.Insert(link.obj_path, link)
		Else
			sources.Insert(link.arc_path, link)
		End If

		Return link
	End Method
	
	Method CreateMergeStage:TSourceFile(source:TSourceFile)

		Local merge:TSourceFile = New TSourceFile
		
		source.CopyInfo(merge)
		
		merge.deps.Insert(merge.obj_path, source)
		merge.stage = STAGE_MERGE
		merge.processed = True
		merge.depsList = New TList
		merge.depsList.AddLast(source)		

		sources.Insert(merge.merge_path, merge)

		Return merge
	End Method
	
	Method CalculateBatches:TList(files:TList)

		Local batches:TList = New TList
	
		Local count:Int
		Local instances:TMap = New TMap
		For Local m:TSourceFile = EachIn files
			instances.Insert(m.GetSourcePath(), m)
			count :+ 1
		Next
		
		
		Local dependencies:TMap = New TMap
		For Local m:TSourceFile = EachIn files
			dependencies.Insert(m.GetSourcePath(), m.deps)		
		Next
		
		Local pct:Float = 100.0 / count
		Local total:Float
		Local num:Int
		
		While Not dependencies.IsEmpty()
			
			Local noDeps:TList = New TList
			For Local depName:String = EachIn dependencies.Keys()
				Local dep:TMap = TMap(dependencies.ValueForKey(depName))
				If dep.IsEmpty() Then
					noDeps.AddLast(depName)
				End If
			Next
			
			If noDeps.IsEmpty() Then
				' circular dependency!
				' TODO : dump current list for user to work out?
				Print "REMAINING :"
				For Local depName:String = EachIn dependencies.Keys()
					Print "  " + depName
				Next
				Throw "circular dependency!"
			End If
		
			' remove from dependencies
			For Local name:String = EachIn noDeps
				dependencies.Remove(name)
			Next
			
			For Local dep:TMap = EachIn dependencies.Values()
				For Local name:String = EachIn noDeps
					dep.Remove(name)
				Next
			Next

			Local list:TList = New TList
			For Local name:String = EachIn noDeps
				Local m:TSourceFile = TSourceFile(instances.ValueForKey(name))

				list.AddLast(m)
			Next 

			batches.AddLast(list)
		
		Wend

		' post process batches
		Local suffix:String[]
		Local stage:Int
		For Local i:Int = 0 Until 3
			Select i
				Case 0
					suffix = ["c", "cpp", "cc", "cxx"]
				Case 1
					suffix = ["o"]
					stage = STAGE_LINK
				Case 2
					suffix = ["o"]
					stage = STAGE_APP_LINK
			End Select
			
			Local newList:TList = New TList
		
			For Local list:TList = EachIn batches
	
				For Local f:TSourceFile = EachIn list
				
					Local p:String = f.GetSourcePath()
					
					If Not p.EndsWith("bmx") Then
						For Local s:String = EachIn suffix
							If p.EndsWith(s) Then
								If app_iface And stage Then
									If (stage = STAGE_LINK And app_iface = f.iface_path) Or (stage = STAGE_APP_LINK And app_iface <> f.iface_path) Then
										Continue
									End If
								End If
								newList.AddLast(f)
								list.Remove(f)
								If list.IsEmpty() Then
									batches.Remove(list)
								End If
								' found, no need to loop further
								Exit
							End If
						Next
					End If
				Next
			Next
			
			If Not newList.IsEmpty() Then
				batches.AddLast(newList)
			End If
		Next
		
		For Local list:TList = EachIn batches
			For Local m:TSourceFile = EachIn list
				total :+ pct
				num :+ 1
				If num = count Then
					m.pct = 100
				Else
					m.pct = total
				End If
			Next
		Next

		Return batches
		
	End Method
	
	Method ShowPct:String(pct:Int)
		Local s:String = "["
		Local p:String = String.FromInt(pct)
		Select p.length
			Case 1
				s :+ "  "
			Case 2
				s :+ " "
		End Select
		Return s + p + "%] "
	End Method
	
	Method FixPct:String(pct:String)
		If processor.Platform() = "win32" Then
			Return pct.Replace("%", "%%")
		Else
			Return pct
		End If
	End Method

	Method CheckPath:String(basePath:String, path:String)
		Local p:String = RealPath(basePath + "/" + path)
		If Not FileType(p) Then
			' maybe path is a full path already?
			p = RealPath(path)
			If Not FileType(p) Then
				' meh... fallback to original
				p = RealPath(basePath + "/" + path)
			End If
		End If
		Return p	
	End Method
	
	Method DoCallback(src:String)
		Local update:Int = True

		Local m:TSourceFile = TSourceFile(sources.ValueForKey(src))
		
		If m Then

			If FileType(m.iface_path) = FILETYPE_FILE Then
				' has the interface/api changed since the last build?
				If FileType(m.iface_path2) = FILETYPE_FILE And m.time = FileTime( m.path ) Then

					If FileSize(m.iface_path) = FileSize(m.iface_path2) Then

						Local i_bytes:Byte[] = LoadByteArray(m.iface_path)
						Local i_bytes2:Byte[] = LoadByteArray(m.iface_path2)
?bmxng
						If i_bytes.length = i_bytes2.length And memcmp_( i_bytes, i_bytes2, Size_T(i_bytes.length) )=0 Then
?Not bmxng											
						If i_bytes.length = i_bytes2.length And memcmp_( i_bytes, i_bytes2, i_bytes.length )=0 Then
?
							update = False
						End If
					End If
				End If
				If update Then
					CopyFile m.iface_path, m.iface_path2
				Else If m.iface_time < m.MaxIfaceTime() Then
					SetFileTimeNow(m.iface_path2)
					m.iface_time = time_(Null)
					m.maxIfaceTimeCache = -1
				End If
			End If
	
			If update Then
				m.SetRequiresBuild(True)
				m.iface_time = time_(Null)
				m.maxIfaceTimeCache = -1
				m.gen_time = time_(Null)
			End If
		
		End If

	End Method
	
End Type


Type TArcTask

	Field m:TSourceFile
	Field path:String
	Field oobjs:TList

	Method Create:TArcTask(m:TSourceFile, path$ , oobjs:TList )
		Self.m = m
		Self.path = path
		Self.oobjs = oobjs
		Return Self
	End Method

	Function _CreateArc:Object(data:Object)
		Return TArcTask(data).CreateArc()
	End Function
	
	Method CreateArc:Object()
		DeleteFile path
		Local cmd$,t$
	
		If processor.Platform() = "win32"
			For t$=EachIn oobjs
				If Len(cmd)+Len(t)>1000

					If opt_standalone And Not opt_nolog processor.PushLog(cmd)

					If processor.Sys( cmd )
						DeleteFile path
						Throw "Build Error: Failed to create archive "+path
					EndIf
					cmd=""
				EndIf
				If Not cmd cmd= processor.Option("path_to_ar", processor.MinGWBinPath() + "/ar.exe") + " -r "+CQuote(path)
				cmd:+" "+CQuote(t)
			Next
		End If
		
		If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
			cmd="libtool -o "+CQuote(path)
			For Local t$=EachIn oobjs
				cmd:+" "+CQuote(t)
			Next
		End If
	
		If processor.Platform() = "ios" Then
			Local proc:String = processor.CPU()
			Select proc
				Case "x86"
					proc = "i386"
				Case "x64"
					proc = "x86_64"
			End Select
		
			cmd="libtool -static -arch_only " + proc + " -o "+CQuote(path)
			For Local t$=EachIn oobjs
				cmd:+" "+CQuote(t)
			Next
		End If
		
		If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi" Or processor.Platform() = "android" Or processor.Platform() = "emscripten" Or processor.Platform() = "nx"
			For Local t$=EachIn oobjs
				If Len(cmd)+Len(t)>1000
				
					If opt_standalone And Not opt_nolog processor.PushLog(cmd)

					If processor.Sys( cmd )
						DeleteFile path
						Throw "Build Error: Failed to create archive "+path
					EndIf
					cmd=""
				EndIf
				If processor.Platform() = "emscripten" Then
					If Not cmd cmd=processor.Option(processor.BuildName("ar"), "emar") + " r "+CQuote(path)
				Else
					If Not cmd cmd=processor.Option(processor.BuildName("ar"), "ar") + " -r "+CQuote(path)
				End If
				cmd:+" "+CQuote(t)
			Next
		End If
	
		If cmd
			If opt_standalone And Not opt_nolog processor.PushLog(cmd)

			If processor.Sys( cmd )
				DeleteFile path
				Throw "Build Error: Failed to create archive "+path
			End If
		EndIf
		
		m.arc_time = time_(Null)
		m.obj_time = time_(Null)

	End Method
	
End Type
