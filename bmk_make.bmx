
Strict

Import "bmk_modutil.bmx"

Rem
Experimental speedup hack by Mark!

Should allow you to modify non-interface affecting code without triggering lots of recompiles.

Works by determining whether blah.bmx's .i file physically changes after blah.bmx is compiled.

If not, then anything importing blah.bmx may not need to be recompiled.

Uses a new '.i2' file which is updated only when actual .i file content changes.
End Rem
Global EXPERIMENTAL_SPEEDUP

Local t$=getenv_( "BMK_SPEEDUP" )
If t EXPERIMENTAL_SPEEDUP=True

Global cc_opts$
Global bcc_opts$
Global app_main$
Global app_type$

Function BeginMake()
	cc_opts=Null
	bcc_opts=Null
	app_main=Null
	opt_framework=""
End Function

Function CheckAndroidPaths()
	' check envs and paths
	Local androidHome:String = getenv_("ANDROID_HOME")
	If Not androidHome Then
		androidHome = processor.Option("android.home", "")
		If Not androidHome Then
			Throw "ANDROID_HOME or 'android.home' config option not set"
		End If
		
		putenv_("ANDROID_HOME=" + androidHome.Trim())
	End If
	
	Local androidSDK:String = getenv_("ANDROID_SDK")
	If Not androidSDK Then
		androidSDK = processor.Option("android.sdk", "")
		If Not androidSDK Then
			Throw "ANDROID_SDK or 'android.sdk' config option not set"
		End If
		
		putenv_("ANDROID_SDK=" + androidSDK.Trim())
	End If

	Local androidNDK:String = getenv_("ANDROID_NDK")
	If Not androidNDK Then
		androidNDK = processor.Option("android.ndk", "")
		If Not androidNDK Then
			Throw "ANDROID_NDK or 'android.ndk' config option not set"
		End If
		
		putenv_("ANDROID_NDK=" + androidNDK.Trim())
	End If

	Local androidABI:String = getenv_("ANDROID_ABI")
	If Not androidABI Then
		androidABI = processor.Option(processor.BuildName("abi"), "")
		If Not androidABI Then
			Throw "ANDROID_ABI or '" + processor.BuildName("abi") + "' config option not set"
		End If
		
		putenv_("ANDROID_ABI=" + androidABI.Trim())
	End If

	Local androidToolchainVersion:String = getenv_("ANDROID_TOOLCHAIN_VERSION")
	If Not androidToolchainVersion Then
		androidToolchainVersion = processor.Option("android.toolchain.version", "")
		If Not androidToolchainVersion Then
			Throw "ANDROID_TOOLCHAIN_VERSION or 'android.toolchain.version' config option not set"
		End If
		
		putenv_("ANDROID_TOOLCHAIN_VERSION=" + androidToolchainVersion.Trim())
	End If

	Local antHome:String = getenv_("ANT_HOME")
	If Not antHome Then
		antHome = processor.Option("ant.home", "")
		If Not androidToolchainVersion Then
			Throw "ANT_HOME or 'ant.home' config option not set"
		End If
		
		putenv_("ANT_HOME=" + antHome.Trim())
	End If

?Not win32	
	Local pathSeparator:String = ":"
	Local dirSeparator:String = "/"
?win32
	Local pathSeparator:String = ";"
	Local dirSeparator:String = "\"
?
	Local path:String = getenv_("PATH")
	path = androidSDK.Trim() + dirSeparator + "platform-tools" + pathSeparator + path
	path = androidSDK.Trim() + dirSeparator + "tools" + pathSeparator + path
	path = androidNDK.Trim() + pathSeparator + path
	path = antHome.Trim() + dirSeparator + "bin" + pathSeparator + path
	putenv_("PATH=" + path)

End Function

