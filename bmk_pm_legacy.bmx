SuperStrict

Import "bmk_ng_utils.bmx"

Type TProcessManager

	Field pool:TThreadPool
	
	Field cpuCount:Int
	
	Field threads:TList = New TList
	
	Method New()
		cpuCount = GetCoreCount()
		
		pool = TThreadPool.Create(Max(1, cpuCount - 1), cpuCount * 6)
		
	End Method

	Method CheckTasks()
		While pool.count() = pool.Size()
			Delay 5
		Wend
	End Method
	
	Method WaitForTasks()
		While pool.Count() Or pool.Running()
			Delay 5
		Wend
	End Method
	
	Method DoSystem(cmd:String, src:String, obj:String, supp:String)
		CheckTasks()

		pool.AddTask(TProcessTask._DoTasks, CreateProcessTask(cmd, src, obj, supp))

	End Method

	Method AddTask:Int(func:Object(data:Object), data:Object)
		CheckTasks()

		pool.AddTask(func, data)
	End Method
	
End Type

Rem
bbdoc: A thread pool.
End Rem
Type TThreadPool

	Field _threads:TThread[]
	Field _queue:TThreadPoolTask[]
	
	Field _lock:TMutex
	Field _waitVar:TCondVar
	
	Field _count:Int
	Field _head:Int
	Field _tail:Int
	Field _running:Int
	
	Field _shutdown:Int

	Rem
	bbdoc: Creates a new thread pool of @threadCount threads and a queue size of @queueSize.
	End Rem
	Function Create:TThreadPool(threadCount:Int, queueSize:Int)
		Local pool:TThreadPool = New TThreadPool
		pool._threads = New TThread[threadCount]
		pool._queue = New TThreadPoolTask[queueSize]
		
		pool._lock = TMutex.Create()
		pool._waitVar = TCondVar.Create()
		
		For Local i:Int = 0 Until threadCount
			pool._threads[i] = TThread.Create(_ThreadPoolThread, pool)
		Next
		
		' cache tasks
		For Local i:Int = 0 Until queueSize
			pool._queue[i] = New TThreadPoolTask
		Next
		
		Return pool
	End Function
	
	Rem
	bbdoc: Returns the number of tasks in the queue.
	End Rem
	Method Count:Int()
		Return _count
	End Method
	
	Rem
	bbdoc: Returns the size of the queue.
	End Rem
	Method Size:Int()
		Return _queue.length
	End Method
	
	Rem
	bbdoc: Returns the number of busy/running threads.
	End Rem
	Method Running:Int()
		Return _running
	End Method
	
	Rem
	bbdoc: Adds a task to the queue.
	End Rem
	Method AddTask:Int(func:Object(data:Object), data:Object)
	
		Local result:Int = True
	
		_lock.Lock()
		
		Local slot:Int = _tail + 1
		If slot = _queue.length Then
			slot = 0
		End If
		
		While True
		
			If _count = _queue.length Then
				result = False
				Exit
			End If
		
			If _shutdown Then
				result = False
				Exit
			End If
			
			_queue[_tail].func = func
			_queue[_tail].data = data
			_tail = slot
			_count :+ 1
			
			_waitVar.Broadcast()
			
			Exit
		Wend
		
		_lock.Unlock()
		
		Return result
	End Method
	
	Rem
	bbdoc: Shutdown the pool.
	about: If @immediately is False, the queue will be processed to the end.
	End Rem
	Method Shutdown(immediately:Int = False)
		_lock.Lock()
		
		While True
		
			If _shutdown Then
				Return
			End If
			
			If immediately Then
				_shutdown = 2
			Else
				_shutdown = 1
			End If
		
			_waitVar.Broadcast()
			_lock.Unlock()
			
			For Local i:Int = 0 Until _threads.length
				_threads[i].Wait()
			Next
		
			Exit
		Wend
		
		_lock.Lock()
		_lock.Close()
		_waitVar.Close()
		
	End Method
	
	Function _ThreadPoolThread:Object(data:Object)
		Local pool:TThreadPool = TThreadPool(data)
		
		While True
		
			pool._lock.Lock()
			
			While pool._count = 0 And Not pool._shutdown
				pool._waitVar.Wait(pool._lock)
				Delay 5
			Wend
			
			If pool._shutdown And pool._count = 0 Then
				' time to finish
				Exit
			End If
			
			Local task:TThreadPoolTask = pool._queue[pool._head]
			
			Local func:Object(data:Object) = task.func
			Local data:Object = task.data
			
			pool._head :+ 1
			
			If pool._head = pool._queue.length Then
				pool._head = 0
			End If
			
			' less queue
			pool._count :- 1
			' more running threads
			pool._running :+ 1
			
			pool._lock.Unlock()
			
			' perform a task
			func(data)
			
			pool._lock.Lock()
			pool._running :- 1
			pool._lock.Unlock()
		Wend
		
		pool._lock.Unlock()
		
	End Function
	
	Method Delete()
		Shutdown()
	End Method
	
End Type

Type TThreadPoolTask

	Field func:Object(data:Object)
	Field data:Object
	
End Type

