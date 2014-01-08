
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

Type TFile

	Field path$,time
	Field itime 'Tommo:added timestamp for included file

	Function Create:TFile( path$,files:TList, time:Int = 0 )
		Local f:TFile=New TFile
		f.path=path
		If time Then
			f.time = time
		Else
			f.time=FileTime(path)
		End If
		If files files.AddFirst f
		Return f
	End Function

End Type

Global make:TMake = New TMake


Type TMake

	Method New()
		LuaRegisterObject Self,"make"
	End Method

	'Method CC(src_path:String)
	'	MakeSrc(RealPath(src_path), True)
	'End Method
	
	Method Make(src_path:String)
		MakeSrc(RealPath(src_path), True)
	End Method

End Type



Global cc_opts$
Global bcc_opts$
Global app_main$
Global app_type$
Global src_files:TList
Global obj_files:TList
Global lnk_files:TList
Global tmp_stack:TList
Global ext_files:TList

Function Push( o:Object )
	tmp_stack.AddLast o
End Function

Function Pop:Object() 
	Return tmp_stack.RemoveLast()
End Function

Function FindFile:TFile( path$,files:TList )
	path=path.ToLower()
	Local f:TFile
	For f=EachIn files
		If f.path.ToLower()=path Return f
	Next
End Function

Function MaxTime( files:TList )
	Local f:TFile,t
	For f=EachIn files
		If f.time>t t=f.time
	Next
	Return t
End Function

Function FilePaths:TList( files:TList )
	Local f:TFile,p:TList=New TList
	For f=EachIn files
		p.AddLast f.path
	Next
	Return p
End Function

Function AddList( src:TList,dst:TList )
	Local t:Object
	For t=EachIn src
		dst.AddLast t
	Next
End Function

Function BeginMake()
	cc_opts=Null
	bcc_opts=Null
	app_main=Null
	src_files=New TList
	obj_files=New TList
	lnk_files=New TList
	tmp_stack=New TList
	ext_files=New TList
	opt_framework=""
End Function

'returns mod interface file
Function MakeMod:TFile( mod_name$, isRequired:Int = False )

	Local path$=ModulePath(mod_name)
	Local id$=ModuleIdent(mod_name)
	Local src_path$=path+"/"+id+".bmx"
	Local arc_path$=path+"/"+id+opt_configmung+processor.CPU()+".a"
	Local iface_path$=path+"/"+id+opt_configmung+processor.CPU()+".i"

	Local skip:String = globals.Get("skip_mod")
	If skip Then
		skip :+ " "
		Local name:String = mod_name + " "
		If skip.tolower().find(name.tolower()) >= 0 Then
			If opt_debug Then
				Print "Skipping " + mod_name + " (d)"
			Else
				Print "Skipping " + mod_name + " (r)"
			End If
			Return
		End If
	End If

	mod_opts = New TModOpt ' BaH

	Local iface:TFile=FindFile( iface_path,src_files )
	If iface Return iface

' commented out, because it throws asserts all the time in debug mode. So,
' either it shouldn't be checking it here, or something else isn't right. I vote the former.
'	Assert Not FindFile( arc_path,lnk_files )

	Local arc:TFile=TFile.Create( arc_path,Null )

	If ((mod_name+".").Find(opt_modfilter)=0 Or (isRequired And opt_modbuild)) And FileType(src_path)=FILETYPE_FILE

		globals.PushAll()
		Push cc_opts
		Push bcc_opts
		Push obj_files

		globals.SetVar("universal", String(opt_universal))
		
		cc_opts=""
		'cc_opts:+" -I"+CQuote(path)
		globals.AddOption("cc_opts", "filepath", "-I"+CQuote(path))
		'cc_opts:+" -I"+CQuote(ModulePath(""))
		globals.AddOption("cc_opts", "modulepath", "-I"+CQuote(ModulePath("")))
		If opt_release Then
			'cc_opts:+" -DNDEBUG"
			globals.AddOption("cc_opts", "nodebug", "-DNDEBUG")
		End If
		If opt_threaded Then
			'cc_opts:+" -DTHREADED"
			globals.AddOption("cc_opts", "threaded", "-DTHREADED")
		End If

		bcc_opts=" -g "+processor.CPU()
		bcc_opts:+" -m "+mod_name$
		If opt_quiet bcc_opts:+" -q"
		If opt_verbose bcc_opts:+" -v"
		If opt_release bcc_opts:+" -r"
		If opt_threaded bcc_opts:+" -h"

		obj_files=New TList
		
		Local force_build:Int = False
		If Not FileType(iface_path) Then
			' if the interface file is missing... we *really* want to force a recompile
			force_build = True
		End If

		MakeSrc src_path,True, force_build, isRequired

