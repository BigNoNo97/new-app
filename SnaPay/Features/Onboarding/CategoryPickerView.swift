import SwiftUI
import SnaPayCore

/// Onboarding: pick and personalize expense categories. Everything starts selected.
struct CategoryPickerView: View {
    @Environment(AppState.self) private var app

    @State private var categories = DefaultCategories.expenses
    @State private var selected = Set(DefaultCategories.expenses.map(\.id))
    @State private var editing: CategoryDraft?
    @State private var isAddingNew = false
    @State private var isSaving = false
    @State private var failure: AuthFailure?
    @State private var isOfferingFaceID = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s + 4), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("איך אתה מוציא כסף?")
                        .font(.largeTitle.weight(.bold))
                    Text("בחרנו בשבילך את הבסיס. לחיצה בוחרת או מסירה, ולחיצה ארוכה פותחת עריכה.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Spacing.l)

                LazyVGrid(columns: columns, spacing: Spacing.s + 4) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, draft in
                        Button {
                            toggle(draft)
                        } label: {
                            CategoryTile(draft: draft, isSelected: selected.contains(draft.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("categories.tile.\(index)")
                        .accessibilityAddTraits(selected.contains(draft.id) ? .isSelected : [])
                        .contextMenu {
                            Button("עריכה", systemImage: "pencil") { editing = draft }
                            Button("מחיקה", systemImage: "trash", role: .destructive) { remove(draft) }
                        }
                    }

                    Button {
                        isAddingNew = true
                    } label: {
                        VStack(spacing: Spacing.s) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 56, height: 56)
                                .background(Theme.brand.opacity(0.14), in: .rect(cornerRadius: 16))
                            Text("קטגוריה חדשה")
                                .font(.footnote.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 112)
                        .padding(Spacing.s)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Theme.brand.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("categories.add")
                }

                if let failure {
                    ErrorBanner(message: failure.message)
                }
            }
            .padding(Spacing.m)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: continueTapped) {
                LoadingLabel(title: "המשך", isLoading: isSaving)
            }
            .buttonStyle(.primary)
            .disabled(selected.isEmpty || isSaving)
            .padding(Spacing.m)
            .accessibilityIdentifier("categories.continue")
        }
        .sheet(item: $editing) { draft in
            CategoryEditorSheet(draft: draft) { updated in
                if let index = categories.firstIndex(where: { $0.id == updated.id }) {
                    categories[index] = updated
                }
            }
        }
        .sheet(isPresented: $isAddingNew) {
            CategoryEditorSheet(draft: CategoryDraft(name: "", emoji: "⭐", colorHex: DefaultCategories.palette[0])) { new in
                categories.append(new)
                selected.insert(new.id)
            }
        }
        .alert("כניסה עם Face ID?", isPresented: $isOfferingFaceID) {
            Button("הפעלה") { save(enableFaceID: true) }
            Button("לא עכשיו", role: .cancel) { save(enableFaceID: false) }
        } message: {
            Text("כך רק את/ה תוכל/י לפתוח את SnaPay. אפשר לשנות את זה בהגדרות.")
        }
    }

    private func toggle(_ draft: CategoryDraft) {
        if selected.contains(draft.id) {
            selected.remove(draft.id)
        } else {
            selected.insert(draft.id)
        }
    }

    private func remove(_ draft: CategoryDraft) {
        categories.removeAll { $0.id == draft.id }
        selected.remove(draft.id)
    }

    private func continueTapped() {
        if BiometricService.isAvailable && !AppConfig.isUITesting {
            isOfferingFaceID = true
        } else {
            save(enableFaceID: false)
        }
    }

    private func save(enableFaceID: Bool) {
        app.setFaceIDEnabled(enableFaceID)
        failure = nil
        isSaving = true
        let chosen = categories.filter { selected.contains($0.id) }
        Task {
            do {
                try await app.completeOnboarding(categories: chosen)
            } catch {
                failure = error as? AuthFailure ?? .unknown
            }
            isSaving = false
        }
    }
}

/// Create or edit a category: name, emoji, color, expense or income.
struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CategoryDraft
    var onSave: (CategoryDraft) -> Void

    private let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 6)

    init(draft: CategoryDraft, onSave: @escaping (CategoryDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack {
                        Spacer()
                        CategoryTile(draft: draft, isSelected: true)
                            .frame(width: 120)
                        Spacer()
                    }

                    GlassTextField(title: "שם הקטגוריה", text: $draft.name, kind: .name, identifier: "editor.name")

                    GlassSegmentedControl(
                        selection: $draft.kind,
                        segments: [.init(value: .expense, title: "הוצאה"), .init(value: .income, title: "הכנסה")],
                        identifier: "editor.kind"
                    )

                    section("אימוג'י") {
                        LazyVGrid(columns: emojiColumns, spacing: 6) {
                            ForEach(DefaultCategories.emojiChoices, id: \.self) { emoji in
                                Button {
                                    draft.emoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(
                                            draft.emoji == emoji ? Theme.brand.opacity(0.2) : Color.clear,
                                            in: .rect(cornerRadius: 12)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section("צבע") {
                        LazyVGrid(columns: colorColumns, spacing: Spacing.s) {
                            ForEach(DefaultCategories.palette, id: \.self) { hex in
                                Button {
                                    draft.colorHex = hex
                                } label: {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hex: hex))
                                        .frame(height: 44)
                                        .overlay {
                                            if draft.colorHex.uppercased() == hex.uppercased() {
                                                Image(systemName: "checkmark")
                                                    .font(.headline)
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("צבע \(hex)"))
                            }
                        }
                    }
                }
                .padding(Spacing.m)
            }
            .navigationTitle(draft.name.isEmpty ? "קטגוריה חדשה" : "עריכת קטגוריה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        var result = draft
                        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(result)
                        dismiss()
                    }
                    .disabled(!DefaultCategories.isValid(draft))
                    .accessibilityIdentifier("editor.save")
                }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
