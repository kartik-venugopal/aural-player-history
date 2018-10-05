import Cocoa

class PlaylistPreferencesViewController: NSViewController, PreferencesViewProtocol {
    
    @IBOutlet weak var btnEmptyPlaylist: NSButton!
    @IBOutlet weak var btnRememberPlaylist: NSButton!
    @IBOutlet weak var btnLoadPlaylist: NSButton!
    @IBOutlet weak var btnBrowse: NSButton!
    
    @IBOutlet weak var errorIcon: NSImageView!
    
    @IBOutlet weak var lblPlaylistFile: NSTextField!
    @IBOutlet weak var lblPlaylistFileCell: ValidatedLabelCell!
    
    override var nibName: String? {return "PlaylistPreferences"}
    
    func getView() -> NSView {
        return self.view
    }
    
    func resetFields(_ preferences: Preferences) {
        
        switch preferences.playlistPreferences.playlistOnStartup {
            
        case .empty:    btnEmptyPlaylist.state = convertToNSControlStateValue(1)
            
        case .rememberFromLastAppLaunch:    btnRememberPlaylist.state = convertToNSControlStateValue(1)
            
        case .loadFile: btnLoadPlaylist.state = convertToNSControlStateValue(1)
            
        }
        
        [btnBrowse, lblPlaylistFile].forEach({
            $0!.isEnabled = Bool(btnLoadPlaylist.state.rawValue)
        })
        
        hideError()
        lblPlaylistFile.stringValue = preferences.playlistPreferences.playlistFile?.path ?? ""
    }
    
    @IBAction func startupPlaylistPrefAction(_ sender: Any) {
        
        // Needed for radio button group
        
        [btnBrowse, lblPlaylistFile].forEach({
            $0!.isEnabled = Bool(btnLoadPlaylist.state.rawValue)
        })
        
        if (btnLoadPlaylist.state.rawValue == 0 && !errorIcon.isHidden) {
            hideError()
        }
    
        if btnLoadPlaylist.state.rawValue == 1 && StringUtils.isStringEmpty(lblPlaylistFile.stringValue) {
            choosePlaylistFileAction(sender)
        }
    }
    
    func save(_ preferences: Preferences) throws {
        
        if btnEmptyPlaylist.state.rawValue == 1 {
            
            preferences.playlistPreferences.playlistOnStartup = .empty
            
        } else if btnRememberPlaylist.state.rawValue == 1 {
            
            preferences.playlistPreferences.playlistOnStartup = .rememberFromLastAppLaunch
            
        } else {
            
            preferences.playlistPreferences.playlistOnStartup = .loadFile
            
            // Make sure 1 - label is not empty, and 2 - no previous error message is shown
            if !StringUtils.isStringEmpty(lblPlaylistFile.stringValue) && errorIcon.isHidden {
                
                preferences.playlistPreferences.playlistFile = URL(fileURLWithPath: lblPlaylistFile.stringValue)
                
            } else {
                
                // Error
                showError()
                throw PlaylistFileNotSpecifiedError("No playlist file specified for loading upon app startup")
            }
        }
    }
    
    @IBAction func choosePlaylistFileAction(_ sender: Any) {
        
        let dialog = DialogsAndAlerts.openPlaylistDialog
        
        let modalResponse = dialog.runModal()
        
        if (modalResponse == NSApplication.ModalResponse.OK) {
            
            let playlistFile = dialog.urls[0]
            
            hideError()
            lblPlaylistFile.stringValue = playlistFile.path
        }
    }
    
    private func showError() {
        
        lblPlaylistFileCell.markError("  Please choose a playlist file!")
        lblPlaylistFile.setNeedsDisplay()
        errorIcon.isHidden = false
    }
    
    private func hideError() {
        
        lblPlaylistFileCell.clearError()
        lblPlaylistFile.setNeedsDisplay()
        errorIcon.isHidden = true
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToNSControlStateValue(_ input: Int) -> NSControl.StateValue {
	return NSControl.StateValue(rawValue: input)
}
