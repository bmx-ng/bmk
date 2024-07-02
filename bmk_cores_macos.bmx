SuperStrict

?Not bmxng
Import "macos/*.h"
Import "macos/macos.m"
Import "macos/NSProcessInfo_PECocoaBackports.m"
?

Extern
?bmxng
	Function sysctlbyname:Int(name:Byte Ptr, count:Int Ptr, size:Size_T Ptr, a:Byte Ptr, b:Size_T)
?Not bmxng
	Function sysctlbyname:Int(name:Byte Ptr, count:Int Ptr, size:Int Ptr, a:Byte Ptr, b:Int)
?
End Extern

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
?bmxng
		Local l:Size_T = 4
?Not bmxng
		Local l:Int = 4
?
		sysctlbyname("hw.ncpu", Varptr count, Varptr l,Null,0)
	End If

	Return count
End Function

