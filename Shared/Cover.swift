import SwiftUI

/// Kansikuva, jossa on paikanpitäjä jos kuvaa ei ole tai sen lataus epäonnistuu.
struct Cover: View {
    let url: URL?
    let size: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").foregroundStyle(.secondary).font(.system(size: size * 0.35))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
