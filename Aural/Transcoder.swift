import Foundation

protocol TranscoderProtocol {
    
    func transcodeImmediately(_ track: Track)
    
    func transcodeInBackground(_ track: Track)
    
    func cancel(_ track: Track)
    
    // ???
//    func moveToBackground(_ track: Track)
}

class Transcoder: TranscoderProtocol, PlaylistChangeListenerProtocol, AsyncMessageSubscriber, PersistentModelObject {
    
    private let avConvBinaryPath: String = Bundle.main.url(forResource: "avconv", withExtension: "")!.path
    
    private let store: TranscoderStore
    private let daemon: TranscoderDaemon
    
    private let preferences: TranscodingPreferences
    
    private let formatsMap: [String: String] = ["flac": "aiff",
                                                "wma": "mp3",
                                                "ogg": "mp3"]
    
    private let defaultOutputFileExtension: String = "mp3"
    
    private lazy var playlist: PlaylistAccessorProtocol = ObjectGraph.playlistAccessor
    private lazy var sequencer: PlaybackSequencerInfoDelegateProtocol = ObjectGraph.playbackSequencerInfoDelegate
    private lazy var player: PlaybackInfoDelegateProtocol = ObjectGraph.playbackInfoDelegate
    
    let subscriberId: String = "Transcoder"
    
    init(_ state: TranscoderState, _ preferences: TranscodingPreferences) {
        
        store = TranscoderStore(state, preferences)
        daemon = TranscoderDaemon()
        self.preferences = preferences
        
        AsyncMessenger.subscribe([.trackChanged], subscriber: self, dispatchQueue: DispatchQueue.global(qos: .background))
    }
    
    func transcodeImmediately(_ track: Track) {
    
        if let outFile = store.getForTrack(track) {
            AudioUtils.prepareTrackWithFile(track, outFile)
            return
        }
        
        // Check if this track is already being transcoded in the background. If so, bring it to the foreground (start monitoring it)
        
        let inputFile = track.file
        let outputFile = outputFileForTrack(track)
        
        AsyncMessenger.publishMessage(TranscodingStartedAsyncMessage(track))
        
        let command = createCommand(track, inputFile, outputFile, self.transcodingProgress, .userInteractive, true)
        
        let successHandler = { (command: Command) -> Void in
            
            self.store.addFileMapping(track, outputFile)
            
            // Only do this if task is in the foreground (i.e. monitoring enabled)
            if command.enableMonitoring {
                AudioUtils.prepareTrackWithFile(track, outputFile)
                AsyncMessenger.publishMessage(TranscodingFinishedAsyncMessage(track, track.lazyLoadingInfo.preparedForPlayback))
            }
        }
        
        let failureHandler = { (command: Command) -> Void in
            
            // Only do this if task is in the foreground (i.e. monitoring enabled)
            if command.enableMonitoring {
                track.lazyLoadingInfo.preparationError = TrackNotPlayableError(track)
                AsyncMessenger.publishMessage(TranscodingFinishedAsyncMessage(track, false))
            }
        }
        
        let cancellationHandler = {
            FileSystemUtils.deleteFile(outputFile.path)
        }
        
        daemon.submitImmediateTask(track, command, successHandler, failureHandler, cancellationHandler)
    }
    
    func transcodeInBackground(_ track: Track) {
        
        let inputFile = track.file
        let outputFile = outputFileForTrack(track)
        
        let command = createCommand(track, inputFile, outputFile, self.transcodingProgress, .background, false)
        
        let successHandler = { (command: Command) -> Void in
            
            self.store.addFileMapping(track, outputFile)
            
            // Only do this if task is in the foreground (i.e. monitoring enabled)
            if command.enableMonitoring {
                
                AudioUtils.prepareTrackWithFile(track, outputFile)
                AsyncMessenger.publishMessage(TranscodingFinishedAsyncMessage(track, track.lazyLoadingInfo.preparedForPlayback))
            }
        }
        
        let failureHandler = { (command: Command) -> Void in
            
            // Only do this if task is in the foreground (i.e. monitoring enabled)
            if command.enableMonitoring {
                
                track.lazyLoadingInfo.preparationError = TrackNotPlayableError(track)
                AsyncMessenger.publishMessage(TranscodingFinishedAsyncMessage(track, false))
            }
        }
        
        let cancellationHandler = {
            FileSystemUtils.deleteFile(outputFile.path)
        }
        
        daemon.submitBackgroundTask(track, command, successHandler, failureHandler, cancellationHandler)
    }
    
