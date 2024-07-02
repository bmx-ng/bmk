SuperStrict

Import BRL.ThreadPool
Import "bmk_ng_utils.bmx"

Type TProcessManager

	Field pool:TThreadPoolExecutor
	
	Field cpuCount:Int
	
	Field threads:TList = New TList
	
	Method New()
		cpuCount = GetCoreCount()
		
		pool = TThreadPoolExecutor.newFixedThreadPool(Max(1, cpuCount - 1))
		
	End Method

	Method CheckTasks()
		While pool.getActiveCount() = pool.maxThreads
			Delay 5
		Wend
	End Method
	
	Method WaitForTasks()
		While pool.getActiveCount() Or Not pool.IsQueueEmpty()
			Delay 5
		Wend
	End Method
	
	Method DoSystem(cmd:String, src:String, obj:String, supp:String)
		CheckTasks()

		pool.execute(new TThreadPoolTask.Create(TProcessTask._DoTasks, CreateProcessTask(cmd, src, obj, supp)))

	End Method

	Method AddTask:Int(func:Object(data:Object), data:Object)
		CheckTasks()

		pool.execute(new TThreadPoolTask.Create(func, data))
	End Method
	
End Type

Type TThreadPoolTask Extends TRunnable

	Field func:Object(data:Object)
	Field data:Object

	Method Create:TThreadPoolTask(func:Object(data:Object), data:Object)
		Self.func = func
		Self.data = data
		Return self
	End Method

	Method run()
		func(data)
	End Method

End Type

