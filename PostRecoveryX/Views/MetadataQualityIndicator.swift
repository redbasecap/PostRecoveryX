import SwiftUI

struct MetadataQualityIndicator: View {
    let score: Int
    
    var quality: QualityLevel {
        switch score {
        case 80...:
            return .excellent
        case 60..<80:
            return .good
        case 40..<60:
            return .fair
        case 20..<40:
            return .poor
        default:
            return .minimal
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: quality.icon)
                .font(.caption)
            Text("\(score)")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(quality.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(quality.color.opacity(0.2))
        .cornerRadius(4)
        .help("Metadata quality score: \(score)/100")
    }
}

enum QualityLevel {
    case excellent
    case good
    case fair
    case poor
    case minimal
    
    var icon: String {
        switch self {
        case .excellent:
            return "star.fill"
        case .good:
            return "star.leadinghalf.filled"
        case .fair:
            return "circle.fill"
        case .poor:
            return "circle.lefthalf.filled"
        case .minimal:
            return "circle"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent:
            return .green
        case .good:
            return .blue
        case .fair:
            return .yellow
        case .poor:
            return .orange
        case .minimal:
            return .red
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        MetadataQualityIndicator(score: 95)
        MetadataQualityIndicator(score: 75)
        MetadataQualityIndicator(score: 50)
        MetadataQualityIndicator(score: 30)
        MetadataQualityIndicator(score: 10)
    }
    .padding()
}