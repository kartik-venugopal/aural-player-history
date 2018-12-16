import Foundation

class TranscoderDaemon {
    
    let immediateExecutionQueue: OperationQueue = OperationQueue()
    let backgroundExecutionQueue: OperationQueue = OperationQueue()
    
    var tasks: [Track: TranscodingTask] = [:]
    
    init() {
        
        immediateExecutionQueue.underlyingQueue = DispatchQueue.global(qos: .userInteractive)
        immediateExecutionQueue.maxConcurrentOperationCount = 1
        immediateExecutionQueue.qualityOfService = .userInteractive
        
        backgroundExecutionQueue.underlyingQueue = DispatchQueue.global(qos: .background)
        backgroundExecutionQueue.maxConcurrentOperationCount = 1    // TODO: This value should come from preferences
        backgroundExecutionQueue.qualityOfService = .background
    }
    
    func submitImmediateTask(_ track: Track, _ command: Command, _ successHandler: @escaping ((_ command: Command) -> Void), _ failureHandler: @escaping ((_ command: Command) -> Void), _ cancellationHandler: @escaping (() -> Void)) {
        
        // Track is already being transcoded
        if let task = tasks[track] {
            
            // Running in foreground, nothing further to do
            if task.priority == .immediate {return}
            
            // Task is running in background, bring it to the foreground.
            doMoveTaskToForeground(task)
            return
        }
        
        doSubmitTask(track, command, successHandler, failureHandler, cancellationHandler, .immediate)
    }
    
    func submitBackgroundTask(_ track: Track, _ command: Command, _ successHandler: @escaping ((_ command: Command) -> Void), _ failureHandler: @escaping ((_ command: Command) -> Void), _ cancellationHandler: @escaping (() -> Void)) {
        
        // Track is already being transcoded. Just return.
        if tasks[track] != nil {return}
        
        doSubmitTask(track, command, successHandler, failureHandler, cancellationHandler, .background)
    }
    
    private func doSubmitTask(_ track: Track, _ command: Command, _ successHandler: @escaping ((_ command: Command) -> Void), _ failureHandler: @escaping ((_ command: Command) -> Void), _ cancellationHandler: @escaping (() -> Void), _ priority: TranscoderPriority) {
        
        let block = {
            
            let result = CommandExecutor.execute(command)
            
            if command.cancelled {
                cancellationHandler()
                return
            }
            
            if result.exitCode == 0 {
                // Success
                successHandler(command)
            } else {
                failureHandler(command)
            }
            
            // Task completed, remove it from the map
            self.tasks.removeValue(forKey: track)
        }
        
        let operation = BlockOperation(block: block)
        
        priority == .immediate ? immediateExecutionQueue.addOperation(operation) : backgroundExecutionQueue.addOperation(operation)
        
        let task = TranscodingTask(track, priority, command, operation)
        tasks[track] = task
    }
    
    func cancelTask(_ track: Track) {
        
        if let task = tasks[track] {
            
            CommandExecutor.cancel(task.command)
            task.operation.cancel()
            tasks.removeValue(forKey: track)
        }
    }
    
    func moveTaskToBackground(_ track: Track) {

        if let task = tasks[track] {
            
            task.command.stopMonitoring()
            task.priority = .background
        }
    }

    func moveTaskToForeground(_ track: Track) {

        if let task = tasks[track] {
            doMoveTaskToForeground(task)
        }
    }
    
    func doMoveTaskToForeground(_ task: TranscodingTask) {
        
        task.command.startMonitoring()
        task.priority = .immediate
        
        let op = task.operation
        
        if !op.isExecuting && !op.isFinished {
            
            // This should prevent it from executing on the background queue
            op.cancel()
            
            // Duplicate the operation and add it to the immediate execution queue.
            immediateExecutionQueue.addOperation(cloneOperation(op))
        }
        
        // If op is already executing, let it finish on the background queue. If finished, nothing left to do.
    }
    
    private func cloneOperation(_ operation: BlockOperation) -> BlockOperation {
        
        let block = operation.executionBlocks[0]
        return BlockOperation(block: block)
    }
}

class TranscodingTask {

    var track: Track

    var priority: TranscoderPriority
    
    var command: Command
    var startTime: Date! {return command.startTime}
    
    var operation: BlockOperation
    
    init(_ track: Track, _ priority: TranscoderPriority, _ command: Command, _ operation: BlockOperation) {
        
        self.track = track
        self.priority = priority
        self.command = command
        self.operation = operation
    }
}

enum TranscoderPriority {
    
    case immediate
    case background
}