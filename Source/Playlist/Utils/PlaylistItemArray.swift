import Foundation

extension Array {
    
    var isNonEmpty: Bool {
        return !isEmpty
    }
}

extension Array where Element: Equatable {
    
    func itemAtIndex(_ index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }

    mutating func addItem(_ item: Element) -> Int {
        
        self.append(item)
        return lastIndex
    }
    
    mutating func removeItem(_ index: Int) -> Element? {
        return indices.contains(index) ? self.remove(at: index) : nil
    }
    
    mutating func removeItem(_ item: Element) -> Int? {
        
        if let index = self.firstIndex(of: item) {
            
            self.remove(at: index)
            return index
        }
        
        return nil
    }
    
    mutating func removeItems(_ indices: IndexSet) -> [Element] {
        
        return indices.sorted(by: descendingIntComparator)
            .compactMap {self.indices.contains($0) ? self.remove(at: $0) : nil}
    }
    
    mutating func removeItems(_ items: [Element]) -> IndexSet {

        // Collect and sort indices before removing items
        let indices: [Int] = items.compactMap {self.firstIndex(of: ($0))}
                                    .sorted(by: descendingIntComparator)
        
        indices.forEach({self.remove(at: $0)})
        
        return IndexSet(indices)
    }
    
    mutating func removeAndInsertItem(_ sourceIndex: Int, _ destinationIndex: Int) {
        self.insert(self.remove(at: sourceIndex), at: destinationIndex)
    }
    
    mutating func moveItemUp(_ index: Int) -> Int {

        swapAt(index, index - 1)
        return index - 1
    }
    
    mutating func moveItemDown(_ index: Int) -> Int {

        swapAt(index, index + 1)
        return index + 1
    }
    
    mutating func moveItemsUp(_ items: [Element]) -> [Int: Int] {
        return moveItemsUp(IndexSet(items.compactMap {self.firstIndex(of: $0)}))
    }

    mutating func moveItemsUp(_ indices: IndexSet) -> [Int: Int] {
        
        // Indices need to be in ascending order, because items need to be moved up, one by one, from top to bottom of the playlist
        let ascendingOldIndices = indices.sorted(by: ascendingIntComparator)
        guard areAscendingIndicesValid(ascendingOldIndices) else {return [:]}
        
        // Mappings of oldIndex (prior to move) -> newIndex (after move)
        var results: [Int: Int] = [:]
        
        // Determine if there is a contiguous block of items at the top of the playlist, that cannot be moved. If there is, determine its size.
        let unmovableBlockSize: Int = self.indices.first(where: {!ascendingOldIndices.contains($0)}) ?? 0
        
        // If there are any items that can be moved, move them and store the index mappings
        if unmovableBlockSize < ascendingOldIndices.count {
            
            for index in unmovableBlockSize..<ascendingOldIndices.count {
                
                let oldIndex = ascendingOldIndices[index]
                results[oldIndex] = moveItemUp(oldIndex)
            }
        }
        
        return results
    }
    
    mutating func moveItemsDown(_ items: [Element]) -> [Int: Int] {
        return moveItemsDown(IndexSet(items.compactMap {self.firstIndex(of: $0)}))
    }
    
    mutating func moveItemsDown(_ indices: IndexSet) -> [Int: Int] {
        
        // Indices need to be in descending order, because items need to be moved down, one by one, from bottom to top of the playlist
        let descendingOldIndices = indices.sorted(by: descendingIntComparator)
        guard areDescendingIndicesValid(descendingOldIndices) else {return [:]}
        
        // Mappings of oldIndex (prior to move) -> newIndex (after move)
        var results: [Int: Int] = [:]
        
        // Determine if there is a contiguous block of items at the bottom of the playlist, that cannot be moved. If there is, determine its size.
        let indicesReversed = self.indices.reversed()
        let unmovableBlockSize = self.lastIndex - (indicesReversed.first(where: {!descendingOldIndices.contains($0)}) ?? 0)
        
        // If there are any items that can be moved, move them and store the index mappings
        if unmovableBlockSize < descendingOldIndices.count {
            
            for index in unmovableBlockSize..<descendingOldIndices.count {
                
                let oldIndex = descendingOldIndices[index]
                results[oldIndex] = moveItemDown(oldIndex)
            }
        }
        
        return results
    }
    
