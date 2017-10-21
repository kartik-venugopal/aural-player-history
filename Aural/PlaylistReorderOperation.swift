import Foundation

// Marker protocol for a playlist reorder operation
protocol PlaylistReorderOperation {}

// Denotes an operation to copy a playlist track from one index to another, overwriting the destination
struct PlaylistCopyOperation: PlaylistReorderOperation {
    
    var srcIndex: Int
    var destIndex: Int
}

// Denotes an operation to copy a given track to a destination index, overwriting the destination
struct PlaylistOverwriteOperation: PlaylistReorderOperation {
    
    var srcTrack: Track
    var destIndex: Int
}