import Foundation

class PitchUnitDelegate: FXUnitDelegate<PitchUnit>, PitchShiftUnitDelegateProtocol {
    
    let preferences: SoundPreferences
    
    var pitch: Float {
        
        get {return unit.pitch * AppConstants.pitchConversion_audioGraphToUI}
        
        set(newValue) {unit.pitch = newValue * AppConstants.pitchConversion_UIToAudioGraph}
    }
    
    var formattedPitch: String {
        return ValueFormatter.formatPitch(pitch)
    }
    
    var overlap: Float {
        
        get {return unit.overlap}
        
        set(newValue) {unit.overlap = newValue}
    }
    
    var formattedOverlap: String {
        return ValueFormatter.formatOverlap(overlap)
    }
    
    init(_ unit: PitchUnit, _ preferences: SoundPreferences) {
        
        self.preferences = preferences
        super.init(unit)
    }
    
    func increasePitch() -> (pitch: Float, pitchString: String) {
        ensureActive()
        return setUnitPitch(min(2400, unit.pitch + Float(preferences.pitchDelta)))
    }
    
    func decreasePitch() -> (pitch: Float, pitchString: String) {
        ensureActive()
        return setUnitPitch(max(-2400, unit.pitch - Float(preferences.pitchDelta)))
    }
    
    private func setUnitPitch(_ value: Float) -> (pitch: Float, pitchString: String) {
        unit.pitch = value
        return (pitch, formattedPitch)
    }
    
    private func ensureActive() {
        
        // If the pitch unit is currently inactive, start at default pitch offset, before the increase/decrease
        if state != .active {
            
            _ = unit.toggleState()
            unit.pitch = AppDefaults.pitch
        }
    }
    
    var presets: PitchPresets {
        return unit.presets
    }
    
    func savePreset(_ presetName: String) {
        unit.savePreset(presetName)
    }
    
    func applyPreset(_ presetName: String) {
        
        if let preset = presets.presetByName(presetName) {
            unit.applyPreset(preset)
        }
    }
}