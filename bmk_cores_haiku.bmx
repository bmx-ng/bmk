SuperStrict

Import "bmk_cores_haiku.c"

Extern
	Function bmx_get_system_info_cpu_count:Int()
End Extern

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
		count = bmx_get_system_info_cpu_count()
	End If

	Return count
End Function