Type TBuildManager

	Field sources:TMap = New TMap
	
	Field buildAll:Int

	Method MakeMods(mods:TList, rebuild:Int = False)

		For Local m:String = EachIn mods
			If (opt_modfilter And ((m).Find(opt_modfilter) = 0)) Or (Not opt_modfilter) Then
				GetMod(m, rebuild Or buildAll)
			End If
		Next
	End Method

	Method MakeApp(main_path:String, makelib:Int)

		app_main = main_path

		Local source:TSourceFile = GetSourceFile(app_main, False, opt_all)

		If Not source Then
			Return
		End If

		Local build_path:String = ExtractDir(main_path) + "/.bmx"

		source.obj_path = build_path + "/" + StripDir( main_path ) + "." + opt_apptype + opt_configmung + processor.CPU() + ".o"
		source.obj_time = FileTime(source.obj_path)
		source.iface_path = StripExt(source.obj_path) + ".o"
		source.iface_time = FileTime(source.iface_path)
	
		Local cc_opts:String = " -I" + CQuote(ModulePath(""))
		If opt_release Then
			cc_opts :+ " -DNDEBUG"
		End If
	
		Local bcc_opts:String = " -g " + processor.CPU()
		If opt_quiet bcc_opts:+" -q"
		If opt_verbose bcc_opts:+" -v"
		If opt_release bcc_opts:+" -r"
		If opt_threaded bcc_opts:+" -h"
		If opt_framework bcc_opts:+" -f " + opt_framework
		If opt_gdbdebug And processor.BCCVersion() <> "BlitzMax" Then
			bcc_opts:+" -d"
		End If

		source.cc_opts :+ cc_opts

		source.modimports.AddLast("brl.blitz")
		source.modimports.AddLast(opt_appstub)

		If source.framewk
			If opt_framework Then
				Throw "Framework already specified on commandline"
			End If
			opt_framework = source.framewk
			bcc_opts :+" -f " + opt_framework
			source.modimports.AddLast(opt_framework)
		Else
			For Local t:String = EachIn EnumModules()
				If t.Find("brl.") = 0 Or t.Find("pub.") = 0 Then
					If t <> "brl.blitz" And t <> opt_appstub Then
						source.modimports.AddLast(t)
					End If
				End If
			Next
		End If
		
		source.bcc_opts = bcc_opts

		source.requiresBuild = opt_all

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
		Local link:TSourceFile = CreateLinkStage(gen)

	End Method
	
	Method DoBuild(app_build:Int = False)
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
					If Not arc_order.Contains(m.arc_path) Then
						arc_order.AddFirst(m.arc_path)
					End If
				End If

				Local build_path:String = ExtractDir(m.path) + "/.bmx"
				
				If Not FileType(build_path) Then
					CreateDir build_path
				End If
				
				If FileType(build_path) <> FILETYPE_DIR Then
					Throw "Unable to create temporary directory"
				End If

				' bmx file
				If Match(m.ext, "bmx") Then
				
					Select m.stage
						Case STAGE_GENERATE
						
							If m.requiresBuild Or (m.time > m.obj_time Or m.iface_time < m.MaxIfaceTime()) Then
							
								m.requiresBuild = True

								If Not opt_quiet Then
									Print "Processing:" + StripDir(m.path)
								End If
								
								CompileBMX m.path, m.obj_path, m.bcc_opts
	
								m.iface_time = time_(Null)
					
							End If

						Case STAGE_FASM2AS

							For Local s:TSourceFile = EachIn m.depsList
								If s.requiresBuild Then
									m.requiresBuild = True
									Exit
								End If
							Next

							If m.requiresBuild Or (m.time > m.obj_time Or m.iface_time < m.MaxIfaceTime()) Then
							
								m.requiresBuild = True

								If Not opt_quiet Then
									Print "Converting:" + StripDir(StripExt(m.obj_path) + ".s")
								End If
								
								Fasm2As m.path, m.obj_path
	
								m.asm_time = time_(Null)
					
							End If
							
						Case STAGE_OBJECT
						
							If m.requiresBuild Or (m.time > m.obj_time Or m.iface_time < m.MaxIfaceTime()) Then
							
								m.requiresBuild = True
								
								If processor.BCCVersion() <> "BlitzMax" Then

									Local csrc_path:String = StripExt(m.obj_path) + ".c"
									Local cobj_path:String = StripExt(m.obj_path) + ".o"

									If Not opt_quiet Then
										Print "Compiling:" + StripDir(csrc_path)
									End If

									CompileC csrc_path,cobj_path, m.cc_opts
								Else
									' asm compilation

									Local src_path:String = StripExt(m.obj_path) + ".s"
									Local obj_path:String = StripExt(m.obj_path) + ".o"

									If Not opt_quiet Then
										Print "Compiling:" + StripDir(src_path)
									End If

									Assemble src_path, obj_path

								End If
								
								m.obj_time = time_(Null)

							End If
						Case STAGE_LINK

							' a module?
							If m.modid Then
								Local max_obj_time:Int = m.MaxObjTime()

								If max_obj_time > m.arc_time Then
									Local objs:TList = New TList
									m.GetObjs(objs)
		
									If Not opt_quiet Then
										Print "Archiving:" + StripDir(m.arc_path)
									End If

									CreateArc m.arc_path, objs

									m.arc_time = time_(Null)
									m.obj_time = time_(Null)
					
								End If
							Else
								' an app!
								Local max_lnk_time:Int = m.MaxLinkTime()
							
								If max_lnk_time > FileTime(opt_outfile) Or opt_all Then
									If Not opt_quiet Then
										Print "Linking:" + StripDir(opt_outfile)
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

									LinkApp opt_outfile, links, False, globals.Get("ld_opts")

									m.obj_time = time_(Null)
								End If

							End If

					End Select

				Else If Match(m.ext, "s") Then

					If m.time > m.obj_time Then ' object is older or doesn't exist
						m.requiresBuild = True
					End If

					If m.requiresBuild Then
					
						If processor.BCCVersion() = "BlitzMax" Then
							Assemble m.path, m.obj_path
						Else
							CompileC m.path, m.obj_path, m.cc_opts
						End If
						
					End If
			
				Else
					' c/c++ source
					If m.time > m.obj_time Then ' object is older or doesn't exist
						m.requiresBuild = True
					End If
					
					If m.requiresBuild Then

						If Not opt_quiet Then
							Print "Compiling:" + StripDir(m.path)
						End If

						CompileC m.path, m.obj_path, m.cc_opts
						
						m.obj_time = time_(Null)
					End If
				End If
				
			Next

