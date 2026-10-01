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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("איך אתה מוציא כסף?")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("בחרנו בשבילך את הבסיס. אפשר לשנות, להוסיף ולעצב.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, Spacing.xl)

                LazyVGrid(columns: columns, spacing: Spacing.s) {
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
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Theme.brandInk)
                                .frame(width: 40, height: 40)
                            Text("קטגוריה חדשה")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.brandInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .padding(.vertical, Spacing.sm)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("categories.add")
                }

                if let failure {
                    ErrorBanner(message: failure.message)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.m)
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: Spacing.sm) {
                Text("לחיצה ארוכה על קטגוריה פותחת עריכה")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                Button(action: continueTapped) {
                    LoadingLabel(title: "המשך", isLoading: isSaving)
                }
                .buttonStyle(.primary)
                .disabled(selected.isEmpty || isSaving)
                .accessibilityIdentifier("categories.continue")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.s)
        }
        .sheet(item: $editing) { draft in
            CategoryEditorSheet(draft: draft, onDelete: { remove(draft) }) { updated in
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
    var onDelete: (() -> Void)?
    var onSave: (CategoryDraft) -> Void

    private let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 8)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 8)

    init(draft: CategoryDraft, onDelete: (() -> Void)? = nil, onSave: @escaping (CategoryDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onDelete = onDelete
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.m)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack(alignment: .bottom, spacing: Spacing.sm) {
                        EmojiTile(emoji: draft.emoji, color: Color(hex: draft.colorHex), size: 64)
                        GlassTextField(title: "שם", text: $draft.name, kind: .name, identifier: "editor.name")
                    }

                    GlassSegmentedControl(
                        selection: $draft.kind,
                        segments: [.init(value: .expense, title: "הוצאה"), .init(value: .income, title: "הכנסה")],
                        identifier: "editor.kind"
                    )

                    section("אימוג׳י") {
                        LazyVGrid(columns: emojiColumns, spacing: Spacing.s) {
                            ForEach(DefaultCategories.emojiChoices, id: \.self) { emoji in
                                let isChosen = draft.emoji == emoji
                                Button {
                                    draft.emoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.title3)
                                        .frame(maxWidth: .infinity, minHeight: 38)
                                        .aspectRatio(1, contentMode: .fit)
                                        .background(isChosen ? Theme.brandTint : Theme.fill, in: .rect(cornerRadius: Radius.tile))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Radius.tile)
                                                .strokeBorder(isChosen ? Theme.brand : .clear, lineWidth: 2)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isChosen ? .isSelected : [])
                            }
                        }
                    }

                    section("צבע") {
                        LazyVGrid(columns: colorColumns, spacing: Spacing.s) {
                            ForEach(DefaultCategories.palette, id: \.self) { hex in
                                let isChosen = draft.colorHex.uppercased() == hex.uppercased()
                                Button {
                                    draft.colorHex = hex
                                } label: {
                                    RoundedRectangle(cornerRadius: Radius.tile)
                                        .fill(Color(hex: hex))
                                        .aspectRatio(1, contentMode: .fit)
                                        .padding(isChosen ? 4 : 0)
                                        .overlay {
                                            if isChosen {
                                                RoundedRectangle(cornerRadius: Radius.tile + 2)
                                                    .strokeBorder(Color(hex: hex), lineWidth: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("צבע \(hex)"))
                                .accessibilityAddTraits(isChosen ? .isSelected : [])
                            }
                        }
                    }

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("מחיקת קטגוריה", systemImage: "trash")
                                .font(.headline)
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                                .background(Theme.expenseTint, in: .rect(cornerRadius: Radius.control))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.m)
                        .accessibilityIdentifier("editor.delete")
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.l)
            }
        }
        .designSheet()
    }

    private var header: some View {
        ZStack {
            Text(onDelete == nil ? "קטגוריה חדשה" : "עריכת קטגוריה")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Button("שמירה") {
                    var result = draft
                    result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(result)
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(Theme.brandInk)
                .disabled(!DefaultCategories.isValid(draft))
                .opacity(DefaultCategories.isValid(draft) ? 1 : 0.4)
                .accessibilityIdentifier("editor.save")
                Spacer()
                IconButton(symbol: "xmark", label: "ביטול") { dismiss() }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}
