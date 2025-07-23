import SwiftUI
import SwiftData

struct SimilarScenesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SimilarSceneGroup.createdDate, order: .reverse) private var sceneGroups: [SimilarSceneGroup]
    
    var body: some View {
        NavigationStack {
            if sceneGroups.isEmpty {
                ContentUnavailableView("No Similar Scenes", 
                                     systemImage: "rectangle.stack",
                                     description: Text("Similar scenes will appear here after scanning"))
            } else {
                List(sceneGroups) { group in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.groupType.rawValue)
                                .font(.headline)
                            Text("\(group.fileCount) files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .navigationTitle("Similar Scenes")
            }
        }
    }
}