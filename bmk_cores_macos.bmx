SuperStrict

?Not bmxng
Import "macos/*.h"
Import "macos/macos.m"
Import "macos/NSProcessInfo_PECocoaBackports.m"
?

Extern
?x64
	Function sysctlbyname:Int(name:Byte Ptr, count:Int Ptr, size:Long Ptr, a:Byte Ptr, b:Int)
?Not x64
	Function sysctlbyname:Int(name:Byte Ptr, count:Int Ptr, size:Int Ptr, a:Byte Ptr, b:Int)
?
End Extern

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
?x64
		Local l:Long = 4
?Not x64
		Local l:Int = 4
?
		sysctlbyname("hw.ncpu", Varptr count, Varptr l,Null,0)
	End If

	Return count
End Function