    private func areAscendingIndicesValid(_ indices: [Int]) -> Bool {
        return !self.isEmpty && !indices.isEmpty && indices.first! >= 0 && indices.last! < self.count && indices.count < self.count
    }
    
    private func areDescendingIndicesValid(_ indices: [Int]) -> Bool {
        return !self.isEmpty && !indices.isEmpty && indices.first! < self.count && indices.last! >= 0 && indices.count < self.count
    }
    
    mutating func moveItemsToTop(_ items: [Element]) -> [Int: Int] {
        return moveItemsToTop(IndexSet(items.compactMap {self.firstIndex(of: $0)}))
    }
    
    mutating func moveItemsToTop(_ indices: IndexSet) -> [Int: Int] {
        
        let sortedIndices = indices.sorted(by: ascendingIntComparator)
        guard areAscendingIndicesValid(sortedIndices) else {return [:]}

        var results: [Int: Int] = [:]
        
        // Remove from original location and insert at the top, one after another, below the previous one
        // No need to move the item if the original location is the same as the destination
        for (newIndex, oldIndex) in sortedIndices.enumerated().filter({$0.0 != $0.1}) {
            
            self.removeAndInsertItem(oldIndex, newIndex)
            results[oldIndex] = newIndex
        }
        
        return results
    }
    
    mutating func moveItemsToBottom(_ items: [Element]) -> [Int: Int] {
        return moveItemsToBottom(IndexSet(items.compactMap {self.firstIndex(of: $0)}))
    }
    
    mutating func moveItemsToBottom(_ indices: IndexSet) -> [Int: Int] {
        
        let sortedIndices = indices.sorted(by: descendingIntComparator)
        guard areDescendingIndicesValid(sortedIndices) else {return [:]}
        
        var results: [Int: Int] = [:]

        // Remove from original location and insert at the bottom, one after another, above the previous one
        // No need to move the item if the original location is the same as the destination
        for (newIndex, oldIndex) in sortedIndices.enumerated().map({(self.lastIndex - $0, $1)}).filter({$0.0 != $0.1}) {
            
            self.removeAndInsertItem(oldIndex, newIndex)
            results[oldIndex] = newIndex
        }
        
        return results
    }
    
    func categorizeBy<C>(_ categorizingFunction: (Element) -> C) -> [C: [Element]] where C: Hashable {
        
        var map: [C: [Element]] = [:]
        
        for item in self {
            
            let category: C = categorizingFunction(item)
            map[category] = map[category] ?? []
            map[category]!.append(item)
        }
        
        return map
    }
    
    /*
       In response to a playlist reordering by drag and drop, and given source indices, a destination index, and the drop operation (on/above), determines which destination indices the source indexs will occupy.
    */
    mutating func dragAndDropItems(_ sourceIndices: IndexSet, _ dropIndex: Int) -> IndexSet {
        
        // Find out how many source items are above the dropIndex and how many below
        let dropsAboveDropIndex = sourceIndices.count(in: 0..<dropIndex)
        let dropsBelowDropIndex = sourceIndices.count - dropsAboveDropIndex
        
        // The destination indices will depend on whether there are more source items above/below the drop index
        let destinationIndices = IndexSet((dropIndex - dropsAboveDropIndex)...(dropIndex + dropsBelowDropIndex - 1))
        
        // Store all source items (tracks) that are being reordered, in a temporary location.
        // Make sure they the source indices are iterated in descending order, because tracks need to be removed from the bottom up.
        let sourceItems: [Element] = sourceIndices.sorted(by: descendingIntComparator).compactMap {self.removeItem($0)}
        
        // Destination indices need to be sorted in ascending order, because tracks need to be inserted from the top down
        let sortedDestinationIndices = destinationIndices.sorted(by: ascendingIntComparator)
        
        // Reverse the source items collection to match the order of the destination indices
        // For each destination index, copy over a source item into the corresponding destination hole
        for (loopIndex, sourceItem) in sourceItems.reversed().enumerated() {
            self.insert(sourceItem, at: sortedDestinationIndices[loopIndex])
        }
        
        return destinationIndices
    }
}