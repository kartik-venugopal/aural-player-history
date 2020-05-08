/*
    View controller that handles the assembly of the player view tree from its multiple pieces, and handles general concerns for the view such as text size and color scheme changes.
 
    The player view tree consists of:
        
        - Playing track info (track info, art, etc)
            - Default view
            - Expanded Art view
 
        - Transcoder info (when a track is being transcoded)
 
        - Player controls (play/seek, next/previous track, repeat/shuffle, volume/balance)
 */
import Cocoa

class PlayerViewController: NSViewController, MessageSubscriber, AsyncMessageSubscriber {
    
    private var playingTrackView: NSView = ViewFactory.playingTrackView
    private var waitingTrackView: NSView = ViewFactory.waitingTrackView
    private var transcodingTrackView: NSView = ViewFactory.transcodingTrackView
    
    // Delegate that conveys all seek and playback info requests to the player
    private let player: PlaybackInfoDelegateProtocol = ObjectGraph.playbackInfoDelegate
    
    override var nibName: String? {return "Player"}
    
    override func viewDidLoad() {
        
        //        [playingTrackView, waitingTrackView, transcodingTrackView].forEach({
        
        [playingTrackView, waitingTrackView].forEach({
            
            self.view.addSubview($0)
            $0.setFrameOrigin(NSPoint.zero)
        })
        
        initSubscriptions()
        switchView()
    }
    
    private func initSubscriptions() {
        
        AsyncMessenger.subscribe([.gapStarted, .transcodingStarted, .transcodingFinished], subscriber: self, dispatchQueue: DispatchQueue.main)
        
        // TODO - Necessary ??? Maybe to find out when gap has ended.
        SyncMessenger.subscribe(messageTypes: [.trackChangedNotification], subscriber: self)
    }
    
    private func switchView() {
        
        switch player.state {

        case .noTrack, .playing, .paused:

            playingTrackView.show()
//            NSView.hideViews(waitingTrackView, transcodingTrackView)
            NSView.hideViews(waitingTrackView)

        case .waiting:

            waitingTrackView.show()
//            NSView.hideViews(playingTrackView, transcodingTrackView)
            NSView.hideViews(playingTrackView)

        case .transcoding:

            transcodingTrackView.show()
            NSView.hideViews(playingTrackView, waitingTrackView)
        }
    }
    
    // MARK: Message handling
    
    var subscriberId: String {
        return self.className
    }
    
    func consumeNotification(_ notification: NotificationMessage) {
        
        if notification is TrackChangedNotification {
            
            switchView()
            return
        }
    }
    
    func consumeAsyncMessage(_ message: AsyncMessage) {
        
        if message is PlaybackGapStartedAsyncMessage || message is TranscodingStartedAsyncMessage || message is TranscodingFinishedAsyncMessage {
            
            switchView()
            return
        }
    }
}