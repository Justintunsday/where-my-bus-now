import MapKit
import SwiftUI

struct RouteStopPoint: Identifiable {
    let seq: Int
    let stopId: String
    let nameZh: String
    let nameEn: String
    let lat: Double?
    let lng: Double?

    var id: Int { seq }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func name(_ language: AppLanguage) -> String {
        language.isChinese ? L10n.display(nameZh) : nameEn
    }
}

struct RouteMapSection: View {
    @Environment(\.transitReduceMotion) private var reduceMotion
    @Environment(\.transitReduceTransparency) private var reduceTransparency
    @Environment(AppState.self) private var app
    let entry: RouteEntry
    let points: [RouteStopPoint]
    @Binding var selectedSeq: Int?

    @State private var camera: MapCameraPosition = .automatic

    private var lineColor: Color { RouteStyle.info(for: entry, provider: app.provider).background }
    private var coordinates: [CLLocationCoordinate2D] { points.compactMap(\.coordinate) }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(points) { point in
                if let coordinate = point.coordinate {
                    Annotation("\(point.seq + 1). \(point.name(L10n.language))", coordinate: coordinate, anchor: .center) {
                        marker(point)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onChange(of: selectedSeq) { _, newValue in
            guard let newValue,
                  let point = points.first(where: { $0.seq == newValue }),
                  let coordinate = point.coordinate
            else { return }
            withAnimation(TransitMotion.selection(reduced: reduceMotion)) {
                camera = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func marker(_ point: RouteStopPoint) -> some View {
        let isSelected = selectedSeq == point.seq
        // The circle is always centered on the stop coordinate; the callout
        // floats above it without shifting the pin.
        Button {
            withAnimation(TransitMotion.selection(reduced: reduceMotion)) { selectedSeq = isSelected ? nil : point.seq }
        } label: { ZStack {
            ZStack {
                Circle().fill(isSelected ? DesignTokens.accent : lineColor)
                Circle().stroke(.white, lineWidth: 1.5)
                Text("\(point.seq + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? DesignTokens.onAccent : RouteStyle.info(for: entry, provider: app.provider).foreground)
            }
            .frame(width: isSelected ? 24 : 19, height: isSelected ? 24 : 19)

            if isSelected {
                Text("\(point.seq + 1). \(point.name(L10n.language))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DesignTokens.surface, in: Capsule())
                    .overlay(Capsule().stroke(Color(uiColor: .separator), lineWidth: 0.5))
                    .fixedSize()
                    .offset(y: -34)
            }
        }.frame(minWidth: 44, minHeight: 44) }
        .buttonStyle(.plain)
        .accessibilityLabel("\(point.seq + 1). \(point.name(L10n.language))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