?threaded
		processManager.WaitForThreads()
?			
		If MaxTime( obj_files )>arc.time Or (Not isRequired And opt_all)
			If Not opt_quiet Print "Archiving:"+StripDir(arc_path)
			CreateArc arc_path,FilePaths( obj_files )
			arc.time=FileTime(arc_path)
		EndIf

		obj_files=TList(Pop())
		bcc_opts=String(Pop())
		cc_opts=String(Pop())
		globals.PopAll()
	EndIf

	Local src:TFile=MakeSrc( iface_path,False )
	lnk_files.AddFirst arc

	Return src

End Function

'adds to obj_files
'returns input src file
Function MakeSrc:TFile( src_path$,buildit, force_build:Int = False, isRequired:Int = False )
'Print "MakeSrc : " + src_path
	Local src:TFile=FindFile( src_path,src_files )
	If src Return src

	If FileType(src_path)<>FILETYPE_FILE Return

	src=TFile.Create( src_path,src_files )

	Local src_file:TSourceFile=ParseSourceFile( src_path )
	If Not src_file Return
	
	Local main_file=(src_path=app_main)
	
	Local keep_opts:TModOpt = mod_opts ' BaH
	If mod_opts Then
		globals.SetVar("mod_ccopts", String(mod_opts.cc_opts))
	End If
	
	If main_file
		If src_file.framewk
			If opt_framework Throw "Framework already specified on commandline"
			opt_framework=src_file.framewk
			bcc_opts:+" -f "+opt_framework
			MakeMod opt_framework
		Else
			If app_type="bmx"
				For Local t$=EachIn EnumModules()
					If t.Find("brl.")=0 Or t.Find("pub.")=0
						If t<>"brl.blitz" And t<>opt_appstub MakeMod t
					EndIf
				Next
			EndIf
		EndIf
	Else If src_file.framewk
		Throw "Framework must appear in main source file"
	EndIf
	
	mod_opts = keep_opts ' BaH
	If mod_opts Then
		globals.SetVar("mod_ccopts", String(mod_opts.cc_opts))
	End If
	
	globals.PushAll(["LD_OPTS"])
	push cc_opts
	Push CurrentDir()
	
	ChangeDir ExtractDir( src_path )
	
	Local src_ext$=ExtractExt( src_path ).ToLower()
	
	Local src_type:Int = String(RunCommand("source_type", [src_ext])).ToInt()

	If src_type & (SOURCE_BMX | SOURCE_IFACE)
		'incbins
		For Local inc$=EachIn src_file.incbins
			Local time=FileTime( inc )
			'Tommo: 
			If time > src.time Then
				src.time = time
				src.itime = time 'update inc timestamp 
			End If
			'Tommo: End of mod
		Next
		'includes
		For Local inc$=EachIn src_file.includes
			Local inc_ext$=ExtractExt(inc).ToLower()
			If Match(inc_ext,"bmx")
				Local dep:TFile=MakeSrc(RealPath(inc),False)
				If Not dep Continue
				'Tommo:
				If dep.time > src.time  'update inc timestamp 
					src.time = dep.time
					src.itime = dep.time
				EndIf
				'Tommo:End of mod
			Else
				Throw "Unrecognized Include file type: "+inc
			EndIf
		Next

		'module imports
		For Local imp$=EachIn src_file.modimports
			Local dep:TFile=MakeMod(imp, True)
			If Not dep Continue
			'cc_opts:+" -I"+CQuote(ExtractDir(dep.path))
			globals.AddOption("cc_opts", "include_"+imp, "-I"+CQuote(ExtractDir(dep.path)))
			If dep.time>src.time src.time=dep.time
		Next

		mod_opts = keep_opts ' BaH
		If mod_opts Then
			globals.SetVar("mod_ccopts", String(mod_opts.cc_opts))
		End If

		For Local imp$=EachIn mod_opts.ld_opts ' BaH
			ext_files.AddLast TModOpt.setPath(imp, ExtractDir(src_path))
		Next

		'quoted imports
		For Local imp$=EachIn src_file.imports
			If imp[0]=Asc("-")
				ext_files.AddLast imp
				Continue
			EndIf
			Local imp_ext$=ExtractExt(imp).ToLower()
			If Match( imp_ext,"h;hpp;hxx" )
				'cc_opts:+" -I"+CQuote(RealPath(ExtractDir(imp)))
				globals.AddOption("cc_opts", "include_" + imp, "-I"+CQuote(RealPath(ExtractDir(imp))))
			Else If Match( imp_ext,"o;a;lib" )
				ext_files.AddLast RealPath(imp)
			Else If Match( imp_ext,ALL_SRC_EXTS )

				Local dep:TFile=MakeSrc(RealPath(imp),True,,isRequired)

				If Not dep Or Not Match( imp_ext,"bmx;i" ) Continue
				
				If EXPERIMENTAL_SPEEDUP And Match( imp_ext,"bmx" )
					Local p$=ExtractDir( dep.path )+"/.bmx"
					Local i_path$=p+"/"+StripDir( dep.path )+opt_configmung+processor.CPU()+".i2"
					If FileType( i_path )=FILETYPE_FILE
						Local i_time=FileTime( i_path )
						If i_time>src.time src.time=i_time
					Else
						If dep.time>src.time src.time=dep.time
					EndIf
				Else
					If dep.time>src.time src.time=dep.time
				EndIf
				
			Else
				Throw "Unrecognized Import file type: "+imp
			EndIf
		Next
	Else If src_type & (SOURCE_C | SOURCE_HEADER) 'If Match( src_ext,"c;m;cpp;cxx;mm;h;hpp;hxx" )
		For Local inc$=EachIn src_file.includes
			Local inc_ext$=ExtractExt(inc).ToLower()
			Local inc_type:Int = String(RunCommand("source_type", [inc_ext])).ToInt()
			If Not inc_type & SOURCE_HEADER 'Match(inc_ext,"h;hpp;hxx")
				Continue
			EndIf
			Local path$=RealPath(inc)
			Local dep:TFile=MakeSrc(path,False)
			If dep And dep.time>src.time src.time=dep.time
			If Not opt_traceheaders Continue
			Local src$=StripExt(path)+".cpp"
			If FileType(src)<>FILETYPE_FILE
				src=""
			EndIf
			If Not src Continue
			MakeSrc src,True
		Next
	EndIf
	
	If buildit And src_type & (SOURCE_BMX | SOURCE_C | SOURCE_ASM) 'Match( src_ext,"bmx;c;m;cpp;cxx;mm;s;asm;cc" )

		Local p$=ExtractDir( src_path )+"/.bmx"
		
		If opt_dumpbuild Or FileType( p )=FILETYPE_NONE
			CreateDir p
			'Sys "mkdir "+p   'Windows no likey...
		EndIf
		
		If FileType( p )<>FILETYPE_DIR Throw "Unable to create temporary directory"

		Local obj_path$=p+"/"+StripDir( src_path )
		If main_file obj_path:+"."+opt_apptype
		obj_path:+opt_configmung+processor.CPU()+".o"

		Local obj:TFile
		Local time:Int
		
		' Has the source been changed since we last compiled?
		If src.time>FileTime( obj_path ) Or (Not isRequired And opt_all) Or force_build

			' pragmas
			For Local pragma:String = EachIn src_file.pragmas
				processor.ProcessPragma(pragma)
			Next

			If Not opt_quiet Print "Compiling:"+StripDir(src_path)
			Select src_type
			Case SOURCE_BMX
				Local opts$=bcc_opts
				If main_file opts=" -t "+opt_apptype+opts
			
				CompileBMX src_path,obj_path,opts
						
				If EXPERIMENTAL_SPEEDUP
					Local i_path$=StripExt( obj_path )+".i"

					If FileType( i_path )=FILETYPE_FILE
				
						Local i_path2$=i_path+"2",update=True

						'Tommo:
						If Not opt_all And FileType(i_path2) = FILETYPE_FILE ..
								And (src.time = FileTime(src.path) Or src.time = src.itime) ' added checking for Included file timestamp
						'Tommo: end of mod

							If FileSize( i_path )=FileSize( i_path2 )
								Local i_bytes:Byte[]=LoadByteArray( i_path )
								Local i_bytes2:Byte[]=LoadByteArray( i_path2 )
								If i_bytes.length=i_bytes2.length And memcmp_( i_bytes,i_bytes2,i_bytes.length )=0
									update=False
								EndIf
							EndIf
						EndIf
						If update CopyFile i_path,i_path2
					EndIf
				EndIf


			Case SOURCE_C '"c","m","cpp","cxx","mm"
				CompileC src_path,obj_path,cc_opts