    private func createCommand(_ track: Track, _ inputFile: URL, _ outputFile: URL, _ progressCallback: @escaping ((_ command: Command, _ output: String) -> Void), _ qualityOfService: QualityOfService, _ enableMonitoring: Bool) -> Command {
        
        // -vn: Ignore video stream (including album art)
        // -sn: Ignore subtitles
        // -ac 2: Convert to stereo audio
        return Command.createMonitoredCommand(track: track, cmd: avConvBinaryPath, args: ["-i", inputFile.path, "-vn", "-sn", "-ac", "2", outputFile.path], qualityOfService: qualityOfService, timeout: nil, callback: progressCallback, enableMonitoring: enableMonitoring)
    }
    
    private func outputFileForTrack(_ track: Track) -> URL {
        
        let inputFile = track.file
        let inputFileName = inputFile.lastPathComponent
        let inputFileExtension = inputFile.pathExtension.lowercased()
        let outputFileExtension = formatsMap[inputFileExtension] ?? defaultOutputFileExtension
        
        // File name needs to be unique. Otherwise, command execution will hang (libav will ask if you want to overwrite).
        
        let now = Date()
        let outputFileName = String(format: "%@-transcoded-%@.%@", inputFileName, now.serializableString_hms(), outputFileExtension)
        
        return store.createOutputFile(track, outputFileName)
    }
    
    private func transcodingProgress(_ command: Command, _ progressStr: String) {
        
        if command.cancelled {return}

        let line = progressStr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if line.contains("size=") && line.contains("time=") {
            
            let timeStr = line.split(separator: "=")[2].split(separator: " ")[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if let time = Double(timeStr) {
                
                let track = command.track
                
                let perc = min(time * 100 / track.duration, 100)
                let timeElapsed = Date().timeIntervalSince(command.startTime)
                let totalTime = (100 * timeElapsed) / perc
                let timeRemaining = totalTime - timeElapsed
                
                let msg = TranscodingProgressAsyncMessage(track, time, perc, timeElapsed, timeRemaining)
                AsyncMessenger.publishMessage(msg)
            }
        }
    }

    func cancel(_ track: Track) {
        daemon.cancelTask(track)
    }
    
//    func moveToBackground(_ track: Track) {
//        daemon.moveTaskToBackground(track)
//    }
    
    func persistentState() -> PersistentState {
        
        let state = TranscoderState()
        store.map.forEach({state.entries[$0.key] = $0.value})
        
        return state
    }
    
    // MARK: Message handling
    
    private func trackChanged() {
        
        // TODO: Use a Set to avoid duplicates. Check to make sure playing track is not included.
        var tracksToTranscode: Set<IndexedTrack> = Set<IndexedTrack>()
        
        let playingTrack = player.playingTrack
        
        if let next = sequencer.peekNext() {tracksToTranscode.insert(next)}
        if let prev = sequencer.peekPrevious() {tracksToTranscode.insert(prev)}
        if let subsequent = sequencer.peekSubsequent() {tracksToTranscode.insert(subsequent)}
        
        for track in tracksToTranscode {
            
            if !track.equals(playingTrack) && trackNeedsTranscoding(track.track) {
                transcodeInBackground(track.track)
            }
        }
    }
    
    private func trackNeedsTranscoding(_ track: Track) -> Bool {
        return !track.nativelySupported && store.getForTrack(track) == nil
    }
    
    func consumeAsyncMessage(_ message: AsyncMessage) {
        
        if message.messageType == .trackChanged {
            trackChanged()
            return
        }
    }
    
    func tracksAdded(_ addResults: [TrackAddResult]) {
        
        if preferences.eagerTranscodingEnabled {
            
            if preferences.eagerTranscodingOption == .allFiles {
                
//                let task = {
//
//                    let tracks = self.playlist.tracks
//                    for track in tracks {
//
//                        if !track.nativelySupported && self.store.getForTrack(track) == nil {
//
//                            let outputFile = self.outputFileForTrack(track)
//
//                            if LibAVWrapper.transcode(track.file, outputFile, self.transcodingProgress) {
//                                self.store.fileAddedToStore(outputFile)
//                            }
//
//                            // TODO: How to continue transcoding more tracks ???
//                            return
//                        }
//                    }
//                }
//
//                daemon.submitTask(task, .background)
            }
        }
    }
}

