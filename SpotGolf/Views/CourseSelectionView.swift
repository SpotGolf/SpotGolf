import SwiftUI
import CoreLocation

struct CourseSelectionView: View {
    @EnvironmentObject var courseService: CourseService
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var roundStore: RoundStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCourse: Course?
    @State private var selectedIndices: [Int] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let course = selectedCourse {
                    subCourseSelectionView(course: course)
                } else {
                    courseListView
                }
            }
            .navigationTitle(selectedCourse != nil ? "Select Nines" : "Select Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedCourse != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            selectedCourse = nil
                            selectedIndices = []
                            errorMessage = nil
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") {
                            roundStore.startRound()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Course List (Phase 1)

    private var courseListView: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading course...")
                        Spacer()
                    }
                }
            }

            if !searchText.isEmpty {
                let results = courseService.searchCourses(query: searchText)
                if results.isEmpty {
                    Section {
                        Text("No courses found")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Search Results") {
                        ForEach(results, id: \.path) { entry in
                            courseRow(entry: entry, distance: nil)
                        }
                    }
                }
            } else if let location = locationManager.lastLocation {
                let nearby = courseService.nearbyCourses(from: location)
                if nearby.isEmpty {
                    Section {
                        Text("No courses nearby")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Nearby Courses") {
                        ForEach(nearby, id: \.entry.path) { result in
                            courseRow(entry: result.entry, distance: result.distanceMiles)
                        }
                    }
                }
            } else {
                Section {
                    Text("Determining location...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search courses")
        .task {
            locationManager.startUpdating()
            await courseService.refreshIndex()
        }
        .onDisappear {
            if roundStore.activeRound == nil {
                locationManager.stopUpdating()
            }
        }
    }

    private func courseRow(entry: CourseIndexEntry, distance: Double?) -> some View {
        Button {
            Task {
                await fetchAndSelect(entry: entry)
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text([entry.city, entry.state].compactMap { $0 }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let distance {
                    Text(String(format: "%.1f mi", distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isLoading)
    }

    private func fetchAndSelect(entry: CourseIndexEntry) async {
        isLoading = true
        errorMessage = nil
        do {
            let course = try await courseService.fetchCourse(path: entry.path)
            if course.subCourses.count <= 1 {
                // Single sub-course — start round immediately
                let indices = course.subCourses.isEmpty ? [] : [0]
                let selection = CourseSelection(course: course, selectedSubCourseIndices: indices)
                roundStore.startRound()
                roundStore.setCourse(selection)
                dismiss()
            } else {
                selectedCourse = course
                selectedIndices = defaultIndices(for: course)
            }
        } catch {
            errorMessage = "Failed to load course: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Sub-Course Selection (Phase 2)

    private func subCourseSelectionView(course: Course) -> some View {
        List {
            ForEach(Array(course.subCourses.enumerated()), id: \.offset) { index, subCourse in
                Button {
                    toggleSelection(index)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(subCourse.name ?? "Course \(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(subCourse.holes.count) holes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let order = selectionOrder(for: index) {
                            Text("\(order)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(.blue))
                        }
                    }
                }
            }

            Section {
                Button {
                    let selection = CourseSelection(course: course, selectedSubCourseIndices: selectedIndices)
                    roundStore.startRound()
                    roundStore.setCourse(selection)
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Start Round")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(selectedIndices.isEmpty)
            }
        }
    }

    private func toggleSelection(_ index: Int) {
        if let pos = selectedIndices.firstIndex(of: index) {
            selectedIndices.remove(at: pos)
        } else if selectedIndices.count < 2 {
            selectedIndices.append(index)
        }
    }

    private func selectionOrder(for index: Int) -> Int? {
        guard let pos = selectedIndices.firstIndex(of: index) else { return nil }
        return pos + 1
    }

    private func defaultIndices(for course: Course) -> [Int] {
        let names = course.subCourses.enumerated().map { ($0.offset, $0.element.name?.lowercased() ?? "") }
        let frontIndex = names.first(where: { $0.1 == "front" })?.0
        let backIndex = names.first(where: { $0.1 == "back" })?.0

        if let front = frontIndex, let back = backIndex {
            return [front, back]
        }

        // Default to first 2
        return Array(0..<min(2, course.subCourses.count))
    }
}
