/*
    Takes care of loading all persistent app state from disk, and constructing the critical objects in the app's object tree - player, playlist, audio graph (i.e., "the back end"), and all delegates (middlemen/facades) for interaction between the UI and the "back end".
 */

import Foundation

class ObjectGraph {
    
    static var appState: AppState!
    static var preferences: Preferences!
    
    static var preferencesDelegate: PreferencesDelegate!
    
    private static var playlist: PlaylistCRUDProtocol!
    static var playlistAccessor: PlaylistAccessorProtocol! {return playlist}
    
    static var playlistDelegate: PlaylistDelegateProtocol!
    static var playlistAccessorDelegate: PlaylistAccessorDelegateProtocol! {return playlistDelegate}
    
    private static var audioGraph: AudioGraphProtocol!
    static var audioGraphDelegate: AudioGraphDelegateProtocol!
    
    private static var player: PlayerProtocol!
    private static var playbackScheduler: PlaybackSchedulerProtocol!
    private static var sequencer: SequencerProtocol!
    
    static var sequencerDelegate: SequencerDelegateProtocol!
    static var sequencerInfoDelegate: SequencerInfoDelegateProtocol! {return sequencerDelegate}
    
    static var playbackDelegate: PlaybackDelegateProtocol!
    static var playbackInfoDelegate: PlaybackInfoDelegateProtocol! {return playbackDelegate}
    
    private static var recorder: Recorder!
    static var recorderDelegate: RecorderDelegateProtocol!
    
    private static var history: History!
    static var historyDelegate: HistoryDelegateProtocol!
    
    private static var favorites: Favorites!
    static var favoritesDelegate: FavoritesDelegateProtocol!
    
    private static var bookmarks: Bookmarks!
    static var bookmarksDelegate: BookmarksDelegateProtocol!
    
    static var transcoder: TranscoderProtocol!
    static var muxer: MuxerProtocol!
    
    static var avAssetReader: AVAssetReader!
    static var commonAVAssetParser: CommonAVAssetParser!
    static var id3Parser: ID3Parser!
    static var iTunesParser: ITunesParser!
    static var audioToolboxParser: AudioToolboxParser!
    
    static var ffmpegReader: FFMpegReader!
    static var commonFFMpegParser: CommonFFMpegMetadataParser!
    static var wmParser: WMParser!
    static var vorbisParser: VorbisCommentParser!
    static var apeParser: ApeV2Parser!
    static var defaultParser: DefaultFFMpegMetadataParser!
    
    static var mediaKeyHandler: MediaKeyHandler!
    
    // Don't let any code invoke this initializer to create instances of ObjectGraph
    private init() {}
    
    // Performs all necessary object initialization
    static func initialize() {
        
        // Load persistent app state from disk
        // Use defaults if app state could not be loaded from disk
        appState = AppStateIO.load() ?? AppState.defaults
        
        // Preferences (and delegate)
        preferences = Preferences.instance
        preferencesDelegate = PreferencesDelegate(preferences)
        
        // Audio Graph (and delegate)
        audioGraph = AudioGraph(appState.audioGraph)
        
        // The new scheduler uses an AVFoundation API that is only available with macOS >= 10.13.
        // Instantiate the legacy scheduler if running on 10.12 Sierra or older systems.
        if #available(macOS 10.13, *) {
            playbackScheduler = PlaybackScheduler(audioGraph.playerNode)
        } else {
            playbackScheduler = LegacyPlaybackScheduler(audioGraph.playerNode)
        }
        
        // Player
        player = Player(audioGraph, playbackScheduler)
        
        // Playlist
        let flatPlaylist = FlatPlaylist()
        let artistsPlaylist = GroupingPlaylist(.artists)
        let albumsPlaylist = GroupingPlaylist(.albums)
        let genresPlaylist = GroupingPlaylist(.genres)
        
        playlist = Playlist(flatPlaylist, [artistsPlaylist, albumsPlaylist, genresPlaylist])
        
        // Sequencer and delegate
        let repeatMode = appState.playbackSequence.repeatMode
        let shuffleMode = appState.playbackSequence.shuffleMode
        let playlistType = PlaylistType(rawValue: appState.ui.playlist.view.lowercased()) ?? .tracks
        
        sequencer = Sequencer(playlist, repeatMode, shuffleMode, playlistType)
        sequencerDelegate = SequencerDelegate(sequencer)
        
        transcoder = Transcoder(appState.transcoder, preferences.playbackPreferences.transcodingPreferences, playlist, sequencerDelegate)
        
        let profiles = PlaybackProfiles()
        
        for profile in appState.playbackProfiles {
            profiles.add(profile.file, profile)
        }
        
        let startPlaybackChain = StartPlaybackChain(player, sequencer, playlist, transcoder, profiles, preferences.playbackPreferences)
        let stopPlaybackChain = StopPlaybackChain(player, sequencer, transcoder, profiles, preferences.playbackPreferences)
        let trackPlaybackCompletedChain = TrackPlaybackCompletedChain(startPlaybackChain, stopPlaybackChain, sequencer)
        