?threaded
				time_(Varptr time)
?

			Case SOURCE_ASM '"s","asm"
				Assemble src_path,obj_path
			End Select

		EndIf

		obj = TFile.Create( obj_path,obj_files, time )
		lnk_files.AddFirst obj
	EndIf

	ChangeDir String(Pop())
	cc_opts=String(Pop())
	globals.PopAll()
	
	Return src
	
End Function

Function MakeApp:TFile( Main$,makelib )

	app_main=Main
	
	cc_opts=""

	globals.AddOption("cc_opts", "modulepath", "-I"+CQuote(ModulePath("")))
	If opt_release Then
		globals.AddOption("cc_opts", "nodebug", "-DNDEBUG")
	End If

	globals.SetVar("universal", String(opt_universal))

	bcc_opts=" -g "+processor.CPU()
	If opt_quiet bcc_opts:+" -q"
	If opt_verbose bcc_opts:+" -v"
	If opt_release bcc_opts:+" -r"
	If opt_threaded bcc_opts:+" -h"
	If opt_framework bcc_opts:+" -f "+opt_framework
	
	Local app_ext$=ExtractExt( app_main ).ToLower()
	Local _type:Int = String(RunCommand("source_type", [app_ext])).ToInt()
	Select _type
	Case SOURCE_BMX
		app_type="bmx"
		MakeMod "brl.blitz"
		MakeSrc Main,True
		MakeMod opt_appstub
	Case SOURCE_C '"c","cpp","cxx","mm"
		app_type="c/c++"
		If opt_framework MakeMod opt_framework
		MakeSrc Main,True
	Default
		Throw "Unrecognized app source file extension:"+app_ext
	End Select
	
?threaded
		processManager.WaitForThreads()
?
	If MaxTime( lnk_files )>FileTime( opt_outfile ) Or opt_all
		If Not opt_quiet Print "Linking:"+StripDir( opt_outfile )
		lnk_files=FilePaths( lnk_files )
		AddList ext_files,lnk_files
'globals.Dump()
		LinkApp opt_outfile,lnk_files,makelib, globals.Get("ld_opts")
	EndIf
	
	' post process
	LoadBMK(ExtractDir(Main) + "/post.bmk")
	
	app_main=""

End Function
