SuperStrict

' http://msdn.microsoft.com/en-us/library/ms724958(VS.85).aspx
Extern "win32"
	Function GetSystemInfo(info:Byte Ptr)
End Extern

Type SYSTEM_INFO
	Field wProcessorArchitecture:Short
	Field wReserved:Short
	Field dwPageSize:Int
	Field lpMinimumApplicationAddress:Byte Ptr
	Field lpMaximumApplicationAddress:Byte Ptr
	Field dwActiveProcessorMask:Int
	Field dwNumberOfProcessors:Int
	Field dwProcessorType:Int
	Field dwAllocationGranularity:Int
	Field wProcessorLevel:Short
	Field wProcessorRevision:Short
End Type

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
		Local info:SYSTEM_INFO = New SYSTEM_INFO
		GetSystemInfo(info)
		count = info.dwNumberOfProcessors
	End If

	Return count
End Function