?threaded
		processManager.WaitForThreads()
?

		Next
	
		If app_build Then
		
			' post process
			LoadBMK(ExtractDir(app_main) + "/post.bmk")
		
			If processor.Platform() = "android"
				' create the apk
				
				' setup environment
				CheckAndroidPaths()
				
				' copy shared object
				Local androidABI:String = getenv_("ANDROID_ABI")
				
				Local appId:String = StripDir(StripExt(opt_outfile))
				Local buildDir:String = ExtractDir(opt_outfile)
				Local projectDir:String = buildDir + "/android-project-" + appId
		
				Local abiPath:String = projectDir + "/libs/" + androidABI
		
				Local sharedObject:String = "lib" + appId + ".so"
				
				CopyFile(buildDir + "/" + sharedObject, abiPath + "/" + sharedObject)
		
				' build the apk :
				Local antHome:String = getenv_("ANT_HOME").Trim()
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
		
			End If
			
		
		End If

	End Method
	
	Method CalculateDependencies(source:TSourceFile, isMod:Int = False, rebuildImports:Int = False)
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
					
						source.cc_opts :+ " -I" + CQuote(ExtractDir(s.path))
					End If
				End If
			Next

			For Local f:String = EachIn source.imports
				If f[0] <> Asc("-") Then
					Local path:String = RealPath(ExtractDir(source.path) + "/" + f)

					Local s:TSourceFile = GetSourceFile(path, isMod)
					If s Then
	
						If rebuildImports Then
							s.requiresBuild = rebuildImports
						End If
	
						If Match(s.ext, "bmx") Then
							s.modimports.AddLast("brl.blitz")
	
							s.bcc_opts :+ source.bcc_opts
							s.cc_opts :+ source.cc_opts
							
							CalculateDependencies(s, isMod, rebuildImports)
							
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
							
							source.deps.Insert(s.GetSourcePath(), s)
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(s)
						End If
						
	
					Else ' header?

						Local ext:String = ExtractExt(path)
						If Match(ext, "h;hpp;hxx") Then
							source.cc_opts :+ " -I" + CQuote(ExtractDir(path))
						End If
						
					End If
				Else
					If Not source.ext_files Then
						source.ext_files = New TList
					End If
					
					source.ext_files.AddLast(f)
					
				End If
			Next

			If source.depsList Then			
				For Local s:TSourceFile = EachIn source.depsList
					If Not Match(s.ext, "bmx") Then
						s.cc_opts = source.cc_opts
					End If
				Next
			End If
			
		End If
	End Method
	
	Method GetSourceFile:TSourceFile(source_path:String, isMod:Int = False, rebuild:Int = False)
		Local source:TSourceFile = TSourceFile(sources.ValueForKey(source_path))

		If Not source Then
			source = ParseSourceFile(source_path)
			
			If source Then
				Local ext:String = ExtractExt(source_path)
				If Match(ext, ALL_SRC_EXTS) Then

					sources.Insert(source_path, source)
					
					source.obj_path = ExtractDir(source_path) + "/.bmx/" + StripDir(source_path) + opt_configmung + processor.CPU() + ".o"
					source.obj_time = FileTime(source.obj_path)
					
					If Match(ext, "bmx") Then
						source.iface_path = ExtractDir(source_path) + "/.bmx/" + StripDir(source_path) + opt_configmung + processor.CPU() + ".i"
						source.iface_time = FileTime(source.iface_path)
					End If
				End If
			End If
		End If
		
		Return source
	End Method
	
	Method GetMod:TSourceFile(m:String, rebuild:Int = False)
	
		If opt_all And ((opt_modfilter And ((m).Find(opt_modfilter) = 0)) Or (Not opt_modfilter)) And Not app_main Then
			rebuild = True
		End If
	
		Local path:String = ModulePath(m)
		Local id:String = ModuleIdent(m)
		Local src_path:String = path + "/" + id + ".bmx"
		Local source:TSourceFile = GetSourceFile(src_path, True, rebuild)
		Local link:TSourceFile

		If Not source Then
			Return Null
		End If
		
		If Not source.processed Then

			source.arc_path = path + "/" + id + opt_configmung + processor.CPU() + ".a"
			source.arc_time = FileTime(source.arc_path)
			source.iface_path = path + "/" + id + opt_configmung + processor.CPU() + ".i"
			source.iface_time = FileTime(source.iface_path)
			
			Local cc_opts:String = " -I" + CQuote(path)
			cc_opts :+ " -I" + CQuote(ModulePath(""))
			If opt_release Then
				cc_opts :+ " -DNDEBUG"
			End If
			If opt_threaded Then
				cc_opts :+ " -DTHREADED"
			End If
			
			source.cc_opts = ""
			If source.mod_opts Then
				source.cc_opts :+ source.mod_opts.cc_opts
			End If
			source.cc_opts :+ cc_opts
	
			' Module BCC opts
			Local bcc_opts:String = " -g "+processor.CPU()
			bcc_opts :+ " -m " + m
			If opt_quiet bcc_opts:+" -q"
			If opt_verbose bcc_opts:+" -v"
			If opt_release bcc_opts:+" -r"
			If opt_threaded bcc_opts:+" -h"
			If opt_gdbdebug And processor.BCCVersion() <> "BlitzMax" Then
				bcc_opts:+" -d"
			End If
	
			source.bcc_opts = bcc_opts
			
			source.requiresBuild = rebuild

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
			
			link = CreateLinkStage(gen)
		Else
			link = TSourceFile(sources.ValueForKey(source.arc_path))
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
	
	Method CreateLinkStage:TSourceFile(source:TSourceFile)
		Local link:TSourceFile = New TSourceFile
		
		source.CopyInfo(link)
		
		link.deps.Insert(StripExt(link.obj_path) + ".c", source)
		link.stage = STAGE_LINK
		link.processed = True
		link.depsList = New TList
		link.depsList.AddLast(source)		

		sources.Insert(link.arc_path, link)

		Return link
	End Method
	
	Method CalculateBatches:TList(files:TList)
		Local batches:TList = New TList
	
		Local instances:TMap = New TMap
		For Local m:TSourceFile = EachIn files
			instances.Insert(m.GetSourcePath(), m)
		Next
		
		Local dependencies:TMap = New TMap
		For Local m:TSourceFile = EachIn files
			dependencies.Insert(m.GetSourcePath(), m.deps)
		Next
		
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
				list.AddLast(instances.ValueForKey(name))
			Next 

			batches.AddLast(list)
		
		Wend
		
		Return batches
		
	End Method

End Type
