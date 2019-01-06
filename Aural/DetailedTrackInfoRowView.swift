/*
    Custom view for a single NSTableView row that displays a single piece of track info. Creates table cells with the necessary track information.
*/

import Cocoa

class DetailedTrackInfoRowView: NSTableRowView {
    
    // A single key-value pair
    var key: String?
    var value: String?
    var tableId: TrackInfoTab?
    
    // Factory method
    static func fromKeyAndValue(_ key: String, _ value: String, _ tableId: TrackInfoTab) -> DetailedTrackInfoRowView {
        
        let view = DetailedTrackInfoRowView()
        view.key = key
        view.value = value
        view.tableId = tableId
        
        return view
    }
    
    override func view(atColumn column: Int) -> Any? {
        
        if (column == 0) {
            
            // Key
            return createCell(UIConstants.trackInfoKeyColumnID, key! + ":")
            
        } else {
            
            // Value
            return createCell(UIConstants.trackInfoValueColumnID, value!)
        }
    }
    
    private func createCell(_ id: String, _ text: String) -> NSTableCellView? {
        
        if let cell = TrackInfoViewHolder.tablesMap[tableId!]!.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: id), owner: nil) as? NSTableCellView {
            
            cell.textField?.stringValue = text
            return cell
        }
        
        return nil
    }
}