        // Playback Delegate
        playbackDelegate = PlaybackDelegate(player, playlist, sequencer, profiles, preferences.playbackPreferences, startPlaybackChain, stopPlaybackChain, trackPlaybackCompletedChain)
        
        audioGraphDelegate = AudioGraphDelegate(audioGraph, playbackDelegate, preferences.soundPreferences, appState.audioGraph)
        
        // Playlist Delegate
        playlistDelegate = PlaylistDelegate(playlist, appState.playlist, preferences,
                                            [playbackDelegate as! PlaybackDelegate])
        
        // Recorder (and delegate)
        recorder = Recorder(audioGraph)
        recorderDelegate = RecorderDelegate(recorder)
        
        // History (and delegate)
        history = History(preferences.historyPreferences)
        historyDelegate = HistoryDelegate(history, playlistDelegate, playbackDelegate, appState.history)
        
        bookmarks = Bookmarks()
        bookmarksDelegate = BookmarksDelegate(bookmarks, playlistDelegate, playbackDelegate, appState.bookmarks)
        
        favorites = Favorites()
        favoritesDelegate = FavoritesDelegate(favorites, playlistDelegate, playbackDelegate, appState!.favorites)
        
        muxer = Muxer()
        
        commonAVAssetParser = CommonAVAssetParser()
        id3Parser = ID3Parser()
        iTunesParser = ITunesParser()
        audioToolboxParser = AudioToolboxParser()
        
        avAssetReader = AVAssetReader(commonAVAssetParser, id3Parser, iTunesParser, audioToolboxParser, muxer)
        
        commonFFMpegParser = CommonFFMpegMetadataParser()
        wmParser = WMParser()
        vorbisParser = VorbisCommentParser()
        apeParser = ApeV2Parser()
        defaultParser = DefaultFFMpegMetadataParser()
        
        ffmpegReader = FFMpegReader(commonFFMpegParser, id3Parser, vorbisParser, apeParser, wmParser, defaultParser, muxer)

        mediaKeyHandler = MediaKeyHandler(preferences.controlsPreferences)
        
        // Initialize utility classes.
        
        AudioUtils.initialize(transcoder)
        MetadataUtils.initialize(playlistDelegate, avAssetReader, ffmpegReader)
        PlaylistIO.initialize(playlist)
        
        // UI-related utility classes
        
        WindowManager.initialize(appState.ui.windowLayout, preferences.viewPreferences)
        UIUtils.initialize(preferences.viewPreferences)
        
        WindowLayouts.loadUserDefinedLayouts(appState.ui.windowLayout.userLayouts)
        ColorSchemes.initialize(appState.ui.colorSchemes)
        
        PlayerViewState.initialize(appState.ui.player)
        PlaylistViewState.initialize(appState.ui.playlist)
        EffectsViewState.initialize(appState.ui.effects)
    }
    
    private static let tearDownOpQueue: OperationQueue = {

        let queue = OperationQueue()
        queue.underlyingQueue = DispatchQueue.global(qos: .userInteractive)
        queue.maxConcurrentOperationCount = 2
        
        return queue
    }()
    
    // Called when app exits
    static func tearDown() {
        
        // Gather all pieces of app state into the appState object
        
        appState.audioGraph = (audioGraph as! PersistentModelObject).persistentState as! AudioGraphState
        appState.playlist = (playlist as! Playlist).persistentState as! PlaylistState
        appState.playbackSequence = (sequencer as! Sequencer).persistentState as! PlaybackSequenceState
        appState.playbackProfiles = playbackDelegate.profiles.all()
        
        appState.transcoder = (transcoder as! Transcoder).persistentState as! TranscoderState
        
        appState.ui = UIState()
        appState.ui.windowLayout = WindowManager.persistentState
        appState.ui.colorSchemes = ColorSchemes.persistentState
        appState.ui.player = PlayerViewState.persistentState
        appState.ui.playlist = PlaylistViewState.persistentState
        appState.ui.effects = EffectsViewState.persistentState
        
        appState.history = (historyDelegate as! HistoryDelegate).persistentState as! HistoryState
        appState.favorites = (favoritesDelegate as! FavoritesDelegate).persistentState
        appState.bookmarks = (bookmarksDelegate as! BookmarksDelegate).persistentState
        
        // App state persistence and shutting down the audio engine can be performed concurrently
        // on two background threads to save some time when exiting the app.
        
        // App state persistence to disk
        tearDownOpQueue.addOperation {
            AppStateIO.save(appState!)
        }

        // Tear down the audio engine
        tearDownOpQueue.addOperation {
            player.tearDown()
            audioGraph.tearDown()
        }

        // Wait for all concurrent operations to finish executing.
        tearDownOpQueue.waitUntilAllOperationsAreFinished()
    }
}
