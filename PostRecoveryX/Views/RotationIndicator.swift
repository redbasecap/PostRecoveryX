import SwiftUI

struct RotationIndicator: View {
    let rotation: Int
    
    var rotationIcon: String {
        switch abs(rotation) {
        case 90:
            return rotation > 0 ? "rotate.right" : "rotate.left"
        case 180:
            return "arrow.up.arrow.down"
        case 270:
            return rotation > 0 ? "rotate.left" : "rotate.right"
        default:
            return "rotate.right"
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: rotationIcon)
                .font(.caption2)
            Text("\(abs(rotation))°")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange)
        .cornerRadius(4)
    }
}

#Preview {
    VStack(spacing: 20) {
        RotationIndicator(rotation: 90)
        RotationIndicator(rotation: -90)
        RotationIndicator(rotation: 180)
        RotationIndicator(rotation: 270)
    }
    .padding()
}